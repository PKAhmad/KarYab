import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_profile.dart';
import '../providers/language_provider.dart';
import '../services/analytics_service.dart';
import '../services/tts_service.dart';
import 'review_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Entry point
//
// Job CV, job-specific questions only. Personal data (name/DOB/nationality/
// address/phone/email/photo) is collected once by PersonalDataScreen before
// this screen is ever reached (via ChooseCvTypeScreen) and is read back from
// 'saved_profile' here rather than being asked again. Berufserfahrung und
// Praktika and IT-Kenntnisse are shared with the Ausbildung CV questionnaire
// (ausbildung_cv_questionnaire_screen.dart) via common SharedPreferences keys.
// ─────────────────────────────────────────────────────────────────────────────

class QuestionnaireScreen extends StatefulWidget {
  final String language;
  final bool voiceMode;
  // False when reached via a fresh "Create CV" flow (ChooseCvTypeScreen) -
  // the shared-data prefill (_loadSharedData) is skipped so the form starts
  // empty. True when reached via "Edit answers" from the CV preview screen -
  // prefill runs exactly as before so existing answers reload for editing.
  final bool isEditMode;

  const QuestionnaireScreen({
    super.key,
    required this.language,
    required this.voiceMode,
    this.isEditMode = false,
  });

  @override
  State<QuestionnaireScreen> createState() => _QuestionnaireScreenState();
}

class _QuestionnaireScreenState extends State<QuestionnaireScreen> {
  static const Color _navy  = Color(0xFF091733);
  static const Color _green = Color(0xFF39EA2B);
  static const Color _muted = Color(0xFF65738A);

  static const int _kMaxJobEntries = 5;
  static const int _kMaxItSkills   = 5;

  // Fixed IT skill checklist - shared with ausbildung_cv_questionnaire_screen.dart
  // (same labels, same 'sharedItSkills' persistence key).
  static const List<String> _kItSkillLabels = [
    'Microsoft Word',
    'Microsoft Excel',
    'Microsoft PowerPoint',
    'Microsoft Outlook',
    'Microsoft Teams',
    'Grundlegende PC-Kenntnisse',
    'Internetrecherche',
  ];

  late String _lang;

  // ── State ────────────────────────────────────────────────────────────────
  String? _educationLevel;
  // Educated users only - asked once an education level is selected.
  final _schoolOrtCtrl = TextEditingController();
  int?    _schoolFromYear;
  String? _schoolUntilYear;

  // Same '$from - $until' format as _JobEntry.duration (heute = present).
  String get _schoolDuration {
    final from = _schoolFromYear?.toString() ?? '';
    final until = _schoolUntilYear == 'present' ? 'heute' : (_schoolUntilYear ?? '');
    if (from.isEmpty && until.isEmpty) return '';
    if (from.isNotEmpty && until.isNotEmpty) return '$from - $until';
    return from.isNotEmpty ? from : until;
  }
  final _skillSearchCtrl = TextEditingController();
  final _refNameCtrl     = TextEditingController();
  final _refPhoneCtrl    = TextEditingController();
  List<String> _skills        = [];
  String?      _workExperience;
  String?      _workType;
  String?      _tools;
  String?      _drivingLicense;
  List<String> _languages     = [];
  String?      _availability;
  String?      _startDate;
  String?      _reference;

  // ── IT-Kenntnisse (shared with the Ausbildung CV questionnaire) ────────────
  final Set<String> _itSkillsSelected = {};
  final _itSkillsCustomCtrl = TextEditingController();
  bool _itSkillsPrefilled = false;

  // ── Educated-only "Other / type your own" free-text state ──────────────────
  // Q8 education, Q9 skills, Q10 work experience, its work-type sub-question,
  // and Q11 tools. Excluded per spec: Q12 license, Q14 availability, Q15
  // start date, Q15/16 reference — those keep chips only.
  bool _educationOtherOpen   = false;
  bool _skillOtherOpen       = false;
  bool _workExpOtherOpen     = false;
  bool _workTypeOtherOpen    = false;
  bool _toolsOtherOpen       = false;
  final _educationOtherCtrl = TextEditingController();
  final _skillOtherCtrl     = TextEditingController();
  final _workExpOtherCtrl   = TextEditingController();
  final _workTypeOtherCtrl  = TextEditingController();
  final _toolsOtherCtrl     = TextEditingController();
  bool _langOtherOpen       = false;
  final _langOtherCtrl      = TextEditingController();

  // ── Q9 (educated) — repeatable employer/role/place/duration/type entries.
  // Shared shape and persistence with ausbildung_cv_questionnaire_screen.dart.
  final List<_JobEntry> _jobEntries = [_JobEntry()];
  bool _jobEntriesPrefilled = false;

  // ── Q13 (educated) — per-language CEFR proficiency ─────────────────────────
  // Language (German display label) -> level. Populated as the user taps a
  // language chip then a level in the same motion.
  Map<String, String> _languageProficiency = {};

  // ── Effective voiceMode (with SharedPreferences fallback) ──────────────────
  late bool _voiceMode;

  // ── TTS state ───────────────────────────────────────────────────────────────
  bool _ttsPlaying = false;

  // ── Validation errors ───────────────────────────────────────────────────────
  String? _pageError;

  // ── Derived ─────────────────────────────────────────────────────────────────
  bool get _isEducated  => !_voiceMode;
  bool get _isRtl       => _lang == 'ps' || _lang == 'fa';
  bool get _showSpeaker => !_isEducated && _isRtl;

