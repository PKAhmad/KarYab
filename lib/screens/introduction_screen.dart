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
import '../ui/karyab_ui.dart';
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
  static const Color navy  = KColors.navy;
  static const Color green = KColors.green;

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
    kSnack(context, 'Press back again to exit',
        duration: const Duration(seconds: 2));
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
                  backgroundColor: KColors.green,
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
    kSnack(context, text);
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
          backgroundColor: KColors.pageBase,
          body: Center(
            child: CircularProgressIndicator(
              color: KColors.green,
            ),
          ),
        ),
      );
    }

    return PopScope(
      canPop: _lang != 'en',
      onPopInvokedWithResult: _onPopInvoked,
      child: Scaffold(
      backgroundColor: KColors.pageBase,
      body: Stack(
        children: [
          const KBackgroundGlow(),
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
                          KNavButton(
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
                              KGlassSurface(
                                borderRadius: 24,
                                padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
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
                                          color: KColors.textSecondary,
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
                                  KGridTile(
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
                                  KGridTile(
                                    icon: Icons.work_rounded,
                                    iconColor: KColors.blue,
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
                                  KGridTile(
                                    icon: Icons.upload_file_rounded,
                                    iconColor: KColors.blue,
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
                                    KGridTile(
                                      icon: Icons.school_rounded,
                                      iconColor: KColors.blue,
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
                                  KGridTile(
                                    icon: Icons.translate_rounded,
                                    iconColor: KColors.purple,
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
                                child: KGlassSurface(
                                  borderRadius: 22,
                                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Container(
                                      width: 54,
                                      height: 54,
                                      decoration: const BoxDecoration(
                                        color: KColors.mint,
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
                                                color: KColors.textSecondary,
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
                                              color: KColors.mintBadge,
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            child: Text(
                                              _cvBadgeLabel,
                                              style: const TextStyle(
                                                color: KColors.greenDarkBadge,
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
                                child: KPrimaryCta(
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
                                    KGridTile(
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
                                    KGridTile(
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
                                    KGridTile(
                                      icon: Icons.upload_file_rounded,
                                      iconColor: KColors.blue,
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
                                      KGridTile(
                                        icon: Icons.school_rounded,
                                        iconColor: KColors.blue,
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
                                    KGridTile(
                                      icon: Icons.translate_rounded,
                                      iconColor: KColors.purple,
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
                      color: KColors.textSecondary,
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
  static const Color navy  = KColors.navy;
  static const Color green = KColors.green;

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
        backgroundColor: KColors.pageBase,
        body: Stack(
          children: [
            const KBackgroundGlow(),
            SafeArea(
              child: Column(
                children: [
                  Padding(
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
                              color: navy,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        KNavButton(icon: Icons.home_rounded, onTap: _goHome),
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
                  color: selected ? green : KColors.borderSoft,
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

// ── Language pill ─────────────────────────────────────────────────────────────

class _LangPill extends StatelessWidget {
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
    return KLangPill(
      label: _label,
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
    );
  }
}

// ── Language picker bottom sheet ──────────────────────────────────────────────

class _LanguagePicker extends StatelessWidget {
  static const Color _navy  = KColors.navy;
  static const Color _green = KColors.green;

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
      decoration: kSheetDecoration,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(child: KSheetHandle()),
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
                      : KColors.pageBase,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected ? _green : KColors.borderSoft,
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
                        color: KColors.textSecondary,
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
