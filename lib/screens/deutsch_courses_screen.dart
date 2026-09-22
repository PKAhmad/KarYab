import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/language_provider.dart';
import '../services/tts_service.dart';
import '../utils/location_helpers.dart';
import 'in_app_browser_screen.dart';

class DeutschCoursesScreen extends StatefulWidget {
  final String language;
  final bool voiceMode;

  const DeutschCoursesScreen({
    super.key,
    required this.language,
    this.voiceMode = false,
  });

  @override
  State<DeutschCoursesScreen> createState() => _DeutschCoursesScreenState();
}

class _DeutschCoursesScreenState extends State<DeutschCoursesScreen> {
  static const Color _navy  = Color(0xFF091733);
  static const Color _green = Color(0xFF39EA2B);
  static const Color _muted = Color(0xFF65738A);

  String _lang = 'en';
  final _cityCtrl = TextEditingController();

  bool get _isRtl       => _lang == 'ps' || _lang == 'fa';
  bool get _showSpeaker => widget.voiceMode && _isRtl;

  void _onSoundChange() { if (mounted) setState(() {}); }

  @override
  void initState() {
    super.initState();
    _lang = widget.language;
    TtsService().addListener(_onSoundChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<LanguageProvider>().syncFromNav(
          widget.language,
          voiceMode: widget.voiceMode,
        );
      }
    });
    _loadCity();
  }

  Future<void> _loadCity() async {
    String? profileCity;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw   = prefs.getString('saved_profile');
      if (raw != null && raw.isNotEmpty) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        final city = (map['city'] as String?) ?? '';
        if (city.isNotEmpty) profileCity = city;
      }
    } catch (_) {}

    String? lastKnownCity;
    try {
      lastKnownCity = await loadLastKnownCity();
    } catch (_) {}

    if (!mounted) return;

    final city = profileCity ?? lastKnownCity ?? '';
    if (city.isNotEmpty) {
      _cityCtrl.text = city;
    }
  }

  @override
  void dispose() {
    TtsService().removeListener(_onSoundChange);
    _cityCtrl.dispose();
    super.dispose();
  }

  void _openBAMF() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InAppBrowserScreen(
          url: 'https://bamf-navi.bamf.de/en/Themen/Integrationskurse/',
          title: 'BAMF',
          language: _lang,
        ),
      ),
    );
  }

  void _openVHS() {
    final city = _cityCtrl.text.trim();
    if (city.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          _lang == 'ps'
              ? 'لطفاً د ښار نوم ولیکئ'
              : _lang == 'fa'
                  ? 'لطفاً نام شهر را وارد کنید'
                  : 'Please enter your city name first',
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: _navy,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InAppBrowserScreen(
          url: _buildVhsUrl(),
          title: 'VHS',
          language: _lang,
        ),
      ),
    );
  }

  String _buildVhsUrl() {
    return 'https://www.volkshochschule.de/kursfinder'
        '?sortierung=relevanz'
        '&text=Deutsch+IntegrationsKurs'
        '&kursart=vorOrtAngebot%2ConlineAngebot%2ChybridesAngebot'
        '&kategorien=';
  }

  // ── Localised strings ─────────────────────────────────────────────────────

  String get _titleLabel {
    switch (_lang) {
      case 'ps': return 'د آلمان ژبې کورسونه';
      case 'fa': return 'دوره‌های زبان آلمانی';
      default:   return 'German Courses';
    }
  }

  String get _infoText {
    switch (_lang) {
      case 'ps':
        return 'وړیا او ارزانه آلمانی کورسونه د BAMF ادغام کورسونو '
            'او سیمه‌ییز VHS مرکزونو له لارې شتون لري.';
      case 'fa':
        return 'دوره‌های رایگان و کم‌هزینه آلمانی از طریق دوره‌های '
            'ادغام BAMF و مراکز محلی VHS در دسترس است.';
      default:
        return 'Free and low-cost German courses are available through '
            'BAMF integration courses and local Volkshochschule (VHS) centers.';
    }
  }

  String get _cityHint {
    switch (_lang) {
      case 'ps': return 'خپل ښار ولیکئ (د VHS لپاره)';
      case 'fa': return 'شهر خود را بنویسید (برای VHS)';
      default:   return 'Your city (for VHS search)';
    }
  }

  String get _bamfNoticeText {
    switch (_lang) {
      case 'ps':
        return 'تاسو به اړتیا ولرئ چې خپل پوستي کوډ د BAMF ویب پاڼې کې ولیکئ';
      case 'fa':
        return 'شما باید کد پستی خود را در وب‌سایت BAMF وارد کنید';
      default:
        return "You'll need to enter your postal code on the BAMF website";
    }
  }

  String get _vhsNoticeText {
    switch (_lang) {
      case 'ps':
        return 'تاسو به اړتیا ولرئ چې خپل ښار د VHS ویب پاڼې کې ولیکئ';
      case 'fa':
        return 'شما باید شهر خود را در وب‌سایت VHS وارد کنید';
      default:
        return "You'll need to enter your city on the VHS website";
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    _lang = context.watch<LanguageProvider>().language;

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
                        _buildInfoCard(),
                        const SizedBox(height: 16),
                        _buildCityField(),
                        const SizedBox(height: 16),
                        _buildOptionCard(
                          icon: Icons.school_rounded,
                          iconBgColor: const Color(0xFFEAFBE9),
                          iconColor: _green,
                          title: _lang == 'ps'
                              ? 'د BAMF ادغام کورس'
                              : _lang == 'fa'
                                  ? 'دوره ادغام BAMF'
                                  : 'BAMF Integration Course',
                          desc: _lang == 'ps'
                              ? 'رسمي آلماني + ادغام کورس، ډیری وخت وړیا'
                              : _lang == 'fa'
                                  ? 'دوره رسمی آلمانی + ادغام، اغلب رایگان'
                                  : 'Official German + integration course, often free depending on your status',
                          ttsTitle: _lang == 'ps'
                              ? 'د BAMF ادغام کورس'
                              : 'دوره ادغام BAMF',
                          ttsDesc: _lang == 'ps'
                              ? 'رسمي آلماني او ادغام کورس'
                              : 'دوره رسمی آلمانی',
                          onTap: _openBAMF,
                        ),
                        _buildBamfNotice(),
                        const SizedBox(height: 12),
                        _buildOptionCard(
                          icon: Icons.menu_book_rounded,
                          iconBgColor: const Color(0xFFEBF3FF),
                          iconColor: const Color(0xFF2D6BE4),
                          title: _lang == 'ps'
                              ? 'نږدې VHS کورسونه ومومئ'
                              : _lang == 'fa'
                                  ? 'دوره‌های VHS نزدیک خود را پیدا کنید'
                                  : 'Find VHS Courses Near You',
                          desc: _lang == 'ps'
                              ? 'د خپل ښار له مخې آلماني کورسونه ومومئ'
                              : _lang == 'fa'
                                  ? 'دوره‌های زبان آلمانی را بر اساس شهر جستجو کنید'
                                  : 'Search German courses by city',
                          ttsTitle: _lang == 'ps'
                              ? 'نږدې VHS کورسونه ومومئ'
                              : 'دوره‌های VHS نزدیک خود را پیدا کنید',
                          ttsDesc: _lang == 'ps'
                              ? 'د خپل ښار له مخې آلماني کورسونه ومومئ'
                              : 'دوره‌های زبان آلمانی را جستجو کنید',
                          onTap: _openVHS,
                        ),
                        _buildVhsNotice(),
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

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
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

  // ── Info card ─────────────────────────────────────────────────────────────

  Widget _buildInfoCard() {
    return _GlassSurface(
      borderRadius: 20,
      padding: const EdgeInsets.all(16),
      child: Row(
        textDirection: _isRtl ? TextDirection.rtl : TextDirection.ltr,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFEAFBE9),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.info_outline_rounded, color: _green, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _infoText,
              textDirection: _isRtl ? TextDirection.rtl : TextDirection.ltr,
              style: const TextStyle(
                color: _navy,
                fontSize: 13,
                height: 1.6,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── City text field ───────────────────────────────────────────────────────

  Widget _buildCityField() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.85),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.9), width: 1.2),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05), blurRadius: 8),
        ],
      ),
      child: Row(
        textDirection: _isRtl ? TextDirection.rtl : TextDirection.ltr,
        children: [
          const Icon(Icons.location_on_rounded, color: _green, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _cityCtrl,
              textDirection: _isRtl ? TextDirection.rtl : TextDirection.ltr,
              style: const TextStyle(color: _navy, fontSize: 14),
              decoration: InputDecoration(
                hintText: _cityHint,
                hintStyle: const TextStyle(color: _muted, fontSize: 14),
                border: InputBorder.none,
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Option card ───────────────────────────────────────────────────────────

  Widget _buildOptionCard({
    required IconData icon,
    required Color iconBgColor,
    required Color iconColor,
    required String title,
    required String desc,
    required String ttsTitle,
    required String ttsDesc,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.85),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white, width: 1.2),
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
        child: Row(
          textDirection: _isRtl ? TextDirection.rtl : TextDirection.ltr,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconBgColor,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: _isRtl
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    textDirection: _isRtl ? TextDirection.rtl : TextDirection.ltr,
                    style: const TextStyle(
                      color: _navy,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    desc,
                    textDirection: _isRtl ? TextDirection.rtl : TextDirection.ltr,
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_showSpeaker) ...[
                  GestureDetector(
                    onTap: () => TtsService().speak(
                      '$ttsTitle. $ttsDesc',
                      _lang,
                    ),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: const BoxDecoration(
                        color: Color(0xFFEAFBE9),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.volume_up_rounded,
                          color: _green, size: 16),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                const Icon(Icons.chevron_right_rounded,
                    color: _muted, size: 20),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── BAMF postal-code notice ────────────────────────────────────────────────

  Widget _buildBamfNotice() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
      child: Row(
        textDirection: _isRtl ? TextDirection.rtl : TextDirection.ltr,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              _bamfNoticeText,
              textDirection: _isRtl ? TextDirection.rtl : TextDirection.ltr,
              style: const TextStyle(
                color: _muted,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
          if (_showSpeaker) ...[
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () => TtsService().speak(_bamfNoticeText, _lang),
              child: Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  color: Color(0xFFEAFBE9),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.volume_up_rounded,
                    color: _green, size: 14),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── VHS city notice ────────────────────────────────────────────────────────

  Widget _buildVhsNotice() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
      child: Row(
        textDirection: _isRtl ? TextDirection.rtl : TextDirection.ltr,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              _vhsNoticeText,
              textDirection: _isRtl ? TextDirection.rtl : TextDirection.ltr,
              style: const TextStyle(
                color: _muted,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
          if (_showSpeaker) ...[
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () => TtsService().speak(_vhsNoticeText, _lang),
              child: Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  color: Color(0xFFEAFBE9),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.volume_up_rounded,
                    color: _green, size: 14),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Nav button ────────────────────────────────────────────────────────────────

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
              colors: [Color(0xFFF9FBFF), Color(0xFFEFF6FF), Color(0xFFF7FFF2)],
            ),
          ),
          child: SizedBox.expand(),
        ),
        Positioned(top: 70,    left: -42,  child: _Orb(size: 170, color: Color(0x6639EA2B))),
        Positioned(top: 135,   right: -65, child: _Orb(size: 160, color: Color(0x44B086FF))),
        Positioned(bottom: 80, left: -50,  child: _Orb(size: 200, color: Color(0x3339EA2B))),
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
            border:
                Border.all(color: Colors.white.withOpacity(0.85), width: 1.2),
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