  // ─────────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _voiceMode = widget.voiceMode;
    AnalyticsService().logScreen('questionnaire');
    _lang = widget.language;
    TtsService().addListener(_onTtsChange);
    _initVoiceMode();
    // Only reload previous answers in edit mode - a fresh "Create CV" pass
    // (isEditMode: false, the default) starts blank except for the shared
    // personal-data fields PersonalDataScreen already collected.
    if (widget.isEditMode) {
      _loadSharedData();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<LanguageProvider>().syncFromNav(
          widget.language,
          voiceMode: _voiceMode,
        );
      }
    });
  }

  Future<void> _initVoiceMode() async {
    final prefs = await SharedPreferences.getInstance();
    if (!_voiceMode) {
      final saved = prefs.getBool('voice_mode') ?? false;
      if (saved && mounted) {
        setState(() => _voiceMode = true);
      }
    }
    await prefs.setBool('voice_mode', _voiceMode);
  }

  static List<String> _splitCsv(String raw) =>
      raw.isEmpty ? const [] : raw.split(',');

  // Duration strings are stored as '$from - $until' (or a single side), with
  // 'heute' meaning "present" - same convention as
  // ausbildung_cv_questionnaire_screen.dart's _WorkExpEntry.duration getter.
  static void _applyDuration(_JobEntry e, String duration) {
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

  // Pre-fills Berufserfahrung und Praktika and IT-Kenntnisse from
  // 'saved_profile' if the user already filled them via the Ausbildung CV
  // questionnaire (or a previous Job CV) - shared keys, so nothing is asked
  // twice. Sprachkenntnisse is left exactly as it was (not pre-filled here),
  // per spec.
  Future<void> _loadSharedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('saved_profile');
      if (raw == null || raw.isEmpty) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;

      final companies  = _splitCsv(map['previousEmployers'] as String? ?? '');
      final roles      = _splitCsv(map['previousJobTitles'] as String? ?? '');
      final durations  = _splitCsv(map['previousJobDurations'] as String? ?? '');
      final orts       = _splitCsv(map['sharedWorkOrts'] as String? ?? '');
      final types      = _splitCsv(map['sharedWorkTypes'] as String? ?? '');
      if (companies.isNotEmpty) {
        final entries = <_JobEntry>[];
        for (var i = 0; i < companies.length; i++) {
          final e = _JobEntry();
          e.employerCtrl.text = companies[i];
          e.titleCtrl.text = i < roles.length ? roles[i] : '';
          e.ortCtrl.text = i < orts.length ? orts[i] : '';
          e.entryType = i < types.length && types[i].isNotEmpty ? types[i] : null;
          if (i < durations.length) _applyDuration(e, durations[i]);
          entries.add(e);
        }
        if (mounted) {
          setState(() {
            for (final old in _jobEntries) {
              old.dispose();
            }
            _jobEntries
              ..clear()
              ..addAll(entries);
            _jobEntriesPrefilled = true;
          });
        }
      }

      final itSkills = _splitCsv(map['sharedItSkills'] as String? ?? '');
      if (itSkills.isNotEmpty && mounted) {
        setState(() {
          _itSkillsSelected
              .addAll(itSkills.where((s) => _kItSkillLabels.contains(s)));
          _itSkillsPrefilled = true;
        });
      }
    } catch (_) {}
  }

  void _onTtsChange() {
    if (mounted) setState(() => _ttsPlaying = TtsService().isPlaying);
  }

  @override
  void dispose() {
    TtsService().removeListener(_onTtsChange);
    TtsService().stop();
    _schoolOrtCtrl.dispose();
    _skillSearchCtrl.dispose();
    _refNameCtrl.dispose();
    _refPhoneCtrl.dispose();
    _educationOtherCtrl.dispose();
    _skillOtherCtrl.dispose();
    _workExpOtherCtrl.dispose();
    _workTypeOtherCtrl.dispose();
    _toolsOtherCtrl.dispose();
    _langOtherCtrl.dispose();
    _itSkillsCustomCtrl.dispose();
    for (final entry in _jobEntries) {
      entry.dispose();
    }
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Localised helpers
  // ─────────────────────────────────────────────────────────────────────────────

  String get _requiredMsg {
    switch (_lang) {
      case 'ps': return 'مهرباني وکړئ ټول تش ځایونه ډک کړئ';
      case 'fa': return 'لطفاً همه فیلدهای ضروری را پر کنید';
      default:   return 'Please fill in all required fields';
    }
  }

  // Shown whenever the user tries to add/select a 6th item in a field
  // capped at 5 (Berufserfahrung entries, IT-Kenntnisse, etc).
  String get _maxLimitMsg {
    switch (_lang) {
      case 'ps': return 'تاسو د ۵ څخه زیات نشئ اضافه کولی';
      case 'fa': return 'شما نمی‌توانید بیشتر از ۵ مورد اضافه کنید';
      default:   return "You can't add more than 5";
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

  // ─────────────────────────────────────────────────────────────────────────────
  // Navigation helpers
  // ─────────────────────────────────────────────────────────────────────────────

  void _goBack() {
    TtsService().stop();
    Navigator.pop(context);
  }

  Future<void> _createCv() async {
    if (_skills.isEmpty || _workExperience == null || _languages.isEmpty) {
      setState(() => _pageError = _requiredMsg);
      return;
    }
    setState(() => _pageError = null);

    // Both educated and uneducated users fill the same repeatable job
    // entries (Q9), now shared with the Ausbildung CV questionnaire. Empty
    // employer rows are dropped; order is preserved (most-recent-first).
    final effectiveEmployers = <String>[];
    final effectiveTitles = <String>[];
    final effectiveDurations = <String>[];
    final effectiveOrts = <String>[];
    final effectiveTypes = <String>[];
    for (final e in _jobEntries) {
      if (e.employer.isEmpty) continue;
      effectiveEmployers.add(e.employer);
      effectiveTitles.add(e.jobTitle);
      effectiveDurations.add(e.duration);
      effectiveOrts.add(e.ort);
      effectiveTypes.add(e.entryType ?? '');
    }

    final customIt = _itSkillsCustomCtrl.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty);
    final itSkills = <String>[..._itSkillsSelected, ...customIt];

    // Personal data (name/DOB/nationality/address/phone/email/photo) was
    // already collected by PersonalDataScreen before this screen was ever
    // reached - read it back from 'saved_profile' rather than asking again.
    var map = <String, dynamic>{};
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('saved_profile');
      if (raw != null && raw.isNotEmpty) {
        map = jsonDecode(raw) as Map<String, dynamic>;
      }
    } catch (_) {}

    map['skill']                 = _skills.join(',');
    map['workExperience']        = _workExperience ?? '';
    map['workType']              = _workType ?? '';
    map['tools']                 = _tools ?? '';
    map['drivingLicense']        = _drivingLicense ?? '';
    map['languages']             = _languages.join(',');
    map['languageProficiency']   =
        UserProfile.encodeProficiency(_languageProficiency);
    map['availability']          = _availability ?? '';
    map['startDate']             = _startDate ?? '';
    map['educationLevel']        = _educationLevel ?? '';
    map['educationOrt']          = _schoolOrtCtrl.text.trim();
    map['educationDuration']     = _schoolDuration;
    map['reference']             = _reference ?? '';
    map['refName']                = _refNameCtrl.text.trim();
    map['refPhone']               = _refPhoneCtrl.text.trim();
    map['previousEmployers']      = effectiveEmployers.join(',');
    map['previousJobTitles']      = effectiveTitles.join(',');
    map['previousJobDurations']   = effectiveDurations.join(',');
    map['sharedWorkOrts']         = effectiveOrts.join(',');
    map['sharedWorkTypes']        = effectiveTypes.join(',');
    map['sharedItSkills']         = itSkills.join(',');

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_profile', jsonEncode(map));
    } catch (_) {}

    final profile = UserProfile.fromMap(map);

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReviewScreen(language: _lang, profile: profile),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Language picker
  // ─────────────────────────────────────────────────────────────────────────────

  void _showLangPicker() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD1D9E6),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Language / ژبه / زبان',
                style: TextStyle(
                  color: _navy,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),
              for (final pair in [
                ['ps', 'پښتو',    'Pashto'],
                ['fa', 'دری',     'Dari'],
                ['en', 'English', 'English'],
              ])
                GestureDetector(
                  onTap: () {
                    setState(() => _lang = pair[0]);
                    Navigator.pop(ctx);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: _lang == pair[0]
                          ? _green.withOpacity(0.08)
                          : const Color(0xFFF7FAFF),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _lang == pair[0] ? _green : const Color(0xFFE4EAF5),
                        width: _lang == pair[0] ? 2.0 : 1.2,
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(pair[1], style: TextStyle(
                          color: _navy,
                          fontSize: 16,
                          fontWeight: _lang == pair[0]
                              ? FontWeight.w800
                              : FontWeight.w600,
                        )),
                        const SizedBox(width: 8),
                        Text(pair[2], style: const TextStyle(
                          color: _muted,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        )),
                        const Spacer(),
                        if (_lang == pair[0])
                          const Icon(Icons.check_circle_rounded,
                              color: _green, size: 20),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
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
                Expanded(child: _buildBody()),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Header
  // ─────────────────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Row(
        children: [
          _NavIconBtn(icon: Icons.arrow_back_ios_new_rounded, onTap: _goBack),
          Expanded(
            child: Text(
              _lang == 'ps' ? 'کار او مهارتونه'
                  : _lang == 'fa' ? 'کار و مهارت‌ها'
                  : 'Work & Skills',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _navy,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (_ttsPlaying && _showSpeaker) ...[
            GestureDetector(
              onTap: () => TtsService().stop(),
              child: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAFBE9),
                  shape: BoxShape.circle,
                  border: Border.all(color: _green.withOpacity(0.4)),
                ),
                child: const Icon(Icons.stop_rounded, color: _green, size: 18),
              ),
            ),
            const SizedBox(width: 8),
          ],
          _LangPill(lang: _lang, onPick: _showLangPicker),
          const SizedBox(width: 8),
          _NavIconBtn(
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
  // Page title glass card
  // ─────────────────────────────────────────────────────────────────────────────

  Widget _buildTitleCard(String title, String subtitle) {
    return _GlassSurface(
      borderRadius: 20,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      shadowOpacity: 0.10,
      child: Directionality(
        textDirection: _isRtl ? TextDirection.rtl : TextDirection.ltr,
        child: Column(
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _navy,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _muted,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Body — Work & Skills (single page; personal data lives in
  // PersonalDataScreen, asked once before this screen is ever reached)
  // ─────────────────────────────────────────────────────────────────────────────

  Widget _buildBody() {
    final title = _lang == 'ps' ? 'ستاسی کار او مهارتونه '
        : _lang == 'fa' ? 'کار و مهارت‌ها'
        : 'Work & Skills';
    final subtitle = _lang == 'ps' ? 'لاندې خپل معلومات ډک کړئ'
        : _lang == 'fa' ? 'جزئیات خود را در زیر پر کنید'
        : 'Fill in your details below';

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
      child: Column(
        children: [
          _buildTitleCard(title, subtitle),
          const SizedBox(height: 16),

          _isEducated ? _buildPage2Educated() : _buildPage2Uneducated(),

          if (_pageError != null) ...[
            const SizedBox(height: 12),
            Text(
              _pageError!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red, fontSize: 13),
            ),
          ],

          const SizedBox(height: 16),
          _BigButton(
            label: _lang == 'ps' ? ' جوړ کړئ CV →'
                : _lang == 'fa' ? 'ایجاد CV →'
                : 'Create CV →',
            onTap: _createCv,
            isGreen: true,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Page 2 — Uneducated (large cards + speaker icons)
  // ─────────────────────────────────────────────────────────────────────────────

  Widget _buildPage2Uneducated() {
    return Column(
      children: [
        // Q8 Skills grid
        _QCard(
          question: _lang == 'ps' ? '۸. تاسو کوم مهارتونه لری؟'
              : _lang == 'fa' ? '۸. چه مهارت‌هایی دارید؟'
              : '8. What skills do you have?',
          isRtl: _isRtl, showSpeaker: _showSpeaker,
          onSpeak: () => _snackSpeak(
              _lang == 'ps' ? 'تاسو کوم مهارتونه لری؟' : 'چه مهارت‌هایی دارید؟'),
          child: _skillGrid(),
        ),
        const SizedBox(height: 12),

        // Q9 Work experience
        _QCard(
          question: _lang == 'ps' ? '۹. ایا مخکې مو چیرت کار کړی دی؟'
              : _lang == 'fa' ? '۹. آیا قبلاً کار کرده‌اید؟'
              : '9. Have you worked before?',
          isRtl: _isRtl, showSpeaker: _showSpeaker,
          onSpeak: () => _snackSpeak(
              _lang == 'ps' ? 'ایا مخکې مو چیرته کار کړی دی؟' : 'آیا قبلاً کار کرده‌اید؟'),
          child: _bigChoices(
            _workExpOptions(),
            _workExperience,
            (v) => setState(() {
              _workExperience = v;
              if (v == 'never') _workType = null;
            }),
          ),
        ),
        const SizedBox(height: 12),

        // Q9b Work type (conditional)
        if (_workExperience != null && _workExperience != 'never') ...[
          _QCard(
            question: _lang == 'ps' ? 'کوم ډول کار مو مخکی کړی دی؟'
                : _lang == 'fa' ? 'چه نوع کاری قبلاً کرده‌اید؟'
                : 'What type of work?',
            isRtl: _isRtl, showSpeaker: _showSpeaker,
            onSpeak: () => _snackSpeak(
                _lang == 'ps' ? 'کوم ډول کار مو مخکی کړی دی؟' : 'چه نوع کاری؟'),
            child: _bigChoices(
              _workTypeOptions(),
              _workType,
              (v) => setState(() => _workType = v),
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Q9c Previous employers (only when user has real work experience)
        if (_workExperience == 'more2' || _workExperience == 'less2') ...[
          _QCard(
            question: _lang == 'ps' ? 'تاسو مخکې چیرته کار کړی دی؟'
                : _lang == 'fa' ? 'قبلاً کجا کار کرده‌اید؟'
                : 'Where have you worked before?',
            isRtl: _isRtl, showSpeaker: _showSpeaker,
            onSpeak: () => _snackSpeak(
                _lang == 'ps' ? 'تاسو مخکې چیرته کار کړی دی؟' : 'قبلاً کجا کار کرده‌اید؟'),
            child: _jobEntriesUneducated(),
          ),
          const SizedBox(height: 12),
        ],

        // Q10 Tools
        _QCard(
          question: _lang == 'ps' ? '۱۰. تاسو کوم ډول سامان یا ماشینونو سره کار کولی شی؟'
              : _lang == 'fa' ? '۱۰. آیا می‌توانید با ابزار کار کنید؟'
              : '10. Can you use tools or machines?',
          isRtl: _isRtl, showSpeaker: _showSpeaker,
          onSpeak: () => _snackSpeak(
              _lang == 'ps' ? 'تاسو کوم ډول سامان یا ماشینونو سره کار کولی شی؟' : 'آیا می‌توانید با ابزار کار کنید؟'),
          child: _bigChoices(_toolsOptions(), _tools,
              (v) => setState(() => _tools = v)),
        ),
        const SizedBox(height: 12),

        // IT-Kenntnisse — shared with the Ausbildung CV questionnaire
        _QCard(
          question: _itSkillsQuestion,
          isRtl: _isRtl, showSpeaker: _showSpeaker,
          onSpeak: () => _snackSpeak(_itSkillsQuestion),
          child: _itSkillsSection(),
        ),
        const SizedBox(height: 12),

        // Q11 Driving license
        _QCard(
          question: _lang == 'ps' ? '۱۱. ایا د موټر چلولو لیسنس لری؟'
              : _lang == 'fa' ? '۱۱. آیا گواهینامه رانندگی دارید؟'
              : '11. Do you have a driving license?',
          isRtl: _isRtl, showSpeaker: _showSpeaker,
          onSpeak: () => _snackSpeak(
              _lang == 'ps' ? 'ایا د موټر چلولو لیسنس لری؟' : 'آیا گواهینامه رانندگی دارید؟'),
          child: _bigChoices(_licenseOptions(), _drivingLicense,
              (v) => setState(() => _drivingLicense = v)),
        ),
        const SizedBox(height: 12),

        // Q12 Languages
        _QCard(
          question: _lang == 'ps' ? '۱۲. تاسو په کومو ژبو خبري کولی شئ؟'
              : _lang == 'fa' ? '۱۲. چه زبان‌هایی صحبت می‌کنید؟'
              : '12. Which languages do you speak?',
          isRtl: _isRtl, showSpeaker: _showSpeaker,
          onSpeak: () => _snackSpeak(
              _lang == 'ps' ? 'تاسو په کومو ژبو خبري کولی شئ؟' : 'چه زبان‌هایی صحبت می‌کنید؟'),
          child: _languageProficiencyUneducated(),
        ),
        const SizedBox(height: 12),

        // Q13 Availability
        _QCard(
          question: _lang == 'ps' ? '۱۳. څرنګه کار غواړی پیدا کړي؟'
              : _lang == 'fa' ? '۱۳. چه زمانی می‌توانید کار کنید؟'
              : '13. When can you work?',
          isRtl: _isRtl, showSpeaker: _showSpeaker,
          onSpeak: () => _snackSpeak(
              _lang == 'ps' ? 'څرنګه کار غواړی پیدا کړي؟' : 'چه زمانی می‌توانید کار کنید؟'),
          child: _bigChoices(_availOptions(), _availability,
              (v) => setState(() => _availability = v)),
        ),
        const SizedBox(height: 12),

        // Q14 Start date
        // Reference question (formerly Q15) intentionally removed for
        // uneducated users — kept for educated users in
        // _buildPage2Educated() below.
        _QCard(
          question: _lang == 'ps' ? '۱۴. کله نوی کار شروع کولی شئ؟'
              : _lang == 'fa' ? '۱۴. چه زمانی می‌توانید شروع کنید؟'
              : '14. When can you start?',
          isRtl: _isRtl, showSpeaker: _showSpeaker,
          onSpeak: () => _snackSpeak(
              _lang == 'ps' ? 'کله نوی کار شروع کولی شئ؟' : 'چه زمانی می‌توانید شروع کنید؟'),
          child: _bigChoices(_startOptions(), _startDate,
              (v) => setState(() => _startDate = v)),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Page 2 — Educated (compact chips, no speaker)
  // ─────────────────────────────────────────────────────────────────────────────

  Widget _buildPage2Educated() {
    return Column(
      children: [
        // Education level (moved from the old personal-info page - job-CV
        // specific, not shared with the Ausbildung CV questionnaire).
        _QCard(
          question: _lang == 'ps' ? 'ستاسو لوړه زده کړه'
              : _lang == 'fa' ? 'بالاترین سطح تحصیلات شما'
              : 'Your highest education level',
          isRtl: _isRtl, showSpeaker: false, onSpeak: () {},
          child: _educationPicker(),
        ),
        const SizedBox(height: 12),

        // Follow-up: school location + years attended - only asked once an
        // education level has been picked above (educated users only).
        if (_educationLevel != null) ...[
          _QCard(
            question: _schoolOrtQuestion,
            isRtl: _isRtl, showSpeaker: false, onSpeak: () {},
            child: _TxtField(
              controller: _schoolOrtCtrl,
              hint: _schoolOrtHint,
              action: TextInputAction.next,
            ),
          ),
          const SizedBox(height: 12),
          _QCard(
            question: _schoolZeitraumQuestion,
            isRtl: _isRtl, showSpeaker: false, onSpeak: () {},
            child: Row(
              children: [
                Expanded(
                  child: _yearDropdownField(
                    hint: _fromYearHint,
                    value: _schoolFromYear?.toString(),
                    includePresent: false,
                    onChanged: (v) => setState(
                        () => _schoolFromYear = v == null ? null : int.tryParse(v)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _yearDropdownField(
                    hint: _untilYearHint,
                    value: _schoolUntilYear,
                    includePresent: true,
                    onChanged: (v) => setState(() => _schoolUntilYear = v),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Q9 Skills with search
        _QCard(
          question: _lang == 'ps' ? '۹. تاسو کوم مهارتونه لري؟'
              : _lang == 'fa' ? '۹. مهارت‌های شما'
              : '9. Your skills',
          isRtl: _isRtl, showSpeaker: false, onSpeak: () {},
          child: _skillsEducated(),
        ),
        const SizedBox(height: 12),

        // Q10 Work experience
        _QCard(
          question: _lang == 'ps' ? '۱۰. تاسو څومره کاری تجربه لری؟'
              : _lang == 'fa' ? '۱۰. تجربه کاری'
              : '10. Work experience',
          isRtl: _isRtl, showSpeaker: false, onSpeak: () {},
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _chipChoices(_workExpOptions(), _workExperience,
                  (v) => setState(() {
                    _workExperience = v;
                    if (v == 'never') _workType = null;
                  })),
              const SizedBox(height: 8),
              _otherOptionRow(
                selected: _workExperience,
                ctrl: _workExpOtherCtrl,
                open: _workExpOtherOpen,
                onToggleOpen: () =>
                    setState(() => _workExpOtherOpen = !_workExpOtherOpen),
                onSubmit: (v) => setState(() {
                  _workExperience = v;
                  _workExpOtherOpen = false;
                }),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        if (_workExperience != null && _workExperience != 'never') ...[
          _QCard(
            question: _lang == 'ps' ? 'کوم ډول کاری تجربه لری؟'
                : _lang == 'fa' ? 'نوع کار قبلاً انجام شده'
                : 'Type of work',
            isRtl: _isRtl, showSpeaker: false, onSpeak: () {},
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _chipChoices(_workTypeOptions(), _workType,
                    (v) => setState(() => _workType = v)),
                const SizedBox(height: 8),
                _otherOptionRow(
                  selected: _workType,
                  ctrl: _workTypeOtherCtrl,
                  open: _workTypeOtherOpen,
                  onToggleOpen: () =>
                      setState(() => _workTypeOtherOpen = !_workTypeOtherOpen),
                  onSubmit: (v) => setState(() {
                    _workType = v;
                    _workTypeOtherOpen = false;
                  }),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        if (_workExperience == 'more2' || _workExperience == 'less2') ...[
          _QCard(
            question: _lang == 'ps' ? 'تاسو مخکې چیرته کار کړی دی؟'
                : _lang == 'fa' ? 'قبلاً کجا کار کرده‌اید؟'
                : 'Where have you worked before?',
            isRtl: _isRtl, showSpeaker: false, onSpeak: () {},
            child: _jobEntriesEducated(),
          ),
          const SizedBox(height: 12),
        ],

        _QCard(
          question: _lang == 'ps' ? '۱۱. تاسو کوم ډول سامان یا ماشینونو سره کار کولی شی؟'
              : _lang == 'fa' ? '۱۱. کار با ابزار'
              : '11. Tool experience',
          isRtl: _isRtl, showSpeaker: false, onSpeak: () {},
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _chipChoices(_toolsOptions(), _tools,
                  (v) => setState(() => _tools = v)),
              const SizedBox(height: 8),
              _otherOptionRow(
                selected: _tools,
                ctrl: _toolsOtherCtrl,
                open: _toolsOtherOpen,
                onToggleOpen: () =>
                    setState(() => _toolsOtherOpen = !_toolsOtherOpen),
                onSubmit: (v) => setState(() {
                  _tools = v;
                  _toolsOtherOpen = false;
                }),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // IT-Kenntnisse — shared with the Ausbildung CV questionnaire
        _QCard(
          question: _itSkillsQuestion,
          isRtl: _isRtl, showSpeaker: false, onSpeak: () {},
          child: _itSkillsSection(),
        ),
        const SizedBox(height: 12),

        _QCard(
          question: _lang == 'ps' ? '۱۲. د موټر جواز'
              : _lang == 'fa' ? '۱۲. گواهینامه رانندگی'
              : '12. Driving license',
          isRtl: _isRtl, showSpeaker: false, onSpeak: () {},
          child: _chipChoices(_licenseOptions(), _drivingLicense,
              (v) => setState(() => _drivingLicense = v)),
        ),
        const SizedBox(height: 12),

        _QCard(
          question: _lang == 'ps' ? '۱۳. ژبې'
              : _lang == 'fa' ? '۱۳. زبان‌ها'
              : '13. Languages',
          isRtl: _isRtl, showSpeaker: false, onSpeak: () {},
          child: _languageProficiencyEducated(),
        ),
        const SizedBox(height: 12),

        _QCard(
          question: _lang == 'ps' ? '۱۴. څرنګه کار غواړی پیدا کړي؟'
              : _lang == 'fa' ? '۱۴. چی رقم کار می‌خواهید؟'
              : '14. Availability',
          isRtl: _isRtl, showSpeaker: false, onSpeak: () {},
          child: _chipChoices(_availOptions(), _availability,
              (v) => setState(() => _availability = v)),
        ),
        const SizedBox(height: 12),

        _QCard(
          question: _lang == 'ps' ? '۱۵. کله نوی کار شروع کولی شئ؟'
              : _lang == 'fa' ? '۱۵. چه وقت کار نو می‌خواهید شروع کنید؟'
              : '15. Start date',
          isRtl: _isRtl, showSpeaker: false, onSpeak: () {},
          child: _chipChoices(_startOptions(), _startDate,
              (v) => setState(() => _startDate = v)),
        ),
        const SizedBox(height: 12),

        _QCard(
           question: _lang == 'ps' ? '۱۵. ایا څوک شته چی ستاسي مخکی کار تایید کړي؟'
              : _lang == 'fa' ? '۱۵. آیا کسی هست که کار شما را تأیید کند؟'
              : '16. Reference contact From Previous Job',
          isRtl: _isRtl, showSpeaker: false, onSpeak: () {},
          child: _referenceSection(),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Option data helpers
  // ─────────────────────────────────────────────────────────────────────────────

  List<_Opt> _workExpOptions() => [
    _Opt('more2', Icons.workspace_premium_rounded,
        _lang == 'ps' ? 'هو، ۲+ کاله'        : _lang == 'fa' ? 'بله، ۲+ سال'           : 'Yes, 2+ years',
        'هو، دوه کاله یا زیات کاری تجربه'),
    _Opt('less2', Icons.work_rounded,
        _lang == 'ps' ? 'هو، لږ له ۲ کاله'   : _lang == 'fa' ? 'بله، کمتر از ۲ سال'    : 'Yes, less than 2 years',
        'هو، یو کال یا زیات کاری تجربه'),
    _Opt('small', Icons.handyman_rounded,
        _lang == 'ps' ? 'یوازې وړوکي کارونه' : _lang == 'fa' ? 'فقط کارهای کوچک'       : 'Small jobs only',
        'یوازې وړې دندې'),
    _Opt('never', Icons.block_rounded,
        _lang == 'ps' ? 'هیڅکله نه دی'       : _lang == 'fa' ? 'هرگز کار نکرده‌ام'      : 'Never worked',
        'هیڅکله کار نه دی کړی'),
  ];

  List<_Opt> _workTypeOptions() => [
    _Opt('construction', Icons.construction_rounded,
        _lang == 'ps' ? 'جوړونه'    : _lang == 'fa' ? 'ساخت‌وساز' : 'Construction',
        'ساختمانی کار'),
    _Opt('cleaning',     Icons.cleaning_services_rounded,
        _lang == 'ps' ? 'پاکوالی'   : _lang == 'fa' ? 'نظافت'     : 'Cleaning',
        'پاک کاری'),
    _Opt('kitchen',      Icons.restaurant_rounded,
        _lang == 'ps' ? 'آشپزخانه'  : _lang == 'fa' ? 'آشپزخانه'  : 'Kitchen',
        'پخلی یا اشپزی'),
    _Opt('driving',      Icons.drive_eta_rounded,
        _lang == 'ps' ? 'چلولو'     : _lang == 'fa' ? 'رانندگی'   : 'Driving',
        'موټر چلول'),
  ];

  List<_Opt> _toolsOptions() => [
    _Opt('power_tools',   Icons.electrical_services_rounded,
        _lang == 'ps' ? 'بریښنایي وسایل'     : _lang == 'fa' ? 'ابزار برقی'              : 'Power tools',
        'بریښنایي یا برقي سامان آلات'),
    _Opt('kitchen_equip', Icons.blender_rounded,
        _lang == 'ps' ? 'د آشپزخانې وسایل'   : _lang == 'fa' ? 'لوازم آشپزخانه'          : 'Kitchen equipment',
        'د اشپزخانی سامان آلات'),
    _Opt('tractor',       Icons.agriculture_rounded,
        _lang == 'ps' ? 'ټراکټر / وسایط'     : _lang == 'fa' ? 'تراکتور / وسیله‌نقلیه'  : 'Tractor/vehicles',
        'موټر یا ماشین'),
    _Opt('no_tools',      Icons.do_not_disturb_rounded,
        _lang == 'ps' ? 'هیڅ وسیله نه'       : _lang == 'fa' ? 'بدون ابزار'              : 'No tools',
        'نه، وسیلې نه کاروم'),
  ];

  List<_Opt> _licenseOptions() => [
    _Opt('german_license',  Icons.directions_car_rounded,
        _lang == 'ps' ? 'جرمني جواز'         : _lang == 'fa' ? 'گواهینامه آلمان'         : 'German license',
        'د جرمني لیسنس'),
    _Opt('foreign_license', Icons.drive_eta_rounded,
        _lang == 'ps' ? 'بهرني جواز'         : _lang == 'fa' ? 'گواهینامه خارجی'         : 'Foreign license',
        'بهرنی لیسنس'),
    _Opt('want_license',    Icons.school_rounded,
        _lang == 'ps' ? 'نه، خو غواړم زده کړم': _lang == 'fa' ? 'نه، می‌خواهم یاد بگیرم': 'No, want to learn',
        'نه، خو زده کول غواړم'),
    _Opt('no_license',      Icons.block_rounded,
        _lang == 'ps' ? 'نه لرم'             : _lang == 'fa' ? 'ندارم'                   : 'No license',
        'نه'),
  ];

  // Q13/Q14 (availability) — PS/FA text is intentionally the German term
  // transliterated into Pashto/Dari script (not a native translation), so
  // users recognize the exact term German employers use. Label and TTS are
  // the same string, matching the existing "فول سایټ یعنی ۴۰ ساعته" style.
  List<_Opt> _availOptions() => [
    // FIX 2: Pashto TTS previously spelled "40" as the digit "۴۰", which
    // Pashto TTS engines read out digit-by-digit ("salor-sifr", i.e.
    // "four-zero") instead of the whole number. "څلوېښت" is the correct
    // Pashto word for "forty" ("Salwekht") and reads correctly. Dari isn't
    // affected — Dari option text is never spoken aloud in this app.
    _Opt('fulltime', Icons.schedule_rounded,
        _lang == 'ps' ? 'فول سایټ یعنی څلوېښت ساعته'
            : _lang == 'fa' ? 'فول تایم یعنی ۴۰ ساعت در ماه'
            : 'Full time',
        _lang == 'ps' ? 'فول سایټ یعنی څلوېښت ساعته' : null),
    _Opt('parttime', Icons.access_time_rounded,
        _lang == 'ps' ? 'تایل سایټ یعنی له څلوېښت ساعتونو کم '
            : _lang == 'fa' ? 'تایل تایم یعنی کمتر از ۴۰ ساعت'
            : 'Part time',
        _lang == 'ps' ? 'تایل سایټ یعنی له څلوېښت ساعتونو کم ' : null),
    _Opt('flexible', Icons.tune_rounded,
        _lang == 'ps' ? 'مینی جوب یعنی لږ ساعته کار'
            : _lang == 'fa' ? 'مینی جاب یعنی کار با ساعت کم'
            : 'Minijob',
        _lang == 'ps' ? 'مینی جوب یعنی لږ ساعته کار' : null),
    _Opt('weekends', Icons.weekend_rounded,
        _lang == 'ps' ? 'زمستاګ او زونتاګ یعنی د اونۍ پای (شنبه او یکشنبه)'
            : _lang == 'fa' ? 'زمستاگ او زونتاگ یعنی آخر هفته (شنبه و یکشنبه)'
            : 'Weekends',
        _lang == 'ps' ? 'زمستاګ او زونتاګ یعنی د اونۍ پای (شنبه او یکشنبه)' : null),
  ];

  List<_Opt> _startOptions() => [
    _Opt('immediately', Icons.bolt_rounded,
        _lang == 'ps' ? 'سمدلاسه'    : _lang == 'fa' ? 'فوری'         : 'Immediately',
        'کولی شم کار شروع کړم سمدستي'),
    _Opt('two_weeks',   Icons.event_rounded,
        _lang == 'ps' ? '۲ اونۍ کې'  : _lang == 'fa' ? 'در ۲ هفته'   : 'In 2 weeks',
        'دوه اونۍ وروسته کولی شم کار شروع کړم'),
    _Opt('one_month',   Icons.calendar_month_rounded,
        _lang == 'ps' ? '۱ میاشت کې' : _lang == 'fa' ? 'در ۱ ماه'    : 'In 1 month',
        'یو میاشت وروسته کولی شم کار شروع کړم'),
    _Opt('unsure',      Icons.help_outline_rounded,
        _lang == 'ps' ? 'ټاکلي نه دی': _lang == 'fa' ? 'مطمئن نیستم' : 'Not sure yet',
        'ډاډه نه یم'),
  ];

  List<_Opt> _refOptions() => [
    _Opt('employer', Icons.business_rounded,
        _lang == 'ps' ? 'پخواني کارفرما' : _lang == 'fa' ? 'کارفرمای سابق'    : 'Former employer',
        'پخوانی کار مشر نوم'),
    _Opt('leader',   Icons.record_voice_over_rounded,
        _lang == 'ps' ? 'ملا / مشر'      : _lang == 'fa' ? 'رهبر / امام'       : 'Community leader/Imam',
        'نوم ټولنیز مشر'),
    _Opt('neighbor', Icons.people_rounded,
        _lang == 'ps' ? 'ګاونډی / دوست' : _lang == 'fa' ? 'همسایه / دوست'     : 'Neighbor/friend',
        'ګاونډی یا ملګری'),
    _Opt('no_ref',   Icons.person_off_rounded,
        _lang == 'ps' ? 'مرجع نه لرم'   : _lang == 'fa' ? 'مرجعی ندارم'       : 'No reference',
        'په تیر کار کی هیڅوک نه پیژنم'),
  ];

  // ─────────────────────────────────────────────────────────────────────────────
  // Sub-widgets built inline
  // ─────────────────────────────────────────────────────────────────────────────

  // ── "Other / type your own" free-text row (educated only) ──────────────────
  // Shared by every educated chip/card question that isn't in the excluded
  // set (Q12 license, Q14 availability, Q15 start date, Q15/16 reference).
  // `selected` should be the field's current value ONLY when that value is
  // a custom string (not one of the preset chip values) — this both
  // highlights the row and keeps the text field pre-filled on rebuild.

  String get _otherLabel {
    switch (_lang) {
      case 'ps': return 'نور (پخپله ولیکئ)';
      case 'fa': return 'دیگر (خودتان بنویسید)';
      default:   return 'Other / type your own';
    }
  }

  String get _otherHint {
    switch (_lang) {
      case 'ps': return 'دلته ولیکئ...';
      case 'fa': return 'اینجا بنویسید...';
      default:   return 'Type your answer...';
    }
  }

  Widget _otherOptionRow({
    required String? selected,
    required TextEditingController ctrl,
    required bool open,
    required VoidCallback onToggleOpen,
    required ValueChanged<String> onSubmit,
  }) {
    final isCustomSelected =
        selected != null && selected.isNotEmpty && selected == ctrl.text;
    final active = open || isCustomSelected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: onToggleOpen,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: active ? const Color(0xFFEAFBE9) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: active ? _green : const Color(0xFFDDE4EF),
                width: active ? 2.0 : 1.2,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.edit_rounded,
                    size: 14, color: active ? _green : _muted),
                const SizedBox(width: 5),
                Text(_otherLabel,
                    style: const TextStyle(
                      color: Color(0xFF091733),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    )),
                if (isCustomSelected) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.check_rounded, color: _green, size: 13),
                ],
              ],
            ),
          ),
        ),
        if (open) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _TxtField(
                  controller: ctrl,
                  hint: _otherHint,
                  action: TextInputAction.done,
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  final v = ctrl.text.trim();
                  if (v.isNotEmpty) onSubmit(v);
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _green,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.check_rounded,
                      color: Color(0xFF091733), size: 20),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  // Follow-up questions shown once an education level is picked -
  // educated users only.
  String get _schoolOrtQuestion {
    switch (_lang) {
      case 'ps': return 'د ښوونځي ځای (ښار)';
      case 'fa': return 'محل مدرسه (شهر)';
      default:   return 'School location (Ort der Schule)';
    }
  }

  String get _schoolOrtHint {
    switch (_lang) {
      case 'ps': return 'د ښار نوم ولیکئ';
      case 'fa': return 'نام شهر را بنویسید';
      default:   return 'Enter city name';
    }
  }

  String get _schoolZeitraumQuestion {
    switch (_lang) {
      case 'ps': return 'د زده کړې موده (له - تر)';
      case 'fa': return 'دوره تحصیل (از - تا)';
      default:   return 'Years attended (Zeitraum)';
    }
  }

  Widget _educationPicker() {
    const opts = [
      ['primary',    'Primary school',         'ابتدایي',      'ابتدایی'],
      ['secondary',  'Secondary school',       'منځنۍ یا متوسط',        'راهنمایی'],
      ['highschool', 'High school (Abitur)',   'لیسه',         'دبیرستان'],
      ['vocational', 'Vocational training',    'مسلکي روزنه یا اوسبلدونګ',  'آموزش حرفه‌ای'],
      ['university', 'University degree',      'پوهنتون',      'دانشگاه'],
      ['masters',    'Master / PhD',           'ماستري',       'کارشناسی ارشد'],
    ];
    final presetCodes = opts.map((o) => o[0]).toSet();
    final isCustom = _educationLevel != null && !presetCodes.contains(_educationLevel);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
      spacing: 8,
      runSpacing: 8,
      children: opts.map((o) {
        final lbl = _lang == 'ps' ? o[2] : _lang == 'fa' ? o[3] : o[1];
        final sel = _educationLevel == o[0];
        return GestureDetector(
          onTap: () => setState(() {
            _educationLevel = o[0];
            _educationOtherOpen = false;
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: sel
                  ? const Color(0xFFEAFBE9)
                  : Colors.white.withOpacity(0.85),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: sel ? _green : Colors.white.withOpacity(0.9),
                width: sel ? 2.0 : 1.2,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(lbl,
                    style: TextStyle(
                      color: _navy,
                      fontSize: 13,
                      fontWeight:
                          sel ? FontWeight.w700 : FontWeight.w500,
                    )),
                if (sel) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.check_rounded, color: _green, size: 14),
                ],
              ],
            ),
          ),
        );
      }).toList(),
        ),
        const SizedBox(height: 8),
        _otherOptionRow(
          selected: isCustom ? _educationLevel : null,
          ctrl: _educationOtherCtrl,
          open: _educationOtherOpen,
          onToggleOpen: () =>
              setState(() => _educationOtherOpen = !_educationOtherOpen),
          onSubmit: (v) => setState(() {
            _educationLevel = v;
            _educationOtherOpen = false;
          }),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // IT-Kenntnisse — shared with ausbildung_cv_questionnaire_screen.dart via
  // the 'sharedItSkills' key. Same fixed checklist + custom free-text field,
  // same max-5 cap.
  // ─────────────────────────────────────────────────────────────────────────────

  String get _itSkillsQuestion => 'IT-Kenntnisse';

  String get _itSkillsPrefilledNote {
    switch (_lang) {
      case 'ps': return 'دا له مخکینیو ډکو معلوماتو څخه راغلي، تاسو یې سمولی شئ';
      case 'fa': return 'این از اطلاعات قبلی شما بارگذاری شده، می‌توانید ویرایش کنید';
      default:   return 'Loaded from your other CV, edit if needed';
    }
  }

  String get _itSkillsCustomHint {
    switch (_lang) {
      case 'ps': return 'نور IT مهارتونه، په کوما سره جلا کړئ';
      case 'fa': return 'مهارت‌های IT دیگر، با کاما جدا کنید';
      default:   return 'Other IT skills, separated by commas';
    }
  }

  Widget _itSkillsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_itSkillsPrefilled) ...[
          Row(
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
          ),
          const SizedBox(height: 8),
        ],
        for (final label in _kItSkillLabels) _itSkillRow(label),
        const SizedBox(height: 4),
        _TxtField(
          controller: _itSkillsCustomCtrl,
          hint: _itSkillsCustomHint,
          action: TextInputAction.done,
        ),
      ],
    );
  }

  Widget _itSkillRow(String label) {
    final selected = _itSkillsSelected.contains(label);
    return GestureDetector(
      onTap: () {
        if (!selected && _itSkillsSelected.length >= _kMaxItSkills) {
          _showMaxLimitSnack();
          return;
        }
        setState(() {
          if (selected) {
            _itSkillsSelected.remove(label);
          } else {
            _itSkillsSelected.add(label);
          }
        });
      },
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

  Widget _skillGrid() {
    const skills = [
      ('lifting',        Icons.fitness_center,         ['Heavy lifting',   'درانه شیان',       'حمل بار'],     'درانه شیان'),
      ('cooking',        Icons.restaurant,             ['Cooking',         'پخلي',              'آشپزی'],       'پخلی یا اشپزی'),
      ('driving',        Icons.drive_eta,              ['Driving',         'چلولو',             'رانندگی'],     'موټر چلول'),
      ('cleaning',       Icons.cleaning_services,      ['Cleaning',        'پاکوالی',           'نظافت'],       'پاک کاری'),
      ('fixing',         Icons.build,                  ['Repair',          'سمون',              'تعمیر'],       'سمون'),
      ('packing',        Icons.inventory_2,            ['Packing',         'بسته کول',          'بسته‌بندی'],   'بسته بندي یا پیکینګ'),
      ('security',       Icons.security,               ['Security',        'امنیت',             'امنیت'],       'سیکیورټی یا امنیت'),
      ('forklift',       Icons.forklift,               ['Forklift',        'فورکلیفت',          'لیفتراک'],     'فورکلیفت'),
      ('farming',        Icons.grass,                  ['Farming',         'کرنه',              'کشاورزی'],     'باغوانی'),
      ('sales',          Icons.store,                  ['Sales',           'پلور',              'فروش'],        'پلور'),
      ('sewing',         Icons.content_cut,            ['Sewing',          'ګنډل',              'خیاطی'],       'ګنډل'),
      ('construction',   Icons.construction,           ['Construction',    'جوړونه',            'ساخت‌وساز'],   'ساختمانی کار'),
      ('mobile_repair',  Icons.phone_android,          ['Mobile repair',   'موبایل سمول',       'تعمیر موبایل'],'موبایل سمول'),
      ('amazon_packing', Icons.local_shipping,         ['Warehouse/Amazon','ګدام',              'انبارداری'],   'ګودام کار یا لاګه لوجستیک'),
      ('dhl',            Icons.delivery_dining,        ['Delivery/DHL',    'ډلیوري',            'تحویل بسته'], 'ډلیوري'),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      childAspectRatio: 2.6,
      children: skills.map((s) {
        final lbl = _lang == 'ps' ? s.$3[1] : _lang == 'fa' ? s.$3[2] : s.$3[0];
        final sel = _skills.contains(s.$1);
        return GestureDetector(
          onTap: () {
            // FIX 3: was Pashto-only; Dari now speaks too, using the
            // already-resolved Dari label (lbl) since no separate Dari
            // TTS phrase is stored for skills.
            if (!_isEducated && _lang == 'ps') {
              TtsService().speak(s.$4, 'ps');
            } else if (!_isEducated && _lang == 'fa') {
              TtsService().speak(lbl, 'fa');
            }
            setState(() {
              if (sel) _skills.remove(s.$1); else _skills.add(s.$1);
            });
          },
          // Opaque background — BackdropFilter compositing fix (see _bigChoices).
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              color: sel
                  ? const Color(0xFFEAFBE9)
                  : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: sel ? _green : const Color(0xFFDDE4EF),
                width: sel ? 2.0 : 1.2,
              ),
              boxShadow: sel
                  ? [BoxShadow(
                      color: _green.withOpacity(0.15), blurRadius: 8)]
                  : [BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 6)],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Icon(s.$2,
                      color: sel
                          ? const Color(0xFF147C20)
                          : _muted,
                      size: 20),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(lbl,
                        style: const TextStyle(
                          color: Color(0xFF091733),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ),
                  if (sel)
                    const Icon(Icons.check_rounded, color: _green, size: 14),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _skillsEducated() {
    const skills = [
      ('lifting',        ['Heavy lifting',   'درانه شیان',   'حمل بار']),
      ('cooking',        ['Cooking',         'پخلي',          'آشپزی']),
      ('driving',        ['Driving',         'چلولو',         'رانندگی']),
      ('cleaning',       ['Cleaning',        'پاکوالی',       'نظافت']),
      ('fixing',         ['Repair',          'سمون',          'تعمیر']),
      ('packing',        ['Packing',         'بسته کول',      'بسته‌بندی']),
      ('security',       ['Security',        'امنیت',         'امنیت']),
      ('forklift',       ['Forklift',        'فورکلیفت',      'لیفتراک']),
      ('farming',        ['Farming',         'کرنه',          'کشاورزی']),
      ('sales',          ['Sales',           'پلور',          'فروش']),
      ('sewing',         ['Sewing',          'ګنډل',          'خیاطی']),
      ('construction',   ['Construction',    'جوړونه',        'ساخت‌وساز']),
      ('mobile_repair',  ['Mobile repair',   'موبایل سمول',   'تعمیر موبایل']),
      ('amazon_packing', ['Warehouse',       'ګدام',          'انبارداری']),
      ('dhl',            ['Delivery',        'ډلیوري',        'تحویل']),
    ];
    final q   = _skillSearchCtrl.text.toLowerCase();
    final all = skills.map((s) {
      final lbl = _lang == 'ps' ? s.$2[1] : _lang == 'fa' ? s.$2[2] : s.$2[0];
      return (s.$1, lbl);
    }).toList();
    final filtered = q.isEmpty
        ? all
        : all.where((s) => s.$2.toLowerCase().contains(q)).toList();

    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.85),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.9)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
              ),
            ],
          ),
          child: TextField(
            controller: _skillSearchCtrl,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(color: _navy, fontSize: 13),
            decoration: InputDecoration(
              hintText: _lang == 'ps' ? 'مهارت لټول...'
                  : _lang == 'fa' ? 'جستجوی مهارت...'
                  : 'Search skills...',
              hintStyle: const TextStyle(color: _muted, fontSize: 13),
              prefixIcon: const Icon(Icons.search, color: _muted, size: 18),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: filtered.map((s) {
            final sel = _skills.contains(s.$1);
            return GestureDetector(
              onTap: () => setState(() {
                if (sel) _skills.remove(s.$1); else _skills.add(s.$1);
              }),
              // Opaque background — BackdropFilter compositing fix.
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: sel
                      ? const Color(0xFFEAFBE9)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: sel ? _green : const Color(0xFFDDE4EF),
                    width: sel ? 2.0 : 1.2,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(s.$2,
                        style: const TextStyle(
                          color: Color(0xFF091733),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        )),
                    if (sel) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.check_rounded,
                          color: _green, size: 13),
                    ],
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        // Custom skills the user typed in themselves (not part of the preset
        // list above) — shown as removable chips, same style as elsewhere.
        if (_skills.any((k) => !skills.any((s) => s.$1 == k))) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _skills
                .where((k) => !skills.any((s) => s.$1 == k))
                .map((k) => GestureDetector(
                      onTap: () => setState(() => _skills.remove(k)),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAFBE9),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _green.withOpacity(0.5)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(k,
                                style: const TextStyle(
                                    color: Color(0xFF0E7A20),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(width: 4),
                            const Icon(Icons.close_rounded,
                                color: Color(0xFF0E7A20), size: 12),
                          ],
                        ),
                      ),
                    ))
                .toList(),
          ),
        ],
        const SizedBox(height: 8),
        _otherOptionRow(
          selected: null,
          ctrl: _skillOtherCtrl,
          open: _skillOtherOpen,
          onToggleOpen: () => setState(() => _skillOtherOpen = !_skillOtherOpen),
          onSubmit: (v) => setState(() {
            if (!_skills.contains(v)) _skills.add(v);
            _skillOtherCtrl.clear();
            _skillOtherOpen = false;
          }),
        ),
      ],
    );
  }

  Widget _bigChoices(
      List<_Opt> opts, String? selected, void Function(String) onSelect) {
    return Column(
      children: opts.map((o) {
        final sel = selected == o.value;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: GestureDetector(
            onTap: () {
              // FIX 3: was Pashto-only. Dari has no separate psTts-style
              // phrase stored per option, but o.label is already resolved
              // to the correct Dari text at _Opt construction time (each
              // _*Options() call site branches on _lang), so it's a valid,
              // non-empty string to speak here.
              if (!_isEducated && _lang == 'ps' && o.psTts != null) {
                TtsService().speak(o.psTts!, 'ps');
              } else if (!_isEducated && _lang == 'fa') {
                TtsService().speak(o.label, 'fa');
              }
              onSelect(o.value);
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: sel
                    ? const Color(0xFFEAFBE9)
                    : Colors.white.withOpacity(0.8),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: sel ? const Color(0xFF39EA2B) : Colors.white,
                  width: sel ? 2 : 1,
                ),
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
              child: Row(
                children: [
                  Icon(o.icon,
                      color: const Color(0xFF39EA2B),
                      size: 26),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      o.label,
                      style: const TextStyle(
                        color: Color(0xFF091733),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (sel)
                    const Icon(Icons.check_circle_rounded,
                        color: Color(0xFF39EA2B), size: 20),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _chipChoices(
      List<_Opt> opts, String? selected, void Function(String) onSelect) {
    // Same BackdropFilter compositing fix as _bigChoices — opaque backgrounds.
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: opts.map((o) {
        final sel = selected == o.value;
        return GestureDetector(
          onTap: () => onSelect(o.value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: sel
                  ? const Color(0xFFEAFBE9)
                  : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: sel ? _green : const Color(0xFFDDE4EF),
                width: sel ? 2.0 : 1.2,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(o.label,
                    style: const TextStyle(
                      color: Color(0xFF091733),
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
    );
  }

  Widget _referenceSection() {
    return Column(
      children: [
        _isEducated
            ? _chipChoices(_refOptions(), _reference,
                (v) => setState(() => _reference = v))
            : _bigChoices(_refOptions(), _reference,
                (v) => setState(() => _reference = v)),
        if (_reference != null && _reference != 'no_ref') ...[
          const SizedBox(height: 10),
          _TxtField(
            controller: _refNameCtrl,
            hint: _lang == 'ps' ? 'د مرجع نوم'
                : _lang == 'fa' ? 'نام مرجع'
                : 'Reference name',
            action: TextInputAction.next,
          ),
          const SizedBox(height: 8),
          _TxtField(
            controller: _refPhoneCtrl,
            hint: _lang == 'ps' ? 'د مرجع تیلیفون'
                : _lang == 'fa' ? 'تلفن مرجع'
                : 'Reference phone',
            type: TextInputType.phone,
            action: TextInputAction.done,
          ),
        ],
      ],
    );
  }

  // ── Q9 — categorized, searchable/browsable, repeatable employer list ──────
  // IMPORTANT: this is a local, hardcoded, categorized list bundled in the
  // app — not a live internet lookup/API call.
  static const List<(String, List<String>)> _kEmployerCategories = [
    ('Logistik & Lager', [
      'Amazon', 'DHL', 'Hermes', 'DPD', 'GLS', 'UPS', 'FedEx', 'DB Schenker',
      'Rhenus', 'Dachser', 'Kühne+Nagel', 'Fiege Logistik',
      'Zalando Logistics', 'DB', 'Lagerhelfer (allgemein)',
    ]),
    ('Einzelhandel', [
      'REWE', 'Edeka', 'Lidl', 'Aldi', 'Kaufland', 'Netto', 'Penny',
      'Rossmann', 'dm', 'Media Markt', 'Saturn', 'IKEA', 'Decathlon',
      'Zalando', 'Einzelhandel (allgemein)',
    ]),
    ('Reinigung', [
      'Piepenbrock', 'Dussmann Group', 'Klüh', 'WISAG', 'Gegenbauer',
      'Reinigungsfirma (allgemein)',
    ]),
    ('Pflege & Gesundheit', [
      'Korian', 'Vitanas', 'Pro Seniore', 'Caritas', 'Diakonie',
      'Deutsches Rotes Kreuz (DRK)', 'AWO (Arbeiterwohlfahrt)',
      'Pflegeeinrichtung (allgemein)',
    ]),
    ('Bau', [
      'Hochtief', 'STRABAG', 'Bilfinger', 'Goldbeck', 'Zeppelin',
      'Bauunternehmen (allgemein)',
    ]),
    ('Gastronomie & Hotel', [
      "McDonald's", 'Burger King', 'KFC', 'Subway', 'Starbucks', 'Vapiano',
      'Compass Group', 'Sodexo', 'Aramark', 'Accor Hotels', 'Marriott',
      'Restaurant/Hotel (allgemein)',
    ]),
    ('Post & Zustellung', [
      'Deutsche Post', 'DHL', 'Hermes', 'DPD', 'GLS', 'Wolt', 'Lieferando',
      'Uber Eats', 'Gorillas', 'Flink',
    ]),
    ('Industrie & Produktion', [
      'Siemens', 'Bosch', 'BMW', 'Volkswagen', 'Mercedes-Benz',
      'Continental', 'ThyssenKrupp', 'BASF', 'Bayer',
      'Fabrik/Produktion (allgemein)',
    ]),
    ('Landwirtschaft', [
      'Landwirtschaftsbetrieb (allgemein)', 'Erntehelfer (allgemein)',
    ]),
    ('Sicherheit', [
      'Securitas', 'Kötter Security', 'WISAG Security',
      'Sicherheitsdienst (allgemein)',
    ]),
    ('Büro & Verwaltung', [
      'SAP', 'Deutsche Telekom', 'Allianz', 'Deutsche Bank', 'Lufthansa',
      'Vonovia', 'Bürotätigkeit (allgemein)',
    ]),
  ];

  Widget _employerSuggestionList(_JobEntry entry) {
    final q = entry.employerCtrl.text.trim().toLowerCase();
    final sections = _kEmployerCategories
        .map((cat) {
          final matches = q.isEmpty
              ? cat.$2
              : cat.$2.where((c) => c.toLowerCase().contains(q)).toList();
          return (cat.$1, matches);
        })
        .where((cat) => cat.$2.isNotEmpty)
        .toList();

    if (sections.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 6),
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDDE4EF)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, 4)),
        ],
      ),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 6),
        children: [
          for (final section in sections) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
              child: Text(
                section.$1,
                style: const TextStyle(
                  color: _muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            for (final name in section.$2)
              GestureDetector(
                onTap: () => setState(() {
                  entry.employerCtrl.text = name;
                  entry.showSuggestions = false;
                  entry.employerFocus.unfocus();
                }),
                child: Container(
                  width: double.infinity,
                  color: Colors.transparent,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  child: Text(
                    name,
                    style: const TextStyle(
                      color: Color(0xFF091733),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  String get _jobSearchHint {
    switch (_lang) {
      case 'ps': return 'د شرکت نوم ولټوئ یا پخپله ولیکئ...';
      case 'fa': return 'نام شرکت را جستجو یا خودتان تایپ کنید...';
      default:   return 'Search or type company name...';
    }
  }

  String get _jobTitleHint {
    switch (_lang) {
      case 'ps': return 'دنده/رول (لکه Lagerhelfer)';
      case 'fa': return 'عنوان شغلی (مثلاً Lagerhelfer)';
      default:   return 'Job title / role';
    }
  }

  String get _jobOrtHint {
    switch (_lang) {
      case 'ps': return 'ځای (ښار)';
      case 'fa': return 'محل (شهر)';
      default:   return 'Ort (place/location)';
    }
  }

  // "Typ" selector shared with ausbildung_cv_questionnaire_screen.dart -
  // Berufserfahrung or Praktikum, kept literal German like every other
  // canonical CV term in this screen.
  Widget _jobTypeSelector(_JobEntry entry) {
    Widget option(String value) {
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
            value,
            style: TextStyle(
              color: selected ? Colors.white : _navy,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [option('Berufserfahrung'), option('Praktikum')],
    );
  }

  // FIX 1 — From/Until year dropdowns (replace free-text duration).
  // Range covers a realistic working lifetime; the max year is always the
  // real current year, computed at runtime (never hardcoded).
  List<int> _jobYearRange() {
    final current = DateTime.now().year;
    return [for (int y = current; y >= current - 40; y--) y];
  }

  String get _fromYearHint {
    switch (_lang) {
      case 'ps': return 'له کال';
      case 'fa': return 'از سال';
      default:   return 'From (Year)';
    }
  }

  String get _untilYearHint {
    switch (_lang) {
      case 'ps': return 'تر کال پورې';
      case 'fa': return 'تا سال';
      default:   return 'Until (Year)';
    }
  }

  String get _presentLabel {
    switch (_lang) {
      case 'ps': return 'اوس مهال (لا دلته کار کوم)';
      case 'fa': return 'در حال حاضر (هنوز اینجا کار می‌کنم)';
      default:   return 'Present / Currently working here';
    }
  }

  Widget _yearDropdownField({
    required String hint,
    required String? value,
    required bool includePresent,
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
          // FIX 1: the app's global ThemeData is dark (brightness.dark),
          // so an unstyled DropdownButton's popup menu inherits a black
          // background with light text. Force white/navy explicitly to
          // match the rest of the app's light glassmorphism style.
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
            for (final y in _jobYearRange())
              DropdownMenuItem(
                value: y.toString(),
                child: Text(y.toString(),
                    style: const TextStyle(color: _navy, fontSize: 13)),
              ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _jobDurationRow(_JobEntry entry) {
    return Row(
      children: [
        Expanded(
          child: _yearDropdownField(
            hint: _fromYearHint,
            value: entry.fromYear?.toString(),
            includePresent: false,
            onChanged: (v) => setState(
                () => entry.fromYear = v == null ? null : int.tryParse(v)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _yearDropdownField(
            hint: _untilYearHint,
            value: entry.untilYear,
            includePresent: true,
            onChanged: (v) => setState(() => entry.untilYear = v),
          ),
        ),
      ],
    );
  }

  Widget _jobEntryCard(int index) {
    final entry = _jobEntries[index];
    final jobLabel = _lang == 'ps' ? 'دنده ${index + 1}'
        : _lang == 'fa' ? 'شغل ${index + 1}'
        : 'Job ${index + 1}';

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
                  jobLabel,
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              if (_jobEntries.length > 1)
                GestureDetector(
                  onTap: () => setState(() {
                    _jobEntries[index].dispose();
                    _jobEntries.removeAt(index);
                  }),
                  child: const Icon(Icons.close_rounded,
                      color: _muted, size: 18),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFDDE4EF)),
            ),
            child: TextField(
              controller: entry.employerCtrl,
              focusNode: entry.employerFocus,
              onTap: () => setState(() => entry.showSuggestions = true),
              onChanged: (_) => setState(() {}),
              style: const TextStyle(
                  color: _navy, fontSize: 13, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                hintText: _jobSearchHint,
                hintStyle: const TextStyle(color: _muted, fontSize: 13),
                prefixIcon: const Icon(Icons.search, color: _muted, size: 18),
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
          ),
          if (entry.showSuggestions) _employerSuggestionList(entry),
          const SizedBox(height: 8),
          _TxtField(
            controller: entry.titleCtrl,
            hint: _jobTitleHint,
            action: TextInputAction.next,
          ),
          const SizedBox(height: 8),
          _TxtField(
            controller: entry.ortCtrl,
            hint: _jobOrtHint,
            action: TextInputAction.next,
          ),
          const SizedBox(height: 8),
          _jobTypeSelector(entry),
          const SizedBox(height: 8),
          _jobDurationRow(entry),
        ],
      ),
    );
  }

  Widget _jobEntriesEducated() {
    final addLabel = _lang == 'ps' ? '+ بله دنده اضافه کړئ'
        : _lang == 'fa' ? '+ افزودن شغل دیگر'
        : '+ Add another job';
    final orderHint = _lang == 'ps'
        ? 'خپل تازه ترین دنده لومړی اضافه کړئ'
        : _lang == 'fa' ? 'ابتدا جدیدترین شغل خود را اضافه کنید'
        : 'Add your most recent job first';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          orderHint,
          style: const TextStyle(
            color: _muted,
            fontSize: 11,
            fontWeight: FontWeight.w500,
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(height: 8),
        _jobEntriesPrefilledBadge(),
        for (int i = 0; i < _jobEntries.length; i++) _jobEntryCard(i),
        GestureDetector(
          onTap: () {
            if (_jobEntries.length >= _kMaxJobEntries) {
              _showMaxLimitSnack();
              return;
            }
            setState(() => _jobEntries.add(_JobEntry()));
          },
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
                Text(addLabel,
                    style: const TextStyle(
                        color: Color(0xFF0E7A20),
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Q9 (uneducated) — same repeatable employer/job-title/duration units,
  // adapted to the uneducated visual pattern: large cards, tap-to-speak,
  // employer chosen via a big-card picker sheet instead of a search field.

  String get _chooseEmployerLabel {
    switch (_lang) {
      case 'ps': return 'کارفرما وټاکئ';
      case 'fa': return 'کارفرما را انتخاب کنید';
      default:   return 'Choose employer';
    }
  }

  String get _employerOtherLabel {
    switch (_lang) {
      case 'ps': return 'نور (پخپله ولیکئ)';
      case 'fa': return 'دیگر (خودتان بنویسید)';
      default:   return 'Other (type it yourself)';
    }
  }

  String get _addAnotherJobLabel {
    switch (_lang) {
      case 'ps': return '+ بله دنده اضافه کړئ';
      case 'fa': return '+ افزودن شغل دیگر';
      default:   return '+ Add another job';
    }
  }

  String get _addMostRecentJobHint {
    switch (_lang) {
      case 'ps': return 'خپل تازه ترین دنده لومړی اضافه کړئ';
      case 'fa': return 'ابتدا جدیدترین شغل خود را اضافه کنید';
      default:   return 'Add your most recent job first';
    }
  }

  String get _jobEntriesPrefilledNote {
    switch (_lang) {
      case 'ps': return 'دا له مخکینیو ډکو معلوماتو څخه راغلي، تاسو یې سمولی شئ';
      case 'fa': return 'این از اطلاعات قبلی شما بارگذاری شده، می‌توانید ویرایش کنید';
      default:   return 'Loaded from your other CV, edit if needed';
    }
  }

  Widget _jobEntriesPrefilledBadge() {
    if (!_jobEntriesPrefilled) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded, color: _green, size: 14),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              _jobEntriesPrefilledNote,
              style: const TextStyle(
                color: Color(0xFF0E7A20),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showEmployerPickerSheet(_JobEntry entry) {
    final manualCtrl = TextEditingController(text: entry.employer);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD1D9E6),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                _chooseEmployerLabel,
                style: const TextStyle(
                  color: _navy, fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              // Manual / "Other" free text — always available, no need to
              // find a matching card below.
              Row(
                children: [
                  Expanded(
                    child: _TxtField(
                      controller: manualCtrl,
                      hint: _employerOtherLabel,
                      action: TextInputAction.done,
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      final v = manualCtrl.text.trim();
                      if (v.isEmpty) return;
                      entry.employerCtrl.text = v;
                      Navigator.pop(ctx);
                      setState(() {});
                    },
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _green,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.check_rounded,
                          color: Color(0xFF091733), size: 22),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(
                child: ListView(
                  children: [
                    for (final section in _kEmployerCategories) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                section.$1,
                                style: const TextStyle(
                                  color: _muted,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: () {
                                // FIX 3: was Pashto-only. Section names are
                                // untranslated proper nouns (e.g. "Logistik
                                // & Lager"), so the same text is valid to
                                // speak for Dari too — just pass 'fa' as
                                // the TTS locale.
                                if (_lang == 'ps' || _lang == 'fa') {
                                  TtsService().speak(section.$1, _lang);
                                }
                              },
                              child: const Icon(Icons.volume_up_rounded,
                                  color: _green, size: 18),
                            ),
                          ],
                        ),
                      ),
                      for (final name in section.$2)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  onTap: () {
                                    entry.employerCtrl.text = name;
                                    Navigator.pop(ctx);
                                    setState(() {});
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 16),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF7FAFF),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                          color: const Color(0xFFDDE4EF)),
                                    ),
                                    child: Text(
                                      name,
                                      style: const TextStyle(
                                        color: _navy,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () {
                                  // FIX 3: was Pashto-only. Employer names
                                  // are untranslated proper nouns (e.g.
                                  // "Amazon"), valid to speak for Dari too.
                                  if (_lang == 'ps' || _lang == 'fa') {
                                    TtsService().speak(name, _lang);
                                  }
                                },
                                child: Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEAFBE9),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.volume_up_rounded,
                                      color: _green, size: 20),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    ).whenComplete(manualCtrl.dispose);
  }

  Widget _employerPickerButton(_JobEntry entry) {
    final hasValue = entry.employer.isNotEmpty;
    return GestureDetector(
      onTap: () => _showEmployerPickerSheet(entry),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: hasValue ? const Color(0xFFEAFBE9) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: hasValue ? _green : const Color(0xFFDDE4EF),
            width: hasValue ? 2.0 : 1.2,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.business_rounded,
                color: hasValue ? _green : _muted, size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                hasValue ? entry.employerCtrl.text : _chooseEmployerLabel,
                style: TextStyle(
                  color: _navy,
                  fontSize: 15,
                  fontWeight: hasValue ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: hasValue ? _green : _muted),
          ],
        ),
      ),
    );
  }

  Widget _jobEntryCardUneducated(int index) {
    final entry = _jobEntries[index];
    final jobLabel = _lang == 'ps' ? 'دنده ${index + 1}'
        : _lang == 'fa' ? 'شغل ${index + 1}'
        : 'Job ${index + 1}';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDDE4EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  jobLabel,
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (_jobEntries.length > 1)
                GestureDetector(
                  onTap: () => setState(() {
                    _jobEntries[index].dispose();
                    _jobEntries.removeAt(index);
                  }),
                  child: const Icon(Icons.close_rounded,
                      color: _muted, size: 24),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _employerPickerButton(entry),
          const SizedBox(height: 10),
          _TxtField(
            controller: entry.ortCtrl,
            hint: _jobOrtHint,
            action: TextInputAction.next,
          ),
          const SizedBox(height: 10),
          _jobTypeSelector(entry),
          const SizedBox(height: 10),
          _jobDurationRow(entry),
        ],
      ),
    );
  }

  Widget _jobEntriesUneducated() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _addMostRecentJobHint,
          style: const TextStyle(
            color: _muted,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(height: 10),
        _jobEntriesPrefilledBadge(),
        for (int i = 0; i < _jobEntries.length; i++) _jobEntryCardUneducated(i),
        GestureDetector(
          onTap: () {
            if (_jobEntries.length >= _kMaxJobEntries) {
              _showMaxLimitSnack();
              return;
            }
            setState(() => _jobEntries.add(_JobEntry()));
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFEAFBE9),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _green.withOpacity(0.5), width: 1.5),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.add_circle_rounded,
                    color: Color(0xFF0E7A20), size: 20),
                const SizedBox(width: 8),
                Text(_addAnotherJobLabel,
                    style: const TextStyle(
                        color: Color(0xFF0E7A20),
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Q13 (educated) — per-language CEFR proficiency ─────────────────────────
  // Tapping a language chip immediately reveals its level row (A1–C2 +
  // Muttersprache); tapping a level selects both language and level in one
  // motion and stores the pair into _languageProficiency.

  static const List<String> _kCefrLevels = ['A1', 'A2', 'B1', 'B2', 'C1', 'C2'];

  String get _motherTongueLabel {
    switch (_lang) {
      case 'ps': return 'مورنۍ ژبه';
      case 'fa': return 'زبان مادری';
      default:   return 'Muttersprache';
    }
  }

  // FIX 2 — Step A (select languages) and Step B (pick a level per
  // selected language) are now visually separate: Step B only appears
  // once at least one language is chosen, under its own heading, with
  // each language's level row labeled by that language's own name so it's
  // unambiguous which row belongs to which language.

  String get _selectLevelHeading {
    switch (_lang) {
      case 'ps': return 'د هرې ژبې لپاره خپله کچه وټاکئ';
      case 'fa': return 'سطح خود را برای هر زبان انتخاب کنید';
      default:   return 'Select your level for each language';
    }
  }

  Widget _languageProficiencyEducated() {
    const langs = [
      ['pashto',  'Paschtu',   'پښتو',    'پشتو'],
      ['dari',    'Dari/Farsi','دري/فارسي','دری/فارسی'],
      ['urdu',    'Urdu',      'اردو',     'اردو'],
      ['arabic',  'Arabisch',  'عربي',     'عربی'],
      ['english', 'Englisch',  'انګليسي',  'انگلیسی'],
      ['german',  'Deutsch',   'جرمني',    'آلمانی'],
    ];
    // _languages keeps using the app's existing internal keys ('german',
    // 'english', ...) so review_screen.dart / the uneducated flow / saved
    // profiles stay consistent; _languageProficiency is keyed by the German
    // display label per Task 4's spec, and is what cv_preview_screen.dart's
    // "Sprachen" section actually renders for educated users.

    Widget levelRow(String key, String germanName, String displayLabel) {
      final current = _languageProficiency[germanName];
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(displayLabel,
                style: const TextStyle(
                  color: _navy,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                )),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Step A — select all languages spoken.
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: langs.map((l) {
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
                          color: Color(0xFF091733),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        )),
                    if (sel) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.check_rounded,
                          color: _green, size: 13),
                    ],
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        _otherOptionRow(
          selected: null,
          ctrl: _langOtherCtrl,
          open: _langOtherOpen,
          onToggleOpen: () => setState(() => _langOtherOpen = !_langOtherOpen),
          onSubmit: (v) => setState(() {
            if (!_languages.contains(v)) _languages.add(v);
            _langOtherCtrl.clear();
            _langOtherOpen = false;
          }),
        ),

        // Step B — appears only once ≥1 language is selected, clearly
        // separated under its own heading, one labeled row per language.
        if (_languages.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Divider(height: 1, color: Color(0xFFE4EAF5)),
          const SizedBox(height: 12),
          Text(_selectLevelHeading,
              style: const TextStyle(
                color: _navy,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              )),
          const SizedBox(height: 10),
          for (final l in langs)
            if (_languages.contains(l[0]))
              levelRow(l[0], l[1],
                  _lang == 'ps' ? l[2] : _lang == 'fa' ? l[3] : l[1]),
          // Custom (free-text) languages typed via "Other" above — keyed by
          // their own raw text in both _languages and _languageProficiency,
          // same fallback-to-identity pattern used for custom
          // skills/country/education elsewhere in this screen.
          for (final custom in _languages
              .where((l) => !langs.any((preset) => preset[0] == l)))
            levelRow(custom, custom, custom),
        ],
      ],
    );
  }

  // ── Q12 (uneducated) — same CEFR proficiency pattern, larger touch
  // targets, and tap-to-speak on every language/level option (Pashto only,
  // matching every other uneducated tap-to-speak control in this screen).

  Widget _languageProficiencyUneducated() {
    const langs = [
      ['pashto',  'Paschtu',    'پښتو',      'پشتو',        'پښتو'],
      ['dari',    'Dari/Farsi', 'دري/فارسي', 'دری/فارسی',   'دري یا فارسی'],
      ['urdu',    'Urdu',       'اردو',      'اردو',        'اردو'],
      ['arabic',  'Arabisch',   'عربي',      'عربی',        'عربي'],
      ['english', 'Englisch',   'انګليسي',   'انگلیسی',     'انګليسي'],
      ['german',  'Deutsch',    'جرمني',     'آلمانی',      'جرمني'],
    ];

    Widget levelBtn(String label, bool selected, VoidCallback onTap) {
      return GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: selected ? _green : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? _green : const Color(0xFFDDE4EF),
              width: selected ? 2.2 : 1.2,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : _navy,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      );
    }

    Widget levelRow(String key, String germanName, String displayLabel) {
      final current = _languageProficiency[germanName];
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(displayLabel,
                    style: const TextStyle(
                      color: _navy,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    )),
                // FIX 3: speaker icon was gated to Pashto only (invisible
                // for Dari, not just silent). displayLabel is already the
                // language-resolved text, valid for either.
                if (_lang == 'ps' || _lang == 'fa') ...[
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => TtsService().speak(displayLabel, _lang),
                    child: const Icon(Icons.volume_up_rounded,
                        color: _green, size: 18),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final level in _kCefrLevels)
                  levelBtn(level, current == level, () {
                    // FIX 3: level codes (A1, B1, ...) are language-neutral
                    // — valid to speak for Dari too, was Pashto-only.
                    if (_lang == 'ps' || _lang == 'fa') {
                      TtsService().speak(level, _lang);
                    }
                    setState(() {
                      if (!_languages.contains(key)) _languages.add(key);
                      _languageProficiency[germanName] = level;
                    });
                  }),
                levelBtn(_motherTongueLabel, current == 'Muttersprache', () {
                  // FIX 3: _motherTongueLabel already resolves to the
                  // correct Dari text via _lang, was Pashto-only.
                  if (_lang == 'ps' || _lang == 'fa') {
                    TtsService().speak(_motherTongueLabel, _lang);
                  }
                  setState(() {
                    if (!_languages.contains(key)) _languages.add(key);
                    _languageProficiency[germanName] = 'Muttersprache';
                  });
                }),
              ],
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Step A — select all languages spoken.
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: langs.map((l) {
            final key = l[0];
            final germanName = l[1];
            final lbl = _lang == 'ps' ? l[2] : _lang == 'fa' ? l[3] : l[1];
            final psTts = l[4];
            final sel = _languages.contains(key);
            return GestureDetector(
              onTap: () {
                // FIX 3: was Pashto-only via the dedicated psTts phrase.
                // No separate Dari TTS phrase is stored per language here,
                // but lbl is already resolved to the correct Dari label
                // text, so it's a valid, non-empty string to speak.
                if (_lang == 'ps') {
                  TtsService().speak(psTts, 'ps');
                } else if (_lang == 'fa') {
                  TtsService().speak(lbl, 'fa');
                }
                setState(() {
                  if (sel) {
                    _languages.remove(key);
                    _languageProficiency.remove(germanName);
                  } else {
                    _languages.add(key);
                  }
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: BoxDecoration(
                  color: sel ? const Color(0xFFEAFBE9) : Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: sel ? _green : const Color(0xFFDDE4EF),
                    width: sel ? 2.2 : 1.2,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(lbl,
                        style: const TextStyle(
                          color: Color(0xFF091733),
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        )),
                    if (sel) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.check_rounded, color: _green, size: 16),
                    ],
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 10),
        _otherOptionRow(
          selected: null,
          ctrl: _langOtherCtrl,
          open: _langOtherOpen,
          onToggleOpen: () => setState(() => _langOtherOpen = !_langOtherOpen),
          onSubmit: (v) => setState(() {
            if (!_languages.contains(v)) _languages.add(v);
            _langOtherCtrl.clear();
            _langOtherOpen = false;
          }),
        ),

        // Step B — appears only once ≥1 language is selected, clearly
        // separated under its own heading, one labeled row per language.
        if (_languages.isNotEmpty) ...[
          const SizedBox(height: 18),
          const Divider(height: 1, color: Color(0xFFE4EAF5)),
          const SizedBox(height: 14),
          Text(_selectLevelHeading,
              style: const TextStyle(
                color: _navy,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              )),
          const SizedBox(height: 12),
          for (final l in langs)
            if (_languages.contains(l[0]))
              levelRow(l[0], l[1],
                  _lang == 'ps' ? l[2] : _lang == 'fa' ? l[3] : l[1]),
          for (final custom in _languages
              .where((l) => !langs.any((preset) => preset[0] == l)))
            levelRow(custom, custom, custom),
        ],
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

  void _snackSpeak(String text) => TtsService().speak(text, _lang);
}

// ─────────────────────────────────────────────────────────────────────────────
// Q9 — one repeatable "job" unit: employer + role + place (Ort) + duration +
// type (Berufserfahrung/Praktikum). Same shape as
// ausbildung_cv_questionnaire_screen.dart's _WorkExpEntry - the two
// questionnaires read/write the same shared SharedPreferences keys.
// ─────────────────────────────────────────────────────────────────────────────

class _JobEntry {
  final employerCtrl = TextEditingController();
  final titleCtrl    = TextEditingController();
  final ortCtrl      = TextEditingController();
  final employerFocus = FocusNode();
  bool showSuggestions = false;

  // From/Until year dropdowns (FIX 1) replace the old free-text duration
  // field. untilYear holds a 4-digit year string, or the sentinel
  // 'present' when the user picks "Present / Currently working here".
  int?    fromYear;
  String? untilYear;
  // 'Berufserfahrung' or 'Praktikum' - shared with the Ausbildung CV
  // questionnaire's Typ selector.
  String? entryType;

  String get employer => employerCtrl.text.trim();
  String get jobTitle => titleCtrl.text.trim();
  String get ort      => ortCtrl.text.trim();

  // Duration string, e.g. "2021 - 2023" or "2021 - heute" - same hyphen
  // format as ausbildung_cv_questionnaire_screen.dart's _WorkExpEntry.duration
  // so both screens can round-trip each other's saved entries.
  String get duration {
    final from  = fromYear?.toString() ?? '';
    final until = untilYear == 'present' ? 'heute' : (untilYear ?? '');
    if (from.isEmpty && until.isEmpty) return '';
    if (from.isNotEmpty && until.isNotEmpty) return '$from - $until';
    return from.isNotEmpty ? from : until;
  }

  void dispose() {
    employerCtrl.dispose();
    titleCtrl.dispose();
    ortCtrl.dispose();
    employerFocus.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Data model for option items
// ─────────────────────────────────────────────────────────────────────────────

class _Opt {
  final String value;
  final IconData icon;
  final String label;
  final String? psTts;
  const _Opt(this.value, this.icon, this.label, [this.psTts]);
}

// ─────────────────────────────────────────────────────────────────────────────
// Question card — glass surface wrapper
// ─────────────────────────────────────────────────────────────────────────────

class _QCard extends StatelessWidget {
  static const Color _navy  = Color(0xFF091733);
  static const Color _green = Color(0xFF39EA2B);

  final String question;
  final bool isRtl;
  final bool showSpeaker;
  final VoidCallback onSpeak;
  final Widget child;

  const _QCard({
    required this.question,
    required this.isRtl,
    required this.showSpeaker,
    required this.onSpeak,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return _GlassSurface(
      borderRadius: 20,
      padding: const EdgeInsets.all(16),
      shadowOpacity: 0.08,
      child: Column(
        crossAxisAlignment:
            isRtl ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
            children: [
              Expanded(
                child: Text(
                  question,
                  textDirection:
                      isRtl ? TextDirection.rtl : TextDirection.ltr,
                  style: const TextStyle(
                    color: _navy,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                  ),
                ),
              ),
              if (showSpeaker) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onSpeak,
                  child: Container(
                    width: 30, height: 30,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAFBE9),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: _green.withOpacity(0.4)),
                    ),
                    child: const Icon(Icons.volume_up_rounded,
                        color: _green, size: 15),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable text field — glass style
// ─────────────────────────────────────────────────────────────────────────────

class _TxtField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final TextInputType type;
  final TextInputAction action;

  const _TxtField({
    required this.controller,
    required this.hint,
    this.type   = TextInputType.text,
    this.action = TextInputAction.next,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        keyboardType: type,
        textInputAction: action,
        textDirection: TextDirection.ltr,
        style: const TextStyle(color: Color(0xFF091733)),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(
              color: Color(0xFF65738A), fontSize: 14),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(14),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Navigation button — navy gradient (page 1) or green (page 2)
// ─────────────────────────────────────────────────────────────────────────────

class _BigButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool isGreen;

  const _BigButton({
    required this.label,
    required this.onTap,
    this.isGreen = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(29),
        color: isGreen ? const Color(0xFF39EA2B) : null,
        gradient: isGreen
            ? null
            : const LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [Color(0xFF081532), Color(0xFF07112B)],
              ),
        boxShadow: [
          BoxShadow(
            color: isGreen
                ? const Color(0xFF39EA2B).withOpacity(0.35)
                : const Color(0xFF07112B).withOpacity(0.30),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(29),
          onTap: onTap,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isGreen
                    ? const Color(0xFF091733)
                    : Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Language pill
// ─────────────────────────────────────────────────────────────────────────────

class _LangPill extends StatelessWidget {
  final String lang;
  final VoidCallback onPick;

  const _LangPill({required this.lang, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final label = lang == 'ps' ? 'PS' : lang == 'fa' ? 'FA' : 'EN';
    return GestureDetector(
      onTap: onPick,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFF091733),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF091733).withOpacity(0.20),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                )),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down_rounded,
                color: Colors.white, size: 14),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Nav icon button (back arrow / sound toggle)
// ─────────────────────────────────────────────────────────────────────────────

class _NavIconBtn extends StatelessWidget {
  static const Color _navy  = Color(0xFF091733);
  static const Color _green = Color(0xFF39EA2B);

  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  final bool hintPulse;

  const _NavIconBtn({
    required this.icon,
    required this.onTap,
    this.active = false,
    this.hintPulse = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
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
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Center(
              child: Icon(icon,
                  color: active ? _green : _navy, size: 20),
            ),
          ),
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
// Glass surface
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
