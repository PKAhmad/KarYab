import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_profile.dart';
import '../services/analytics_service.dart';
import '../services/tts_service.dart';
import '../ui/karyab_ui.dart';
import 'ausbildung_cv_questionnaire_screen.dart';
import 'letter_document_screen.dart';
import 'personal_data_screen.dart';
import 'questionnaire_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// The single entry point for creating any application document. Offers four
// sibling options - Job CV, Ausbildung CV, Cover Letter, Deckblatt - none
// nested under another. Job CV / Ausbildung CV route into that questionnaire
// (through PersonalDataScreen first if shared personal data doesn't exist
// yet). Cover Letter / Deckblatt are type-agnostic: they generate directly
// from whatever's already in 'saved_profile', no extra questionnaire step,
// usable regardless of which CV type (if any) the user has.
// ─────────────────────────────────────────────────────────────────────────────

class ChooseCvTypeScreen extends StatefulWidget {
  final String language;
  final bool voiceMode;

  const ChooseCvTypeScreen({
    super.key,
    required this.language,
    this.voiceMode = false,
  });

  @override
  State<ChooseCvTypeScreen> createState() => _ChooseCvTypeScreenState();
}

class _ChooseCvTypeScreenState extends State<ChooseCvTypeScreen> {
  static const Color _navy  = KColors.navy;
  static const Color _green = KColors.green;
  static const Color _muted = KColors.textSecondary;

  late String _lang;
  late bool _voiceMode;
  bool _checking = false;

  bool get _isRtl => _lang == 'ps' || _lang == 'fa';
  bool get _showSpeaker => _voiceMode && _isRtl;

  @override
  void initState() {
    super.initState();
    _lang = widget.language;
    _voiceMode = widget.voiceMode;
    AnalyticsService().logScreen('choose_cv_type');
  }

  @override
  void dispose() {
    TtsService().stop();
    super.dispose();
  }

  void _speak(String text) => TtsService().speak(text, _lang);

