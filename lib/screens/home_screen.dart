import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/user_profile.dart';
import '../providers/language_provider.dart';
import '../services/analytics_service.dart';
import '../services/tts_service.dart';
import '../widgets/cv_upload_info_sheet.dart';
import 'ausbildung_document_preview_screen.dart';

/// KarYab home hub — glassmorphic profile/CV bar, a "find jobs near me"
/// search pill, and a 2-column grid of quick actions (create/view/upload CV,
/// find an Ausbildung, learn German). Mirrors the returning-user dashboard
/// that used to live inline in IntroductionScreen, as its own route.
class HomeScreen extends StatefulWidget {
  final String language;
  final bool voiceMode;

  const HomeScreen({super.key, required this.language, this.voiceMode = false});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeAction {
  final String label;
  final IconData icon;
  final Color bg;
  final Color tint;
  final VoidCallback onTap;

  const _HomeAction({
    required this.label,
    required this.icon,
    required this.bg,
    required this.tint,
    required this.onTap,
  });
}

class _HomeScreenState extends State<HomeScreen> {
  static const Color _bg = Color(0xFFFBFCFA);
  static const Color _ink = Color(0xFF16211C);
  static const Color _green = Color(0xFF2FA84F);
  static const Color _pillNavy = Color(0xFF0D1B2A);
  static const Color _muted = Color(0xFF7C8A80);
  static const Color _footer = Color(0xFFA8B3AC);

  String _lang = 'en';
  bool _voiceMode = false;
  bool _cvCreated = false;
  String _cvType = '';
  String _userName = '';
  String _userCity = '';
  // No dedicated 'ausbildung_cv_created' flag exists (unlike the Job CV's
  // 'cv_created'/'cv_type') - the Ausbildung questionnaire/Schulabschluss
  // screens only ever write into 'saved_profile', so this is derived in
  // _loadPrefs() from the presence of that flow's own keys.
  bool _ausbildungCvCreated = false;

  bool get _isRtl => _lang != 'en';

  // Job CV = the questionnaire-generated CV ('cv_created' true and not an
  // uploaded file). Kept separate from _cvCreated/_cvType, which also cover
  // the uploaded-CV case.
  bool get _jobCvExists => _cvCreated && _cvType != 'uploaded';
  bool get _anyCvExists => _cvCreated || _ausbildungCvCreated;

  String get _displayName {
    final trimmed = _userName.trim();
    return trimmed.isEmpty ? '' : trimmed.split(' ').first;
  }

