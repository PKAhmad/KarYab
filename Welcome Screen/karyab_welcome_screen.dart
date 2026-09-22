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
  final String name;
  final String? nativeName;
  final bool hasVoice;

  const LanguageOption({
    required this.id,
    required this.name,
    required this.nativeName,
    required this.hasVoice,
  });
}

class KarYabWelcomeScreen extends StatefulWidget {
  final ValueChanged<AppLanguage>? onContinue;

  const KarYabWelcomeScreen({
    super.key,
    this.onContinue,
  });

  @override
  State<KarYabWelcomeScreen> createState() => _KarYabWelcomeScreenState();
}

class _KarYabWelcomeScreenState extends State<KarYabWelcomeScreen> {
  static const Color neon = Color(0xFF39FF14);
  static const Color navy = Color(0xFF1A1A2E);
  static const Color darkButton = Color(0xFF0D0D1A);

  AppLanguage selectedLanguage = AppLanguage.pashto;

  static const List<LanguageOption> languages = [
    LanguageOption(
      id: AppLanguage.pashto,
      name: 'Pashto',
      nativeName: 'پشتو',
      hasVoice: true,
    ),
    LanguageOption(
      id: AppLanguage.dari,
      name: 'Dari',
      nativeName: 'دری',
      hasVoice: true,
    ),
    LanguageOption(
      id: AppLanguage.english,
      name: 'English',
      nativeName: null,
      hasVoice: false,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            const _DecorativeOrbs(),
            LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 2),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: _HelpButton(onTap: () {}),
                          ),
                        ),
                        const SizedBox(height: 4),
                        const _LogoBlock(),
                        const SizedBox(height: 12),
                        const _FeaturePills(),
                        const SizedBox(height: 16),
                        _LanguageSelectionCard(
                          languages: languages,
                          selectedLanguage: selectedLanguage,
                          onChanged: (language) {
                            setState(() => selectedLanguage = language);
                          },
                        ),
                        const SizedBox(height: 16),
                        const _InfoBox(),
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                          child: _ContinueButton(
                            onTap: () => widget.onContinue?.call(selectedLanguage),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Your Job. Your CV. Your Future.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF9CA3AF),
                            fontSize: 10,
                            letterSpacing: 0.3,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        const SizedBox(height: 22),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DecorativeOrbs extends StatelessWidget {
  const _DecorativeOrbs();

  @override
  Widget build(BuildContext context) {
    return const Stack(
      children: [
        Positioned(
          top: -60,
          right: -60,
          child: _RadialOrb(
            size: 200,
            color: Color(0x2E39FF14),
          ),
        ),
        Positioned(
          top: 80,
          left: -80,
          child: _RadialOrb(
            size: 180,
            color: Color(0x1FFF8C32),
          ),
        ),
      ],
    );
  }
}

class _RadialOrb extends StatelessWidget {
  final double size;
  final Color color;

  const _RadialOrb({
    required this.size,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 34, sigmaY: 34),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [color, Colors.transparent],
              stops: const [0.0, 0.72],
            ),
          ),
        ),
      ),
    );
  }
}

class _HelpButton extends StatelessWidget {
  final VoidCallback onTap;

