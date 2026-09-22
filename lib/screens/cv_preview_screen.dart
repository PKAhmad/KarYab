import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/document_template.dart';
import '../models/user_profile.dart';
import '../providers/language_provider.dart';
import '../services/analytics_service.dart';
import '../services/cv_pdf_generator.dart';
import '../services/tts_service.dart';
import '../utils/navigation_helpers.dart';
import '../widgets/document_template_picker.dart';
import 'questionnaire_screen.dart';

// ── Data class ────────────────────────────────────────────────────────────────

class _CvRow {
  final String label;
  final String value;
  const _CvRow(this.label, this.value);
}

// ── Screen ────────────────────────────────────────────────────────────────────

class CvPreviewScreen extends StatefulWidget {
  final UserProfile profile;
  // Which SharedPreferences key this screen instance persists its template
  // choice under. Defaults to the regular home-screen CV flow's key so every
  // existing caller (review_screen.dart, introduction_screen.dart) is
  // unaffected. The Ausbildung flow passes its own independent key
  // ('selected_cv_template_ausbildung') so the two never share state.
  final String templatePrefsKey;
  // True when embedded inside the "My CV" toggle screen
  // (introduction_screen.dart's _MyCvScreen), which supplies its own
  // shared header/background - this screen then renders only its body
  // content (edit bar + template row + preview + bottom buttons), no
  // duplicate header/background.
  final bool embedded;

  const CvPreviewScreen({
    super.key,
    required this.profile,
    this.templatePrefsKey = 'selected_cv_template_regular',
    this.embedded = false,
  });

  @override
  State<CvPreviewScreen> createState() => _CvPreviewScreenState();
}

class _CvPreviewScreenState extends State<CvPreviewScreen> {
  static const Color _navy  = Color(0xFF091733);
  static const Color _green = Color(0xFF39EA2B);
  static const Color _muted = Color(0xFF65738A);

  static String _countryFullName(String value) {
    const map = {
      'af': 'Afghanistan',
      'pk': 'Pakistan',
      'ir': 'Iran',
      'iq': 'Iraq',
      'sy': 'Syria',
      'so': 'Somalia',
      'er': 'Eritrea',
      'other': 'Other',
    };
    return map[value] ?? value;
  }

  Future<Uint8List>? _pdfFutureCache;
  Future<void>? _templateReadyFuture;
  DocumentTemplate _template = DocumentTemplate.atsBlue;
  bool _saving  = false;
  String _refName            = '';
  String _refPhone           = '';
  List<String> _loadedEmployers     = [];
  List<String> _loadedJobTitles     = [];
  List<String> _loadedJobDurations  = [];