  void _onSoundChange() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _lang = widget.language;
    _voiceMode = widget.voiceMode;
    AnalyticsService().logScreen('home');
    TtsService().addListener(_onSoundChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<LanguageProvider>().syncFromNav(
              widget.language,
              voiceMode: widget.voiceMode,
            );
      }
    });
    _loadPrefs();
  }

  @override
  void dispose() {
    TtsService().removeListener(_onSoundChange);
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final created = prefs.getBool('cv_created') ?? false;
      final cvType = prefs.getString('cv_type') ?? '';
      final name = prefs.getString('questionnaire_full_name')?.isNotEmpty == true
          ? prefs.getString('questionnaire_full_name')!
          : prefs.getString('user_name') ?? '';
      String city = prefs.getString('user_city') ?? '';
      bool ausbildungExists = false;
      final profileJson = prefs.getString('saved_profile');
      if (profileJson != null && profileJson.isNotEmpty) {
        try {
          final map = jsonDecode(profileJson) as Map<String, dynamic>;
          final mapCity = map['city'] as String? ?? '';
          if (mapCity.isNotEmpty) city = mapCity;
          // Same existence check used by ausbildung_document_preview_screen.dart's
          // caller flow: ausbildungEduInstitutions/ausbildungEscoSkills are
          // written by the Ausbildung ESCO questionnaire, schulabschluss by
          // the Ausbildung-only Schulabschluss step - any one of them present
          // means the user has an Ausbildung CV.
          bool nonEmpty(String key) =>
              ((map[key] as String?) ?? '').trim().isNotEmpty;
          ausbildungExists = nonEmpty('ausbildungEduInstitutions') ||
              nonEmpty('ausbildungEscoSkills') ||
              nonEmpty('schulabschluss');
        } catch (_) {}
      }
      final savedLang = prefs.getString('app_language');
      if (!mounted) return;
      setState(() {
        _cvCreated = created;
        _cvType = cvType;
        _userName = name;
        _userCity = city;
        _ausbildungCvCreated = ausbildungExists;
        if (savedLang != null && savedLang.isNotEmpty) _lang = savedLang;
      });
    } catch (_) {}
  }

  void _showSnack(String text, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text, style: const TextStyle(color: Colors.white)),
      backgroundColor: color ?? _pillNavy,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  // ── Navigation actions ─────────────────────────────────────────────────────

  // Routes through ChooseCvTypeScreen (Job CV / Ausbildung CV) instead of
  // straight into QuestionnaireScreen - the only entry point for CV
  // creation now.
  void _createNewCv() => Navigator.pushNamed(
        context,
        '/choose-cv-type',
        arguments: {'language': _lang, 'voiceMode': _voiceMode},
      );

  void _goAusbildung() => Navigator.pushNamed(
        context,
        '/ausbildung',
        arguments: {'language': _lang, 'voiceMode': _voiceMode},
      );

  void _goDeutsch() => Navigator.pushNamed(
        context,
        '/deutsch-courses',
        arguments: {'language': _lang, 'voiceMode': _voiceMode},
      );

  void _goJobFinder() => Navigator.pushNamed(
        context,
        '/jobfinder',
        arguments: {'language': _lang, 'voiceMode': _voiceMode},
      );

  Future<void> _viewCv() async {
    if (!_anyCvExists) {
      _showSnack(_noCvFoundText);
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final cvType = prefs.getString('cv_type') ?? '';
      if (cvType == 'uploaded') {
        final path = prefs.getString('uploaded_cv_path') ?? '';
        if (path.isEmpty) return;
        final exists = await File(path).exists();
        if (!exists) {
          _showSnack(_lang == 'ps'
              ? 'د CV فایل ونه موندل شو'
              : _lang == 'fa'
                  ? 'فایل CV پیدا نشد'
                  : 'CV file not found');
          return;
        }
        if (!await launchUrl(Uri.file(path), mode: LaunchMode.externalApplication)) {
          _showSnack(_lang == 'ps'
              ? 'CV پرانستل نشوه'
              : _lang == 'fa'
                  ? 'CV باز نشد'
                  : 'Could not open CV file');
        }
        return;
      }
      final profileJson = prefs.getString('saved_profile');
      if (profileJson == null || profileJson.isEmpty) {
        _showSnack(_noCvFoundText);
        return;
      }
      final map = jsonDecode(profileJson) as Map<String, dynamic>;
      final profile = UserProfile.fromMap(map);
      if (!mounted) return;

      final jobExists = _jobCvExists;
      final ausbildungExists = _ausbildungCvCreated;
      if (jobExists && ausbildungExists) {
        _showCvTypePicker(profile);
      } else if (ausbildungExists) {
        _openAusbildungCv(profile);
      } else if (jobExists) {
        Navigator.pushNamed(context, '/cv_preview', arguments: profile);
      } else {
        _showSnack(_noCvFoundText);
      }
    } catch (_) {}
  }

  void _openAusbildungCv(UserProfile profile) {
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

  // Shown when both a Job CV and an Ausbildung CV exist - lets the user pick
  // which one to open instead of always defaulting to the Job CV.
  void _showCvTypePicker(UserProfile profile) {
    const navy = Color(0xFF091733);
    const neonGreen = Color(0xFF39EA2B);

    Widget cvTypeCard({
      required BuildContext sheetCtx,
      required IconData icon,
      required String title,
      required VoidCallback onOpen,
    }) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF7FAFF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE4EAF5), width: 1.2),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration:
                  BoxDecoration(color: navy, borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: neonGreen, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(title,
                  style: const TextStyle(
                      color: navy, fontSize: 14, fontWeight: FontWeight.w700)),
            ),
            GestureDetector(
              onTap: () {
                Navigator.pop(sheetCtx);
                onOpen();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration:
                    BoxDecoration(color: navy, borderRadius: BorderRadius.circular(999)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.remove_red_eye_outlined,
                        color: neonGreen, size: 14),
                    const SizedBox(width: 4),
                    Text(_viewActionLabel,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                Navigator.pop(sheetCtx);
                onOpen();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                    color: neonGreen, borderRadius: BorderRadius.circular(999)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.download_rounded, color: navy, size: 14),
                    const SizedBox(width: 4),
                    Text(_downloadActionLabel,
                        style: const TextStyle(
                            color: navy, fontSize: 11, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

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
              Text(
                _chooseCvLabel,
                style: const TextStyle(
                    color: navy, fontSize: 15, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 14),
              cvTypeCard(
                sheetCtx: ctx,
                icon: Icons.work_outline_rounded,
                title: _jobCvLabel,
                onOpen: () =>
                    Navigator.pushNamed(context, '/cv_preview', arguments: profile),
              ),
              const SizedBox(height: 12),
              cvTypeCard(
                sheetCtx: ctx,
                icon: Icons.school_outlined,
                title: _ausbildungCvLabel,
                onOpen: () => _openAusbildungCv(profile),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _uploadCv() async {
    try {
      final result = await FilePicker.platform
          .pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
      if (result == null || result.files.isEmpty) return;
      final pickedPath = result.files.single.path ?? '';
      if (pickedPath.isEmpty) return;
      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => CvUploadInfoSheet(
          language: _lang,
          voiceMode: _voiceMode,
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
              _cvType = 'uploaded';
              _userName = name;
            });
            _showSnack(
              _lang == 'ps'
                  ? 'CV اپلوډ شوه'
                  : _lang == 'fa'
                      ? 'CV آپلود شد'
                      : 'CV uploaded successfully',
              color: const Color(0xFF39EA2B),
            );
          },
        ),
      );
    } catch (e) {
      debugPrint('Upload error: $e');
    }
  }

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
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD1D9E6),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Language / ژبه / زبان',
                style: TextStyle(color: _pillNavy, fontSize: 15, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 14),
              for (final pair in [
                ['ps', 'پښتو', 'Pashto'],
                ['fa', 'دری', 'Dari'],
                ['en', 'English', 'English'],
              ])
                GestureDetector(
                  onTap: () async {
                    setState(() => _lang = pair[0]);
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString('app_language', pair[0]);
                    if (mounted) context.read<LanguageProvider>().setLanguage(pair[0]);
                    if (ctx.mounted) Navigator.pop(ctx);
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
                        Text(pair[1],
                            style: TextStyle(
                              color: _pillNavy,
                              fontSize: 16,
                              fontWeight: _lang == pair[0] ? FontWeight.w800 : FontWeight.w600,
                            )),
                        const SizedBox(width: 8),
                        Text(pair[2],
                            style: const TextStyle(
                              color: _muted,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            )),
                        const Spacer(),
                        if (_lang == pair[0])
                          const Icon(Icons.check_circle_rounded, color: _green, size: 20),
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

  // ── Localised strings (kept consistent with IntroductionScreen) ────────────

  String get _welcomeBack {
    switch (_lang) {
      case 'ps':
        return 'ښه راغلاست،';
      case 'fa':
        return 'خوش آمدید،';
      default:
        return 'Welcome back,';
    }
  }

  String get _subtitleFallback {
    switch (_lang) {
      case 'ps':
        return 'د جرمني د دندو موندلو غوښتنلیک';
      case 'fa':
        return 'اپلیکیشن یافتن کار در آلمان';
      default:
        return 'Job Finder for Afghan Workers in Germany';
    }
  }

  String get _noCvFoundText {
    switch (_lang) {
      case 'ps':
        return 'ستاسی سییوی پیدا نشوه، لطفاً نوی سییوی جوړ کړی.';
      case 'fa':
        return ' سییوی یافت نشد. لطفاًسییوی نو بسازید.';
      default:
        return 'No CV found. Please create one first.';
    }
  }

  // Shown in the "which CV?" picker sheet when both a Job CV and an
  // Ausbildung CV exist.
  String get _chooseCvLabel {
    switch (_lang) {
      case 'ps':
        return 'کوم CV؟';
      case 'fa':
        return 'کدام CV؟';
      default:
        return 'Which CV?';
    }
  }

  String get _jobCvLabel {
    switch (_lang) {
      case 'ps':
        return 'د کار CV';
      case 'fa':
        return 'رزومه کاری';
      default:
        return 'Job CV';
    }
  }

  String get _ausbildungCvLabel {
    switch (_lang) {
      case 'ps':
        return 'د زده کړې CV';
      case 'fa':
        return 'رزومه کارآموزی';
      default:
        return 'Ausbildung CV';
    }
  }

  String get _viewActionLabel {
    switch (_lang) {
      case 'ps':
        return 'کتل';
      case 'fa':
        return 'مشاهده';
      default:
        return 'View';
    }
  }

  String get _downloadActionLabel {
    switch (_lang) {
      case 'ps':
        return 'ډاونلوډ';
      case 'fa':
        return 'دانلود';
      default:
        return 'Download';
    }
  }

  String get _findJobsLabel {
    switch (_lang) {
      case 'ps':
        return 'نژدي کارونه پیدا کړئ';
      case 'fa':
        return 'کارهای نزدیک را پیدا کنید';
      default:
        return 'Find Jobs Near Me';
    }
  }

  String get _viewCvLabel {
    switch (_lang) {
      case 'ps':
        return 'زما جوړه شوی CV وګورئ';
      case 'fa':
        return 'CV من را ببینید';
      default:
        return 'View / Download My CV';
    }
  }

  String get _newCvLabel {
    switch (_lang) {
      case 'ps':
        return 'نوی CV جوړ کړئ';
      case 'fa':
        return 'ایجاد CV جدید';
      default:
        return 'Create New CV';
    }
  }

  String get _uploadCvLabel {
    switch (_lang) {
      case 'ps':
        return 'خپله CV اپلوډ کړئ';
      case 'fa':
        return 'CV خود را اپلوډ کنید';
      default:
        return 'Upload Your own CV';
    }
  }

  String get _findAusbildungLabel {
    switch (_lang) {
      case 'ps':
        return 'د زده کړې کار وموندئ';
      case 'fa':
        return 'کارآموزی پیدا کنید';
      default:
        return 'Find Ausbildung';
    }
  }

  String get _learnGermanLabel {
    switch (_lang) {
      case 'ps':
        return 'آلمانی زده کړئ';
      case 'fa':
        return 'آلمانی یاد بگیرید';
      default:
        return 'Learn German';
    }
  }

  List<_HomeAction> get _actions => [
        _HomeAction(
          label: _newCvLabel,
          icon: Icons.add_rounded,
          bg: const Color(0xFFE3F5E7),
          tint: _green,
          onTap: _createNewCv,
        ),
        _HomeAction(
          label: _viewCvLabel,
          icon: Icons.description_outlined,
          bg: const Color(0xFFE3F5E7),
          tint: _green,
          onTap: _viewCv,
        ),
        _HomeAction(
          label: _uploadCvLabel,
          icon: Icons.upload_file_rounded,
          bg: const Color(0xFFE6EDFD),
          tint: const Color(0xFF3A6DF0),
          onTap: _uploadCv,
        ),
        _HomeAction(
          label: _findAusbildungLabel,
          icon: Icons.school_outlined,
          bg: const Color(0xFFE6EDFD),
          tint: const Color(0xFF3A6DF0),
          onTap: _goAusbildung,
        ),
        _HomeAction(
          label: _learnGermanLabel,
          icon: Icons.translate_rounded,
          bg: const Color(0xFFF3E6FA),
          tint: const Color(0xFFA355D1),
          onTap: _goDeutsch,
        ),
      ];

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: _isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: _bg,
        body: Stack(
          children: [
            const Positioned(
              top: -60,
              left: -40,
              child: _Blob(size: 260, color: Color(0x59A8E0A0)),
            ),
            const Positioned(
              top: 120,
              right: -60,
              child: _Blob(size: 220, color: Color(0x4DF0B4BE)),
            ),
            SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 16),
                    _buildProfileCvBar(),
                    const SizedBox(height: 14),
                    _buildSearchPill(),
                    const SizedBox(height: 18),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 14,
                      childAspectRatio: 1.15,
                      children: _actions.map((a) => _ActionTile(action: a, isRtl: _isRtl, lang: _lang)).toList(),
                    ),
                    const SizedBox(height: 22),
                    const Text(
                      'KarYab v1.0',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _footer, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        RichText(
          text: TextSpan(
            style: GoogleFonts.lora(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: _ink,
            ),
            children: const [
              TextSpan(text: 'Kar'),
              TextSpan(text: 'Yab', style: TextStyle(color: _green)),
            ],
          ),
        ),
        Row(
          children: [
            GestureDetector(
              onTap: _showLangPicker,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: _pillNavy,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _lang == 'ps' ? 'PS' : _lang == 'fa' ? 'FA' : 'EN',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 16),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () {
                TtsService().toggleSound();
                setState(() {});
              },
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 8, offset: Offset(0, 2))],
                ),
                child: Icon(
                  TtsService().soundEnabled ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                  color: _green,
                  size: 18,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildProfileCvBar() {
    return GestureDetector(
      onTap: _anyCvExists ? _viewCv : _createNewCv,
      child: _GlassCard(
        radius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: const BoxDecoration(color: Color(0xE5E3F5E7), shape: BoxShape.circle),
                child: const Icon(Icons.person, color: _green, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$_welcomeBack${_displayName.isNotEmpty ? ' $_displayName' : ''}!',
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.vazirmatn(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _ink,
                      ),
                    ),
                    Text(
                      _userCity.isNotEmpty ? '$_userCity, Deutschland' : _subtitleFallback,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.vazirmatn(fontSize: 11, color: _muted),
                    ),
                  ],
                ),
              ),
              if (_anyCvExists) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xE5EAF8EE),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _cvType == 'uploaded' ? Icons.upload_file_rounded : Icons.description,
                        size: 12,
                        color: const Color(0xFF2FA84F),
                      ),
                      const SizedBox(width: 5),
                      const Text(
                        'CV ✓',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF218A3B)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Icon(_isRtl ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
                  size: 18, color: _muted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchPill() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: GestureDetector(
          onTap: _goJobFinder,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xD90D1B2A),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0x1FFFFFFF)),
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => TtsService().speak(_findJobsLabel, _lang),
                  child: const Icon(Icons.volume_up_rounded, color: _green, size: 18),
                ),
                Expanded(
                  child: Text(
                    _findJobsLabel,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.vazirmatn(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(color: Color(0x1AFFFFFF), shape: BoxShape.circle),
                  child: const Icon(Icons.search_rounded, color: _green, size: 16),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  final double size;
  final Color color;
  const _Blob({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withOpacity(0)]),
        ),
      ),
    );
  }
}

