import 'dart:ui';
import 'package:flutter/material.dart';

void main() {
  runApp(const KarYabWelcomeApp());
}

class KarYabWelcomeApp extends StatelessWidget {
  const KarYabWelcomeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: KarYabWelcomeScreen(),
    );
  }
}

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

class KarYabWelcomeScreen extends StatefulWidget {
  final ValueChanged<AppLanguage>? onContinue;

  /// Optional: put the attached background image in your project and pass its path,
  /// for example: 'assets/images/karyab_welcome_bg.png'.
  /// If null, the screen draws a matching soft background using gradients and orbs.
  final String? backgroundImageAsset;

  const KarYabWelcomeScreen({
    super.key,
    this.onContinue,
    this.backgroundImageAsset,
  });

  @override
  State<KarYabWelcomeScreen> createState() => _KarYabWelcomeScreenState();
}

class _KarYabWelcomeScreenState extends State<KarYabWelcomeScreen> {
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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBFCFF),
      body: Stack(
        children: [
          _BackgroundGlow(imageAsset: widget.backgroundImageAsset),
          SafeArea(
            child: Center(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxHeight < 720;

                  return SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      18,
                      compact ? 10 : 18,
                      18,
                      compact ? 12 : 22,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 430),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                '9:41',
                                style: TextStyle(
                                  color: navy,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Row(
                                children: const [
                                  Icon(Icons.signal_cellular_alt_rounded, color: navy, size: 17),
                                  SizedBox(width: 6),
                                  Icon(Icons.wifi_rounded, color: navy, size: 18),
                                  SizedBox(width: 6),
                                  Icon(Icons.battery_full_rounded, color: navy, size: 22),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 22),
                          Align(
                            alignment: Alignment.centerRight,
                            child: _HelpButton(onTap: () {}),
                          ),
                          SizedBox(height: compact ? 16 : 28),
                          const _HeroGlassCard(),
                          SizedBox(height: compact ? 18 : 26),
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
                          const SizedBox(height: 7),
                          const Text(
                            'We support Pashto, Dari & English',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFF65738A),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 20),
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
                          const SizedBox(height: 18),
                          const _InfoBox(),
                          const SizedBox(height: 18),
                          _ContinueButton(
                            onTap: () => widget.onContinue?.call(selectedLanguage),
                          ),
                          const SizedBox(height: 18),
                          const _PageDots(),
                          const SizedBox(height: 12),
                          RichText(
                            textAlign: TextAlign.center,
                            text: const TextSpan(
                              style: TextStyle(
                                color: navy,
                                fontSize: 14,
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
  final String? imageAsset;

  const _BackgroundGlow({this.imageAsset});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (imageAsset != null)
          Positioned.fill(
            child: Image.asset(
              imageAsset!,
              fit: BoxFit.cover,
              alignment: Alignment.center,
            ),
          )
        else ...const [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFFBFCFF),
                  Color(0xFFF2F7FF),
                  Color(0xFFF8FFF4),
                ],
              ),
            ),
            child: SizedBox.expand(),
          ),
          Positioned(top: 20, left: 30, child: _Orb(size: 180, color: Color(0x35FF8FA3))),
          Positioned(top: 110, left: -72, child: _Orb(size: 210, color: Color(0x6B39EA2B))),
          Positioned(top: 120, right: -82, child: _Orb(size: 190, color: Color(0x4AFFB86B))),
          Positioned(bottom: 80, left: -78, child: _Orb(size: 240, color: Color(0x3839EA2B))),
          Positioned(bottom: -35, right: 8, child: _Orb(size: 155, color: Color(0x5A39EA2B))),
          Positioned(top: 235, right: 10, child: _Orb(size: 125, color: Color(0x45DDE8FF))),
        ],
        // Soft white veil, like the mockup photo, but still allows the image/glow to show.
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
            ),
          ),
        ),
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

class _HelpButton extends StatelessWidget {
  static const Color navy = Color(0xFF091733);
  final VoidCallback onTap;

