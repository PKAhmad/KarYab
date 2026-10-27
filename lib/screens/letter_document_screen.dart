import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/document_template.dart';
import '../models/user_profile.dart';
import '../services/analytics_service.dart';
import '../services/cv_pdf_generator.dart';
import '../utils/navigation_helpers.dart';
import '../utils/pdf_save_helper.dart';
import '../widgets/document_template_picker.dart';
import '../ui/karyab_ui.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Cover Letter / Deckblatt — type-agnostic application documents, reached
// from ChooseCvTypeScreen as sibling options to Job CV / Ausbildung CV.
// Generated via generateAnschreiben()/generateDeckblatt() in
// services/cv_pdf_generator.dart from the UserProfile built out of
// 'saved_profile' - no extra questionnaire step, usable regardless of which
// CV type (if any) the user has. Both document types let the user pick a
// template via showAnschreibenTemplatePicker()/showDeckblattTemplatePicker()
// (same UX as the CV template picker).
// ─────────────────────────────────────────────────────────────────────────────

// Independent from every other DocumentTemplate/AnschreibenTemplate/
// DeckblattTemplate prefs key in the app (regular CV, Ausbildung CV) - each
// document type's template choice must never share or clobber another's.
const String kAnschreibenTemplatePrefsKey = 'selected_anschreiben_template';
const String kDeckblattTemplatePrefsKey = 'selected_deckblatt_template';

enum LetterDocType { coverLetter, deckblatt }

class LetterDocumentScreen extends StatefulWidget {
  final UserProfile profile;
  final String language;
  final LetterDocType docType;
  // Optional per-job overrides - set when this screen is opened from a
  // specific job posting (e.g. an Ausbildung listing's "Cover Letter
  // erstellen" button) so the generated Anschreiben is relevant to that
  // exact posting instead of the user's generic saved target position.
  // Ignored for docType == deckblatt. Null/empty preserves the existing
  // profile-derived behavior unchanged (e.g. the ChooseCvTypeScreen entry
  // point below, which passes none of these).
  final String? jobTitle;
  final String? companyName;
  final bool isAusbildungCv;

  const LetterDocumentScreen({
    super.key,
    required this.profile,
    required this.language,
    required this.docType,
    this.jobTitle,
    this.companyName,
    this.isAusbildungCv = false,
  });

  @override
  State<LetterDocumentScreen> createState() => _LetterDocumentScreenState();
}

class _LetterDocumentScreenState extends State<LetterDocumentScreen> {
  static const Color _navy  = KColors.navy;
  static const Color _green = KColors.green;

  late String _lang;
  bool _saving = false;
  AnschreibenTemplate _anschreibenTemplate = AnschreibenTemplate.blauMinimal;
  DeckblattTemplate _deckblattTemplate = DeckblattTemplate.braunIconSet;

  // Cover letter only: the four editable sections, prefilled from the
  // phrase bank. _generated keeps the last composed text so we can tell
  // whether the user changed anything before a regenerate overwrites it.
  final _subjectCtrl = TextEditingController();
  final _openingCtrl = TextEditingController();
  final _middleCtrl = TextEditingController();
  final _closingCtrl = TextEditingController();
  AnschreibenTexts? _generated;
  bool _loadingTexts = false;

  // Deckblatt only: which documents the Deckblatt lists under "Unterlagen:".
  // Nothing is listed unless the user ticked it (or typed it as a custom
  // entry); the last selection is persisted. The list is capped at
  // _kMaxUnterlagen entries in total.
  static const String _kUnterlagenPrefsKey = 'deckblatt_unterlagen_selection';
  static const String _kAnschreibenCreatedKey = 'anschreiben_created';
  static const int _kMaxUnterlagen = 8;
  // key -> German name printed on the Deckblatt (also the persisted key order)
  static const Map<String, String> _kStdUnterlagen = {
    'lebenslauf': 'Lebenslauf',
    'anschreiben': 'Anschreiben',
    'zeugnisse': 'Zeugnisse',
    'sprachzertifikat': 'Sprachzertifikat',
    'fuehrerschein': 'Führerschein',
    'praktikum': 'Praktikumsbescheinigung',
  };
  final Set<String> _ticked = {};
  final List<String> _custom = [];
  final _customCtrl = TextEditingController();
  bool _unterlagenLoaded = false;
  bool _deckblattCreated = false;

