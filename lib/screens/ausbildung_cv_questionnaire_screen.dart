import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_profile.dart';
import '../services/analytics_service.dart';
import '../services/tts_service.dart';
import 'ausbildung_document_preview_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Ausbildung CV Questionnaire
//
// Five sections (fixed order): work experience, general/vocational education,
// languages, IT skills, ESCO-powered occupation skills. Persists additively
// into the same 'saved_profile' SharedPreferences map used by
// questionnaire_screen.dart / schulabschluss_screen.dart, so nothing already
// stored there is disturbed. Not yet wired into navigation from
// ausbildung_screen.dart or main.dart (out of scope for this change) - this
// screen is self-contained and ready to be pushed from anywhere once wired.
// ─────────────────────────────────────────────────────────────────────────────

class AusbildungCvQuestionnaireScreen extends StatefulWidget {
  final String language;
  final bool voiceMode;
  // False when reached via a fresh "Create CV" flow (ChooseCvTypeScreen) -
  // the shared/own-answer prefill (_loadExisting) is skipped so the form
  // starts empty. True when reached via "Edit answers" from the Ausbildung
  // document preview screen - prefill runs exactly as before.
  final bool isEditMode;

  const AusbildungCvQuestionnaireScreen({
    super.key,
    required this.language,
    this.voiceMode = false,
    this.isEditMode = false,
  });

  @override
  State<AusbildungCvQuestionnaireScreen> createState() =>
      _AusbildungCvQuestionnaireScreenState();
}