  Future<bool> _hasPersonalData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('saved_profile');
      if (raw == null || raw.isEmpty) return false;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      String v(String key) => (map[key] as String? ?? '').trim();
      return v('fullName').isNotEmpty &&
          v('phone').isNotEmpty &&
          v('email').isNotEmpty &&
          v('country').isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> _select(String cvType) async {
    if (_checking) return;
    setState(() => _checking = true);
    final hasData = await _hasPersonalData();
    if (!mounted) return;
    setState(() => _checking = false);

    if (cvType == 'cover_letter' || cvType == 'deckblatt') {
      await _openLetterDocument(cvType, hasData);
      return;
    }

    if (hasData) {
      _goToQuestionnaire(cvType);
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PersonalDataScreen(
            language: _lang,
            voiceMode: _voiceMode,
            nextCvType: cvType,
          ),
        ),
      );
    }
  }

  void _goToQuestionnaire(String cvType) {
    if (cvType == 'job') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => QuestionnaireScreen(
              language: _lang, voiceMode: _voiceMode, isEditMode: false),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AusbildungCvQuestionnaireScreen(
              language: _lang, voiceMode: _voiceMode, isEditMode: false),
        ),
      );
    }
  }

  // Cover Letter / Deckblatt generate directly from 'saved_profile' - no
  // extra questionnaire step. They still need the core personal data
  // (name/contact) to be worth generating; since PersonalDataScreen only
  // knows how to hand off into the 'job'/'ausbildung' questionnaires, a user
  // with no personal data yet is asked to create a CV first instead.
  Future<void> _openLetterDocument(String cvType, bool hasData) async {
    if (!hasData) {
      _showNoDataSnack();
      return;
    }
    final profile = await _loadProfile();
    if (!mounted || profile == null) {
      _showNoDataSnack();
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LetterDocumentScreen(
          profile: profile,
          language: _lang,
          docType: cvType == 'cover_letter'
              ? LetterDocType.coverLetter
              : LetterDocType.deckblatt,
        ),
      ),
    );
  }

  Future<UserProfile?> _loadProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('saved_profile');
      if (raw == null || raw.isEmpty) return null;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return UserProfile.fromMap(map);
    } catch (_) {
      return null;
    }
  }

  void _showNoDataSnack() {
    kSnack(context, _noDataMsg);
  }

  // ── Localised strings ──────────────────────────────────────────────────────

  String get _titleLabel {
    switch (_lang) {
      case 'ps': return 'خپل غوښتنلیک اسناد جوړ کړئ';
      case 'fa': return 'اسناد درخواست خود را بسازید';
      default:   return 'Create Application Documents';
    }
  }

  String get _subtitleLabel {
    switch (_lang) {
      case 'ps': return 'هغه سند غوره کړئ چې غواړئ جوړ کړئ';
      case 'fa': return 'سندی که می‌خواهید بسازید را انتخاب کنید';
      default:   return 'Choose which document you want to create';
    }
  }

  String get _coverLetterLabel {
    switch (_lang) {
      case 'ps': return 'د پوښتنلیک لیک';
      case 'fa': return 'نامه پوششی';
      default:   return 'Cover Letter';
    }
  }

  String get _coverLetterSubtitle {
    switch (_lang) {
      case 'ps': return 'ستاسو د معلوماتو پر بنسټ اتومات جوړ شوی';
      case 'fa': return 'به‌طور خودکار از اطلاعات شما ساخته می‌شود';
      default:   return 'Auto-generated from your saved details';
    }
  }

  // "Deckblatt" stays untranslated, same principle as "Ausbildung" elsewhere
  // in the app.
  String get _deckblattLabel => 'Deckblatt';

  String get _deckblattSubtitle {
    switch (_lang) {
      case 'ps': return 'د غوښتنلیک پوښ پاڼه، اتومات جوړ شوی';
      case 'fa': return 'برگه روی جلد درخواست، به‌طور خودکار ساخته می‌شود';
      default:   return 'Application cover page, auto-generated';
    }
  }

  String get _noDataMsg {
    switch (_lang) {
      case 'ps': return 'لومړی خپل شخصي معلومات د CV په جوړولو سره اضافه کړئ';
      case 'fa': return 'ابتدا با ساختن یک رزومه، اطلاعات شخصی خود را اضافه کنید';
      default:   return 'Please create a Job CV or Ausbildung CV first to add your details';
    }
  }

  String get _jobCvLabel {
    switch (_lang) {
      case 'ps': return 'د دندې CV';
      case 'fa': return 'رزومه شغلی';
      default:   return 'Job CV';
    }
  }

  String get _jobCvSubtitle {
    switch (_lang) {
      case 'ps': return 'د کار موندلو لپاره';
      case 'fa': return 'برای پیدا کردن یک شغل';
      default:   return 'For finding a job in Germany';
    }
  }

  // "Ausbildung" stays untranslated, same principle as elsewhere in the app.
  String get _ausbildungCvLabel => 'Ausbildung CV';

  String get _ausbildungCvSubtitle {
    switch (_lang) {
      case 'ps': return 'د زده کړې کار لپاره غوښتنلیک';
      case 'fa': return 'برای درخواست کارآموزی (Ausbildung)';
      default:   return 'For applying to vocational training (Ausbildung)';
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        TtsService().stop();
      },
      child: Scaffold(
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
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                      child: Column(
                        children: [
                          const SizedBox(height: 20),
                          _CvTypeCard(
                            icon: Icons.work_rounded,
                            iconColor: _green,
                            label: _jobCvLabel,
                            subtitle: _jobCvSubtitle,
                            isRtl: _isRtl,
                            showSpeaker: _showSpeaker,
                            loading: _checking,
                            onSpeak: () =>
                                _speak('$_jobCvLabel. $_jobCvSubtitle'),
                            onTap: () => _select('job'),
                          ),
                          const SizedBox(height: 16),
                          _CvTypeCard(
                            icon: Icons.school_rounded,
                            iconColor: KColors.blue,
                            label: _ausbildungCvLabel,
                            subtitle: _ausbildungCvSubtitle,
                            isRtl: _isRtl,
                            showSpeaker: _showSpeaker,
                            loading: _checking,
                            onSpeak: () =>
                                _speak('$_ausbildungCvLabel. $_ausbildungCvSubtitle'),
                            onTap: () => _select('ausbildung'),
                          ),
                          const SizedBox(height: 16),
                          _CvTypeCard(
                            icon: Icons.mail_rounded,
                            iconColor: KColors.purple,
                            label: _coverLetterLabel,
                            subtitle: _coverLetterSubtitle,
                            isRtl: _isRtl,
                            showSpeaker: _showSpeaker,
                            loading: _checking,
                            onSpeak: () =>
                                _speak('$_coverLetterLabel. $_coverLetterSubtitle'),
                            onTap: () => _select('cover_letter'),
                          ),
                          const SizedBox(height: 16),
                          _CvTypeCard(
                            icon: Icons.badge_rounded,
                            iconColor: const Color(0xFFC77B1E),
                            label: _deckblattLabel,
                            subtitle: _deckblattSubtitle,
                            isRtl: _isRtl,
                            showSpeaker: _showSpeaker,
                            loading: _checking,
                            onSpeak: () =>
                                _speak('$_deckblattLabel. $_deckblattSubtitle'),
                            onTap: () => _select('deckblatt'),
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
          KNavButton(
            icon: Icons.arrow_back_ios_new_rounded,
            onTap: () {
              TtsService().stop();
              Navigator.pop(context);
            },
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  _titleLabel,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _navy,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _subtitleLabel,
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
          const SizedBox(width: 44),
        ],
      ),
    );
  }
}

class _CvTypeCard extends StatelessWidget {
  static const Color _navy  = KColors.navy;
  static const Color _green = KColors.green;
  static const Color _muted = KColors.textSecondary;

  final IconData icon;
  final Color iconColor;
  final String label;
  final String subtitle;
  final bool isRtl;
  final bool showSpeaker;
  final bool loading;
  final VoidCallback onSpeak;
  final VoidCallback onTap;

  const _CvTypeCard({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.subtitle,
    required this.isRtl,
    required this.showSpeaker,
    required this.loading,
    required this.onSpeak,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: KGlassSurface(
        borderRadius: 22,
        padding: const EdgeInsets.all(20),
        child: Row(
          textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: KColors.mint,
                shape: BoxShape.circle,
                border: Border.all(color: iconColor.withOpacity(0.3), width: 1),
              ),
              child: Icon(icon, color: iconColor, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment:
                    isRtl ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
                    style: const TextStyle(
                      color: _navy,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            if (showSpeaker) ...[
              GestureDetector(
                onTap: onSpeak,
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: KColors.mint,
                    shape: BoxShape.circle,
                    border: Border.all(color: _green.withOpacity(0.4)),
                  ),
                  child: const Icon(Icons.volume_up_rounded,
                      color: _green, size: 17),
                ),
              ),
              const SizedBox(width: 8),
            ],
            if (loading)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: _green),
              )
            else
              const Icon(Icons.chevron_right_rounded, color: _muted, size: 24),
          ],
        ),
      ),
    );
  }
}
