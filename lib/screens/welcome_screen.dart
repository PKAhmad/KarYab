import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/analytics_service.dart';
import '../services/tts_service.dart';
import '../utils/navigation_helpers.dart';

enum AppLanguage { pashto, dari, english }

class LanguageOption {
  final AppLanguage id;
  final String title;
  final String? nativeTitle;
  final bool hasVoice;

  const LanguageOption({
    required this.id,
    required this.title,
    this.nativeTitle,
    required this.hasVoice,
  });
}

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  static const Color navy = Color(0xFF091733);
  static const Color green = Color(0xFF39EA2B);

  AppLanguage selectedLanguage = AppLanguage.pashto;

  static const List<LanguageOption> languages = [
    LanguageOption(
      id: AppLanguage.pashto,
      title: 'Pashto',
      nativeTitle: 'پښتو',
      hasVoice: true,
    ),
    LanguageOption(
      id: AppLanguage.dari,
      title: 'Dari',
      nativeTitle: 'دری',
      hasVoice: true,
    ),
    LanguageOption(
      id: AppLanguage.english,
      title: 'English',
      nativeTitle: null,
      hasVoice: false,
    ),
  ];

  @override
  void initState() {
    super.initState();
    AnalyticsService().logScreen('welcome');
  }

  Future<void> _onContinue() async {
    String langCode;
    switch (selectedLanguage) {
      case AppLanguage.pashto:
        langCode = 'ps';
        break;
      case AppLanguage.dari:
        langCode = 'fa';
        break;
      case AppLanguage.english:
        langCode = 'en';
        break;
    }
    AnalyticsService().logLanguageSelected(langCode);

    // Pashto/Dari always go to Education first; Education itself decides
    // whether to route through Permissions (first run only) or straight to
    // Introduction, since voiceMode isn't known until the user answers
    // there.
    if (langCode != 'en') {
      Navigator.pushNamed(
        context,
        '/education',
        arguments: {'language': langCode},
      );
      return;
    }

    // English skips Education entirely and is treated as "educated" by
    // default, so mute voice here too — same default the 'yes' branch in
    // education_screen.dart sets for Pashto/Dari. Permissions (shown once
    // per install) still sits right after Welcome.
    TtsService().setSoundEnabled(false);
    final prefs = await SharedPreferences.getInstance();
    final permissionsShown =
        prefs.getBool('permissions_onboarding_shown') ?? false;
    if (!mounted) return;

    if (permissionsShown) {
      await proceedAfterLanguageSelection(context, langCode);
      return;
    }

    Navigator.pushNamed(
      context,
      '/permissions',
      arguments: {'language': langCode, 'voiceMode': false},
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFF),
      body: Stack(
        children: [
          const _BackgroundGlow(),
          SafeArea(
            child: Center(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 430),
                      child: Column(
                        children: [
                          const SizedBox(height: 8),
                          const _HeroGlassCard(),
                          const SizedBox(height: 14),
                          const Text(
                            'Choose your language',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: navy,
                              fontSize: 22,
                              height: 1.1,
                              letterSpacing: -0.4,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'We support Pashto, Dari & English',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFF65738A),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              for (int i = 0; i < languages.length; i++) ...[
                                Expanded(
                                  child: _LanguageCard(
                                    option: languages[i],
                                    selected: selectedLanguage == languages[i].id,
                                    onTap: () => setState(() => selectedLanguage = languages[i].id),
                                  ),
                                ),
                                if (i != languages.length - 1) const SizedBox(width: 10),
                              ],
                            ],
                          ),
                          const SizedBox(height: 10),
                          const _InfoBox(),
                          const SizedBox(height: 10),
                          _ContinueButton(onTap: _onContinue),
                          const SizedBox(height: 8),
                          const _PageDots(),
                          const SizedBox(height: 12),
                          RichText(
                            textAlign: TextAlign.center,
                            text: const TextSpan(
                              style: TextStyle(
                                color: navy,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                letterSpacing: -0.1,
                              ),
                              children: [
                                TextSpan(text: 'Your Job. Your CV. '),
                                TextSpan(
                                  text: 'Your Future.',
                                  style: TextStyle(color: green),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
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
              colors: [
                Color(0xFFF9FBFF),
                Color(0xFFEFF6FF),
                Color(0xFFF7FFF2),
              ],
            ),
          ),
          child: SizedBox.expand(),
        ),
        Positioned(top: 70, left: -42, child: _Orb(size: 170, color: Color(0x6639EA2B))),
        Positioned(top: 135, right: -65, child: _Orb(size: 170, color: Color(0x44FFB86B))),
        Positioned(bottom: 95, left: -60, child: _Orb(size: 210, color: Color(0x3339EA2B))),
        Positioned(bottom: -30, right: 14, child: _Orb(size: 145, color: Color(0x5539EA2B))),
        Positioned(top: 20, left: 30, child: _Orb(size: 170, color: Color(0x30FF8FA3))),
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
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}


class _HeroGlassCard extends StatelessWidget {
  static const Color navy = Color(0xFF091733);

  const _HeroGlassCard();

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        _GlassSurface(
          borderRadius: 36,
          padding: const EdgeInsets.fromLTRB(14, 50, 14, 14),
          shadowOpacity: 0.13,
          child: Column(
            children: const [
              _KarYabWordMark(),
              SizedBox(height: 5),
              Directionality(
                textDirection: TextDirection.rtl,
                child: Text(
                  'کاریاب',
                  style: TextStyle(
                    color: navy,
                    fontSize: 16,
                    height: 1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              SizedBox(height: 8),
              _HeroDivider(),
              SizedBox(height: 8),
              Text(
                'Find jobs and build your German CV',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: navy,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(height: 12),
              _HeroFeatures(),
            ],
          ),
        ),
        const Positioned(
          top: -22,
          child: _LogoTile(),
        ),
      ],
    );
  }
}

class _LogoTile extends StatelessWidget {
  static const Color navy = Color(0xFF091733);
  static const Color green = Color(0xFF39EA2B);

  const _LogoTile();

  @override
  Widget build(BuildContext context) {
    return _GlassSurface(
      width: 70,
      height: 66,
      borderRadius: 22,
      padding: EdgeInsets.zero,
      shadowOpacity: 0.10,
      child: Stack(
        alignment: Alignment.center,
        children: const [
          Positioned(
            left: 17,
            top: 16,
            child: Text(
              'K',
              style: TextStyle(
                color: navy,
                fontSize: 34,
                height: 1,
                fontWeight: FontWeight.w900,
                letterSpacing: -2,
              ),
            ),
          ),
          Positioned(
            right: 13,
            bottom: 16,
            child: Icon(Icons.check_rounded, color: green, size: 26),
          ),
          Positioned(
            right: 10,
            bottom: 13,
            child: Text(
              '.',
              style: TextStyle(
                color: green,
                fontSize: 26,
                height: 0.7,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _KarYabWordMark extends StatelessWidget {
  static const Color navy = Color(0xFF091733);
  static const Color green = Color(0xFF39EA2B);

  const _KarYabWordMark();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          'Kar',
          style: TextStyle(
            color: navy,
            fontSize: 24,
            height: 1,
            fontWeight: FontWeight.w900,
            letterSpacing: -1,
          ),
        ),
        Text(
          'Yab',
          style: TextStyle(
            color: green,
            fontSize: 24,
            height: 1,
            fontWeight: FontWeight.w900,
            letterSpacing: -1,
          ),
        ),
      ],
    );
  }
}

class _HeroDivider extends StatelessWidget {
  const _HeroDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(width: 60, height: 1, color: const Color(0xFFDDE3EA)),
        const SizedBox(width: 14),
        Container(
          width: 6,
          height: 6,
          decoration: const BoxDecoration(
            color: Color(0xFF39EA2B),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 14),
        Container(width: 60, height: 1, color: const Color(0xFFDDE3EA)),
      ],
    );
  }
}

class _HeroFeatures extends StatelessWidget {
  const _HeroFeatures();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: const [
        _HeroFeature(icon: Icons.work_rounded, label: 'Job Finder'),
        _HeroFeature(icon: Icons.article_rounded, label: 'CV Generator'),
        _HeroFeature(icon: Icons.volume_up_rounded, label: 'Voice Support'),
      ],
    );
  }
}

class _HeroFeature extends StatelessWidget {
  static const Color navy = Color(0xFF091733);

  final IconData icon;
  final String label;

  const _HeroFeature({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _GlassSurface(
          width: 36,
          height: 36,
          borderRadius: 12,
          padding: EdgeInsets.zero,
          shadowOpacity: 0.08,
          child: Icon(icon, color: const Color(0xFF4B5B6E), size: 16),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          style: const TextStyle(
            color: navy,
            fontSize: 9,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _LanguageCard extends StatelessWidget {
  static const Color navy = Color(0xFF091733);
  static const Color green = Color(0xFF39EA2B);

  final LanguageOption option;
  final bool selected;
  final VoidCallback onTap;

  const _LanguageCard({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      height: 116,
      decoration: BoxDecoration(
        color: selected ? const Color(0xF0F6FFF5) : Colors.white.withOpacity(0.62),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(
          color: selected ? green : Colors.white.withOpacity(0.80),
          width: selected ? 1.8 : 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: selected ? green.withOpacity(0.17) : Colors.black.withOpacity(0.06),
            blurRadius: selected ? 24 : 16,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(25),
          onTap: onTap,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              if (selected)
                const Positioned(
                  top: -8,
                  right: -4,
                  child: CircleAvatar(
                    radius: 17,
                    backgroundColor: green,
                    child: Icon(Icons.check_rounded, color: Colors.white, size: 23),
                  ),
                ),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected ? const Color(0xFFE9FFE6) : const Color(0xFFF7F9FC),
                      boxShadow: [
                        BoxShadow(
                          color: selected ? green.withOpacity(0.22) : Colors.black.withOpacity(0.05),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: option.hasVoice
                        ? Icon(
                            Icons.volume_up_rounded,
                            color: selected ? green : const Color(0xFF0E7A20),
                            size: 22,
                          )
                        : const Text(
                            'A',
                            style: TextStyle(
                              color: navy,
                              fontSize: 24,
                              height: 1,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    option.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: navy,
                      fontSize: 13,
                      height: 1,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  if (option.nativeTitle != null) ...[
                    const SizedBox(height: 3),
                    Directionality(
                      textDirection: TextDirection.rtl,
                      child: Text(
                        option.nativeTitle!,
                        style: const TextStyle(
                          color: Color(0xFF40516A),
                          fontSize: 11,
                          height: 1,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                  if (option.hasVoice) ...[
                    const SizedBox(height: 6),
                    const _VoiceBadge(),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VoiceBadge extends StatelessWidget {
  static const Color green = Color(0xFF169C1F);

  const _VoiceBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFEFFFF0),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.graphic_eq_rounded, color: green, size: 13),
          SizedBox(width: 4),
          Text(
            'Voice',
            style: TextStyle(
              color: green,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  static const Color navy = Color(0xFF091733);

  const _InfoBox();

  @override
  Widget build(BuildContext context) {
    return _GlassSurface(
      borderRadius: 20,
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      shadowOpacity: 0.06,
      child: Row(
        children: const [
          CircleAvatar(
            radius: 18,
            backgroundColor: Color(0xFFEAFBE9),
            child: Icon(Icons.groups_rounded, color: Color(0xFF147C20), size: 20),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Find jobs & build a German CV — fast, free, and in your language.',
              style: TextStyle(
                color: navy,
                fontSize: 11,
                height: 1.34,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GermanyPin extends StatelessWidget {
  static const Color green = Color(0xFF39EA2B);

  const _GermanyPin();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 46,
      height: 56,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.map_rounded, color: const Color(0xFFB9C2CE), size: 47),
          Positioned(
            top: 15,
            right: 6,
            child: Container(
              width: 23,
              height: 23,
              decoration: const BoxDecoration(
                color: Color(0xFFB9F5A9),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.location_on_rounded, color: green, size: 19),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContinueButton extends StatelessWidget {
  static const Color green = Color(0xFF39EA2B);

  final VoidCallback onTap;

  const _ContinueButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 68,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(34),
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
          borderRadius: BorderRadius.circular(34),
          onTap: onTap,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Text(
                'Continue',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              SizedBox(width: 34),
              Icon(Icons.arrow_forward_rounded, color: green, size: 33),
            ],
          ),
        ),
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: const BoxDecoration(color: Color(0xFF39EA2B), shape: BoxShape.circle),
        ),
        const SizedBox(width: 11),
        Container(
          width: 18,
          height: 10,
          decoration: BoxDecoration(
            color: const Color(0xFFD7DFE8),
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        const SizedBox(width: 11),
        Container(
          width: 10,
          height: 10,
          decoration: const BoxDecoration(color: Color(0xFFD7DFE8), shape: BoxShape.circle),
        ),
      ],
    );
  }
}

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
            border: Border.all(color: Colors.white.withOpacity(0.85), width: 1.2),
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