/// Reusable frosted-glass container matching the design's blurred cards.
class _GlassCard extends StatelessWidget {
  final Widget child;
  final BorderRadius radius;
  final List<BoxShadow>? shadow;
  const _GlassCard({required this.child, required this.radius, this.shadow});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0x73FFFFFF),
            borderRadius: radius,
            border: Border.all(color: const Color(0x99FFFFFF), width: 1),
            boxShadow: shadow ??
                const [BoxShadow(color: Color(0x14142819), blurRadius: 24, offset: Offset(0, 8))],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final _HomeAction action;
  final bool isRtl;
  final String lang;
  const _ActionTile({required this.action, required this.isRtl, required this.lang});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: action.onTap,
      child: Stack(
        children: [
          _GlassCard(
            radius: BorderRadius.circular(24),
            shadow: [
              BoxShadow(
                color: const Color(0xFF2A5729).withOpacity(0.15),
                blurRadius: 12,
                offset: const Offset(4, 4),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: action.bg,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [BoxShadow(color: Color(0x14142819), blurRadius: 8, offset: Offset(0, 3))],
                    ),
                    child: Icon(action.icon, color: action.tint, size: 22),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    action.label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: GoogleFonts.vazirmatn(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF16211C),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isRtl)
            Positioned(
              top: 8,
              left: 8,
              child: GestureDetector(
                onTap: () => TtsService().speak(action.label, lang),
                child: Icon(Icons.volume_up_rounded, color: action.tint, size: 15),
              ),
            ),
        ],
      ),
    );
  }
}
