import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/language_provider.dart';
import '../services/analytics_service.dart';
import '../services/tts_service.dart';

class EducationScreen extends StatefulWidget {
  final String language;
  const EducationScreen({super.key, required this.language});

  @override
  State<EducationScreen> createState() => _EducationScreenState();
}

class _EducationScreenState extends State<EducationScreen> {
  static const Color navy  = Color(0xFF091733);
  static const Color green = Color(0xFF39EA2B);

  static bool _hasAutoPlayed = false;

  String? _selectedCard; // 'yes' | 'no'
  String  _lang = 'en';

  void _onSoundChange() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    AnalyticsService().logScreen('education');
    TtsService().addListener(_onSoundChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<LanguageProvider>().syncFromNav(widget.language);
    });

    if (!_hasAutoPlayed &&
        TtsService().soundEnabled &&
        (widget.language == 'ps' || widget.language == 'fa')) {
      _hasAutoPlayed = true;
      final text = widget.language == 'ps'
          ? 'ایا تاسو لوستل او لیکل کولی شئ؟'
          : 'آیا می‌توانید بخوانید و بنویسید؟';
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) TtsService().speak(text, widget.language);
      });
    }
  }

  @override
  void dispose() {
    TtsService().removeListener(_onSoundChange);
    _hasAutoPlayed = false;
    TtsService().stop();
    super.dispose();
  }

  bool get _isRtl       => _lang == 'ps' || _lang == 'fa';
  bool get _showSpeaker => _lang == 'ps' || _lang == 'fa';

  String get _question {
    switch (_lang) {
      case 'ps': return 'ایا تاسو لوستل او لیکل کولی شئ؟';
      case 'fa': return 'آیا می‌توانید بخوانید و بنویسید؟';
      default:   return 'Can you read and write?';
    }
  }

  String get _subtitle {
    switch (_lang) {
      case 'ps': return 'دا مونږ سره مرسته کوي چې ستاسو لپاره مخکی پروسه اسانه کړو';
      case 'fa': return 'این به ما کمک می‌کند بهترین روش کمک را پیدا کنیم';
      default:   return 'This helps us find the best way to assist you';
    }
  }

  String get _continueLabel {
    switch (_lang) {
      case 'ps': return 'مخکی لاړ شی';
      case 'fa': return 'ادامه';
      default:   return 'Continue';
    }
  }

  String get _hintText {
    switch (_lang) {
      case 'ps': return 'ستاسو ځواب مونږ سره ستاسی د تجربې ښه کولو کې مرسته کوي';
      case 'fa': return 'پاسخ شما به ما کمک می‌کند تجربه را شخصی‌سازی کنیم';
      default:   return 'Your answer helps us personalize your experience';
    }
  }

  Future<void> _onContinue() async {
    if (_selectedCard == null) return;
    final voiceMode = _selectedCard == 'no';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('voice_mode', voiceMode);
    await prefs.setString('app_language', _lang);
    TtsService().setSoundEnabled(voiceMode);
    if (!mounted) return;
    context.read<LanguageProvider>().setVoiceMode(voiceMode);

    // Permissions onboarding only ever shows once per install — if it's
    // already been shown (e.g. from a previous English run, or a previous
    // Pashto/Dari run), skip straight to Introduction as before.
    final permissionsShown =
        prefs.getBool('permissions_onboarding_shown') ?? false;
    if (permissionsShown) {
      Navigator.pushNamed(
        context,
        '/introduction',
        arguments: {
          'language': _lang,
          'voiceMode': voiceMode,
        },
      );
      return;
    }

    Navigator.pushNamed(
      context,
      '/permissions',
      arguments: {
        'language': _lang,
        'voiceMode': voiceMode,
      },
    );
  }

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
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Fixed top row ──────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _TopButton(
                        icon: Icons.arrow_back_ios_new_rounded,
                        onTap: () {
                          TtsService().stop();
                          Navigator.pop(context);
                        },
                      ),
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
                ),

                // ── Scrollable content ─────────────────────────────────────
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 430),
                        child: Column(
                          children: [
                            // ── Hero question card ──────────────────────────
                            _GlassSurface(
                              borderRadius: 24,
                              padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
                              shadowOpacity: 0.11,
                              child: Column(
                                children: [
                                  Container(
                                    width: 72,
                                    height: 72,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFEAFBE9),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.menu_book_rounded,
                                      color: green,
                                      size: 52,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Directionality(
                                    textDirection: _isRtl
                                        ? TextDirection.rtl
                                        : TextDirection.ltr,
                                    child: Text(
                                      _question,
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
                                      _subtitle,
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

                            const SizedBox(height: 18),

                            // ── YES / NO option cards ───────────────────────
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: _OptionCard(
                                    isYes: true,
                                    lang: _lang,
                                    selected: _selectedCard == 'yes',
                                    onTap: () {
                                      setState(() => _selectedCard = 'yes');
                                      AnalyticsService().logEducationLevel(true);
                                    },
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _OptionCard(
                                    isYes: false,
                                    lang: _lang,
                                    selected: _selectedCard == 'no',
                                    onTap: () {
                                      setState(() => _selectedCard = 'no');
                                      AnalyticsService().logEducationLevel(false);
                                      if (_lang == 'ps') {
                                        TtsService().speak(
                                          'زه لوستل او لیکل نشم کولی،یعنی زه تعلیم نه لرم',
                                          'ps',
                                        );
                                      } else if (_lang == 'fa') {
                                        TtsService().speak(
                                          'نه، نمی‌توانم بخوانم یا بنویسم',
                                          'fa',
                                        );
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 20),

                            // ── Continue button ─────────────────────────────
                            _ContinueButton(
                              label: _continueLabel,
                              enabled: _selectedCard != null,
                              onTap: _onContinue,
                            ),

                            const SizedBox(height: 12),

                            // ── Hint text ───────────────────────────────────
                            Directionality(
                              textDirection:
                                  _isRtl ? TextDirection.rtl : TextDirection.ltr,
                              child: Text(
                                _hintText,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFF65738A),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
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
              child: Icon(
                icon,
                color: active ? green : navy,
                size: 20,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Option card (YES / NO) ────────────────────────────────────────────────────

class _OptionCard extends StatelessWidget {
  static const Color navy  = Color(0xFF091733);
  static const Color green = Color(0xFF39EA2B);
  static const Color red   = Color(0xFFFF6B6B);

  final bool isYes;
  final String lang;
  final bool selected;
  final VoidCallback onTap;

  const _OptionCard({
    required this.isYes,
    required this.lang,
    required this.selected,
    required this.onTap,
  });

  bool get _isRtl => lang == 'ps' || lang == 'fa';

  String get _title {
    if (isYes) {
      switch (lang) {
        case 'ps': return 'هو، زه لوستل او لیکل کولی شم';
        case 'fa': return 'بله، می‌توانم بخوانم و بنویسم';
        default:   return 'Yes, I can read & write';
      }
    } else {
      switch (lang) {
        case 'ps': return  ' نه، زه لوستل او لیکل نشم کولی';
        case 'fa': return 'نه، نمی‌توانم بخوانم یا بنویسم';
        default:   return 'No, I cannot read or write';
      }
    }
  }

  String get _cardSubtitle {
    if (isYes) {
      switch (lang) {
        case 'ps': return 'تعلیم بافته';
        case 'fa': return 'تحصیلاتی دارم';
        default:   return 'I have some education';
      }
    } else {
      switch (lang) {
        case 'ps': return 'زه د غږ کومک یا لارښوونې ته اړتیا لرم';
        case 'fa': return 'به راهنمایی صوتی نیاز دارم';
        default:   return 'I need voice guidance';
      }
    }
  }

  Color get _accentColor => isYes ? green : red;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: selected
            ? (isYes
                ? const Color(0xF0F6FFF5)
                : const Color(0xFFFFF5F5))
            : Colors.white.withOpacity(0.62),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: selected ? _accentColor : Colors.white.withOpacity(0.80),
          width: selected ? 2.0 : 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: selected
                ? _accentColor.withOpacity(0.15)
                : Colors.black.withOpacity(0.06),
            blurRadius: selected ? 22 : 14,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Green checkmark badge top-right (YES selected only)
              if (selected && isYes)
                const Positioned(
                  top: -8,
                  right: -4,
                  child: CircleAvatar(
                    radius: 13,
                    backgroundColor: green,
                    child: Icon(Icons.check_rounded,
                        color: Colors.white, size: 17),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 18, 12, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Icon circle
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: selected
                            ? (isYes
                                ? const Color(0xFFE9FFE6)
                                : const Color(0xFFFFEBEB))
                            : const Color(0xFFF7F9FC),
                      ),
                      child: Icon(
                        isYes
                            ? Icons.check_circle_outline_rounded
                            : Icons.cancel_outlined,
                        color: _accentColor,
                        size: 30,
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Title
                    Directionality(
                      textDirection:
                          _isRtl ? TextDirection.rtl : TextDirection.ltr,
                      child: Text(
                        _title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: navy,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          height: 1.3,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 5),
                    // Subtitle
                    Directionality(
                      textDirection:
                          _isRtl ? TextDirection.rtl : TextDirection.ltr,
                      child: Text(
                        _cardSubtitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF65738A),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          height: 1.3,
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
    );
  }
}

// ── Continue button ───────────────────────────────────────────────────────────

class _ContinueButton extends StatelessWidget {
  static const Color green = Color(0xFF39EA2B);

  final String label;
  final bool enabled;
  final VoidCallback onTap;

  const _ContinueButton({
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
        height: 60,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          gradient: const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Color(0xFF081532), Color(0xFF07112B)],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF07112B).withOpacity(0.30),
              blurRadius: 22,
              offset: const Offset(0, 13),
            ),
            BoxShadow(
              color: green.withOpacity(0.22),
              blurRadius: 28,
              offset: const Offset(18, 16),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(30),
            onTap: enabled ? onTap : null,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(width: 28),
                const Icon(Icons.arrow_forward_rounded, color: green, size: 28),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Background glow (matches welcome screen exactly) ─────────────────────────

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

// ── Glass surface (matches welcome screen exactly) ────────────────────────────

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
            border:
                Border.all(color: Colors.white.withOpacity(0.85), width: 1.2),
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
