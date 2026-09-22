import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../constants/app_colors.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  String? _selectedLanguage;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.18).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _selectLanguage(String language) {
    if (_selectedLanguage != null) return;
    setState(() => _selectedLanguage = language);
    Future.delayed(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      Navigator.pushNamed(context, '/education', arguments: language);
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) setState(() => _selectedLanguage = null);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          _BackgroundDecoration(screenSize: size),
          SafeArea(
            child: Column(
              children: [
                // ── App name section ──────────────────────────────────────
                Expanded(
                  flex: 32,
                  child: _AppNameSection(),
                ),
                // ── Language selection section ────────────────────────────
                Expanded(
                  flex: 42,
                  child: _LanguageSection(
                    selectedLanguage: _selectedLanguage,
                    onSelect: _selectLanguage,
                  ),
                ),
                // ── Microphone section ───────────────────────────────────
                Expanded(
                  flex: 26,
                  child: _MicSection(pulseAnimation: _pulseAnimation),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Subtle radial background gradient decoration ───────────────────────────────

class _BackgroundDecoration extends StatelessWidget {
  final Size screenSize;
  const _BackgroundDecoration({required this.screenSize});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: CustomPaint(
        painter: _BackgroundPainter(screenSize: screenSize),
      ),
    );
  }
}

class _BackgroundPainter extends CustomPainter {
  final Size screenSize;
  const _BackgroundPainter({required this.screenSize});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0, -0.6),
        radius: 0.9,
        colors: [
          const Color(0xFF0E2040),
          AppColors.background,
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);

    // Subtle green glow at top center
    final glowPaint = Paint()
      ..shader = RadialGradient(
        center: Alignment.topCenter,
        radius: 0.5,
        colors: [
          AppColors.accent.withOpacity(0.07),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), glowPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── App name section ──────────────────────────────────────────────────────────

class _AppNameSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 16),
        // English logo mark
        Text(
          'KarYab',
          style: GoogleFonts.poppins(
            color: AppColors.textPrimary,
            fontSize: 48,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.5,
            height: 1.1,
          ),
        ),
        // Dari/Pashto name in green
        const Text(
          'کاریاب',
          style: TextStyle(
            color: AppColors.accent,
            fontSize: 32,
            fontWeight: FontWeight.bold,
            height: 1.2,
          ),
          textDirection: TextDirection.rtl,
        ),
        const SizedBox(height: 10),
        // Tagline
        Text(
          'Job Finder · جرمني کې د دندې موندل',
          style: GoogleFonts.poppins(
            color: AppColors.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w400,
            letterSpacing: 0.4,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

// ── Language selection section ─────────────────────────────────────────────────

class _LanguageSection extends StatelessWidget {
  final String? selectedLanguage;
  final ValueChanged<String> onSelect;

  const _LanguageSection({
    required this.selectedLanguage,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'خپله ژبه غوره کړئ  ·  زبان خود را انتخاب کنید  ·  Select Language',
            style: GoogleFonts.poppins(
              color: AppColors.textMuted,
              fontSize: 11,
              letterSpacing: 0.2,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          _LanguageButton(
            label: 'پښتو',
            sublabel: 'Pashto',
            language: 'ps',
            isRtl: true,
            isSelected: selectedLanguage == 'ps',
            onTap: onSelect,
          ),
          const SizedBox(height: 14),
          _LanguageButton(
            label: 'دری',
            sublabel: 'Dari',
            language: 'fa',
            isRtl: true,
            isSelected: selectedLanguage == 'fa',
            onTap: onSelect,
          ),
          const SizedBox(height: 14),
          _LanguageButton(
            label: 'English',
            sublabel: 'English',
            language: 'en',
            isRtl: false,
            isSelected: selectedLanguage == 'en',
            onTap: onSelect,
          ),
        ],
      ),
    );
  }
}

class _LanguageButton extends StatefulWidget {
  final String label;
  final String sublabel;
  final String language;
  final bool isRtl;
  final bool isSelected;
  final ValueChanged<String> onTap;

  const _LanguageButton({
    required this.label,
    required this.sublabel,
    required this.language,
    required this.isRtl,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_LanguageButton> createState() => _LanguageButtonState();
}

class _LanguageButtonState extends State<_LanguageButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressController;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _pressController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool active = widget.isSelected;

    return ScaleTransition(
      scale: _scaleAnim,
      child: GestureDetector(
        onTapDown: (_) => _pressController.forward(),
        onTapUp: (_) {
          _pressController.reverse();
          widget.onTap(widget.language);
        },
        onTapCancel: () => _pressController.reverse(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: double.infinity,
          height: 68,
          decoration: BoxDecoration(
            color: active ? AppColors.accent.withOpacity(0.15) : AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: active ? AppColors.accent : AppColors.accentDim,
              width: active ? 1.8 : 1.0,
            ),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: AppColors.accent.withOpacity(0.18),
                      blurRadius: 16,
                      spreadRadius: 1,
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
          ),
          child: Row(
            textDirection: widget.isRtl ? TextDirection.rtl : TextDirection.ltr,
            children: [
              const SizedBox(width: 20),
              // Language flag indicator dot
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: active ? AppColors.accent : AppColors.accentDim,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: widget.isRtl
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.label,
                      style: TextStyle(
                        color: active ? AppColors.accent : AppColors.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                      textDirection:
                          widget.isRtl ? TextDirection.rtl : TextDirection.ltr,
                    ),
                  ],
                ),
              ),
              // Chevron
              Icon(
                widget.isRtl
                    ? Icons.chevron_left_rounded
                    : Icons.chevron_right_rounded,
                color: active ? AppColors.accent : AppColors.textMuted,
                size: 26,
              ),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Microphone section ────────────────────────────────────────────────────────

class _MicSection extends StatelessWidget {
  final Animation<double> pulseAnimation;
  const _MicSection({required this.pulseAnimation});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Divider line
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 60),
          child: Row(
            children: [
              Expanded(
                child: Divider(color: AppColors.textMuted.withOpacity(0.3), height: 1),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text(
                  'یا · یا · or',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                  ),
                ),
              ),
              Expanded(
                child: Divider(color: AppColors.textMuted.withOpacity(0.3), height: 1),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        // Pulsing microphone button
        ScaleTransition(
          scale: pulseAnimation,
          child: GestureDetector(
            onTap: () {
              // TODO: Launch voice mode flow
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Voice mode coming soon...'),
                  backgroundColor: AppColors.surface,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              );
            },
            child: Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: AppColors.accent,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.accent.withOpacity(0.45),
                    blurRadius: 24,
                    spreadRadius: 2,
                  ),
                  BoxShadow(
                    color: AppColors.accent.withOpacity(0.15),
                    blurRadius: 48,
                    spreadRadius: 8,
                  ),
                ],
              ),
              child: const Icon(
                Icons.mic_rounded,
                color: Colors.white,
                size: 34,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'د غږ له لارې  ·  با صدا  ·  Use Voice',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 11,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
