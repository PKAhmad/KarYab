import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/user_profile.dart';
import '../providers/language_provider.dart';
import '../services/analytics_service.dart';
import '../services/tts_service.dart';
import '../utils/navigation_helpers.dart';
import '../widgets/cv_upload_info_sheet.dart';
import 'ausbildung_document_preview_screen.dart';
import 'cv_preview_screen.dart';

class IntroductionScreen extends StatefulWidget {
  final String language;
  final bool voiceMode;

  const IntroductionScreen({
    super.key,
    required this.language,
    required this.voiceMode,
  });

  @override
  State<IntroductionScreen> createState() => _IntroductionScreenState();
}

class _IntroductionScreenState extends State<IntroductionScreen> {
  static const Color navy  = Color(0xFF091733);
  static const Color green = Color(0xFF39EA2B);

  String? _selectedCard;
  String  _lang      = 'en';
  bool    _cvCreated = false;
  String  _cvType    = '';
  String  _userName  = '';
  String  _userCity  = '';
  String  _userPhotoPath = '';
  // No dedicated 'ausbildung_cv_created' flag exists (unlike the Job CV's
  // 'cv_created'/'cv_type') - the Ausbildung questionnaire/Schulabschluss
  // screens only ever write into 'saved_profile', so this is derived in
  // _loadSavedData() from the presence of that flow's own keys.
  bool    _ausbildungCvCreated = false;
  bool    _voiceMode = false;
  bool    _isLoading = true;
  DateTime? _lastBackPressAt;