  const _HelpButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _GlassSurface(
      borderRadius: 21,
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(21),
          onTap: onTap,
          child: const SizedBox(
            width: 58,
            height: 58,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.volume_up_rounded, color: navy, size: 24),
                SizedBox(height: 3),
                Text(
                  'Help',
                  style: TextStyle(
                    color: navy,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroGlassCard extends StatelessWidget {
  static const Color navy = Color(0xFF091733);
  static const Color green = Color(0xFF39EA2B);

  const _HeroGlassCard();

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        _GlassSurface(
          borderRadius: 36,
          padding: const EdgeInsets.fromLTRB(22, 70, 22, 25),
          shadowOpacity: 0.13,
          child: Column(
            children: const [
              _KarYabWordMark(),
              SizedBox(height: 9),
              Directionality(
                textDirection: TextDirection.rtl,
                child: Text(
                  'کاریاب',
                  style: TextStyle(
                    color: navy,
                    fontSize: 30,
                    height: 1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              SizedBox(height: 13),
              _HeroDivider(),
              SizedBox(height: 13),
              Text(
                'Find jobs and build your German CV',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: navy,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(height: 22),
              _HeroFeatures(),
            ],
          ),
        ),
        const Positioned(
          top: -28,
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
      width: 86,
      height: 82,
      borderRadius: 26,
      padding: EdgeInsets.zero,
      shadowOpacity: 0.10,
      child: Stack(
        alignment: Alignment.center,
        children: const [
          Positioned(
            left: 23,
            top: 21,
            child: Text(
              'K',
              style: TextStyle(
                color: navy,
                fontSize: 43,
                height: 1,
                fontWeight: FontWeight.w900,
                letterSpacing: -2,
              ),
            ),
          ),
          Positioned(
            right: 18,
            bottom: 21,
            child: Icon(Icons.check_rounded, color: green, size: 34),
          ),
          Positioned(
            right: 14,
            bottom: 18,
            child: Text(
              '.',
              style: TextStyle(
                color: green,
                fontSize: 34,
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
            fontSize: 36,
            height: 1,
            fontWeight: FontWeight.w900,
            letterSpacing: -1,
          ),
        ),
        Text(
          'Yab',
          style: TextStyle(
            color: green,
            fontSize: 36,
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
          width: 47,
          height: 47,
          borderRadius: 16,
          padding: EdgeInsets.zero,
          shadowOpacity: 0.08,
          child: Icon(icon, color: const Color(0xFF4B5B6E), size: 24),
        ),
        const SizedBox(height: 9),
        Text(
          label,
          style: const TextStyle(
            color: navy,
            fontSize: 12,
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
      height: 154,
      decoration: BoxDecoration(
        color: selected ? Colors.white.withOpacity(0.16) : Colors.white.withOpacity(0.10),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(
          color: selected ? green : Colors.white.withOpacity(0.45),
          width: selected ? 1.8 : 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: selected ? green.withOpacity(0.12) : Colors.black.withOpacity(0.025),
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
                    width: 58,
                    height: 58,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected ? const Color(0x33E9FFE6) : Colors.white.withOpacity(0.16),
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
                            size: 31,
                          )
                        : const Text(
                            'A',
                            style: TextStyle(
                              color: navy,
                              fontSize: 34,
                              height: 1,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    option.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: navy,
                      fontSize: 16,
                      height: 1,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  if (option.nativeTitle != null) ...[
                    const SizedBox(height: 5),
                    Directionality(
                      textDirection: TextDirection.rtl,
                      child: Text(
                        option.nativeTitle!,
                        style: const TextStyle(
                          color: Color(0xFF40516A),
                          fontSize: 15,
                          height: 1,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                  if (option.hasVoice) ...[
                    const SizedBox(height: 10),
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
        color: Colors.white.withOpacity(0.18),
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
  static const Color green = Color(0xFF39EA2B);

  const _InfoBox();

  @override
  Widget build(BuildContext context) {
    return _GlassSurface(
      borderRadius: 20,
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      shadowOpacity: 0.06,
      child: Row(
        children: const [
          CircleAvatar(
            radius: 23,
            backgroundColor: Color(0xFFEAFBE9),
            child: Icon(Icons.groups_rounded, color: Color(0xFF147C20), size: 27),
          ),
          SizedBox(width: 13),
          Expanded(
            child: Text(
              'KarYab helps Afghan workers in Germany find the right jobs and create professional CVs that get noticed.',
              style: TextStyle(
                color: navy,
                fontSize: 13,
                height: 1.34,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          SizedBox(width: 8),
          _GermanyPin(),
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
        filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
          width: width ?? double.infinity,
          height: height,
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.10),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: Colors.white.withOpacity(0.42), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(shadowOpacity),
                blurRadius: 30,
                offset: const Offset(0, 18),
              ),
              BoxShadow(
                color: Colors.white.withOpacity(0.18),
                blurRadius: 8,
                offset: const Offset(-4, -4),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}