  void _onSoundChange() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    AnalyticsService().logScreen('cv_preview');
    TtsService().addListener(_onSoundChange);
    _loadRefData();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureTemplateReady());
  }

  // ── Template selection ────────────────────────────────────────────────────
  // Shown before CV generation: the very first time (no persisted choice
  // yet) this pops the picker automatically; on later visits it just loads
  // the remembered choice silently. Either way it's resolved before
  // generateCv() ever runs — see _buildPdf().
  Future<void> _ensureTemplateReady() {
    return _templateReadyFuture ??= _initTemplate();
  }

  Future<void> _initTemplate() async {
    final prefs = await SharedPreferences.getInstance();
    final storedKey = prefs.getString(widget.templatePrefsKey);
    if (storedKey != null) {
      _template = DocumentTemplateInfo.fromStorageKey(storedKey);
      if (mounted) setState(() {});
      return;
    }
    if (!mounted) return;
    final chosen =
        await showDocumentTemplatePicker(context, current: _template);
    if (!mounted) return;
    _template = chosen;
    await saveSelectedDocumentTemplate(widget.templatePrefsKey, chosen);
    setState(() {});
  }

  Future<void> _changeTemplate() async {
    await _ensureTemplateReady();
    if (!mounted) return;
    final chosen =
        await showDocumentTemplatePicker(context, current: _template);
    if (!mounted || chosen == _template) return;
    setState(() {
      _template = chosen;
      _pdfFutureCache = null;
    });
    await saveSelectedDocumentTemplate(widget.templatePrefsKey, chosen);
  }

  Future<void> _loadRefData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('saved_profile');
      if (raw != null) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        if (mounted) {
          final empStr      = (map['previousEmployers'] as String?) ?? '';
          final titlesStr   = (map['previousJobTitles'] as String?) ?? '';
          final durationsStr = (map['previousJobDurations'] as String?) ?? '';
          setState(() {
            _refName            = (map['refName']  as String?) ?? '';
            _refPhone           = (map['refPhone'] as String?) ?? '';
            _loadedEmployers    = empStr.isEmpty
                ? []
                : empStr.split(',').where((s) => s.isNotEmpty).toList();
            _loadedJobTitles    =
                titlesStr.isEmpty ? [] : titlesStr.split(',');
            _loadedJobDurations =
                durationsStr.isEmpty ? [] : durationsStr.split(',');
          });
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    TtsService().removeListener(_onSoundChange);
    super.dispose();
  }

  // ── German key-label maps ─────────────────────────────────────────────────

  static const Map<String, String> _skillDe = {
    'lifting':        'Schwere Lasten tragen',
    'cooking':        'Kochen',
    'driving':        'Fahren / Transport',
    'cleaning':       'Reinigung',
    'fixing':         'Reparatur / Instandhaltung',
    'packing':        'Packen / Lagerhaltung',
    'security':       'Sicherheitsdienst',
    'forklift':       'Gabelstapler',
    'farming':        'Landwirtschaft',
    'sales':          'Verkauf / Handel',
    'sewing':         'Nähen / Schneiderei',
    'construction':   'Bauarbeiten',
    'mobile_repair':  'Handy-Reparatur',
    'amazon_packing': 'Lagerlogistik',
    'dhl':            'Paketdienst / Auslieferung',
  };

  static const Map<String, String> _workExpDe = {
    'more2': 'Mehr als 2 Jahre Erfahrung',
    'less2': 'Weniger als 2 Jahre Erfahrung',
    'small': 'Nur einfache Tätigkeiten',
    'never': 'Keine Berufserfahrung',
  };

  static const Map<String, String> _workTypeDe = {
    'construction': 'Baugewerbe',
    'cleaning':     'Gebäudereinigung',
    'kitchen':      'Küche / Gastronomie',
    'driving':      'Fahrertätigkeit',
  };

  static const Map<String, String> _toolsDe = {
    'power_tools':   'Elektrowerkzeuge',
    'kitchen_equip': 'Küchengeräte',
    'tractor':       'Traktor / Schwere Fahrzeuge',
    'no_tools':      'Keine Werkzeugerfahrung',
  };

  static const Map<String, String> _licenseDe = {
    'german_license':  'Deutsches Führerschein (vorhanden)',
    'foreign_license': 'Ausländisches Führerschein',
    'want_license':    'Kein Führerschein (möchte erwerben)',
    'no_license':      'Kein Führerschein',
  };

  static const Map<String, String> _langDe = {
    'pashto':  'Paschtu',
    'dari':    'Dari / Farsi',
    'urdu':    'Urdu',
    'arabic':  'Arabisch',
    'english': 'Englisch',
    'german':  'Deutsch',
    'other':   'Andere',
  };

  static const Map<String, String> _availDe = {
    'fulltime': 'Vollzeit (40 Std./Woche)',
    'parttime': 'Teilzeit (20 Std./Woche)',
    'flexible': 'Flexibel',
    'weekends': 'Nur Wochenende',
  };

  static const Map<String, String> _startDe = {
    'immediately': 'Sofort',
    'two_weeks':   'Innerhalb von 2 Wochen',
    'one_month':   'Innerhalb eines Monats',
    'unsure':      'Noch nicht festgelegt',
  };

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _r(String? key, Map<String, String> map) {
    if (key == null || key.isEmpty) return '—';
    return map[key] ?? key;
  }

  String get _skillsText {
    final s = widget.profile.skill;
    if (s == null || s.isEmpty) return '—';
    return s.split(',').map((k) => _r(k.trim(), _skillDe)).join(', ');
  }

  String get _langsText {
    // Educated users (Task 4): each language shown with its CEFR level,
    // e.g. "Deutsch – B1". Falls back to the old comma-joined key list for
    // uneducated users / older saved profiles that never populated
    // languageProficiency.
    final prof = widget.profile.languageProficiency;
    if (prof.isNotEmpty) {
      return prof.entries.map((e) => '${e.key} – ${e.value}').join('\n');
    }
    final l = widget.profile.languages;
    if (l.isEmpty) return '—';
    return l.map((k) => _r(k.trim(), _langDe)).join(', ');
  }

  List<_CvRow> get _personalRows {
    final p = widget.profile;
    return [
      _CvRow('Geburtsdatum', p.dobFormatted),
      if (p.country != null && p.country!.isNotEmpty)
        _CvRow('Geburtsort', _countryFullName(p.country!)),
      if (p.country != null && p.country!.isNotEmpty)
        _CvRow('Nationalität', _countryFullName(p.country!)),
    ];
  }

  List<String> get _effectiveEmployers {
    final fromProfile = widget.profile.previousEmployers;
    return fromProfile.isNotEmpty ? fromProfile : _loadedEmployers;
  }

  List<String> get _effectiveJobTitles {
    final fromProfile = widget.profile.previousJobTitles;
    return fromProfile.isNotEmpty ? fromProfile : _loadedJobTitles;
  }

  List<String> get _effectiveJobDurations {
    final fromProfile = widget.profile.previousJobDurations;
    return fromProfile.isNotEmpty ? fromProfile : _loadedJobDurations;
  }

  // FIX 3 — "None/No" style selections are recorded for the app's own
  // logic (e.g. skipping the work-type question) but must never appear as
  // a negative line item on the generated CV. Covers every known
  // negative/absence sentinel used across the questionnaire's _Opt id
  // values, not just tools/license.
  static const Set<String> _negativeSentinels = {
    'no_tools', 'no_license', 'never', 'no_ref',
  };

  bool _isNegative(String? value) =>
      value != null && _negativeSentinels.contains(value);

  // Task 3: each previous job as its own line item — "[Job Title] –
  // [Company]" then the duration on its own line if captured — in the
  // order they were entered, which the questionnaire instructs the user to
  // fill most-recent-first (no explicit per-entry dates are captured, so
  // entry order is the recency proxy).
  List<_CvRow> get _experienceRows {
    final p = widget.profile;
    final rows = <_CvRow>[
      if (p.workType != null)
        _CvRow('Tätigkeitsbereich', _r(p.workType, _workTypeDe)),
      if (p.workExperience != null && !_isNegative(p.workExperience))
        _CvRow('Berufserfahrung', _r(p.workExperience, _workExpDe)),
    ];
    final employers  = _effectiveEmployers;
    final titles      = _effectiveJobTitles;
    final durations   = _effectiveJobDurations;
    for (var i = 0; i < employers.length; i++) {
      final title    = i < titles.length ? titles[i] : '';
      final duration = i < durations.length ? durations[i] : '';
      final headline = title.isNotEmpty ? '$title – ${employers[i]}' : employers[i];
      final value    = duration.isNotEmpty ? '$headline\n$duration' : headline;
      rows.add(_CvRow('Station ${i + 1}', value));
    }
    return rows;
  }

  List<_CvRow> get _skillRows {
    final p = widget.profile;
    return [
      if (p.skill != null && p.skill!.isNotEmpty)
        _CvRow('Tätigkeiten', _skillsText),
      _CvRow('Sprachen', _langsText),
      if (p.tools != null && !_isNegative(p.tools))
        _CvRow('Werkzeugkenntnisse', _r(p.tools, _toolsDe)),
      if (p.drivingLicense != null && !_isNegative(p.drivingLicense))
        _CvRow('Führerschein', _r(p.drivingLicense, _licenseDe)),
    ];
  }

  List<_CvRow> get _availabilityRows {
    final p = widget.profile;
    return [
      if (p.startDate != null)
        _CvRow('Arbeitsbeginn', _r(p.startDate, _startDe)),
      if (p.availability != null)
        _CvRow('Arbeitszeit', _r(p.availability, _availDe)),
    ];
  }

  // ── PDF Builder ───────────────────────────────────────────────────────────
  // Template-aware: waits for the template picker/preference to resolve
  // (see _ensureTemplateReady), then delegates to the shared generator so
  // every visual template stays in one place (services/cv_pdf_generator.dart)
  // instead of duplicated per screen.

  UserProfile get _effectiveProfile => widget.profile.copyWith(
        previousEmployers: _effectiveEmployers,
        previousJobTitles: _effectiveJobTitles,
        previousJobDurations: _effectiveJobDurations,
        refName: _refName.isNotEmpty ? _refName : null,
        refPhone: _refPhone.isNotEmpty ? _refPhone : null,
      );

  Future<Uint8List> _getPdf() {
    return _pdfFutureCache ??= _buildPdf();
  }

  Future<Uint8List> _buildPdf() async {
    await _ensureTemplateReady();
    return generateCv(_effectiveProfile, _template);
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  String get _pdfFilename {
    final name = widget.profile.fullName.replaceAll(' ', '_');
    return 'Lebenslauf_$name.pdf';
  }

  Future<void> _download() async {
    // TEMP DEBUG (task: "still unresolved download bug") — remove once
    // confirmed fixed on-device.
    debugPrint('[JobCV-DL] _download() tapped, _saving=$_saving');
    if (_saving) return;
    setState(() => _saving = true);
    try {
      // Matches ausbildung_document_preview_screen.dart's _download(): generate
      // fresh bytes directly rather than going through _getPdf()/_pdfFutureCache,
      // so a single failed attempt can't leave the button permanently stuck
      // replaying the same rejected cached future on every subsequent tap.
      await _ensureTemplateReady();
      debugPrint('[JobCV-DL] template ready ($_template), calling generateCv()');
      final bytes = await generateCv(_effectiveProfile, _template);
      debugPrint('[JobCV-DL] generateCv() returned ${bytes.length} bytes, '
          'attempting direct write');
      bool saved = false;
      try {
        final dir = Directory('/storage/emulated/0/Download');
        if (!await dir.exists()) await dir.create(recursive: true);
        await File('${dir.path}/$_pdfFilename').writeAsBytes(bytes);
        saved = true;
        debugPrint('[JobCV-DL] direct write SUCCEEDED: ${dir.path}/$_pdfFilename');
      } catch (e) {
        debugPrint('[JobCV-DL] direct write FAILED: $e');
      }

      if (!mounted) return;
      if (saved) {
        debugPrint('[JobCV-DL] saved=true -> showing saved-to-Downloads snackbar');
        _saveCvStatus();
        AnalyticsService().logCVDownloaded();
        AnalyticsService().logCVCreated();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'CV saved to Downloads',
              style: TextStyle(
                color: Color(0xFF091733),
                fontWeight: FontWeight.w600,
              ),
            ),
            backgroundColor: _green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      } else {
        debugPrint('[JobCV-DL] saved=false -> falling back to Printing.sharePdf()');
        await Printing.sharePdf(bytes: bytes, filename: _pdfFilename);
        _saveCvStatus();
        AnalyticsService().logCVDownloaded();
        AnalyticsService().logCVCreated();
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _share() async {
    final bytes = await _getPdf();
    await Printing.sharePdf(bytes: bytes, filename: _pdfFilename);
  }

  void _goHome() {
    final lang = context.read<LanguageProvider>().language;
    goHomeToIntroduction(context, language: lang, voiceMode: false);
  }

  // Pushes a fresh questionnaire instance in edit mode, mirroring
  // ausbildung_document_preview_screen.dart's _editAnswers() - reopens
  // QuestionnaireScreen with isEditMode: true so it reloads the previously
  // saved answers instead of starting blank.
  Future<void> _editAnswers() async {
    final lang = context.read<LanguageProvider>().language;
    final prefs = await SharedPreferences.getInstance();
    final voiceMode = prefs.getBool('voice_mode') ?? false;
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QuestionnaireScreen(
          language: lang,
          voiceMode: voiceMode,
          isEditMode: true,
        ),
      ),
    );
  }

  String get _editLabel {
    final lang = context.read<LanguageProvider>().language;
    switch (lang) {
      case 'ps': return 'ځوابونه سمول';
      case 'fa': return 'ویرایش پاسخ‌ها';
      default:   return 'Edit answers';
    }
  }

  Future<void> _saveCvStatus() async {
    try {
      print('DEBUG saving cv_created = true');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('cv_created', true);
      await prefs.setString(
          'user_name', widget.profile.fullName.split(' ').first);
      await prefs.setString(
          'questionnaire_full_name', widget.profile.fullName);
      print('DEBUG cv_created saved successfully');
    } catch (_) {}
  }

  Future<void> _findJobs(String lang) async {
    try {
      final bytes = await _getPdf();
      final tempDir = await getTemporaryDirectory();
      final cleanName = widget.profile.fullName
          .replaceAll(' ', '_')
          .replaceAll(RegExp(r'[^\w]'), '');
      final tempCvPath =
          '${tempDir.path}/Lebenslauf_${cleanName.isEmpty ? 'Bewerber' : cleanName}.pdf';
      final tempFile = File(tempCvPath);
      await tempFile.writeAsBytes(bytes);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('temp_cv_path', tempFile.path);
      await prefs.setString(
          'temp_cv_timestamp', DateTime.now().toIso8601String());
      await prefs.setBool('cv_created', true);
      await prefs.setString(
          'questionnaire_full_name', widget.profile.fullName);
    } catch (_) {}
    if (!mounted) return;
    Navigator.pushNamed(context, '/jobfinder', arguments: lang);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final lang        = context.watch<LanguageProvider>().language;
    final showSpeaker = lang == 'ps' || lang == 'fa';
    final body = SafeArea(
      top: !widget.embedded,
      child: Column(
        children: [
          if (!widget.embedded) _buildHeader(lang),
          const SizedBox(height: 4),
          _buildEditBar(),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildTemplateRow(),
                  const SizedBox(height: 8),
                  _buildCvPreview(),
                ],
              ),
            ),
          ),
          _buildBottomButtons(lang, showSpeaker),
        ],
      ),
    );

    if (widget.embedded) {
      return body;
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFF),
      body: Stack(
        children: [
          const _BackgroundGlow(),
          body,
        ],
      ),
    );
  }

  Widget _buildEditBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        onTap: _editAnswers,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFEAFBE9),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _green.withOpacity(0.5), width: 1.2),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.edit_rounded, color: Color(0xFF0E7A20), size: 18),
              const SizedBox(width: 8),
              Text(
                _editLabel,
                style: const TextStyle(
                  color: Color(0xFF0E7A20),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader(String lang) {
    final title = lang == 'ps' ? ' CV ستاسو'
        : lang == 'fa' ? 'CV شما'
        : 'Your CV';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          _NavBtn(
            icon: Icons.arrow_back_ios_new_rounded,
            onTap: () => Navigator.pop(context),
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _navy,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          _NavBtn(icon: Icons.home_rounded, onTap: _goHome),
          const SizedBox(width: 8),
          _NavBtn(
            icon: TtsService().soundEnabled
                ? Icons.volume_up_rounded
                : Icons.volume_off_rounded,
            active: TtsService().soundEnabled,
            hintPulse: TtsService().hintPulseActive,
            onTap: () {
              TtsService().toggleSound();
              setState(() {});
            },
          ),
        ],
      ),
    );
  }

  // ── Template row ──────────────────────────────────────────────────────────
  // The on-screen card below is a rough approximation of the CV content
  // regardless of template (unchanged) — only the generated PDF (download/
  // share/find jobs) actually renders the chosen template's design.

  Widget _buildTemplateRow() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2, left: 4, right: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Template: ${_template.displayName}',
            style: const TextStyle(
              color: _muted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          GestureDetector(
            onTap: _changeTemplate,
            child: const Text(
              'Change',
              style: TextStyle(
                color: _green,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                decoration: TextDecoration.underline,
                decorationColor: _green,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Live template preview ─────────────────────────────────────────────────
  // Matches ausbildung_document_preview_screen.dart's _buildCvSection(): a
  // real PdfPreview rendering the actual generated PDF for the chosen
  // template, instead of an on-screen approximation that can drift from what
  // the download/share/find-jobs actions actually produce.

  Widget _buildCvPreview() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 440,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: Colors.white.withOpacity(0.9), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.18),
              blurRadius: 24,
              spreadRadius: 2,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: PdfPreview(
          key: ValueKey(_template),
          build: (PdfPageFormat format) =>
              generateCv(_effectiveProfile, _template),
          canChangeOrientation: false,
          canChangePageFormat: false,
          canDebug: false,
          pdfFileName: _pdfFilename,
          loadingWidget: const Center(
            child: CircularProgressIndicator(color: _green),
          ),
        ),
      ),
    );
  }

  // ── CV card (document) — superseded by _buildCvPreview() above; kept
  // unused/unreferenced rather than deleted, see report for this task.
  // ────────────────────────────────────────────────────────────────────────

  Widget _buildCvCard() {
    final p = widget.profile;
    final profession = p.workType != null
        ? _r(p.workType, _workTypeDe)
        : _skillsText != '—' ? _skillsText : null;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: Colors.white.withOpacity(0.9), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 24,
            spreadRadius: 2,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 8,
            spreadRadius: 0,
            offset: const Offset(0, 2),
          ),
          BoxShadow(
            color: Colors.white.withOpacity(0.9),
            blurRadius: 0,
            spreadRadius: 0,
            offset: const Offset(-2, -2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Two-column header ─────────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left: photo + name + profession
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (p.photoPath != null) ...[
                      ClipOval(
                        child: Image.file(
                          File(p.photoPath!),
                          width: 70,
                          height: 70,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Text(
                      p.fullName,
                      style: const TextStyle(
                        color: _navy,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (profession != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        profession,
                        style: const TextStyle(
                          color: _muted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // Right: contact info
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (p.street.isNotEmpty || p.city.isNotEmpty)
                    _contactLine(p.fullAddress),
                  if (p.phone.isNotEmpty)
                    _contactLine(p.phone),
                  if (p.email.isNotEmpty)
                    _contactLine(p.email),
                ],
              ),
            ],
          ),

          const SizedBox(height: 14),
          Container(height: 2, color: _green),
          const SizedBox(height: 16),

          // ── CV sections ───────────────────────────────────────────────────
          _buildSection('PERSÖNLICHE INFORMATIONEN', _personalRows),
          if (_experienceRows.isNotEmpty)
            _buildSection('BERUFSERFAHRUNG', _experienceRows),
          _buildSection('FÄHIGKEITEN', _skillRows),
          if (_availabilityRows.isNotEmpty)
            _buildSection('VERFÜGBARKEIT', _availabilityRows),
          if (_refName.isNotEmpty)
            _buildSection('REFERENZ', [
              _CvRow('Name', _refName),
              if (_refPhone.isNotEmpty) _CvRow('Telefon', _refPhone),
            ]),

          const SizedBox(height: 8),
          const Center(
            child: Text(
              'Erstellt mit KarYab – Die Job-App für Geflüchtete',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF999999),
                fontSize: 9,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _contactLine(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Text(
        text,
        textAlign: TextAlign.right,
        style: const TextStyle(color: _muted, fontSize: 12),
      ),
    );
  }

  Widget _buildSection(String title, List<_CvRow> rows) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.only(left: 8),
          decoration: const BoxDecoration(
            border: Border(
              left: BorderSide(color: _green, width: 3),
            ),
          ),
          child: Text(
            title,
            style: const TextStyle(
              color: _navy,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 8),
        ...rows.map(
          (r) => Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 115,
                  child: Text(
                    '${r.label}:',
                    style: const TextStyle(
                      color: Color(0xFF444444),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    r.value,
                    style: const TextStyle(
                      color: Colors.black87,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
      ],
    );
  }

  // ── Bottom buttons (fixed) ────────────────────────────────────────────────

  Widget _buildBottomButtons(String lang, bool showSpeaker) {
    final downloadLabel = lang == 'ps' ? 'ډاونلوډ کړئ CV '
        : lang == 'fa' ? 'دانلود CV'
        : 'Download CV (PDF)';
    final jobsLabel = lang == 'ps' ? 'نژدی کارونه وګورئ'
        : lang == 'fa' ? 'کارها را پیدا کنید'
        : 'Find Jobs Now';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.85),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.9), width: 1.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Download PDF button — matches
              // ausbildung_document_preview_screen.dart's download button
              // exactly (height 52, radius 26, icon/text sizing).
              GestureDetector(
                onTap: _saving ? null : _download,
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
                            color: _green,
                            strokeWidth: 2.5,
                          ),
                        )
                      else
                        const Icon(Icons.download_rounded,
                            color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        downloadLabel,
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
              const SizedBox(height: 10),

              // Find Jobs button
              Stack(
                children: [
                  GestureDetector(
                    onTap: () => _findJobs(lang),
                    child: Container(
                      width: double.infinity,
                      height: 56,
                      decoration: BoxDecoration(
                        color: _green,
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: _green.withOpacity(0.35),
                            blurRadius: 22,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.search_rounded,
                              color: _navy, size: 20),
                          const SizedBox(width: 10),
                          Text(
                            jobsLabel,
                            style: const TextStyle(
                              color: _navy,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (showSpeaker)
                    Positioned(
                      right: 16,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => TtsService().speak(
                            lang == 'ps'
                                ? 'نژدی کارونه وګورئ'
                                : 'کارها را پیدا کنید',
                            lang,
                          ),
                          child: const Icon(Icons.volume_up_rounded,
                              color: _navy, size: 18),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Nav button (glass surface, matches questionnaire_screen pattern)
// ─────────────────────────────────────────────────────────────────────────────

class _NavBtn extends StatelessWidget {
  static const Color _navy  = Color(0xFF091733);
  static const Color _green = Color(0xFF39EA2B);

  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  final bool hintPulse;

  const _NavBtn({
    required this.icon,
    required this.onTap,
    this.active = false,
    this.hintPulse = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        decoration: BoxDecoration(
          color: hintPulse
              ? const Color(0xFF091733).withOpacity(0.85)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: _GlassSurface(
          width: 44,
          height: 44,
          borderRadius: 14,
          padding: EdgeInsets.zero,
          shadowOpacity: 0.08,
          child: Icon(icon, color: active ? _green : _navy, size: 20),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Background glow — copied from welcome_screen.dart
// ─────────────────────────────────────────────────────────────────────────────

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
              colors: [
                Color(0xFFF9FBFF),
                Color(0xFFEFF6FF),
                Color(0xFFF7FFF2),
              ],
            ),
          ),
          child: SizedBox.expand(),
        ),
        Positioned(top: 70,    left: -42,  child: _Orb(size: 170, color: Color(0x6639EA2B))),
        Positioned(top: 135,   right: -65, child: _Orb(size: 170, color: Color(0x44FFB86B))),
        Positioned(bottom: 95, left: -60,  child: _Orb(size: 210, color: Color(0x3339EA2B))),
        Positioned(bottom: -30,right: 14,  child: _Orb(size: 145, color: Color(0x5539EA2B))),
        Positioned(top: 20,    left: 30,   child: _Orb(size: 170, color: Color(0x30FF8FA3))),
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

// ─────────────────────────────────────────────────────────────────────────────
// Glass surface — copied from welcome_screen.dart
// ─────────────────────────────────────────────────────────────────────────────

class _GlassSurface extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final double shadowOpacity;

  const _GlassSurface({
    required this.child,
    this.width,
    this.height,
    required this.borderRadius,
    required this.padding,
    this.shadowOpacity = 0.09,
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
            border: Border.all(
                color: Colors.white.withOpacity(0.85), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.18),
                blurRadius: 24,
                spreadRadius: 2,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 8,
                spreadRadius: 0,
                offset: const Offset(0, 2),
              ),
              BoxShadow(
                color: Colors.white.withOpacity(0.9),
                blurRadius: 0,
                spreadRadius: 0,
                offset: const Offset(-2, -2),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}