  void _onSoundChange() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void initState() {
    super.initState();
    _voiceMode = widget.voiceMode;
    AnalyticsService().logScreen('introduction');
    TtsService().addListener(_onSoundChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<LanguageProvider>().syncFromNav(
          widget.language,
          voiceMode: _voiceMode,
        );
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    setState(() => _isLoading = true);
    _loadSavedData();
  }

  @override
  void dispose() {
    TtsService().stop();
    TtsService().removeListener(_onSoundChange);
    super.dispose();
  }

  // English has no Education screen below Introduction in the stack (the
  // welcome screen skips straight here), so a single back press has nowhere
  // meaningful to go — require a second press within 2s to exit instead.
  // Pashto/Dari keep normal back navigation (down to Education).
  void _onPopInvoked(bool didPop, dynamic result) {
    TtsService().stop();
    if (didPop || _lang != 'en') return;
    final now = DateTime.now();
    if (_lastBackPressAt != null &&
        now.difference(_lastBackPressAt!) < const Duration(seconds: 2)) {
      SystemNavigator.pop();
      return;
    }
    _lastBackPressAt = now;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('Press back again to exit'),
      duration: const Duration(seconds: 2),
      backgroundColor: navy,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  Future<void> _loadSavedData() async {
    try {
      final prefs   = await SharedPreferences.getInstance();
      final alreadyCleaned = prefs.getBool('belgium_cleanup_done') ?? false;
      if (!alreadyCleaned) {
        await prefs.remove('selected_country');
        await prefs.remove('selected_country_name');
        await prefs.remove('cv_language');
        await prefs.setBool('belgium_cleanup_done', true);
      }
      final created = prefs.getBool('cv_created') ?? false;
      final cvType  = prefs.getString('cv_type') ?? '';
      final name    = prefs.getString('questionnaire_full_name')
                          ?.isNotEmpty == true
                          ? prefs.getString('questionnaire_full_name')!
                          : prefs.getString('user_name') ?? '';
      String city  = '';
      String photo = '';
      bool ausbildungExists = false;
      final profileJson = prefs.getString('saved_profile');
      if (profileJson != null && profileJson.isNotEmpty) {
        try {
          final map = jsonDecode(profileJson) as Map<String, dynamic>;
          city  = map['city']      as String? ?? '';
          photo = map['photoPath'] as String? ?? '';
          // Bug fix: this used to require ausbildungEduInstitutions/
          // ausbildungEscoSkills/schulabschluss to have actual content, but
          // Bildung and ESCO skills are both optional in the Ausbildung CV
          // questionnaire - a user who only fills Berufserfahrung/Sprachen/
          // IT-Kenntnisse gets a fully real, generated Ausbildung CV whose
          // preview screen is reachable, yet none of those three fields end
          // up non-empty, so this check said "no CV" for a CV that
          // genuinely exists (visible as "No CV found" back on this screen
          // after tapping Home from the preview).
          //
          // ausbildung_cv_questionnaire_screen.dart's _continueToPreview()
          // unconditionally WRITES ausbildungEduInstitutions into
          // saved_profile every time that questionnaire is submitted - even
          // as an empty string when Bildung was left blank. So KEY
          // PRESENCE, not value content, is the reliable "an Ausbildung CV
          // was created" signal here. questionnaire_screen.dart (Job CV)
          // never writes any 'ausbildung*'-prefixed key, so this can't
          // produce a false positive from a Job-only profile.
          // schulabschluss (from the separate Schulabschluss-only step)
          // stays as a value-based fallback alongside it.
          bool nonEmpty(String key) =>
              ((map[key] as String?) ?? '').trim().isNotEmpty;
          ausbildungExists = map.containsKey('ausbildungEduInstitutions') ||
              nonEmpty('schulabschluss');
        } catch (_) {}
      }
      final hasPhoto = photo.isNotEmpty && await File(photo).exists();
      final voiceMode = prefs.getBool('voice_mode') ?? false;
      final savedLang = prefs.getString('app_language');
      print('DEBUG cv_created: $created');
      print('DEBUG user_name: $name');
      if (mounted) {
        setState(() {
          _cvCreated     = created;
          _cvType        = cvType;
          _userName      = name;
          _userCity      = city;
          _userPhotoPath = hasPhoto ? photo : '';
          _ausbildungCvCreated = ausbildungExists;
          _voiceMode     = voiceMode;
          if (savedLang != null) _lang = savedLang;
          _isLoading     = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _goToQuestionnaire() async {
    final prefs     = await SharedPreferences.getInstance();
    final voiceMode = prefs.getBool('voice_mode') ?? false;
    if (!mounted) return;
    // Routes through ChooseCvTypeScreen (Job CV / Ausbildung CV) instead of
    // straight into QuestionnaireScreen - the only entry point for CV
    // creation now. Both callers of this method (the new-user "Create CV &
    // Find Jobs" card and the returning-user "Create a new CV" card) get
    // this automatically.
    Navigator.pushNamed(
      context,
      '/choose-cv-type',
      arguments: {
        'language': _lang,
        'voiceMode': voiceMode,
      },
    );
  }

  bool get _isRtl       => _lang == 'ps' || _lang == 'fa';
  bool get _showSpeaker => _lang == 'ps' || _lang == 'fa';

  void _selectCard(String card, VoidCallback navigate) {
    if (_selectedCard != null) return;
    setState(() => _selectedCard = card);
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      navigate();
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) setState(() => _selectedCard = null);
      });
    });
  }

  // ── String getters ──────────────────────────────────────────────────────────

  String get _pageTitle {
    switch (_lang) {
      case 'ps': return 'تاسو  کولای دلته لاندی کارونه ترسره کړئ';
      case 'fa': return 'شما می‌توانید کارهای زیر را انجام دهید.';
      default:   return 'Click on one of the options below to get started';
    }
  }

  String get _pageSubtitle {
    switch (_lang) {
      case 'ps': return 'د پیل لپاره یوه بټن کلیک کړئ';
      case 'fa': return 'یک گزینه را برای شروع انتخاب کنید';
      default:   return 'Choose an option to get started';
    }
  }

  // English-only per spec - see _newCvLabel above.
  String get _card1Title => 'Create CV/Cover letter';

  String get _card1Subtitle {
    switch (_lang) {
      case 'ps': return 'خپل جرمني CV جوړ کړئ او د کارونو لپاره غوښتنه وکړئ';
      case 'fa': return 'CV آلمانی بسازید و درخواست شغل دهید';
      default:   return 'Build your German CV and apply for jobs';
    }
  }

  String get _card2Title {
    switch (_lang) {
      case 'ps': return 'غواړي چی نژدي کارونه پیدا کړي؟';
      case 'fa': return 'کارهای نزدیک من را پیدا کنید';
      default:   return 'Find Jobs Near Me';
    }
  }

  String get _card2Subtitle {
    switch (_lang) {
      case 'ps': return 'د خپل سیمې کارونه وګورئ';
      case 'fa': return 'مشاغل موجود در منطقه خود را مرور کنید';
      default:   return 'Browse available jobs in your area';
    }
  }

  String get _welcomeBack {
    switch (_lang) {
      case 'ps': return 'ښه راغلاست،';
      case 'fa': return 'خوش آمدید،';
      default:   return 'Welcome back,';
    }
  }

  String get _findJobsLabel {
    switch (_lang) {
      case 'ps': return 'نژدي کارونه پیدا کړئ';
      case 'fa': return 'کارهای نزدیک را پیدا کنید';
      default:   return 'Find Jobs Near Me';
    }
  }

  String get _viewCvLabel {
    switch (_lang) {
      case 'ps': return 'زما جوړه شوی CV وګورئ';
      case 'fa': return 'CV من را ببینید';
      default:   return 'View / Download My CV';
    }
  }

  // English-only per spec - not translated to ps/fa like the rest of this
  // screen's labels (confirmed: every other label here stays multilingual).
  String get _newCvLabel => 'Create CV/Cover letter';

  String get _cvBadgeLabel {
    switch (_lang) {
      case 'ps': return 'ستاسو CV جوړه شوی ده.✓';
      case 'fa': return 'CV شما جور شد. ✓';
      default:   return 'CV Created ✓';
    }
  }

  String get _uploadDifferentCvLabel {
    switch (_lang) {
      case 'ps': return 'خپله CV اپلوډ کړئ';
      case 'fa': return 'CV خود را اپلوډ کنید';
      default:   return 'Upload Your own CV';
    }
  }

  String get _card3Title {
    switch (_lang) {
      case 'ps': return 'زه خپله CV لرم.';
      case 'fa': return 'من قبلاً CV دارم';
      default:   return 'I Already Have a CV';
    }
  }

  String get _card3Subtitle {
    switch (_lang) {
      case 'ps': return 'PDF اپلوډ کړئ او کارونه پیدا کړئ';
      case 'fa': return 'PDF آپلود کنید و کار پیدا کنید';
      default:   return 'Upload PDF and find jobs';
    }
  }

  String get _learnGermanLabel {
    switch (_lang) {
      case 'ps': return 'آلمانی زده کړئ';
      case 'fa': return 'آلمانی یاد بگیرید';
      default:   return 'Learn German';
    }
  }

  String get _displayName {
    final trimmed = _userName.trim();
    if (trimmed.isEmpty) return '';
    return trimmed.split(' ').first;
  }

  Future<void> _uploadCv() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (result != null && result.files.isNotEmpty) {
        final pickedPath = result.files.single.path ?? '';
        if (pickedPath.isEmpty) return;
        if (!mounted) return;
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (ctx) => CvUploadInfoSheet(
            language: _lang,
            voiceMode: widget.voiceMode,
            onComplete: (name, phone, email) async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('uploaded_cv_path', pickedPath);
              await prefs.setBool('cv_created', true);
              await prefs.setString('cv_type', 'uploaded');
              await prefs.setString('questionnaire_full_name', name);
              await prefs.setString('user_name', name);
              await prefs.setString('user_phone', phone);
              await prefs.setString('user_email', email);
              if (!mounted) return;
              Navigator.pop(context);
              setState(() {
                _cvCreated = true;
                _cvType    = 'uploaded';
                _userName  = name;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    _lang == 'ps'
                        ? 'CV اپلوډ شوه'
                        : _lang == 'fa'
                            ? 'CV آپلود شد'
                            : 'CV uploaded successfully',
                  ),
                  backgroundColor: const Color(0xFF39EA2B),
                ),
              );
            },
          ),
        );
      }
    } catch (e) {
      debugPrint('Upload error: $e');
    }
  }

  Future<void> _openSavedCv() async {
    try {
      final prefs  = await SharedPreferences.getInstance();
      final cvType = prefs.getString('cv_type') ?? '';
      if (cvType == 'uploaded') {
        final path = prefs.getString('uploaded_cv_path') ?? '';
        if (path.isEmpty) return;
        final exists = await File(path).exists();
        if (!exists) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
              _lang == 'ps'
                  ? 'د CV فایل ونه موندل شو'
                  : _lang == 'fa'
                      ? 'فایل CV پیدا نشد'
                      : 'CV file not found',
            ),
          ));
          return;
        }
        if (!await launchUrl(Uri.file(path),
            mode: LaunchMode.externalApplication)) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
              _lang == 'ps'
                  ? 'CV پرانستل نشوه'
                  : _lang == 'fa'
                      ? 'CV باز نشد'
                      : 'Could not open CV file',
            ),
          ));
        }
        return;
      }
      final profileJson = prefs.getString('saved_profile');
      if (profileJson == null || profileJson.isEmpty) return;
      final map = jsonDecode(profileJson) as Map<String, dynamic>;
      String? opt(String k) {
        final v = map[k] as String? ?? '';
        return v.isEmpty ? null : v;
      }
      final profile = UserProfile(
        fullName:       map['fullName']      as String? ?? '',
        phone:          map['phone']         as String? ?? '',
        email:          map['email']         as String? ?? '',
        street:         map['street']        as String? ?? '',
        city:           map['city']          as String? ?? '',
        languages:      (map['languages'] as String? ?? '').isEmpty
                            ? []
                            : (map['languages'] as String).split(','),
        dobDay:         int.tryParse(map['dobDay']   as String? ?? ''),
        dobMonth:       int.tryParse(map['dobMonth'] as String? ?? ''),
        dobYear:        int.tryParse(map['dobYear']  as String? ?? ''),
        country:        opt('country'),
        skill:          opt('skill'),
        workExperience: opt('workExperience'),
        workType:       opt('workType'),
        tools:          opt('tools'),
        drivingLicense: opt('drivingLicense'),
        availability:   opt('availability'),
        startDate:      opt('startDate'),
        photoPath:      opt('photoPath'),
      );
      if (!mounted) return;

      final jobExists = _cvCreated && _cvType != 'uploaded';
      final ausbildungExists = _ausbildungCvCreated;
      if (!jobExists && !ausbildungExists) {
        _showSnack(_noCvFoundText);
        return;
      }
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _MyCvScreen(
            profile: profile,
            language: _lang,
            jobExists: jobExists,
            ausbildungExists: ausbildungExists,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Error loading CV: $e');
    }
  }

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text, style: const TextStyle(color: Colors.white)),
      backgroundColor: navy,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  String get _noCvFoundText {
    switch (_lang) {
      case 'ps': return 'ستاسی سییوی پیدا نشوه، لطفاً نوی سییوی جوړ کړی.';
      case 'fa': return ' سییوی یافت نشد. لطفاًسییوی نو بسازید.';
      default:   return 'No CV found. Please create one first.';
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    _lang = context.watch<LanguageProvider>().language;

    if (_isLoading) {
      return PopScope(
        canPop: _lang != 'en',
        onPopInvokedWithResult: _onPopInvoked,
        child: const Scaffold(
          backgroundColor: Color(0xFFF7FAFF),
          body: Center(
            child: CircularProgressIndicator(
              color: Color(0xFF39EA2B),
            ),
          ),
        ),
      );
    }

    return PopScope(
      canPop: _lang != 'en',
      onPopInvokedWithResult: _onPopInvoked,
      child: Scaffold(
      backgroundColor: const Color(0xFFF7FAFF),
      body: Stack(
        children: [
          const _BackgroundGlow(),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Fixed top row ──────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      RichText(
                        text: const TextSpan(
                          children: [
                            TextSpan(
                              text: 'Kar',
                              style: TextStyle(
                                color: navy,
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.5,
                                height: 1,
                              ),
                            ),
                            TextSpan(
                              text: 'Yab',
                              style: TextStyle(
                                color: green,
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.5,
                                height: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _LangPill(
                            lang: _lang,
                            onLanguageChanged: (newLang, voiceMode) {
                              if (mounted) {
                                setState(() => _voiceMode = voiceMode);
                              }
                            },
                          ),
                          const SizedBox(width: 8),
                          _TopButton(
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
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ── Scrollable content ─────────────────────────────────────
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 430),
                        child: Column(
                          children: [
                            // ── State 1: New user ──────────────────────────
                            // Bug fix: this used to gate on _cvCreated alone,
                            // so a user who completed only an Ausbildung CV
                            // (cv_created stays false - that flag is Job-CV-
                            // specific) still saw the "New user" state
                            // instead of "Returning user" with its View/
                            // Download My CV button, regardless of which
                            // Home button (Postings or Preview screen) they
                            // used to get back here.
                            if (!_cvCreated && !_ausbildungCvCreated) ...[
                              _GlassSurface(
                                borderRadius: 24,
                                padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
                                shadowOpacity: 0.11,
                                child: Column(
                                  children: [
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment: CrossAxisAlignment.baseline,
                                      textBaseline: TextBaseline.alphabetic,
                                      children: const [
                                        Text(
                                          'Kar',
                                          style: TextStyle(
                                            color: navy,
                                            fontSize: 26,
                                            height: 1,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: -1,
                                          ),
                                        ),
                                        Text(
                                          'Yab',
                                          style: TextStyle(
                                            color: green,
                                            fontSize: 26,
                                            height: 1,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: -1,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 14),
                                    Directionality(
                                      textDirection: _isRtl
                                          ? TextDirection.rtl
                                          : TextDirection.ltr,
                                      child: Text(
                                        _pageTitle,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: navy,
                                          fontSize: 22,
                                          fontWeight: FontWeight.w800,
                                          height: 1.3,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Directionality(
                                      textDirection: _isRtl
                                          ? TextDirection.rtl
                                          : TextDirection.ltr,
                                      child: Text(
                                        _pageSubtitle,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: Color(0xFF65738A),
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          height: 1.4,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 16),

                              // Action grid — 2 columns, same tile style and
                              // educated/uneducated sizing rule as State 2's
                              // grid below. Educated users additionally get
                              // the Ausbildung tile (5 tiles total); everyone
                              // gets Create CV, Find Jobs, Upload CV and
                              // Deutschkurs.
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                child: GridView.count(
                                crossAxisCount: 2,
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12,
                                childAspectRatio: _voiceMode ? 0.95 : 1.25,
                                children: [
                                  _SecondaryActionCard(
                                    icon: Icons.article_rounded,
                                    iconColor: green,
                                    label: _card1Title,
                                    isRtl: _isRtl,
                                    showSpeaker: _showSpeaker,
                                    compact: !_voiceMode,
                                    onSpeaker: _showSpeaker
                                        ? () => TtsService().speak(
                                              _lang == 'ps'
                                                  ? 'آیا غواړی چی د ځان لپاره یوه نوی سییوی جوړ کړي؟'
                                                  : 'سییوی نو بسازید و کار پیدا کنید',
                                              _lang,
                                            )
                                        : null,
                                    onTap: () =>
                                        _selectCard('cv', _goToQuestionnaire),
                                  ),
                                  _SecondaryActionCard(
                                    icon: Icons.work_rounded,
                                    iconColor: const Color(0xFF2D6BE4),
                                    label: _card2Title,
                                    isRtl: _isRtl,
                                    showSpeaker: _showSpeaker,
                                    compact: !_voiceMode,
                                    onSpeaker: _showSpeaker
                                        ? () => TtsService().speak(
                                              _lang == 'ps'
                                                  ? 'غواړي چی نژدي کارونه پیدا کړي؟'
                                                  : 'کارهای نزدیک من را پیدا کنید',
                                              _lang,
                                            )
                                        : null,
                                    onTap: () => _selectCard('jobs', () {
                                      Navigator.pushNamed(
                                        context,
                                        '/jobfinder',
                                        arguments: _lang,
                                      );
                                    }),
                                  ),
                                  _SecondaryActionCard(
                                    icon: Icons.upload_file_rounded,
                                    iconColor: const Color(0xFF2D6BE4),
                                    label: _card3Title,
                                    isRtl: _isRtl,
                                    showSpeaker: _showSpeaker,
                                    compact: !_voiceMode,
                                    onSpeaker: _showSpeaker
                                        ? () => TtsService().speak(
                                              _lang == 'ps'
                                                  ? 'زه خپله سییوی لرم'
                                                  : 'من قبلاً سییوی دارم',
                                              _lang,
                                            )
                                        : null,
                                    onTap: () =>
                                        _selectCard('upload', () => _uploadCv()),
                                  ),
                                  if (!_voiceMode)
                                    _SecondaryActionCard(
                                      icon: Icons.school_rounded,
                                      iconColor: const Color(0xFF2D6BE4),
                                      // "Ausbildung" is always German — never
                                      // translated to PS/FA, same principle
                                      // as the Job Type filter.
                                      label: 'Ausbildung',
                                      isRtl: _isRtl,
                                      showSpeaker: _showSpeaker,
                                      compact: true,
                                      onSpeaker: _showSpeaker
                                          ? () => TtsService().speak(
                                                _lang == 'ps'
                                                    ? 'د زده کړې کار ومومئ'
                                                    : 'کارآموزی پیدا کنید',
                                                _lang,
                                              )
                                          : null,
                                      onTap: () => _selectCard('ausbildung', () {
                                        Navigator.pushNamed(
                                          context,
                                          '/ausbildung',
                                          arguments: {
                                            'language': _lang,
                                            'voiceMode': _voiceMode,
                                          },
                                        );
                                      }),
                                    ),
                                  _SecondaryActionCard(
                                    icon: Icons.translate_rounded,
                                    iconColor: const Color(0xFF9C27B0),
                                    label: _learnGermanLabel,
                                    isRtl: _isRtl,
                                    showSpeaker: _showSpeaker,
                                    compact: !_voiceMode,
                                    onSpeaker: _showSpeaker
                                        ? () => TtsService().speak(
                                              _lang == 'ps'
                                                  ? 'آلمانی زده کړئ'
                                                  : 'آلمانی یاد بگیرید',
                                              _lang,
                                            )
                                        : null,
                                    onTap: () => _selectCard('deutsch', () {
                                      Navigator.pushNamed(
                                        context,
                                        '/deutsch-courses',
                                        arguments: {
                                          'language': _lang,
                                          'voiceMode': _voiceMode,
                                        },
                                      );
                                    }),
                                  ),
                                ],
                                ),
                              ),
                            ],

                            // ── State 2: Returning user ────────────────────
                            if (_cvCreated || _ausbildungCvCreated) ...[
                              const SizedBox(height: 12),
                              Container(
                                margin: const EdgeInsets.symmetric(horizontal: 15),
                                child: _GlassSurface(
                                  borderRadius: 22,
                                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                                  shadowOpacity: 0.10,
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Container(
                                      width: 54,
                                      height: 54,
                                      decoration: const BoxDecoration(
                                        color: Color(0xFFEAFBE9),
                                        shape: BoxShape.circle,
                                      ),
                                      child: _userPhotoPath.isNotEmpty
                                          ? ClipOval(
                                              child: Image.file(
                                                File(_userPhotoPath),
                                                width: 54,
                                                height: 54,
                                                fit: BoxFit.cover,
                                                errorBuilder:
                                                    (context, error, stack) =>
                                                        const Icon(
                                                  Icons.person_rounded,
                                                  color: green,
                                                  size: 30,
                                                ),
                                              ),
                                            )
                                          : const Icon(
                                              Icons.person_rounded,
                                              color: green,
                                              size: 30,
                                            ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: _isRtl
                                            ? CrossAxisAlignment.end
                                            : CrossAxisAlignment.start,
                                        children: [
                                          Directionality(
                                            textDirection: _isRtl
                                                ? TextDirection.rtl
                                                : TextDirection.ltr,
                                            child: Text(
                                              '$_welcomeBack${_displayName.isNotEmpty ? ' $_displayName' : ''}!',
                                              style: const TextStyle(
                                                color: navy,
                                                fontSize: 18,
                                                fontWeight: FontWeight.w800,
                                                height: 1.2,
                                              ),
                                            ),
                                          ),
                                          if (_userCity.isNotEmpty) ...[
                                            const SizedBox(height: 3),
                                            Text(
                                              '$_userCity, Deutschland',
                                              style: const TextStyle(
                                                color: Color(0xFF65738A),
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                          const SizedBox(height: 7),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFE9FFE6),
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            child: Text(
                                              _cvBadgeLabel,
                                              style: const TextStyle(
                                                color: Color(0xFF147C20),
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              ),

                              const SizedBox(height: 12),

                              // Search bar — Find Jobs (primary filled)
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                child: _PrimaryActionCard(
                                  icon: Icons.search_rounded,
                                  label: _findJobsLabel,
                                  isRtl: _isRtl,
                                  isSelected: _selectedCard == 'jobs',
                                  showSpeaker: _showSpeaker,
                                  onSpeaker: _showSpeaker
                                      ? () => TtsService().speak(
                                            _lang == 'ps'
                                                ? 'د خپل ښار نژدي کارونه پیدا کړئ'
                                                : 'کارهای نزدیک را پیدا کنید',
                                            _lang,
                                          )
                                      : null,
                                  onTap: () => _selectCard('jobs', () {
                                    Navigator.pushNamed(
                                      context,
                                      '/jobfinder',
                                      arguments: _lang,
                                    );
                                  }),
                                ),
                              ),

                              const SizedBox(height: 14),

                              // Action grid — 2 columns. Ausbildung is
                              // restricted to educated users (voiceMode ==
                              // false); uneducated users get a clean 2x2 of
                              // the remaining four tiles.
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                child: GridView.count(
                                  crossAxisCount: 2,
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  mainAxisSpacing: 12,
                                  crossAxisSpacing: 12,
                                  // Educated users get a 5th tile (Ausbildung)
                                  // so their tiles need to be flatter/smaller
                                  // to still fit one screen; uneducated stays
                                  // at its current size.
                                  childAspectRatio: _voiceMode ? 0.95 : 1.25,
                                  children: [
                                    _SecondaryActionCard(
                                      icon: Icons.add_circle_outline_rounded,
                                      iconColor: green,
                                      label: _newCvLabel,
                                      isRtl: _isRtl,
                                      showSpeaker: _showSpeaker,
                                      compact: !_voiceMode,
                                      onSpeaker: _showSpeaker
                                          ? () => TtsService().speak(
                                                _lang == 'ps'
                                                    ? 'نوی سییوی جوړ کړئ'
                                                    : 'ایجاد CV جدید',
                                                _lang,
                                              )
                                          : null,
                                      onTap: _goToQuestionnaire,
                                    ),
                                    _SecondaryActionCard(
                                      icon: Icons.description_rounded,
                                      iconColor: green,
                                      label: _viewCvLabel,
                                      isRtl: _isRtl,
                                      showSpeaker: _showSpeaker,
                                      compact: !_voiceMode,
                                      onSpeaker: _showSpeaker
                                          ? () => TtsService().speak(
                                                _lang == 'ps'
                                                    ? 'زما جوړه شوی سییوی ښکاره کړی'
                                                    : 'سییوی من را ببینید',
                                                _lang,
                                              )
                                          : null,
                                      onTap: () { _openSavedCv(); },
                                    ),
                                    _SecondaryActionCard(
                                      icon: Icons.upload_file_rounded,
                                      iconColor: const Color(0xFF2D6BE4),
                                      label: _uploadDifferentCvLabel,
                                      isRtl: _isRtl,
                                      showSpeaker: _showSpeaker,
                                      compact: !_voiceMode,
                                      onSpeaker: _showSpeaker
                                          ? () => TtsService().speak(
                                                _lang == 'ps'
                                                    ? 'خپله سییوی اپلوډ کړئ'
                                                    : 'سییوی خود را اپلوډ کنید',
                                                _lang,
                                              )
                                          : null,
                                      onTap: () => _uploadCv(),
                                    ),
                                    if (!_voiceMode)
                                      _SecondaryActionCard(
                                        icon: Icons.school_rounded,
                                        iconColor: const Color(0xFF2D6BE4),
                                        // "Ausbildung" is always German —
                                        // never translated to PS/FA, same
                                        // principle as the Job Type filter.
                                        label: 'Ausbildung',
                                        isRtl: _isRtl,
                                        showSpeaker: _showSpeaker,
                                        compact: true,
                                        onSpeaker: _showSpeaker
                                            ? () => TtsService().speak(
                                                  _lang == 'ps'
                                                      ? 'د زده کړې کار ومومئ'
                                                      : 'کارآموزی پیدا کنید',
                                                  _lang,
                                                )
                                            : null,
                                        onTap: () => _selectCard('ausbildung', () {
                                          Navigator.pushNamed(
                                            context,
                                            '/ausbildung',
                                            arguments: {
                                              'language': _lang,
                                              'voiceMode': _voiceMode,
                                            },
                                          );
                                        }),
                                      ),
                                    _SecondaryActionCard(
                                      icon: Icons.translate_rounded,
                                      iconColor: const Color(0xFF9C27B0),
                                      label: _learnGermanLabel,
                                      isRtl: _isRtl,
                                      showSpeaker: _showSpeaker,
                                      compact: !_voiceMode,
                                      onSpeaker: _showSpeaker
                                          ? () => TtsService().speak(
                                                _lang == 'ps'
                                                    ? 'آلمانی زده کړئ'
                                                    : 'آلمانی یاد بگیرید',
                                                _lang,
                                              )
                                          : null,
                                      onTap: () => _selectCard('deutsch', () {
                                        Navigator.pushNamed(
                                          context,
                                          '/deutsch-courses',
                                          arguments: {
                                            'language': _lang,
                                            'voiceMode': _voiceMode,
                                          },
                                        );
                                      }),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // ── Fixed version footer ───────────────────────────────────
                const Padding(
                  padding: EdgeInsets.fromLTRB(0, 8, 0, 12),
                  child: Text(
                    'KarYab v1.0',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF65738A),
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
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
}

// ── My CV — full-screen View/Download, replaces the old "which CV?" bottom
// sheet. A Job CV / Ausbildung CV toggle sits at the top; whichever side is
// selected is rendered by embedding the existing CvPreviewScreen /
// AusbildungDocumentPreviewScreen widgets directly (embedded: true
// suppresses their own header/background so this screen supplies one shared
// header + toggle instead) - reuses their full template-picker/PdfPreview/
// download/edit-answers UI as-is rather than rebuilding it. If only one CV
// type exists, that side's toggle segment is disabled (greyed out,
// non-tappable) instead of hidden.
// ─────────────────────────────────────────────────────────────────────────────

class _MyCvScreen extends StatefulWidget {
  final UserProfile profile;
  final String language;
  final bool jobExists;
  final bool ausbildungExists;

  const _MyCvScreen({
    required this.profile,
    required this.language,
    required this.jobExists,
    required this.ausbildungExists,
  });

  @override
  State<_MyCvScreen> createState() => _MyCvScreenState();
}

class _MyCvScreenState extends State<_MyCvScreen> {
  static const Color navy  = Color(0xFF091733);
  static const Color green = Color(0xFF39EA2B);

  late String _selected; // 'job' or 'ausbildung'

  @override
  void initState() {
    super.initState();
    _selected = widget.jobExists ? 'job' : 'ausbildung';
  }

  bool get _isRtl => widget.language == 'ps' || widget.language == 'fa';

  String get _titleLabel {
    switch (widget.language) {
      case 'ps': return 'زما CV';
      case 'fa': return 'CV من';
      default:   return 'My CV';
    }
  }

  String get _jobCvLabel {
    switch (widget.language) {
      case 'ps': return 'د کار CV';
      case 'fa': return 'رزومه کاری';
      default:   return 'Job CV';
    }
  }

  String get _ausbildungCvLabel {
    switch (widget.language) {
      case 'ps': return 'د زده کړې CV';
      case 'fa': return 'رزومه کارآموزی';
      default:   return 'Ausbildung CV';
    }
  }

  void _goHome() =>
      goHomeToIntroduction(context, language: widget.language, voiceMode: false);

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: _isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: const Color(0xFFF7FAFF),
        body: Stack(
          children: [
            const _BackgroundGlow(),
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Row(
                      children: [
                        _TopButton(
                          icon: Icons.arrow_back_ios_new_rounded,
                          onTap: () => Navigator.pop(context),
                        ),
                        Expanded(
                          child: Text(
                            _titleLabel,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: navy,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        _TopButton(icon: Icons.home_rounded, onTap: _goHome),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _cvTypeToggle(),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: _selected == 'job'
                        ? CvPreviewScreen(profile: widget.profile, embedded: true)
                        : AusbildungDocumentPreviewScreen(
                            profile: widget.profile,
                            language: widget.language,
                            embedded: true,
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

  Widget _cvTypeToggle() {
    Widget segment({
      required String value,
      required String label,
      required bool exists,
    }) {
      final selected = _selected == value;
      return Expanded(
        child: GestureDetector(
          onTap: exists ? () => setState(() => _selected = value) : null,
          child: Opacity(
            opacity: exists ? 1 : 0.4,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: selected ? green : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected ? green : const Color(0xFFE4EAF5),
                  width: selected ? 2.0 : 1.2,
                ),
              ),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: selected ? Colors.white : navy,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        segment(value: 'job', label: _jobCvLabel, exists: widget.jobExists),
        const SizedBox(width: 10),
        segment(
            value: 'ausbildung',
            label: _ausbildungCvLabel,
            exists: widget.ausbildungExists),
      ],
    );
  }
}

// ── Top icon button ───────────────────────────────────────────────────────────

class _TopButton extends StatelessWidget {
  static const Color navy  = Color(0xFF091733);
  static const Color green = Color(0xFF39EA2B);

  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  final bool hintPulse;

  const _TopButton({
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
              child: Icon(icon, color: active ? green : navy, size: 20),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Language pill ─────────────────────────────────────────────────────────────

class _LangPill extends StatelessWidget {
  static const Color _navy = Color(0xFF091733);

  final String lang;
  // Called after the language switch (and its SharedPreferences /
  // LanguageProvider updates) completes, so the parent screen can refresh
  // any of its own local state that depends on voiceMode (e.g. which tile
  // grid to show) immediately instead of waiting for the next screen load.
  final void Function(String newLang, bool voiceMode)? onLanguageChanged;

  const _LangPill({required this.lang, this.onLanguageChanged});

  String get _label {
    switch (lang) {
      case 'ps': return 'PS';
      case 'fa': return 'FA';
      default:   return 'EN';
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        final provider = context.read<LanguageProvider>();
        final currentVoiceMode = provider.voiceMode;
        showModalBottomSheet(
          context: context,
          backgroundColor: Colors.transparent,
          isScrollControlled: true,
          builder: (ctx) => _LanguagePicker(
            currentLang: lang,
            onSelect: (newLang) async {
              Navigator.pop(ctx);
              // Switching TO English always forces the educated interface;
              // switching between Pashto/Dari leaves voiceMode untouched —
              // that was set explicitly on the education screen.
              final voiceMode =
                  newLang == 'en' ? false : currentVoiceMode;
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('voice_mode', voiceMode);
              await prefs.setString('app_language', newLang);
              provider.syncFromNav(newLang, voiceMode: voiceMode);
              onLanguageChanged?.call(newLang, voiceMode);
            },
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: _navy,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: _navy.withOpacity(0.20),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down_rounded,
                color: Colors.white, size: 14),
          ],
        ),
      ),
    );
  }
}

// ── Language picker bottom sheet ──────────────────────────────────────────────

class _LanguagePicker extends StatelessWidget {
  static const Color _navy  = Color(0xFF091733);
  static const Color _green = Color(0xFF39EA2B);

  final String currentLang;
  final ValueChanged<String> onSelect;

  const _LanguagePicker({
    required this.currentLang,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final langs = [
      {'code': 'ps', 'native': 'پښتو',    'roman': 'Pashto'},
      {'code': 'fa', 'native': 'دری',     'roman': 'Dari'},
      {'code': 'en', 'native': 'English', 'roman': 'English'},
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
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
          ...langs.map((e) {
            final isSelected = e['code'] == currentLang;
            return GestureDetector(
              onTap: () => onSelect(e['code']!),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: isSelected
                      ? _green.withOpacity(0.08)
                      : const Color(0xFFF7FAFF),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected ? _green : const Color(0xFFE4EAF5),
                    width: isSelected ? 2.0 : 1.2,
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      e['native']!,
                      style: TextStyle(
                        color: _navy,
                        fontSize: 16,
                        fontWeight: isSelected
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      e['roman']!,
                      style: const TextStyle(
                        color: Color(0xFF65738A),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    if (isSelected)
                      const Icon(Icons.check_circle_rounded,
                          color: _green, size: 20),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ── Nav option card (State 1) ─────────────────────────────────────────────────

class _NavOptionCard extends StatefulWidget {
  final IconData icon;
  final Color iconBgColor;
  final Color iconColor;
  final Color arrowColor;
  final Color selectedBorderColor;
  final String title;
  final String subtitle;
  final bool isRtl;
  final bool showSpeaker;
  final bool isSelected;
  final VoidCallback? onSpeaker;
  final VoidCallback onTap;

  const _NavOptionCard({
    required this.icon,
    required this.iconBgColor,
    required this.iconColor,
    required this.arrowColor,
    required this.selectedBorderColor,
    required this.title,
    required this.subtitle,
    required this.isRtl,
    required this.showSpeaker,
    required this.isSelected,
    this.onSpeaker,
    required this.onTap,
  });

  @override
  State<_NavOptionCard> createState() => _NavOptionCardState();
}

class _NavOptionCardState extends State<_NavOptionCard>
    with SingleTickerProviderStateMixin {
  static const Color navy = Color(0xFF091733);

  late AnimationController _pressCtrl;
  late Animation<double>   _scaleAnim;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.97)
        .animate(CurvedAnimation(parent: _pressCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool lit = widget.isSelected;
    return ScaleTransition(
      scale: _scaleAnim,
      child: GestureDetector(
        onTapDown: (_) => _pressCtrl.forward(),
        onTapUp: (_) {
          _pressCtrl.reverse();
          widget.onTap();
        },
        onTapCancel: () => _pressCtrl.reverse(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: lit
                ? widget.selectedBorderColor.withOpacity(0.07)
                : Colors.white.withOpacity(0.62),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: lit
                  ? widget.selectedBorderColor
                  : Colors.white.withOpacity(0.80),
              width: lit ? 2.0 : 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: lit
                    ? widget.selectedBorderColor.withOpacity(0.14)
                    : Colors.black.withOpacity(0.06),
                blurRadius: lit ? 22 : 14,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            textDirection:
                widget.isRtl ? TextDirection.rtl : TextDirection.ltr,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: widget.iconBgColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(widget.icon, color: widget.iconColor, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: widget.isRtl
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      textDirection: widget.isRtl
                          ? TextDirection.rtl
                          : TextDirection.ltr,
                      style: const TextStyle(
                        color: navy,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      widget.subtitle,
                      textDirection: widget.isRtl
                          ? TextDirection.rtl
                          : TextDirection.ltr,
                      style: const TextStyle(
                        color: Color(0xFF65738A),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.showSpeaker && widget.onSpeaker != null)
                IconButton(
                  onPressed: widget.onSpeaker,
                  icon: const Icon(Icons.volume_up, color: Color(0xFF39EA2B)),
                  iconSize: 18,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              const SizedBox(width: 10),
              Icon(
                widget.isRtl
                    ? Icons.arrow_back_ios_new_rounded
                    : Icons.arrow_forward_ios_rounded,
                color: widget.arrowColor,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Primary action card (State 2 — Find Jobs, navy gradient) ──────────────────

class _PrimaryActionCard extends StatelessWidget {
  static const Color green = Color(0xFF39EA2B);

  final IconData icon;
  final String label;
  final bool isRtl;
  final bool isSelected;
  final bool showSpeaker;
  final VoidCallback? onSpeaker;
  final VoidCallback onTap;

  const _PrimaryActionCard({
    required this.icon,
    required this.label,
    required this.isRtl,
    required this.isSelected,
    this.showSpeaker = false,
    this.onSpeaker,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: isSelected ? 0.75 : 1.0,
      duration: const Duration(milliseconds: 200),
      child: Container(
        width: double.infinity,
        height: 64,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Color(0xFF081532), Color(0xFF07112B)],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF07112B).withOpacity(0.30),
              blurRadius: 22,
              offset: const Offset(0, 12),
            ),
            BoxShadow(
              color: green.withOpacity(0.20),
              blurRadius: 26,
              offset: const Offset(14, 14),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                textDirection:
                    isRtl ? TextDirection.rtl : TextDirection.ltr,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: green.withOpacity(0.18),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: green, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      label,
                      textDirection:
                          isRtl ? TextDirection.rtl : TextDirection.ltr,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  if (showSpeaker && onSpeaker != null)
                    IconButton(
                      onPressed: onSpeaker,
                      icon: const Icon(Icons.volume_up, color: Color(0xFF39EA2B)),
                      iconSize: 18,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  Icon(
                    isRtl
                        ? Icons.arrow_back_ios_new_rounded
                        : Icons.arrow_forward_rounded,
                    color: green,
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Secondary action card (State 2 — 2-column grid tile) ───────────────────────
// Same colors/glass style as before; internal layout is a compact vertical
// stack (icon over label) instead of a horizontal bar, so it fits a square
// GridView cell.

class _SecondaryActionCard extends StatelessWidget {
  static const Color navy = Color(0xFF091733);

  final IconData icon;
  final Color iconColor;
  final String label;
  final bool isRtl;
  final bool showSpeaker;
  final VoidCallback? onSpeaker;
  final VoidCallback onTap;
  // True for the 5-tile educated grid, which needs slightly smaller tiles
  // to fit on one screen; the 4-tile uneducated grid keeps its full size.
  final bool compact;

  const _SecondaryActionCard({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.isRtl,
    this.showSpeaker = false,
    this.onSpeaker,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final double iconBox  = compact ? 34 : 40;
    final double iconSize = compact ? 16 : 20;
    final double gap      = compact ? 6  : 8;
    final double pad      = compact ? 8  : 10;
    final double fontSize = compact ? 11 : 12;

    return Stack(
      children: [
        // SizedBox.expand forces the card to fill the exact GridView cell
        // size regardless of label length — only the content inside is
        // allowed to vary, never the card itself.
        SizedBox.expand(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.62),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                  color: Colors.white.withOpacity(0.85), width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 14,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: onTap,
                child: Padding(
                  padding: EdgeInsets.all(pad),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: iconBox,
                        height: iconBox,
                        decoration: BoxDecoration(
                          color: iconColor.withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(icon, color: iconColor, size: iconSize),
                      ),
                      SizedBox(height: gap),
                      Text(
                        label,
                        textDirection:
                            isRtl ? TextDirection.rtl : TextDirection.ltr,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: navy,
                          fontSize: fontSize,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (showSpeaker && onSpeaker != null)
          Positioned(
            top: 2,
            right: isRtl ? null : 2,
            left: isRtl ? 2 : null,
            child: IconButton(
              onPressed: onSpeaker,
              icon: const Icon(Icons.volume_up, color: Color(0xFF39EA2B)),
              iconSize: 16,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ),
      ],
    );
  }
}

// ── Background glow ───────────────────────────────────────────────────────────

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
        Positioned(top: 70,   left: -42,  child: _Orb(size: 170, color: Color(0x6639EA2B))),
        Positioned(top: 135,  right: -65, child: _Orb(size: 170, color: Color(0x44FFB86B))),
        Positioned(bottom: 95,  left: -60, child: _Orb(size: 210, color: Color(0x3339EA2B))),
        Positioned(bottom: -30, right: 14, child: _Orb(size: 145, color: Color(0x5539EA2B))),
        Positioned(top: 20,   left: 30,   child: _Orb(size: 170, color: Color(0x30FF8FA3))),
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

// ── Glass surface ─────────────────────────────────────────────────────────────

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
