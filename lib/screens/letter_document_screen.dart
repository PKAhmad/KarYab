import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../models/document_template.dart';
import '../models/user_profile.dart';
import '../services/analytics_service.dart';
import '../services/cv_pdf_generator.dart';
import '../utils/navigation_helpers.dart';
import '../widgets/document_template_picker.dart';

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
  static const Color _navy  = Color(0xFF091733);
  static const Color _green = Color(0xFF39EA2B);

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
    }
  }

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _openingCtrl.dispose();
    _middleCtrl.dispose();
    _closingCtrl.dispose();
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
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
        : generateDeckblatt(widget.profile, _deckblattTemplate);
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
      bool saved = false;
      try {
        final dir = Directory('/storage/emulated/0/Download');
        if (!await dir.exists()) await dir.create(recursive: true);
        await File('${dir.path}/$_pdfFilename').writeAsBytes(bytes);
        saved = true;
      } catch (_) {}

      if (!mounted) return;
      if (saved) {
        _snack(_savedMsg);
      } else {
        await Printing.sharePdf(bytes: bytes, filename: _pdfFilename);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: _navy,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
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
      backgroundColor: const Color(0xFFF7FAFF),
      body: Stack(
        children: [
          const _BackgroundGlow(),
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
          _NavBtn(
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
          _NavBtn(icon: Icons.home_rounded, onTap: _goHome),
        ],
      ),
    );
  }

  Widget _buildDocSection() {
    return _GlassSurface(
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
                  color: Color(0xFFEAFBE9),
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
              GestureDetector(
                onTap: _pickTemplate,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAFBE9),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _green.withOpacity(0.4)),
                  ),
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
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_isCoverLetter)
            _buildLetterEditor()
          else
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                height: 440,
                // Keyed to the Deckblatt template, so the preview
                // regenerates when the user picks a different one.
                child: PdfPreview(
                  key: ValueKey(_deckblattTemplate.name),
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
          GestureDetector(
            onTap: (_saving || (_isCoverLetter && _loadingTexts))
                ? null
                : _download,
            child: Container(
              width: double.infinity,
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                gradient: const LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [Color(0xFF081532), Color(0xFF07112B)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF07112B).withOpacity(0.30),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_saving)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: _green, strokeWidth: 2.5),
                    )
                  else
                    Icon(
                        _isCoverLetter
                            ? Icons.picture_as_pdf_rounded
                            : Icons.download_rounded,
                        color: Colors.white,
                        size: 18),
                  const SizedBox(width: 8),
                  Text(
                    _isCoverLetter ? _createPdfLabel : _downloadLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
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
          child: GestureDetector(
            onTap: (_loadingTexts || _saving) ? null : _regenerate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xFFEAFBE9),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _green.withOpacity(0.5)),
              ),
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
          TextField(
            controller: ctrl,
            enabled: !_loadingTexts && !_saving,
            minLines: minLines,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            // The letter itself is German, so the field is always LTR.
            textDirection: TextDirection.ltr,
            style: const TextStyle(color: _navy, fontSize: 13, height: 1.4),
            cursorColor: _green,
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white.withOpacity(0.85),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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

class _NavBtn extends StatelessWidget {
  static const Color _navy = Color(0xFF091733);

  final IconData icon;
  final VoidCallback onTap;

  const _NavBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: _GlassSurface(
        width: 44,
        height: 44,
        borderRadius: 14,
        padding: EdgeInsets.zero,
        child: Icon(icon, color: _navy, size: 20),
      ),
    );
  }
}

class _BackgroundGlow extends StatelessWidget {
  const _BackgroundGlow();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: const [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFF9FBFF), Color(0xFFEFF6FF), Color(0xFFF7FFF2)],
            ),
          ),
          child: SizedBox.expand(),
        ),
        Positioned(top: 70,   left: -42,  child: _Orb(size: 170, color: Color(0x6639EA2B))),
        Positioned(top: 135,  right: -65, child: _Orb(size: 170, color: Color(0x44FFB86B))),
        Positioned(bottom: 95, left: -60, child: _Orb(size: 210, color: Color(0x3339EA2B))),
      ],
    );
  }
}

class _Orb extends StatelessWidget {
  final double size;
  final Color color;
  const _Orb({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 35, sigmaY: 35),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}

class _GlassSurface extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;
  final double borderRadius;
  final EdgeInsetsGeometry padding;

  const _GlassSurface({
    required this.child,
    this.width,
    this.height,
    required this.borderRadius,
    required this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          width: width ?? double.infinity,
          height: height,
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.62),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: Colors.white.withOpacity(0.85), width: 1.2),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.18),
                  blurRadius: 24,
                  spreadRadius: 2,
                  offset: const Offset(0, 8)),
              BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2)),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}