  const _HelpButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF3F4F6),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.volume_up_rounded, size: 12, color: Color(0xFF6B7280)),
              SizedBox(width: 6),
              Text(
                'Help',
                style: TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LogoBlock extends StatelessWidget {
  static const Color neon = Color(0xFF39FF14);
  static const Color navy = Color(0xFF1A1A2E);

  const _LogoBlock();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: _GlassContainer(
        borderRadius: 32,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
        color: Colors.white.withOpacity(0.08),
        borderColor: Colors.white.withOpacity(0.45),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF13DBE8).withOpacity(0.12),
            blurRadius: 48,
            offset: const Offset(0, 20),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 68,
              height: 68,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1A1A2E), Color(0xFF2D2D50)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: neon.withOpacity(0.25),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(0.20),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Transform.translate(
                offset: const Offset(-1.5, 0),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'K',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1,
                        height: 1,
                      ),
                    ),
                    Text(
                      'y',
                      style: TextStyle(
                        color: neon,
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1,
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  'Kar',
                  style: TextStyle(
                    color: navy,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
                Text(
                  'Yab',
                  style: TextStyle(
                    color: neon,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            const Directionality(
              textDirection: TextDirection.rtl,
              child: Text(
                'کاریاب',
                style: TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Find jobs and build your German CV',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF9CA3AF),
                fontSize: 12,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeaturePills extends StatelessWidget {
  const _FeaturePills();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: _GlassContainer(
        borderRadius: 24,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
        color: Colors.white.withOpacity(0.22),
        borderColor: Colors.white.withOpacity(0.60),
        sigma: 28,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF39FF14).withOpacity(0.08),
            blurRadius: 32,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _FeatureItem(icon: Icons.work_rounded, label: 'Job Finder'),
            _FeatureItem(icon: Icons.description_rounded, label: 'CV Generator'),
            _FeatureItem(icon: Icons.mic_rounded, label: 'Voice Support'),
          ],
        ),
      ),
    );
  }
}

class _FeatureItem extends StatelessWidget {
  final IconData icon;
  final String label;

  const _FeatureItem({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.70),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.85), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.07),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(icon, size: 17, color: const Color(0xFF374151)),
        ),
        const SizedBox(height: 7),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF6B7280),
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _LanguageSelectionCard extends StatelessWidget {
  static const Color neon = Color(0xFF39FF14);

  final List<LanguageOption> languages;
  final AppLanguage selectedLanguage;
  final ValueChanged<AppLanguage> onChanged;

  const _LanguageSelectionCard({
    required this.languages,
    required this.selectedLanguage,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: _GlassContainer(
        borderRadius: 28,
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 18),
        color: Colors.white.withOpacity(0.80),
        borderColor: Colors.white.withOpacity(0.75),
        sigma: 32,
        boxShadow: [
          BoxShadow(
            color: neon.withOpacity(0.22),
            blurRadius: 60,
            offset: const Offset(0, 20),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
        child: Column(
          children: [
            const Text(
              'Choose your language',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF1A1A2E),
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            const Text(
              'We support Pashto, Dari & English',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF9CA3AF),
                fontSize: 11,
                fontWeight: FontWeight.w400,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                for (int i = 0; i < languages.length; i++) ...[
                  Expanded(
                    child: _LanguageCard(
                      language: languages[i],
                      isSelected: selectedLanguage == languages[i].id,
                      onTap: () => onChanged(languages[i].id),
                    ),
                  ),
                  if (i != languages.length - 1) const SizedBox(width: 10),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LanguageCard extends StatelessWidget {
  static const Color neon = Color(0xFF39FF14);

  final LanguageOption language;
  final bool isSelected;
  final VoidCallback onTap;

  const _LanguageCard({
    required this.language,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      constraints: const BoxConstraints(minHeight: 100),
      decoration: BoxDecoration(
        color: isSelected ? neon.withOpacity(0.12) : Colors.white.withOpacity(0.80),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isSelected ? neon : Colors.white.withOpacity(0.65),
          width: isSelected ? 2 : 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: isSelected
                ? neon.withOpacity(0.35)
                : Colors.black.withOpacity(0.07),
            blurRadius: isSelected ? 32 : 20,
            offset: const Offset(0, 8),
          ),
          if (isSelected)
            BoxShadow(
              color: neon.withOpacity(0.18),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Stack(
            children: [
              if (isSelected)
                const Positioned(
                  top: 8,
                  right: 8,
                  child: Icon(
                    Icons.check_circle_rounded,
                    size: 15,
                    color: neon,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (language.hasVoice)
                      Icon(
                        Icons.volume_up_rounded,
                        size: 22,
                        color: isSelected
                            ? const Color(0xFF374151)
                            : const Color(0xFF9CA3AF),
                      )
                    else
                      Text(
                        'A',
                        style: TextStyle(
                          color: isSelected
                              ? const Color(0xFF374151)
                              : const Color(0xFF9CA3AF),
                          fontSize: 22,
                          height: 1,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    const SizedBox(height: 6),
                    Text(
                      language.name,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF1A1A2E),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (language.nativeName != null) ...[
                      const SizedBox(height: 2),
                      Directionality(
                        textDirection: TextDirection.rtl,
                        child: Text(
                          language.nativeName!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFF6B7280),
                            fontSize: 11,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                    ],
                    if (language.hasVoice) ...[
                      const SizedBox(height: 6),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.volume_up_rounded, size: 9, color: neon),
                          SizedBox(width: 2),
                          Text(
                            'Voice',
                            style: TextStyle(
                              color: neon,
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
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

class _InfoBox extends StatelessWidget {
  const _InfoBox();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF39FF14), Colors.black],
                ),
              ),
              child: const Text('🌿', style: TextStyle(fontSize: 16)),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'KarYab helps Afghan workers in Germany find the right jobs and create professional CVs that get noticed.',
                style: TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 10.5,
                  height: 1.5,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContinueButton extends StatelessWidget {
  final VoidCallback onTap;

  const _ContinueButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(50),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0D0D1A), Color(0xFF1A1A33)],
        ),
        border: Border.all(color: const Color(0x991A1A50), width: 1),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00001A).withOpacity(0.55),
            blurRadius: 28,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.30),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(50),
          onTap: onTap,
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Continue',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(width: 8),
              Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final Color color;
  final Color borderColor;
  final List<BoxShadow> boxShadow;
  final double sigma;

  const _GlassContainer({
    required this.child,
    required this.padding,
    required this.borderRadius,
    required this.color,
    required this.borderColor,
    this.boxShadow = const [],
    this.sigma = 32,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: Container(
          width: double.infinity,
          padding: padding,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: borderColor, width: 1.5),
            boxShadow: boxShadow,
          ),
          child: child,
        ),
      ),
    );
  }
}
