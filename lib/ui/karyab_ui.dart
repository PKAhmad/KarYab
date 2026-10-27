import 'dart:ui';

import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Shared KarYab UI kit. Every value here is lifted unchanged from
// lib/screens/introduction_screen.dart, the design reference, so that screens
// can stop carrying their own private copies. Nothing in this file is a
// redesign.
// ─────────────────────────────────────────────────────────────────────────────

// ── Tokens ───────────────────────────────────────────────────────────────────

class KColors {
  KColors._();

  // Brand
  static const Color navy = Color(0xFF091733);
  static const Color green = Color(0xFF39EA2B);
  static const Color mint = Color(0xFFEAFBE9);
  static const Color mintBadge = Color(0xFFE9FFE6);
  static const Color greenDark = Color(0xFF0E7A20);
  static const Color greenDarkBadge = Color(0xFF147C20);

  // Accents used for tile icons
  static const Color blue = Color(0xFF2D6BE4);
  static const Color purple = Color(0xFF9C27B0);

  // Text and lines
  static const Color textSecondary = Color(0xFF65738A);
  static const Color border = Color(0xFFDDE4EF);
  // The reference screen itself uses these two slightly different greys.
  static const Color borderSoft = Color(0xFFE4EAF5);
  static const Color handle = Color(0xFFD1D9E6);

  // Page
  static const Color pageBase = Color(0xFFF7FAFF);
  static const Color gradientTop = Color(0xFFF9FBFF);
  static const Color gradientMid = Color(0xFFEFF6FF);
  static const Color gradientBottom = Color(0xFFF7FFF2);

  // Glow orbs (ARGB)
  static const Color orbGreenA = Color(0x6639EA2B);
  static const Color orbOrange = Color(0x44FFB86B);
  static const Color orbGreenB = Color(0x3339EA2B);
  static const Color orbGreenC = Color(0x5539EA2B);
  static const Color orbPink = Color(0x30FF8FA3);

  // Primary button gradient
  static const Color ctaStart = Color(0xFF081532);
  static const Color ctaEnd = Color(0xFF07112B);
}

// ── Background ───────────────────────────────────────────────────────────────

class KOrb extends StatelessWidget {
  final double size;
  final Color color;

  const KOrb({super.key, required this.size, required this.color});

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

// Page gradient plus the 5 glow orbs. [accent], when given, replaces the
// orange orb (the second one), for screens that carry their own accent.
class KBackgroundGlow extends StatelessWidget {
  final Color? accent;

  const KBackgroundGlow({super.key, this.accent});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                KColors.gradientTop,
                KColors.gradientMid,
                KColors.gradientBottom,
              ],
            ),
          ),
          child: SizedBox.expand(),
        ),
        const Positioned(
            top: 70, left: -42, child: KOrb(size: 170, color: KColors.orbGreenA)),
        Positioned(
            top: 135,
            right: -65,
            child: KOrb(size: 170, color: accent ?? KColors.orbOrange)),
        const Positioned(
            bottom: 95, left: -60, child: KOrb(size: 210, color: KColors.orbGreenB)),
        const Positioned(
            bottom: -30, right: 14, child: KOrb(size: 145, color: KColors.orbGreenC)),
        const Positioned(
            top: 20, left: 30, child: KOrb(size: 170, color: KColors.orbPink)),
      ],
    );
  }
}

// ── Glass surface ────────────────────────────────────────────────────────────

class KGlassSurface extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;
  final double borderRadius;
  final EdgeInsetsGeometry padding;

  const KGlassSurface({
    super.key,
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

// ── Nav / top icon button ────────────────────────────────────────────────────

// 44x44 glass icon button. [active] turns the icon green (voice on);
// [hintPulse] shows the navy pulse background behind it.
class KNavButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  final bool hintPulse;

  const KNavButton({
    super.key,
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
            ? KColors.navy.withOpacity(0.85)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
      ),
      child: KGlassSurface(
        width: 44,
        height: 44,
        borderRadius: 14,
        padding: EdgeInsets.zero,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Center(
              child: Icon(icon,
                  color: active ? KColors.green : KColors.navy, size: 20),
            ),
          ),
        ),
      ),
    );
  }
}

// The reference calls this widget "top button"; it is the same widget.
typedef KTopButton = KNavButton;