  bool get _isCoverLetter => widget.docType == LetterDocType.coverLetter;
  bool get _isRtl => _lang == 'ps' || _lang == 'fa';

  @override
  void initState() {
    super.initState();
    _lang = widget.language;
    if (_isCoverLetter) _composeTexts();
    AnalyticsService().logScreen(
        widget.docType == LetterDocType.coverLetter
            ? 'cover_letter'
            : 'deckblatt');
    if (widget.docType == LetterDocType.coverLetter) {
      _loadAnschreibenTemplate();
    } else {
      _loadDeckblattTemplate();
      _loadUnterlagen();
    }
  }

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _openingCtrl.dispose();
    _middleCtrl.dispose();
    _closingCtrl.dispose();
    _customCtrl.dispose();
    super.dispose();
  }

  // Picks fresh random phrase-bank variants and puts them into the fields.
  Future<void> _composeTexts() async {
    setState(() => _loadingTexts = true);
    try {
      final t = await composeAnschreibenTexts(
        widget.profile,
        isAusbildungCv: widget.isAusbildungCv,
        jobTitleOverride: widget.jobTitle,
      );
      if (!mounted) return;
      _generated = t;
      _subjectCtrl.text = t.subject;
      _openingCtrl.text = t.opening;
      _middleCtrl.text = t.middle;
      _closingCtrl.text = t.closing;
    } finally {
      if (mounted) setState(() => _loadingTexts = false);
    }
  }

  bool get _hasEdits {
    final g = _generated;
    if (g == null) return false;
    return _subjectCtrl.text != g.subject ||
        _openingCtrl.text != g.opening ||
        _middleCtrl.text != g.middle ||
        _closingCtrl.text != g.closing;
  }

  Future<void> _regenerate() async {
    if (_loadingTexts || _saving) return;
    if (_hasEdits) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => Directionality(
          textDirection: _isRtl ? TextDirection.rtl : TextDirection.ltr,
          child: AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Text(_replaceTitle,
                style: const TextStyle(
                    color: _navy, fontSize: 16, fontWeight: FontWeight.w800)),
            content: Text(_replaceBody,
                style: const TextStyle(color: _navy, fontSize: 13, height: 1.4)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(_cancelLabel,
                    style: const TextStyle(
                        color: _navy, fontWeight: FontWeight.w700)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(_replaceLabel,
                    style: const TextStyle(
                        color: _navy, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ),
      );
      if (ok != true || !mounted) return;
    }
    await _composeTexts();
  }

  Future<void> _loadAnschreibenTemplate() async {
    final t = await loadSelectedAnschreibenTemplate(kAnschreibenTemplatePrefsKey);
    if (mounted) setState(() => _anschreibenTemplate = t);
  }

  Future<void> _pickAnschreibenTemplate() async {
    final chosen =
        await showAnschreibenTemplatePicker(context, current: _anschreibenTemplate);
    if (!mounted || chosen == _anschreibenTemplate) return;
    setState(() => _anschreibenTemplate = chosen);
    await saveSelectedAnschreibenTemplate(kAnschreibenTemplatePrefsKey, chosen);
  }

  int get _unterlagenCount => _ticked.length + _custom.length;

  // Print order: ticked standard documents in their fixed order, then the
  // custom entries as typed.
  List<String> get _unterlagenList => [
        for (final e in _kStdUnterlagen.entries)
          if (_ticked.contains(e.key)) e.value,
        ..._custom,
      ];

  // Restores the last selection. With none saved yet, Lebenslauf and
  // Anschreiben are pre-ticked only if the app knows the user created them.
  Future<void> _loadUnterlagen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kUnterlagenPrefsKey);
      final ticked = <String>{};
      final custom = <String>[];
      if (raw != null && raw.isNotEmpty) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        for (final k in (map['ticked'] as List<dynamic>? ?? [])) {
          if (_kStdUnterlagen.containsKey(k)) ticked.add(k as String);
        }
        for (final c in (map['custom'] as List<dynamic>? ?? [])) {
          final t = (c as String).trim();
          if (t.isNotEmpty && !custom.contains(t)) custom.add(t);
        }
      } else {
        if (prefs.getBool('cv_created') ?? false) ticked.add('lebenslauf');
        if (prefs.getBool(_kAnschreibenCreatedKey) ?? false) {
          ticked.add('anschreiben');
        }
      }
      while (ticked.length + custom.length > _kMaxUnterlagen &&
          custom.isNotEmpty) {
        custom.removeLast();
      }
      if (!mounted) return;
      setState(() {
        _ticked
          ..clear()
          ..addAll(ticked);
        _custom
          ..clear()
          ..addAll(custom);
      });
    } catch (_) {
      // Fall through to an empty selection; the user can tick manually.
    } finally {
      if (mounted) setState(() => _unterlagenLoaded = true);
    }
  }

  Future<void> _saveUnterlagen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kUnterlagenPrefsKey,
        jsonEncode({'ticked': _ticked.toList(), 'custom': _custom}),
      );
    } catch (_) {}
  }

  void _toggleUnterlage(String key, bool on) {
    setState(() {
      if (on) {
        if (_unterlagenCount < _kMaxUnterlagen) _ticked.add(key);
      } else {
        _ticked.remove(key);
      }
    });
  }

  void _addCustomUnterlage() {
    final t = _customCtrl.text.trim();
    if (t.isEmpty || _custom.contains(t)) return;
    if (_unterlagenCount >= _kMaxUnterlagen) return;
    setState(() {
      _custom.add(t);
      _customCtrl.clear();
    });
  }

  Future<void> _createDeckblatt() async {
    await _saveUnterlagen();
    if (mounted) setState(() => _deckblattCreated = true);
  }

  Future<void> _markAnschreibenCreated() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kAnschreibenCreatedKey, true);
    } catch (_) {}
  }

  Future<void> _loadDeckblattTemplate() async {
    final t = await loadSelectedDeckblattTemplate(kDeckblattTemplatePrefsKey);
    if (mounted) setState(() => _deckblattTemplate = t);
  }

  Future<void> _pickDeckblattTemplate() async {
    final chosen =
        await showDeckblattTemplatePicker(context, current: _deckblattTemplate);
    if (!mounted || chosen == _deckblattTemplate) return;
    setState(() => _deckblattTemplate = chosen);
    await saveSelectedDeckblattTemplate(kDeckblattTemplatePrefsKey, chosen);
  }

  void _pickTemplate() => widget.docType == LetterDocType.coverLetter
      ? _pickAnschreibenTemplate()
      : _pickDeckblattTemplate();

  String get _currentTemplateDisplayName => widget.docType == LetterDocType.coverLetter
      ? _anschreibenTemplate.displayName
      : _deckblattTemplate.displayName;

  void _goHome() =>
      goHomeToIntroduction(context, language: _lang, voiceMode: false);

  Future<Uint8List> _buildBytes(PdfPageFormat format) {
    return widget.docType == LetterDocType.coverLetter
        ? generateAnschreiben(
            widget.profile,
            _anschreibenTemplate,
            isAusbildungCv: widget.isAusbildungCv,
            jobTitleOverride: widget.jobTitle,
            companyNameOverride: widget.companyName,
            // Exactly what is in the fields, including the user's edits.
            subjectText: _subjectCtrl.text.trim(),
            openingText: _openingCtrl.text.trim(),
            middleText: _middleCtrl.text.trim(),
            closingText: _closingCtrl.text.trim(),
          )
        : generateDeckblatt(
            widget.profile,
            _deckblattTemplate,
            // Only what the user ticked or typed, in print order.
            unterlagen: _unterlagenList,
          );
  }

  String get _pdfFilename {
    final name = widget.profile.fullName.replaceAll(' ', '_');
    final prefix =
        widget.docType == LetterDocType.coverLetter ? 'Anschreiben' : 'Deckblatt';
    return '${prefix}_$name.pdf';
  }

  Future<void> _download() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final bytes = await _buildBytes(PdfPageFormat.a4);
      final saved = await savePdfToDownloads(bytes, _pdfFilename);

      if (!mounted) return;
      if (saved) {
        _snack(_savedMsg);
      } else {
        await Printing.sharePdf(bytes: bytes, filename: _pdfFilename);
      }
      // Lets the Deckblatt checklist pre-tick Anschreiben next time.
      if (_isCoverLetter) _markAnschreibenCreated();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg) {
    kSnack(context, msg);
  }

  String get _titleLabel {
    if (widget.docType == LetterDocType.coverLetter) {
      switch (_lang) {
        case 'ps': return 'د پوښتنلیک لیک';
        case 'fa': return 'نامه پوششی';
        default:   return 'Cover Letter';
      }
    }
    return 'Deckblatt';
  }

  String _t({
    required String en,
    required String de,
    required String ps,
    required String fa,
  }) {
    switch (_lang) {
      case 'ps': return ps;
      case 'fa': return fa;
      case 'de': return de;
      default:   return en;
    }
  }

  String get _unterlagenTitle => _t(
        en: 'Documents to list on the Deckblatt',
        de: 'Unterlagen für das Deckblatt',
        ps: 'هغه اسناد چې په Deckblatt کې لیکل کیږي',
        fa: 'مدارکی که روی Deckblatt فهرست می‌شوند',
      );

  String get _unterlagenHint => _t(
        en: 'Tick only what you will really send. The Deckblatt lists exactly these.',
        de: 'Wähle nur aus, was du wirklich mitschickst. Das Deckblatt listet genau diese Unterlagen.',
        ps: 'یوازې هغه اسناد وټاکئ چې رښتیا یې لیږئ. Deckblatt به یوازې همدا اسناد ولیکي.',
        fa: 'فقط مدارکی را انتخاب کنید که واقعا ارسال می‌کنید. Deckblatt دقیقا همین‌ها را فهرست می‌کند.',
      );

  String _stdUnterlageHelp(String key) {
    switch (key) {
      case 'lebenslauf':
        return _t(en: 'CV', de: '', ps: 'CV', fa: 'رزومه');
      case 'anschreiben':
        return _t(en: 'Cover letter', de: '', ps: 'د پوښتنلیک لیک', fa: 'نامه پوششی');
      case 'zeugnisse':
        return _t(en: 'Certificates', de: '', ps: 'تصدیق‌نامې', fa: 'گواهی‌نامه‌ها');
      case 'sprachzertifikat':
        return _t(en: 'Language certificate', de: '', ps: 'د ژبې تصدیق‌نامه', fa: 'گواهی زبان');
      case 'fuehrerschein':
        return _t(en: 'Driving licence', de: '', ps: 'د موټر چلولو جواز', fa: 'گواهی‌نامه رانندگی');
      default:
        return _t(en: 'Internship certificate', de: '', ps: 'د کارورزۍ تصدیق‌نامه', fa: 'گواهی کارآموزی');
    }
  }

  String get _customHint => _t(
        en: 'Add another document',
        de: 'Weitere Unterlage hinzufügen',
        ps: 'بل سند اضافه کړئ',
        fa: 'سند دیگری اضافه کنید',
      );

  String get _addLabel =>
      _t(en: 'Add', de: 'Hinzufügen', ps: 'اضافه کړئ', fa: 'افزودن');

  String get _maxReachedLabel => _t(
        en: 'Maximum of 8 documents reached',
        de: 'Höchstens 8 Unterlagen möglich',
        ps: 'تر ډېره ۸ اسناد کېدای شي',
        fa: 'حداکثر ۸ سند ممکن است',
      );

  String get _createDeckblattLabel => _t(
        en: 'Create Deckblatt',
        de: 'Deckblatt erstellen',
        ps: 'Deckblatt جوړ کړئ',
        fa: 'ساخت Deckblatt',
      );

  String get _changeDocumentsLabel => _t(
        en: 'Change documents',
        de: 'Unterlagen ändern',
        ps: 'اسناد بدل کړئ',
        fa: 'تغییر مدارک',
      );

  String get _createPdfLabel {
    switch (_lang) {
      case 'ps': return 'PDF جوړ کړئ';
      case 'fa': return 'ساخت PDF';
      default:   return 'Create PDF';
    }
  }

  String get _subjectLabel {
    switch (_lang) {
      case 'ps': return 'Betreff (موضوع)';
      case 'fa': return 'Betreff (موضوع)';
      default:   return 'Betreff (Subject)';
    }
  }

  String get _openingLabel {
    switch (_lang) {
      case 'ps': return 'پیل';
      case 'fa': return 'مقدمه';
      default:   return 'Opening';
    }
  }

  String get _skillsLabel {
    switch (_lang) {
      case 'ps': return 'د وړتیاوو پاراګراف';
      case 'fa': return 'بند مهارت‌ها';
      default:   return 'Skills paragraph';
    }
  }

  String get _closingLabel {
    switch (_lang) {
      case 'ps': return 'پای';
      case 'fa': return 'پایان';
      default:   return 'Closing';
    }
  }

  String get _regenerateLabel {
    switch (_lang) {
      case 'ps': return 'نوی متن جوړ کړئ';
      case 'fa': return 'ساخت متن جدید';
      default:   return 'Regenerate';
    }
  }

  String get _replaceTitle {
    switch (_lang) {
      case 'ps': return 'ستاسو بدلونونه بدل شي؟';
      case 'fa': return 'تغییرات شما جایگزین شود؟';
      default:   return 'Replace your changes?';
    }
  }

  String get _replaceBody {
    switch (_lang) {
      case 'ps': return 'نوی متن به هغه متن بدل کړي چې تاسو سم کړی دی.';
      case 'fa': return 'متن جدید جایگزین متنی می‌شود که ویرایش کرده‌اید.';
      default:   return 'A new text will replace the text you edited.';
    }
  }

  String get _cancelLabel {
    switch (_lang) {
      case 'ps': return 'لغوه کړئ';
      case 'fa': return 'لغو';
      default:   return 'Cancel';
    }
  }

  String get _replaceLabel {
    switch (_lang) {
      case 'ps': return 'بدل کړئ';
      case 'fa': return 'جایگزین کن';
      default:   return 'Replace';
    }
  }

  String get _germanHint {
    switch (_lang) {
      case 'ps': return 'د لیک متن تل په آلماني دی. تاسو کولی شئ هر ساحه سم کړئ.';
      case 'fa': return 'متن نامه همیشه به آلمانی است. می‌توانید هر بخش را ویرایش کنید.';
      default:   return 'The letter text is always German. You can edit every section.';
    }
  }

  String get _downloadLabel {
    switch (_lang) {
      case 'ps': return 'ډاونلوډ کړئ';
      case 'fa': return 'دانلود';
      default:   return 'Download PDF';
    }
  }

  String get _chooseTemplateLabel {
    switch (_lang) {
      case 'ps': return 'کینډۍ وټاکئ';
      case 'fa': return 'انتخاب قالب';
      default:   return 'Choose Template';
    }
  }

  String get _savedMsg {
    switch (_lang) {
      case 'ps': return 'سند په ډاونلوډ کې خوندي شو';
      case 'fa': return 'سند در دانلودها ذخیره شد';
      default:   return 'Saved to Downloads';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KColors.pageBase,
      body: Stack(
        children: [
          const KBackgroundGlow(),
          SafeArea(
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    child: _buildDocSection(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          KNavButton(
            icon: Icons.arrow_back_ios_new_rounded,
            onTap: () => Navigator.pop(context),
          ),
          Expanded(
            child: Text(
              _titleLabel,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _navy,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          KNavButton(icon: Icons.home_rounded, onTap: _goHome),
        ],
      ),
    );
  }

  Widget _buildDocSection() {
    return KGlassSurface(
      borderRadius: 20,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  color: KColors.mint,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  widget.docType == LetterDocType.coverLetter
                      ? Icons.mail_rounded
                      : Icons.badge_rounded,
                  color: _green,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _titleLabel,
                  style: const TextStyle(
                    color: _navy,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              KGlassCard(
                borderRadius: 20,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                onTap: _pickTemplate,
                child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$_chooseTemplateLabel: $_currentTemplateDisplayName',
                        style: const TextStyle(
                          color: _navy,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 3),
                      const Icon(Icons.keyboard_arrow_down_rounded,
                          color: _green, size: 15),
                    ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_isCoverLetter)
            _buildLetterEditor()
          else if (!_deckblattCreated)
            _buildUnterlagenSelector()
          else
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                height: 440,
                // Keyed to the Deckblatt template, so the preview
                // regenerates when the user picks a different one.
                child: PdfPreview(
                  key: ValueKey(
                      '${_deckblattTemplate.name}|${_unterlagenList.join('|')}'),
                  build: _buildBytes,
                  canChangeOrientation: false,
                  canChangePageFormat: false,
                  canDebug: false,
                  pdfFileName: _pdfFilename,
                  loadingWidget: const Center(
                    child: CircularProgressIndicator(color: _green),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 12),
          Stack(
            children: [
              KPrimaryCta(
                icon: _isCoverLetter
                ? Icons.picture_as_pdf_rounded
                : (_deckblattCreated
                    ? Icons.download_rounded
                    : Icons.badge_rounded),
                label: _isCoverLetter
                ? _createPdfLabel
                : (_deckblattCreated ? _downloadLabel : _createDeckblattLabel),
                isRtl: _isRtl,
                isSelected: false,
                onTap: () {
                if (_isCoverLetter) {
                  if (!_saving && !_loadingTexts) _download();
                } else if (!_deckblattCreated) {
                  if (_unterlagenLoaded) _createDeckblatt();
                } else if (!_saving) {
                  _download();
                }
              },
              ),
              if (_saving)
                Positioned.directional(
                  textDirection: _isRtl ? TextDirection.rtl : TextDirection.ltr,
                  start: 8,
                  top: 13,
                  child: Container(
                    width: 38,
                    height: 38,
                    padding: const EdgeInsets.all(9),
                    decoration: const BoxDecoration(
                      color: KColors.ctaStart,
                      shape: BoxShape.circle,
                    ),
                    child: const CircularProgressIndicator(
                        color: KColors.green, strokeWidth: 2.5),
                  ),
                ),
            ],
          ),
          if (!_isCoverLetter && _deckblattCreated) ...[
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed:
                    _saving ? null : () => setState(() => _deckblattCreated = false),
                child: Text(
                  _changeDocumentsLabel,
                  style: const TextStyle(
                      color: _navy, fontSize: 12, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Deckblatt step 1: pick what the Deckblatt lists under "Unterlagen:".
  Widget _buildUnterlagenSelector() {
    if (!_unterlagenLoaded) {
      return const SizedBox(
        height: 160,
        child: Center(child: CircularProgressIndicator(color: _green)),
      );
    }
    final full = _unterlagenCount >= _kMaxUnterlagen;
    final dir = _isRtl ? TextDirection.rtl : TextDirection.ltr;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _unterlagenTitle,
          textDirection: dir,
          style: const TextStyle(
              color: _navy, fontSize: 14, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          _unterlagenHint,
          textDirection: dir,
          style: TextStyle(
              color: _navy.withOpacity(0.65), fontSize: 12, height: 1.4),
        ),
        const SizedBox(height: 8),
        for (final e in _kStdUnterlagen.entries)
          _unterlageTile(e.key, e.value, full),
        if (_custom.isNotEmpty) ...[
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final c in _custom)
                Chip(
                  label: Text(c,
                      style: const TextStyle(
                          color: _navy,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                  backgroundColor: KColors.mint,
                  side: BorderSide(color: _green.withOpacity(0.5)),
                  deleteIconColor: _navy,
                  onDeleted: () => setState(() => _custom.remove(c)),
                ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _customCtrl,
                enabled: !full,
                maxLength: 40,
                textDirection: TextDirection.ltr,
                style: const TextStyle(color: _navy, fontSize: 13),
                cursorColor: _green,
                onSubmitted: (_) => _addCustomUnterlage(),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: full ? _maxReachedLabel : _customHint,
                  hintStyle:
                      TextStyle(color: _navy.withOpacity(0.45), fontSize: 12),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.85),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: _navy.withOpacity(0.12)),
                  ),
                  disabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: _navy.withOpacity(0.08)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: _green, width: 1.6),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: full ? null : _addCustomUnterlage,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  color: full ? const Color(0xFFE4E8EE) : _green,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  _addLabel,
                  style: const TextStyle(
                      color: _navy, fontSize: 12, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _unterlageTile(String key, String germanName, bool full) {
    final on = _ticked.contains(key);
    final help = _stdUnterlageHelp(key);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: (!on && full) ? null : () => _toggleUnterlage(key, !on),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          textDirection: _isRtl ? TextDirection.rtl : TextDirection.ltr,
          children: [
            Checkbox(
              value: on,
              activeColor: _green,
              checkColor: _navy,
              side: BorderSide(color: _navy.withOpacity(0.4), width: 1.4),
              onChanged: (!on && full)
                  ? null
                  : (v) => _toggleUnterlage(key, v ?? false),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment:
                    _isRtl ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  Text(
                    germanName,
                    style: const TextStyle(
                        color: _navy, fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  if (help.isNotEmpty)
                    Text(
                      help,
                      textDirection:
                          _isRtl ? TextDirection.rtl : TextDirection.ltr,
                      style: TextStyle(
                          color: _navy.withOpacity(0.55), fontSize: 11),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Editable letter text: Betreff, Opening, Skills paragraph, Closing.
  // Salutation, signature and sender/recipient blocks are fixed in the PDF.
  Widget _buildLetterEditor() {
    if (_loadingTexts && _generated == null) {
      return const SizedBox(
        height: 160,
        child: Center(child: CircularProgressIndicator(color: _green)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _germanHint,
          textDirection: _isRtl ? TextDirection.rtl : TextDirection.ltr,
          style: TextStyle(
              color: _navy.withOpacity(0.65), fontSize: 12, height: 1.4),
        ),
        const SizedBox(height: 12),
        _letterField(_subjectLabel, _subjectCtrl, minLines: 1),
        _letterField(_openingLabel, _openingCtrl, minLines: 3),
        _letterField(_skillsLabel, _middleCtrl, minLines: 3),
        _letterField(_closingLabel, _closingCtrl, minLines: 3),
        const SizedBox(height: 4),
        Align(
          alignment: _isRtl ? Alignment.centerLeft : Alignment.centerRight,
          child: KGlassCard(
            borderRadius: 20,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            onTap: (_loadingTexts || _saving) ? null : _regenerate,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_loadingTexts)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        color: _green, strokeWidth: 2),
                  )
                else
                  const Icon(Icons.refresh_rounded, color: _navy, size: 16),
                const SizedBox(width: 6),
                Text(
                  _regenerateLabel,
                  style: const TextStyle(
                    color: _navy,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _letterField(String label, TextEditingController ctrl,
      {required int minLines}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: _isRtl ? Alignment.centerRight : Alignment.centerLeft,
            child: Text(
              label,
              textDirection: _isRtl ? TextDirection.rtl : TextDirection.ltr,
              style: const TextStyle(
                color: _navy,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 6),
          KGlassCard(
            borderRadius: 14,
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: TextField(
            controller: ctrl,
            enabled: !_loadingTexts && !_saving,
            minLines: minLines,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            // The letter itself is German, so the field is always LTR.
            textDirection: TextDirection.ltr,
            style: const TextStyle(color: _navy, fontSize: 13, height: 1.4),
            cursorColor: _green,
            decoration: const InputDecoration(
              isDense: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
          ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared small widgets (duplicated per-file, matching the existing pattern
// already used the same way in cv_preview_screen.dart,
// ausbildung_document_preview_screen.dart, choose_cv_type_screen.dart and
// introduction_screen.dart).
// ─────────────────────────────────────────────────────────────────────────────