class _AusbildungCvQuestionnaireScreenState
    extends State<AusbildungCvQuestionnaireScreen> {
  static const Color _navy  = Color(0xFF091733);
  static const Color _green = Color(0xFF39EA2B);
  static const Color _muted = Color(0xFF65738A);

  static const int _kMaxWorkEntries = 5;
  static const int _kMaxEduEntries  = 5;
  static const int _kMaxItSkills    = 5;
  static const int _kMaxEscoSkills  = 5;

  // School/education type dropdown options - German term with the English
  // term alongside on the same line, e.g. "Hauptschule (Secondary School)".
  static const List<String> _kSchoolTypes = [
    'Hauptschule (Secondary School)',
    'Realschule (Intermediate School)',
    'Gymnasium (Grammar School)',
    'Gesamtschule (Comprehensive School)',
    'Ausbildung (Vocational Training)',
    'Universität / University',
    'Sprachkurs / Language Course',
    'Sonstiges (Other)',
  ];

  // Fixed IT skill checklist - literal product/term names, not translated.
  static const List<String> _kItSkillLabels = [
    'Microsoft Word',
    'Microsoft Excel',
    'Microsoft PowerPoint',
    'Microsoft Outlook',
    'Microsoft Teams',
    'Grundlegende PC-Kenntnisse',
    'Internetrecherche',
  ];

  static const List<String> _kCefrLevels = ['A1', 'A2', 'B1', 'B2', 'C1', 'C2'];

  // key, German display name, Pashto label, Dari label - same set and same
  // proficiency-map key convention (German name) as questionnaire_screen.dart
  // so data saved here is directly compatible with the main CV flow.
  static const List<List<String>> _kLangs = [
    ['pashto',  'Paschtu',    'پښتو',      'پشتو'],
    ['dari',    'Dari/Farsi', 'دري/فارسي', 'دری/فارسی'],
    ['urdu',    'Urdu',       'اردو',      'اردو'],
    ['arabic',  'Arabisch',   'عربي',      'عربی'],
    ['english', 'Englisch',   'انګليسي',   'انگلیسی'],
    ['german',  'Deutsch',    'جرمني',     'آلمانی'],
  ];

  late String _lang;
  late bool _voiceMode;
  bool _saving = false;

  // ── Section 1 - Berufserfahrung und Praktika (shared with
  // questionnaire_screen.dart) ────────────────────────────────────────────────
  final List<_WorkExpEntry> _workEntries = [_WorkExpEntry()];
  bool _workEntriesPrefilled = false;

  // ── Section 2 - Allgemeine und berufliche Bildung ───────────────────────────
  final List<_EduEntry> _eduEntries = [_EduEntry()];
  bool _eduPrefilled = false;

  // ── Section 3 - Sprachkenntnisse ────────────────────────────────────────────
  List<String> _languages = [];
  Map<String, String> _languageProficiency = {};
  bool _langPrefilled = false;
  bool _langOtherOpen = false;
  final _langOtherCtrl = TextEditingController();

  // ── Section 4 - IT-Kenntnisse (shared with questionnaire_screen.dart) ──────
  final Set<String> _itSkillsSelected = {};
  final _itSkillsCustomCtrl = TextEditingController();
  bool _itSkillsPrefilled = false;

  // ── Section 5 - Skills (ESCO) ───────────────────────────────────────────────
  final _escoSearchCtrl = TextEditingController();
  bool _escoLoading = false;
  bool _escoDetailLoading = false;
  bool _escoError = false;
  List<_EscoOccupation> _escoResults = [];
  _EscoOccupation? _selectedOccupation;
  List<_EscoSkill> _essentialSkills = [];
  List<_EscoSkill> _optionalSkills = [];
  bool _skillsDropdownOpen = false;
  final Set<String> _selectedSkills = {};
  final _customSkillCtrl = TextEditingController();
  bool _escoPrefilled = false;

  bool get _isEducated  => !_voiceMode;
  bool get _isRtl       => _lang == 'ps' || _lang == 'fa';
  bool get _showSpeaker => !_isEducated && _isRtl;

  @override
  void initState() {
    super.initState();
    _lang = widget.language;
    _voiceMode = widget.voiceMode;
    AnalyticsService().logScreen('ausbildung_cv_questionnaire');
    TtsService().addListener(_onSoundChange);
    // Only reload previous answers in edit mode - a fresh "Create CV" pass
    // (isEditMode: false, the default) starts blank except for the shared
    // personal-data fields PersonalDataScreen already collected.
    if (widget.isEditMode) {
      _loadExisting();
    }
  }

  void _onSoundChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    TtsService().removeListener(_onSoundChange);
    TtsService().stop();
    for (final e in _workEntries) {
      e.dispose();
    }
    for (final e in _eduEntries) {
      e.dispose();
    }
    _langOtherCtrl.dispose();
    _itSkillsCustomCtrl.dispose();
    _escoSearchCtrl.dispose();
    _customSkillCtrl.dispose();
    super.dispose();
  }

  void _speak(String text) => TtsService().speak(text, _lang);

  // ─────────────────────────────────────────────────────────────────────────────
  // Persistence - additive merge into 'saved_profile', same pattern as
  // schulabschluss_screen.dart._persist().
  // ─────────────────────────────────────────────────────────────────────────────

  static Map<String, String> _decodeProficiency(String raw) {
    if (raw.isEmpty) return {};
    final result = <String, String>{};
    for (final pair in raw.split(',')) {
      final idx = pair.indexOf(':');
      if (idx == -1) continue;
      final lang = pair.substring(0, idx);
      final level = pair.substring(idx + 1);
      if (lang.isNotEmpty && level.isNotEmpty) result[lang] = level;
    }
    return result;
  }

  static List<String> _splitCsv(String raw) =>
      raw.isEmpty ? const [] : raw.split(',');

  // Duration strings are '$from - $until' (or a single side), 'heute'
  // meaning "present" - same convention as _WorkExpEntry.duration and
  // questionnaire_screen.dart's _JobEntry.duration, so entries saved by
  // either questionnaire round-trip correctly through the other.
  static void _applyDuration(_WorkExpEntry e, String duration) {
    if (duration.isEmpty) return;
    final parts = duration.split(' - ');
    if (parts.length == 2) {
      e.fromYear = int.tryParse(parts[0].trim());
      final until = parts[1].trim();
      e.untilYear = until == 'heute' ? 'present' : until;
    } else {
      final v = parts.first.trim();
      if (v == 'heute') {
        e.untilYear = 'present';
      } else {
        e.fromYear = int.tryParse(v);
      }
    }
  }

  // Same convention as _applyDuration, applied to an education entry instead
  // of a work-experience one - kept separate since the two entry classes
  // don't share a common type.
  static void _applyEduDuration(_EduEntry e, String duration) {
    if (duration.isEmpty) return;
    final parts = duration.split(' - ');
    if (parts.length == 2) {
      e.fromYear = int.tryParse(parts[0].trim());
      final until = parts[1].trim();
      e.untilYear = until == 'heute' ? 'present' : until;
    } else {
      final v = parts.first.trim();
      if (v == 'heute') {
        e.untilYear = 'present';
      } else {
        e.fromYear = int.tryParse(v);
      }
    }
  }

  Future<void> _loadExisting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('saved_profile');
      if (raw == null || raw.isEmpty) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final langsRaw = map['languages'] as String? ?? '';
      final profRaw  = map['languageProficiency'] as String? ?? '';
      final langs = langsRaw.isEmpty ? <String>[] : langsRaw.split(',');
      final prof  = _decodeProficiency(profRaw);
      if (langs.isNotEmpty || prof.isNotEmpty) {
        if (!mounted) return;
        setState(() {
          _languages = langs;
          _languageProficiency = prof;
          _langPrefilled = true;
        });
      }

      // Berufserfahrung und Praktika - shared with questionnaire_screen.dart
      // via previousEmployers/previousJobTitles/previousJobDurations (same
      // keys UserProfile.fromMap() already reads) plus sharedWorkOrts/Types.
      final companies = _splitCsv(map['previousEmployers'] as String? ?? '');
      final roles      = _splitCsv(map['previousJobTitles'] as String? ?? '');
      final durations  = _splitCsv(map['previousJobDurations'] as String? ?? '');
      final orts       = _splitCsv(map['sharedWorkOrts'] as String? ?? '');
      final types       = _splitCsv(map['sharedWorkTypes'] as String? ?? '');
      if (companies.isNotEmpty) {
        final entries = <_WorkExpEntry>[];
        for (var i = 0; i < companies.length; i++) {
          final e = _WorkExpEntry();
          e.companyCtrl.text = companies[i];
          e.roleCtrl.text = i < roles.length ? roles[i] : '';
          e.ortCtrl.text = i < orts.length ? orts[i] : '';
          e.entryType = i < types.length && types[i].isNotEmpty ? types[i] : null;
          if (i < durations.length) _applyDuration(e, durations[i]);
          entries.add(e);
        }
        if (!mounted) return;
        setState(() {
          for (final old in _workEntries) {
            old.dispose();
          }
          _workEntries
            ..clear()
            ..addAll(entries);
          _workEntriesPrefilled = true;
        });
      }

      // Allgemeine und berufliche Bildung - Ausbildung-only keys (written by
      // _continueToPreview below), same additive-merge/round-trip shape as
      // the work-experience block above.
      final eduInstitutions =
          _splitCsv(map['ausbildungEduInstitutions'] as String? ?? '');
      final eduOrts    = _splitCsv(map['ausbildungEduOrts'] as String? ?? '');
      final eduTypes   = _splitCsv(map['ausbildungEduTypes'] as String? ?? '');
      final eduAbschluesse =
          _splitCsv(map['ausbildungEduAbschluss'] as String? ?? '');
      final eduDurations =
          _splitCsv(map['ausbildungEduDurations'] as String? ?? '');
      final eduGrades = _splitCsv(map['ausbildungEduGrades'] as String? ?? '');
      if (eduInstitutions.isNotEmpty) {
        final entries = <_EduEntry>[];
        for (var i = 0; i < eduInstitutions.length; i++) {
          final e = _EduEntry();
          e.institutionCtrl.text = eduInstitutions[i];
          e.ortCtrl.text = i < eduOrts.length ? eduOrts[i] : '';
          e.schoolType =
              i < eduTypes.length && eduTypes[i].isNotEmpty ? eduTypes[i] : null;
          e.abschlussCtrl.text = i < eduAbschluesse.length ? eduAbschluesse[i] : '';
          if (i < eduDurations.length) _applyEduDuration(e, eduDurations[i]);
          if (i < eduGrades.length && eduGrades[i].isNotEmpty) {
            e.gradeCtrl.text = eduGrades[i];
            e.showGrades = true;
          }
          entries.add(e);
        }
        if (!mounted) return;
        setState(() {
          for (final old in _eduEntries) {
            old.dispose();
          }
          _eduEntries
            ..clear()
            ..addAll(entries);
          _eduPrefilled = true;
        });
      }

      // IT-Kenntnisse - shared with questionnaire_screen.dart via
      // 'sharedItSkills'.
      final itSkills = _splitCsv(map['sharedItSkills'] as String? ?? '');
      if (itSkills.isNotEmpty) {
        if (!mounted) return;
        setState(() {
          _itSkillsSelected
              .addAll(itSkills.where((s) => _kItSkillLabels.contains(s)));
          _itSkillsPrefilled = true;
        });
      }

      // Skills (ESCO) - restores the selected skill chips immediately, and
      // (if a target occupation with a URI was saved) re-selects that
      // occupation so its essential/optional skill checklist refetches from
      // ESCO exactly like a fresh selection would via _selectOccupation.
      final escoSkills = _splitCsv(map['ausbildungEscoSkills'] as String? ?? '');
      final targetOccTitle =
          (map['ausbildungTargetOccupation'] as String? ?? '').trim();
      final targetOccUri =
          (map['ausbildungTargetOccupationUri'] as String? ?? '').trim();
      if (escoSkills.isNotEmpty || targetOccTitle.isNotEmpty) {
        if (!mounted) return;
        setState(() {
          _selectedSkills.addAll(escoSkills);
          if (targetOccTitle.isNotEmpty) _escoSearchCtrl.text = targetOccTitle;
          _escoPrefilled = true;
        });
        if (targetOccUri.isNotEmpty) {
          _selectOccupation(_EscoOccupation(uri: targetOccUri, title: targetOccTitle));
        }
      }
    } catch (_) {}
  }

  // Persists into 'saved_profile' (same additive-merge pattern as before),
  // then hands off into AusbildungDocumentPreviewScreen - mirroring how
  // questionnaire_screen.dart's _createCv() persists the profile and
  // immediately navigates into the next step (ReviewScreen there;
  // AusbildungDocumentPreviewScreen here, the Ausbildung equivalent).
  // Navigation always happens once persistence has been attempted, even if
  // the SharedPreferences read/write itself fails, matching
  // schulabschluss_screen.dart's _persist()/_goToPreview() pattern.
  Future<void> _continueToPreview() async {
    setState(() => _saving = true);

    final companies = <String>[];
    final roles = <String>[];
    final workOrts = <String>[];
    final workDurations = <String>[];
    final workTypes = <String>[];
    for (final e in _workEntries) {
      if (e.company.isEmpty) continue;
      companies.add(e.company);
      roles.add(e.role);
      workOrts.add(e.ort);
      workDurations.add(e.duration);
      workTypes.add(e.entryType ?? '');
    }

    final institutions = <String>[];
    final eduOrts = <String>[];
    final schoolTypes = <String>[];
    final abschluesse = <String>[];
    final eduDurations = <String>[];
    final grades = <String>[];
    for (final e in _eduEntries) {
      if (e.institution.isEmpty) continue;
      institutions.add(e.institution);
      eduOrts.add(e.ort);
      schoolTypes.add(e.schoolType ?? '');
      abschluesse.add(e.abschluss);
      eduDurations.add(e.duration);
      grades.add(e.grade);
    }

    final customIt = _itSkillsCustomCtrl.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty);
    final itSkills = <String>[..._itSkillsSelected, ...customIt];

    var map = <String, dynamic>{};
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('saved_profile');
      if (raw != null && raw.isNotEmpty) {
        map = jsonDecode(raw) as Map<String, dynamic>;
      }
    } catch (_) {}

    // Berufserfahrung und Praktika - shared keys with
    // questionnaire_screen.dart (previousEmployers/previousJobTitles/
    // previousJobDurations are also what UserProfile.fromMap() reads).
    map['previousEmployers']          = companies.join(',');
    map['previousJobTitles']          = roles.join(',');
    map['sharedWorkOrts']             = workOrts.join(',');
    map['previousJobDurations']       = workDurations.join(',');
    map['sharedWorkTypes']            = workTypes.join(',');
    map['ausbildungEduInstitutions']  = institutions.join(',');
    map['ausbildungEduOrts']          = eduOrts.join(',');
    map['ausbildungEduTypes']         = schoolTypes.join(',');
    map['ausbildungEduAbschluss']     = abschluesse.join(',');
    map['ausbildungEduDurations']     = eduDurations.join(',');
    map['ausbildungEduGrades']        = grades.join(',');
    map['languages']                  = _languages.join(',');
    map['languageProficiency']        =
        UserProfile.encodeProficiency(_languageProficiency);
    map['sharedItSkills']             = itSkills.join(',');
    map['ausbildungEscoSkills']          = _selectedSkills.join(',');
    map['ausbildungTargetOccupation']    = _selectedOccupation?.title ?? '';
    map['ausbildungTargetOccupationUri'] = _selectedOccupation?.uri ?? '';

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_profile', jsonEncode(map));
    } catch (_) {}

    final profile = UserProfile.fromMap(map);

    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AusbildungDocumentPreviewScreen(
          profile: profile,
          language: _lang,
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // ESCO API
  // ─────────────────────────────────────────────────────────────────────────────

  Future<void> _searchOccupations() async {
    final query = _escoSearchCtrl.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _escoLoading = true;
      _escoError = false;
      _escoResults = [];
      _selectedOccupation = null;
      _essentialSkills = [];
      _optionalSkills = [];
    });
    try {
      final uri = Uri.parse('https://ec.europa.eu/esco/api/search').replace(
        queryParameters: {
          'text': query,
          'language': 'de',
          'type': 'occupation',
        },
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final embedded = data['_embedded'] as Map<String, dynamic>?;
        final results = embedded?['results'] as List<dynamic>? ?? [];
        final parsed = results
            .map((r) => _EscoOccupation.fromJson(r as Map<String, dynamic>))
            .where((o) => o.title.isNotEmpty && o.uri.isNotEmpty)
            .toList();
        if (!mounted) return;
        setState(() {
          _escoResults = parsed;
          _escoLoading = false;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _escoLoading = false;
          _escoError = true;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _escoLoading = false;
        _escoError = true;
      });
    }
  }

  Future<void> _selectOccupation(_EscoOccupation occ) async {
    setState(() {
      _selectedOccupation = occ;
      _escoDetailLoading = true;
      _essentialSkills = [];
      _optionalSkills = [];
    });
    try {
      final uri = Uri.parse('https://ec.europa.eu/esco/api/resource/occupation')
          .replace(queryParameters: {'uri': occ.uri, 'language': 'de'});
      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final links = data['_links'] as Map<String, dynamic>? ?? {};
        final essential = (links['hasEssentialSkill'] as List<dynamic>? ?? [])
            .map((s) => _EscoSkill.fromJson(s as Map<String, dynamic>))
            .where((s) => s.title.isNotEmpty)
            .toList();
        final optional = (links['hasOptionalSkill'] as List<dynamic>? ?? [])
            .map((s) => _EscoSkill.fromJson(s as Map<String, dynamic>))
            .where((s) => s.title.isNotEmpty)
            .toList();
        if (!mounted) return;
        setState(() {
          _essentialSkills = essential;
          _optionalSkills = optional;
          _escoDetailLoading = false;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _escoDetailLoading = false;
          _escoError = true;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _escoDetailLoading = false;
        _escoError = true;
      });
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Localised strings
  // ─────────────────────────────────────────────────────────────────────────────

  // Shows the specific target Beruf once one has been chosen in the Skills
  // section below, instead of the generic "Ausbildung" label - falls back
  // to a clearer default (professional German CV term) until then.
  String get _titleLabel {
    if (_selectedOccupation != null && _selectedOccupation!.title.isNotEmpty) {
      return _selectedOccupation!.title;
    }
    switch (_lang) {
      case 'ps': return 'د زده کړې لیوالتیا لیک';
      case 'fa': return 'رزومه کارآموزی';
      default:   return 'Ausbildungs-Lebenslauf';
    }
  }

  // Same literal strings as questionnaire_screen.dart's "Create CV →"
  // button, so finishing this questionnaire mirrors that exact flow/label.
  String get _continueLabel {
    switch (_lang) {
      case 'ps': return ' جوړ کړئ CV →';
      case 'fa': return 'ایجاد CV →';
      default:   return 'Create CV →';
    }
  }

  // Section 1
  String get _workSubtitle {
    switch (_lang) {
      case 'ps': return 'خپلې تیرې دندې یا کارورزۍ اضافه کړئ (تر ۵ پورې)';
      case 'fa': return 'سوابق کاری یا کارآموزی خود را اضافه کنید (حداکثر ۵)';
      default:   return 'Add your previous jobs or internships (up to 5)';
    }
  }

  String get _workEntriesPrefilledNote {
    switch (_lang) {
      case 'ps': return 'دا معلومات ستاسو د بلې CV څخه راغلي، تاسو یې سمولی شئ';
      case 'fa': return 'این از رزومه دیگر شما بارگذاری شده، می‌توانید ویرایش کنید';
      default:   return 'Loaded from your other CV, edit if needed';
    }
  }

  String get _itSkillsPrefilledNote {
    switch (_lang) {
      case 'ps': return 'دا معلومات ستاسو د بلې CV څخه راغلي، تاسو یې سمولی شئ';
      case 'fa': return 'این از رزومه دیگر شما بارگذاری شده، می‌توانید ویرایش کنید';
      default:   return 'Loaded from your other CV, edit if needed';
    }
  }

  // Ausbildung-only sections (Bildung, ESCO skills) aren't shared with the
  // Job CV flow, so this uses "your previous answers" rather than the
  // "other CV" wording the shared sections above use.
  String get _ausbildungPrefilledNote {
    switch (_lang) {
      case 'ps': return 'دا معلومات ستاسو د پخوانیو ځوابونو څخه راغلي، تاسو یې سمولی شئ';
      case 'fa': return 'این از پاسخ‌های قبلی شما بارگذاری شده، می‌توانید ویرایش کنید';
      default:   return 'Loaded from your previous answers, edit if needed';
    }
  }

  String get _companyHint {
    switch (_lang) {
      case 'ps': return 'د شرکت نوم';
      case 'fa': return 'نام شرکت';
      default:   return 'Company name';
    }
  }

  String get _roleHint {
    switch (_lang) {
      case 'ps': return 'دنده / موقف';
      case 'fa': return 'سمت / موقعیت شغلی';
      default:   return 'Role / position';
    }
  }

  // Shared "Ort" (place/location) hint - used by both the work-experience
  // and education repeatable entries.
  String get _ortHint {
    switch (_lang) {
      case 'ps': return 'ځای (ښار)';
      case 'fa': return 'محل (شهر)';
      default:   return 'Ort (place/location)';
    }
  }

  String get _addWorkLabel {
    switch (_lang) {
      case 'ps': return '+ بله دنده اضافه کړئ';
      case 'fa': return '+ افزودن شغل دیگر';
      default:   return '+ Add another position';
    }
  }

  // Section 2
  String get _eduSubtitle {
    switch (_lang) {
      case 'ps': return 'خپلې زده کړې اضافه کړئ (تر ۵ پورې)';
      case 'fa': return 'سوابق تحصیلی خود را اضافه کنید (حداکثر ۵)';
      default:   return 'Add your education history (up to 5)';
    }
  }

  String get _institutionHint {
    switch (_lang) {
      case 'ps': return 'د ښوونځي نوم';
      case 'fa': return 'نام موسسه';
      default:   return 'Institution name';
    }
  }

  String get _schoolTypeHint {
    switch (_lang) {
      case 'ps': return 'د زده کړې ډول وټاکئ';
      case 'fa': return 'نوع مدرسه را انتخاب کنید';
      default:   return 'Select school/education type';
    }
  }

  String get _abschlussHint {
    switch (_lang) {
      case 'ps': return 'د سند ډول (لکه Abschluss)';
      case 'fa': return 'نوع مدرک (Abschluss)';
      default:   return 'Qualification / Abschluss type';
    }
  }

  String get _addEduLabel {
    switch (_lang) {
      case 'ps': return '+ بله زده کړه اضافه کړئ';
      case 'fa': return '+ افزودن مدرک دیگر';
      default:   return '+ Add another qualification';
    }
  }

  String get _addGradesLabel {
    switch (_lang) {
      case 'ps': return 'Noten hinzufügen (نمرې اضافه کړئ)';
      case 'fa': return 'Noten hinzufügen (افزودن نمرات)';
      default:   return 'Noten hinzufügen (add grades)';
    }
  }

  String get _gradeHint {
    switch (_lang) {
      case 'ps': return 'خپلې نمرې دلته ولیکئ';
      case 'fa': return 'نمرات خود را اینجا بنویسید';
      default:   return 'Enter your grades';
    }
  }

  // Section 3
  String get _langSubtitle {
    switch (_lang) {
      case 'ps': return 'خپلې ژبې او د هرې ژبې کچه وټاکئ';
      case 'fa': return 'زبان‌ها و سطح خود را برای هر زبان انتخاب کنید';
      default:   return 'Select the languages you speak and your level for each';
    }
  }

  String get _langPrefilledNote {
    switch (_lang) {
      case 'ps': return 'دا معلومات ستاسو د پروفایل څخه راغلي، تاسو یې سمولی شئ';
      case 'fa': return 'این اطلاعات از پروفایل شما بارگذاری شده، می‌توانید ویرایش کنید';
      default:   return 'Loaded from your saved profile, edit if needed';
    }
  }

  String get _motherTongueLabel {
    switch (_lang) {
      case 'ps': return 'مورنۍ ژبه';
      case 'fa': return 'زبان مادری';
      default:   return 'Muttersprache';
    }
  }

  String get _otherLangLabel {
    switch (_lang) {
      case 'ps': return 'نور (پخپله ولیکئ)';
      case 'fa': return 'دیگر (خودتان بنویسید)';
      default:   return 'Other / type your own';
    }
  }

  // Section 4
  String get _itSubtitle {
    switch (_lang) {
      case 'ps': return 'هغه مهارتونه وټاکئ چې تاسو یې لری';
      case 'fa': return 'مهارت‌هایی که دارید را انتخاب کنید';
      default:   return 'Select the skills you have';
    }
  }

  String get _itCustomHint {
    switch (_lang) {
      case 'ps': return 'نور IT مهارتونه، په کوما سره جلا کړئ';
      case 'fa': return 'مهارت‌های IT دیگر، با کاما جدا کنید';
      default:   return 'Other IT skills, separated by commas';
    }
  }

  // Section 5
  String get _skillsSubtitle {
    switch (_lang) {
      case 'ps': return 'خپل موخه یی مسلک ولیکئ او لټون وکړئ';
      case 'fa': return 'شغل هدف خود را بنویسید و جستجو کنید';
      default:   return 'Type your target job (Beruf) and search';
    }
  }

  String get _skillsSearchHint {
    switch (_lang) {
      case 'ps': return 'لکه Elektroniker, Verkäufer...';
      case 'fa': return 'مثلاً Elektroniker, Verkäufer...';
      default:   return 'e.g. Elektroniker, Verkäufer...';
    }
  }

  String get _noResultsMsg {
    switch (_lang) {
      case 'ps': return 'پایله ونه موندل شوه';
      case 'fa': return 'نتیجه‌ای یافت نشد';
      default:   return 'No results found';
    }
  }

  String get _essentialSkillsLabel => 'Wesentliche Fähigkeiten';
  String get _optionalSkillsLabel  => 'Optionale Fähigkeiten';
  String get _skillsDropdownLabel  => 'Fähigkeiten auswählen';

  String get _customSkillHint {
    switch (_lang) {
      case 'ps': return 'خپل مهارت ولیکئ او اضافه یې کړئ';
      case 'fa': return 'مهارت خود را بنویسید و اضافه کنید';
      default:   return 'Type a custom skill and add it';
    }
  }

  // Shown when the user tries to select a 6th ESCO skill (capped at 5).
  String get _maxLimitMsg {
    switch (_lang) {
      case 'ps': return 'تاسو د ۵ څخه زیات نشئ اضافه کولی';
      case 'fa': return 'شما نمی‌توانید بیشتر از ۵ مورد اضافه کنید';
      default:   return "You can't add more than 5";
    }
  }

  // Shown once the 5th ESCO skill has been selected and the dropdown
  // auto-closes.
  String get _maxReachedMsg {
    switch (_lang) {
      case 'ps': return '۵ ټاکل شوي - اعظمي';
      case 'fa': return '۵ انتخاب شد - حداکثر';
      default:   return '5 selected - maximum reached';
    }
  }

  void _showMaxLimitSnack() {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_maxLimitMsg,
            style: const TextStyle(color: Colors.white, fontSize: 13)),
        backgroundColor: _navy.withOpacity(0.85),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showMaxReachedSnack() {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_maxReachedMsg,
            style: const TextStyle(color: Colors.white, fontSize: 13)),
        backgroundColor: _navy.withOpacity(0.85),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  String get _presentLabel {
    switch (_lang) {
      case 'ps': return 'اوس مهال';
      case 'fa': return 'اکنون';
      default:   return 'Present';
    }
  }

  String get _fromYearHint {
    switch (_lang) {
      case 'ps': return 'له کال';
      case 'fa': return 'از سال';
      default:   return 'From year';
    }
  }

  String get _untilYearHint {
    switch (_lang) {
      case 'ps': return 'تر کاله';
      case 'fa': return 'تا سال';
      default:   return 'Until year';
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        TtsService().stop();
      },
      child: Scaffold(
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
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                      child: Column(
                        children: [
                          _buildWorkSection(),
                          const SizedBox(height: 14),
                          _buildEduSection(),
                          const SizedBox(height: 14),
                          _buildLangSection(),
                          const SizedBox(height: 14),
                          _buildItSection(),
                          const SizedBox(height: 14),
                          _buildEscoSection(),
                          const SizedBox(height: 20),
                          _BigButton(
                            label: _continueLabel,
                            enabled: !_saving,
                            onTap: _continueToPreview,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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
            onTap: () {
              TtsService().stop();
              Navigator.pop(context);
            },
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

  // ─────────────────────────────────────────────────────────────────────────────
  // Section 1 - BERUFSERFAHRUNG UND PRAKTIKA
  // ─────────────────────────────────────────────────────────────────────────────

  Widget _buildWorkSection() {
    return _SectionCard(
      title: 'BERUFSERFAHRUNG UND PRAKTIKA',
      subtitle: _workSubtitle,
      isRtl: _isRtl,
      showSpeaker: _showSpeaker,
      onSpeak: () => _speak(_workSubtitle),
      badge: _workEntriesPrefilled
          ? Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: _green, size: 14),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    _workEntriesPrefilledNote,
                    style: const TextStyle(
                      color: Color(0xFF0E7A20),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < _workEntries.length; i++) _workEntryCard(i),
          if (_workEntries.length < _kMaxWorkEntries)
            _addEntryButton(
              label: _addWorkLabel,
              onTap: () => setState(() => _workEntries.add(_WorkExpEntry())),
            ),
        ],
      ),
    );
  }

  Widget _workEntryCard(int index) {
    final entry = _workEntries[index];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDDE4EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (_workEntries.length > 1)
                GestureDetector(
                  onTap: () => setState(() {
                    _workEntries[index].dispose();
                    _workEntries.removeAt(index);
                  }),
                  child: const Icon(Icons.close_rounded, color: _muted, size: 18),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _workTypeSelector(entry),
          const SizedBox(height: 8),
          _TxtField(controller: entry.companyCtrl, hint: _companyHint),
          const SizedBox(height: 8),
          _TxtField(controller: entry.roleCtrl, hint: _roleHint),
          const SizedBox(height: 8),
          _TxtField(controller: entry.ortCtrl, hint: _ortHint),
          const SizedBox(height: 8),
          _yearDurationRow(
            fromYear: entry.fromYear,
            untilYear: entry.untilYear,
            onFromChanged: (v) =>
                setState(() => entry.fromYear = v == null ? null : int.tryParse(v)),
            onUntilChanged: (v) => setState(() => entry.untilYear = v),
          ),
        ],
      ),
    );
  }

  // "Typ" category tag on a Berufserfahrung entry - Berufserfahrung or
  // Praktikum. Both options share the same fields (company/role/place/
  // duration); this only tags the entry, it isn't a separate section.
  Widget _workTypeSelector(_WorkExpEntry entry) {
    Widget option(String value, String label) {
      final selected = entry.entryType == value;
      return GestureDetector(
        onTap: () => setState(() => entry.entryType = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? _green : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? _green : const Color(0xFFDDE4EF),
              width: selected ? 2.0 : 1.2,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : _navy,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            option('Berufserfahrung', 'Berufserfahrung'),
            option('Praktikum', 'Praktikum'),
          ],
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Section 2 - ALLGEMEINE UND BERUFLICHE BILDUNG
  // ─────────────────────────────────────────────────────────────────────────────

  Widget _buildEduSection() {
    return _SectionCard(
      title: 'ALLGEMEINE UND BERUFLICHE BILDUNG',
      subtitle: _eduSubtitle,
      isRtl: _isRtl,
      showSpeaker: _showSpeaker,
      onSpeak: () => _speak(_eduSubtitle),
      badge: _eduPrefilled
          ? Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: _green, size: 14),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    _ausbildungPrefilledNote,
                    style: const TextStyle(
                      color: Color(0xFF0E7A20),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < _eduEntries.length; i++) _eduEntryCard(i),
          if (_eduEntries.length < _kMaxEduEntries)
            _addEntryButton(
              label: _addEduLabel,
              onTap: () => setState(() => _eduEntries.add(_EduEntry())),
            ),
        ],
      ),
    );
  }

  Widget _eduEntryCard(int index) {
    final entry = _eduEntries[index];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDDE4EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (_eduEntries.length > 1)
                GestureDetector(
                  onTap: () => setState(() {
                    _eduEntries[index].dispose();
                    _eduEntries.removeAt(index);
                  }),
                  child: const Icon(Icons.close_rounded, color: _muted, size: 18),
                ),
            ],
          ),
          const SizedBox(height: 6),
          _TxtField(controller: entry.institutionCtrl, hint: _institutionHint),
          const SizedBox(height: 8),
          _TxtField(controller: entry.ortCtrl, hint: _ortHint),
          const SizedBox(height: 8),
          _dropdownField(
            hint: _schoolTypeHint,
            value: entry.schoolType,
            items: _kSchoolTypes,
            onChanged: (v) => setState(() => entry.schoolType = v),
          ),
          const SizedBox(height: 8),
          _TxtField(controller: entry.abschlussCtrl, hint: _abschlussHint),
          const SizedBox(height: 8),
          _yearDurationRow(
            fromYear: entry.fromYear,
            untilYear: entry.untilYear,
            onFromChanged: (v) =>
                setState(() => entry.fromYear = v == null ? null : int.tryParse(v)),
            onUntilChanged: (v) => setState(() => entry.untilYear = v),
          ),
          const SizedBox(height: 8),
          if (!entry.showGrades)
            GestureDetector(
              onTap: () => setState(() => entry.showGrades = true),
              child: Text(
                _addGradesLabel,
                style: const TextStyle(
                  color: _green,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.underline,
                  decorationColor: _green,
                ),
              ),
            )
          else
            _TxtField(controller: entry.gradeCtrl, hint: _gradeHint),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Section 3 - SPRACHKENNTNISSE
  // ─────────────────────────────────────────────────────────────────────────────

  Widget _buildLangSection() {
    Widget levelRow(String key, String germanName, String displayLabel) {
      final current = _languageProficiency[germanName];
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(displayLabel,
                style: const TextStyle(
                  color: _navy, fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final level in _kCefrLevels)
                  _levelChip(
                    label: level,
                    selected: current == level,
                    onTap: () => setState(() {
                      if (!_languages.contains(key)) _languages.add(key);
                      _languageProficiency[germanName] = level;
                    }),
                  ),
                _levelChip(
                  label: _motherTongueLabel,
                  selected: current == 'Muttersprache',
                  onTap: () => setState(() {
                    if (!_languages.contains(key)) _languages.add(key);
                    _languageProficiency[germanName] = 'Muttersprache';
                  }),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return _SectionCard(
      title: 'SPRACHKENNTNISSE',
      subtitle: _langSubtitle,
      isRtl: _isRtl,
      showSpeaker: _showSpeaker,
      onSpeak: () => _speak(_langSubtitle),
      badge: _langPrefilled
          ? Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: _green, size: 14),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    _langPrefilledNote,
                    style: const TextStyle(
                      color: Color(0xFF0E7A20),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _kLangs.map((l) {
              final key = l[0];
              final germanName = l[1];
              final lbl = _lang == 'ps' ? l[2] : _lang == 'fa' ? l[3] : l[1];
              final sel = _languages.contains(key);
              return GestureDetector(
                onTap: () => setState(() {
                  if (sel) {
                    _languages.remove(key);
                    _languageProficiency.remove(germanName);
                  } else {
                    _languages.add(key);
                  }
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: sel ? const Color(0xFFEAFBE9) : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: sel ? _green : const Color(0xFFDDE4EF),
                      width: sel ? 2.0 : 1.2,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(lbl,
                          style: const TextStyle(
                            color: _navy,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          )),
                      if (sel) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.check_rounded, color: _green, size: 13),
                      ],
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          _otherRow(
            open: _langOtherOpen,
            ctrl: _langOtherCtrl,
            hint: _otherLangLabel,
            onToggleOpen: () => setState(() => _langOtherOpen = !_langOtherOpen),
            onSubmit: () {
              final v = _langOtherCtrl.text.trim();
              if (v.isEmpty) return;
              setState(() {
                if (!_languages.contains(v)) _languages.add(v);
                _langOtherCtrl.clear();
                _langOtherOpen = false;
              });
            },
          ),
          if (_languages.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Divider(height: 1, color: Color(0xFFE4EAF5)),
            const SizedBox(height: 12),
            for (final l in _kLangs)
              if (_languages.contains(l[0]))
                levelRow(l[0], l[1], _lang == 'ps' ? l[2] : _lang == 'fa' ? l[3] : l[1]),
            for (final custom in _languages
                .where((l) => !_kLangs.any((preset) => preset[0] == l)))
              levelRow(custom, custom, custom),
          ],
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Section 4 - IT-KENNTNISSE
  // ─────────────────────────────────────────────────────────────────────────────

  Widget _buildItSection() {
    return _SectionCard(
      title: 'IT-KENNTNISSE',
      subtitle: _itSubtitle,
      isRtl: _isRtl,
      showSpeaker: _showSpeaker,
      onSpeak: () => _speak(_itSubtitle),
      badge: _itSkillsPrefilled
          ? Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: _green, size: 14),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    _itSkillsPrefilledNote,
                    style: const TextStyle(
                      color: Color(0xFF0E7A20),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final label in _kItSkillLabels) _itSkillRow(label),
          const SizedBox(height: 4),
          _TxtField(controller: _itSkillsCustomCtrl, hint: _itCustomHint),
        ],
      ),
    );
  }

  Widget _itSkillRow(String label) {
    final selected = _itSkillsSelected.contains(label);
    return GestureDetector(
      onTap: () => setState(() {
        if (selected) {
          _itSkillsSelected.remove(label);
        } else if (_itSkillsSelected.length < _kMaxItSkills) {
          _itSkillsSelected.add(label);
        }
      }),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEAFBE9) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? _green : const Color(0xFFDDE4EF),
            width: selected ? 2.0 : 1.2,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.check_box_rounded
                  : Icons.check_box_outline_blank_rounded,
              color: selected ? _green : _muted,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: _navy,
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Section 5 - SKILLS (ESCO)
  // ─────────────────────────────────────────────────────────────────────────────

  Widget _buildEscoSection() {
    return _SectionCard(
      title: 'BERUFLICHE FÄHIGKEITEN',
      subtitle: _skillsSubtitle,
      isRtl: _isRtl,
      showSpeaker: _showSpeaker,
      onSpeak: () => _speak(_skillsSubtitle),
      badge: _escoPrefilled
          ? Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: _green, size: 14),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    _ausbildungPrefilledNote,
                    style: const TextStyle(
                      color: Color(0xFF0E7A20),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _TxtField(
                  controller: _escoSearchCtrl,
                  hint: _skillsSearchHint,
                  action: TextInputAction.search,
                  onSubmitted: (_) => _searchOccupations(),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _escoLoading ? null : _searchOccupations,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _green,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: _escoLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: _navy),
                        )
                      : const Icon(Icons.search_rounded, color: _navy, size: 22),
                ),
              ),
            ],
          ),
          if (!_escoError && _escoResults.isNotEmpty) ...[
            const SizedBox(height: 12),
            // Once one match is selected, the other unselected alternatives
            // from this search are hidden - only the chosen one stays visible.
            for (final occ in _escoResults)
              if (_selectedOccupation == null ||
                  _selectedOccupation!.uri == occ.uri)
                _occupationRow(occ),
          ],
          if (!_escoError &&
              !_escoLoading &&
              _escoResults.isEmpty &&
              _escoSearchCtrl.text.trim().isNotEmpty &&
              _selectedOccupation == null) ...[
            const SizedBox(height: 8),
            Text(_noResultsMsg,
                style: const TextStyle(color: _muted, fontSize: 12)),
          ],
          if (_escoDetailLoading) ...[
            const SizedBox(height: 14),
            const Center(
              child: CircularProgressIndicator(color: _green, strokeWidth: 2.5),
            ),
          ],
          if (!_escoError &&
              _selectedOccupation != null &&
              !_escoDetailLoading &&
              (_essentialSkills.isNotEmpty || _optionalSkills.isNotEmpty)) ...[
            const SizedBox(height: 14),
            _skillsMultiSelect(),
          ],
          if (_selectedSkills.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _selectedSkills
                  .map((s) => _skillChip(s, true, () => setState(() {
                        _selectedSkills.remove(s);
                      })))
                  .toList(),
            ),
          ],
          const SizedBox(height: 14),
          _otherRow(
            open: true,
            ctrl: _customSkillCtrl,
            hint: _customSkillHint,
            onToggleOpen: () {},
            onSubmit: () {
              final v = _customSkillCtrl.text.trim();
              if (v.isEmpty) return;
              if (_selectedSkills.length >= _kMaxEscoSkills &&
                  !_selectedSkills.contains(v)) {
                return;
              }
              setState(() {
                _selectedSkills.add(v);
                _customSkillCtrl.clear();
              });
            },
          ),
        ],
      ),
    );
  }

  // Suggested-skills dropdown: closed by default (shows the "Fähigkeiten
  // auswählen" label), expands into a checklist grouped under "Wesentliche
  // Fähigkeiten" / "Optionale Fähigkeiten". Replaces the old always-visible
  // chip Wrap so the section doesn't take up so much vertical space before
  // the user has actually opened it. Selection logic/data model unchanged -
  // this only changes how the suggestions are presented.
  Widget _skillsMultiSelect() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => _skillsDropdownOpen = !_skillsDropdownOpen),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _skillsDropdownOpen ? _green : const Color(0xFFDDE4EF),
                width: _skillsDropdownOpen ? 2.0 : 1.2,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _skillsDropdownLabel,
                    style: const TextStyle(
                      color: _navy,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (_selectedSkills.isNotEmpty) ...[
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAFBE9),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${_selectedSkills.length}',
                      style: const TextStyle(
                        color: Color(0xFF0E7A20),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Icon(
                  _skillsDropdownOpen
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: _muted,
                ),
              ],
            ),
          ),
        ),
        if (_skillsDropdownOpen) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF7FAFF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFDDE4EF)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_essentialSkills.isNotEmpty) ...[
                  Text(_essentialSkillsLabel,
                      style: const TextStyle(
                        color: _navy,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      )),
                  const SizedBox(height: 4),
                  for (final s in _essentialSkills) _skillCheckRow(s.title),
                ],
                if (_optionalSkills.isNotEmpty) ...[
                  if (_essentialSkills.isNotEmpty) const SizedBox(height: 10),
                  Text(_optionalSkillsLabel,
                      style: const TextStyle(
                        color: _navy,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      )),
                  const SizedBox(height: 4),
                  for (final s in _optionalSkills) _skillCheckRow(s.title),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _skillCheckRow(String label) {
    final selected = _selectedSkills.contains(label);
    return GestureDetector(
      onTap: () {
        if (!selected && _selectedSkills.length >= _kMaxEscoSkills) {
          _showMaxLimitSnack();
          return;
        }
        setState(() {
          if (selected) {
            _selectedSkills.remove(label);
          } else {
            _selectedSkills.add(label);
            // Dropdown stays open so the user can pick multiple skills in
            // one session - only auto-close once the cap is reached.
            if (_selectedSkills.length >= _kMaxEscoSkills) {
              _skillsDropdownOpen = false;
            }
          }
        });
        if (!selected && _selectedSkills.length >= _kMaxEscoSkills) {
          _showMaxReachedSnack();
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.check_box_rounded
                  : Icons.check_box_outline_blank_rounded,
              color: selected ? _green : _muted,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: _navy,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _occupationRow(_EscoOccupation occ) {
    final selected = _selectedOccupation?.uri == occ.uri;
    return GestureDetector(
      onTap: () => _selectOccupation(occ),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEAFBE9) : const Color(0xFFF7FAFF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? _green : const Color(0xFFDDE4EF),
            width: selected ? 2.0 : 1.2,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                occ.title,
                style: const TextStyle(
                  color: _navy, fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: selected ? _green : _muted, size: 18),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Shared small builders
  // ─────────────────────────────────────────────────────────────────────────────

  Widget _addEntryButton({required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFEAFBE9),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _green.withOpacity(0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add_rounded, color: Color(0xFF0E7A20), size: 16),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(
                  color: Color(0xFF0E7A20),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                )),
          ],
        ),
      ),
    );
  }

  Widget _yearDurationRow({
    required int? fromYear,
    required String? untilYear,
    required ValueChanged<String?> onFromChanged,
    required ValueChanged<String?> onUntilChanged,
  }) {
    return Row(
      children: [
        Expanded(
          child: _dropdownField(
            hint: _fromYearHint,
            value: fromYear?.toString(),
            items: _yearOptions(),
            onChanged: onFromChanged,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _dropdownField(
            hint: _untilYearHint,
            value: untilYear,
            items: _yearOptions(),
            includePresent: true,
            onChanged: onUntilChanged,
          ),
        ),
      ],
    );
  }

  List<String> _yearOptions() {
    final currentYear = DateTime.now().year;
    return List.generate(50, (i) => (currentYear + 1 - i).toString());
  }

  Widget _dropdownField({
    required String hint,
    required String? value,
    required List<String> items,
    bool includePresent = false,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDDE4EF)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          hint: Text(hint,
              style: const TextStyle(color: _muted, fontSize: 13),
              overflow: TextOverflow.ellipsis),
          isExpanded: true,
          dropdownColor: Colors.white,
          icon: const Icon(Icons.keyboard_arrow_down_rounded,
              color: _muted, size: 20),
          style: const TextStyle(
              color: _navy, fontSize: 13, fontWeight: FontWeight.w600),
          items: [
            if (includePresent)
              DropdownMenuItem(
                value: 'present',
                child: Text(_presentLabel,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: _navy,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ),
            for (final item in items)
              DropdownMenuItem(
                value: item,
                child: Text(item,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _navy, fontSize: 13)),
              ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _otherRow({
    required bool open,
    required TextEditingController ctrl,
    required String hint,
    required VoidCallback onToggleOpen,
    required VoidCallback onSubmit,
  }) {
    if (!open) {
      return GestureDetector(
        onTap: onToggleOpen,
        child: Text(
          hint,
          style: const TextStyle(
            color: _green,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            decoration: TextDecoration.underline,
            decorationColor: _green,
          ),
        ),
      );
    }
    return Row(
      children: [
        Expanded(
          child: _TxtField(
            controller: ctrl,
            hint: hint,
            action: TextInputAction.done,
            onSubmitted: (_) => onSubmit(),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: onSubmit,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _green,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.add_rounded, color: _navy, size: 20),
          ),
        ),
      ],
    );
  }

  Widget _levelChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? _green : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? _green : const Color(0xFFDDE4EF),
            width: selected ? 2.0 : 1.2,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : _navy,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _skillChip(String label, bool selected, VoidCallback onTap) {
    // Capped to a max width with ellipsis truncation so long ESCO skill
    // titles never push the chip wider than its available space (was
    // producing "RIGHT OVERFLOWED" warnings for longer labels).
    return GestureDetector(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? _green : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? _green : const Color(0xFFDDE4EF),
              width: selected ? 2.0 : 1.2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? Colors.white : _navy,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 4),
                const Icon(Icons.check_rounded, color: Colors.white, size: 13),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Repeatable entry data models
// ─────────────────────────────────────────────────────────────────────────────

class _WorkExpEntry {
  final companyCtrl = TextEditingController();
  final roleCtrl = TextEditingController();
  final ortCtrl = TextEditingController();
  int? fromYear;
  String? untilYear;
  // Category tag on this entry - 'Berufserfahrung' or 'Praktikum'. Same
  // fields apply to both; this is not a separate section.
  String? entryType;

  String get company => companyCtrl.text.trim();
  String get role => roleCtrl.text.trim();
  String get ort => ortCtrl.text.trim();

  String get duration {
    final from = fromYear?.toString() ?? '';
    final until = untilYear == 'present' ? 'heute' : (untilYear ?? '');
    if (from.isEmpty && until.isEmpty) return '';
    if (from.isNotEmpty && until.isNotEmpty) return '$from - $until';
    return from.isNotEmpty ? from : until;
  }

  void dispose() {
    companyCtrl.dispose();
    roleCtrl.dispose();
    ortCtrl.dispose();
  }
}

class _EduEntry {
  final institutionCtrl = TextEditingController();
  final ortCtrl = TextEditingController();
  final abschlussCtrl = TextEditingController();
  final gradeCtrl = TextEditingController();
  String? schoolType;
  int? fromYear;
  String? untilYear;
  bool showGrades = false;

  String get institution => institutionCtrl.text.trim();
  String get ort => ortCtrl.text.trim();
  String get abschluss => abschlussCtrl.text.trim();
  String get grade => gradeCtrl.text.trim();

  String get duration {
    final from = fromYear?.toString() ?? '';
    final until = untilYear == 'present' ? 'heute' : (untilYear ?? '');
    if (from.isEmpty && until.isEmpty) return '';
    if (from.isNotEmpty && until.isNotEmpty) return '$from - $until';
    return from.isNotEmpty ? from : until;
  }

  void dispose() {
    institutionCtrl.dispose();
    ortCtrl.dispose();
    abschlussCtrl.dispose();
    gradeCtrl.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ESCO API models
// ─────────────────────────────────────────────────────────────────────────────

class _EscoOccupation {
  final String uri;
  final String title;

  const _EscoOccupation({required this.uri, required this.title});

  factory _EscoOccupation.fromJson(Map<String, dynamic> j) => _EscoOccupation(
        uri: j['uri'] as String? ?? '',
        title: j['title'] as String? ?? '',
      );
}

class _EscoSkill {
  final String uri;
  final String title;

  const _EscoSkill({required this.uri, required this.title});

  factory _EscoSkill.fromJson(Map<String, dynamic> j) => _EscoSkill(
        uri: j['uri'] as String? ?? '',
        title: j['title'] as String? ?? '',
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Section card - glass surface wrapper with title/subtitle/speaker/badge
// ─────────────────────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  static const Color _navy  = Color(0xFF091733);
  static const Color _muted = Color(0xFF65738A);
  static const Color _green = Color(0xFF39EA2B);

  final String title;
  final String subtitle;
  final bool isRtl;
  final bool showSpeaker;
  final VoidCallback onSpeak;
  final Widget child;
  final Widget? badge;

  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.isRtl,
    required this.showSpeaker,
    required this.onSpeak,
    required this.child,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return _GlassSurface(
      borderRadius: 22,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment:
            isRtl ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
            children: [
              Expanded(
                child: Text(
                  title,
                  textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
                  style: const TextStyle(
                    color: _navy,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              if (showSpeaker) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onSpeak,
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAFBE9),
                      shape: BoxShape.circle,
                      border: Border.all(color: _green.withOpacity(0.4)),
                    ),
                    child: const Icon(Icons.volume_up_rounded,
                        color: _green, size: 15),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
            style: const TextStyle(
              color: _muted,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              height: 1.4,
            ),
          ),
          if (badge != null) ...[
            const SizedBox(height: 8),
            badge!,
          ],
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Text field - glass style
// ─────────────────────────────────────────────────────────────────────────────

class _TxtField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final TextInputType type;
  final TextInputAction action;
  final ValueChanged<String>? onSubmitted;

  const _TxtField({
    required this.controller,
    required this.hint,
    this.type = TextInputType.text,
    this.action = TextInputAction.next,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.9)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10),
        ],
      ),
      child: TextField(
        controller: controller,
        keyboardType: type,
        textInputAction: action,
        onSubmitted: onSubmitted,
        textDirection: TextDirection.ltr,
        style: const TextStyle(color: Color(0xFF091733)),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFF65738A), fontSize: 14),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(14),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Big action button
// ─────────────────────────────────────────────────────────────────────────────

class _BigButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  const _BigButton({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: enabled ? 1.0 : 0.45,
      duration: const Duration(milliseconds: 200),
      child: Container(
        height: 58,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(29),
          color: const Color(0xFF39EA2B),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF39EA2B).withOpacity(0.35),
              blurRadius: 22,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(29),
            onTap: enabled ? onTap : null,
            child: Center(
              child: Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF091733),
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Nav button (back arrow / sound toggle)
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
          child: Icon(icon, color: active ? _green : _navy, size: 20),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Background glow
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
              colors: [Color(0xFFF9FBFF), Color(0xFFEFF6FF), Color(0xFFF7FFF2)],
            ),
          ),
          child: SizedBox.expand(),
        ),
        Positioned(top: 70,    left: -42,  child: _Orb(size: 170, color: Color(0x6639EA2B))),
        Positioned(top: 135,   right: -65, child: _Orb(size: 170, color: Color(0x44FFB86B))),
        Positioned(bottom: 95, left: -60,  child: _Orb(size: 210, color: Color(0x3339EA2B))),
        Positioned(bottom: -30,right: 14,  child: _Orb(size: 145, color: Color(0x5539EA2B))),
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
// Glass surface
// ─────────────────────────────────────────────────────────────────────────────

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
              BoxShadow(
                  color: Colors.white.withOpacity(0.9),
                  blurRadius: 0,
                  offset: const Offset(-2, -2)),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}