// ── Language pill (visual only) ──────────────────────────────────────────────

// Navy pill with the language code and a chevron. What happens on tap
// (opening the picker, switching language) is up to the caller.
class KLangPill extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const KLangPill({super.key, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: KColors.navy,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: KColors.navy.withOpacity(0.20),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
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

// ── Primary button ───────────────────────────────────────────────────────────

// Full-width navy gradient button: 64 high, radius 22, two shadows, green icon
// circle on the left, green arrow on the right.
class KPrimaryCta extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isRtl;
  final bool isSelected;
  final bool showSpeaker;
  final VoidCallback? onSpeaker;
  final VoidCallback onTap;

  const KPrimaryCta({
    super.key,
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
            colors: [KColors.ctaStart, KColors.ctaEnd],
          ),
          boxShadow: [
            BoxShadow(
              color: KColors.ctaEnd.withOpacity(0.30),
              blurRadius: 22,
              offset: const Offset(0, 12),
            ),
            BoxShadow(
              color: KColors.green.withOpacity(0.20),
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
                      color: KColors.green.withOpacity(0.18),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: KColors.green, size: 20),
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
                      icon: const Icon(Icons.volume_up, color: KColors.green),
                      iconSize: 18,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  Icon(
                    isRtl
                        ? Icons.arrow_back_ios_new_rounded
                        : Icons.arrow_forward_rounded,
                    color: KColors.green,
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

// ── Glass grid tile ──────────────────────────────────────────────────────────

// Translucent (not blurred) tile for the 2-column action grid: icon in a
// tinted circle over a short label. [compact] is the smaller size used when
// the grid holds 5 tiles.
class KGridTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final bool isRtl;
  final bool showSpeaker;
  final VoidCallback? onSpeaker;
  final VoidCallback onTap;
  final bool compact;

  const KGridTile({
    super.key,
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
        // SizedBox.expand forces the tile to fill the exact grid cell
        // regardless of label length.
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
                          color: KColors.navy,
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
              icon: const Icon(Icons.volume_up, color: KColors.green),
              iconSize: 16,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ),
      ],
    );
  }
}

// ── Glass card ───────────────────────────────────────────────────────────────

// Translucent (not blurred) card with the same decoration as [KGridTile]:
// white 0.62 fill, white 0.85 border at 1.2, one black 0.06 shadow. Safe to
// use inside lists, because it never uses a BackdropFilter. [selected] gives
// the 2.0 green border and a 0.07 green tint.
class KGlassCard extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final bool selected;

  const KGlassCard({
    super.key,
    required this.child,
    required this.borderRadius,
    this.padding = EdgeInsets.zero,
    this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: selected
            ? KColors.green.withOpacity(0.07)
            : Colors.white.withOpacity(0.62),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: selected ? KColors.green : Colors.white.withOpacity(0.85),
          width: selected ? 2.0 : 1.2,
        ),
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
          borderRadius: BorderRadius.circular(borderRadius),
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

// ── Snackbar ─────────────────────────────────────────────────────────────────

enum KSnackKind { info, success, error }

// Navy floating snackbar with radius 12 and white text. [success] and [error]
// only change the background (green with navy text, red with white text).
void kSnack(
  BuildContext context,
  String message, {
  KSnackKind kind = KSnackKind.info,
  Duration duration = const Duration(seconds: 4),
}) {
  final Color bg;
  final Color fg;
  switch (kind) {
    case KSnackKind.success:
      bg = KColors.green;
      fg = KColors.navy;
      break;
    case KSnackKind.error:
      bg = Colors.redAccent;
      fg = Colors.white;
      break;
    case KSnackKind.info:
      bg = KColors.navy;
      fg = Colors.white;
      break;
  }
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(message, style: TextStyle(color: fg)),
    duration: duration,
    backgroundColor: bg,
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ));
}

// ── Bottom sheet ─────────────────────────────────────────────────────────────

// White sheet with a 24 top radius. Use as the decoration of the sheet's
// outer Container (the route itself stays transparent) and put a
// [KSheetHandle] at the top of its content.
const BoxDecoration kSheetDecoration = BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
);

// The 36x4 grab handle at the top of a sheet.
class KSheetHandle extends StatelessWidget {
  const KSheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 4,
      decoration: BoxDecoration(
        color: KColors.handle,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}
