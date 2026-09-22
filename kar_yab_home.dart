import 'dart:ui';
import 'package:flutter/material.dart';

/// KarYab home screen — glassmorphic profile bar, search pill, and a
/// 2-column grid of quick-action tiles. Add 'Vazirmatn' and 'Lora' as
/// fonts in pubspec.yaml (or swap fontFamily for a bundled equivalent).

class KarYabAction {
  final String label;
  final IconData icon;
  final Color bg;
  final Color tint;
  const KarYabAction(this.label, this.icon, this.bg, this.tint);
}

const List<KarYabAction> kActions = [
  KarYabAction('نوی CV جوړ کړئ', Icons.add_rounded, Color(0xFFE3F5E7), Color(0xFF2FA84F)),
  KarYabAction('زما جوړه شوی CV وګورئ', Icons.description_outlined, Color(0xFFE3F5E7), Color(0xFF2FA84F)),
  KarYabAction('خپله CV اپلوډ کړئ', Icons.upload_file_rounded, Color(0xFFE6EDFD), Color(0xFF3A6DF0)),
  KarYabAction('د زده کړې کار وموندئ', Icons.school_outlined, Color(0xFFE6EDFD), Color(0xFF3A6DF0)),
  KarYabAction('آلمانی زده کړئ', Icons.translate_rounded, Color(0xFFF3E6FA), Color(0xFFA355D1)),
];

class KarYabHome extends StatelessWidget {
  const KarYabHome({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFFBFCFA),
        body: Stack(
          children: [
            // soft blurred background blobs
            Positioned(
              top: -60,
              left: -40,
              child: _Blob(size: 260, color: const Color(0x59A8E0A0)),
            ),
            Positioned(
              top: 120,
              right: -60,
              child: _Blob(size: 220, color: const Color(0x4DF0B4BE)),
            ),
            SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Header(),
                    const SizedBox(height: 16),
                    _ProfileCvBar(),
                    const SizedBox(height: 14),
                    _SearchPill(),
                    const SizedBox(height: 18),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 14,
                      childAspectRatio: 1.15,
                      children: kActions.map((a) => _ActionTile(a)).toList(),
                    ),
                    const SizedBox(height: 22),
                    const Text(
                      'KarYab v1.0',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFFA8B3AC), fontSize: 12),
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

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        RichText(
          text: const TextSpan(
            style: TextStyle(fontFamily: 'Lora', fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF16211C)),
            children: [
              TextSpan(text: 'Kar'),
              TextSpan(text: 'Yab', style: TextStyle(color: Color(0xFF2FA84F))),
            ],
          ),
        ),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(color: const Color(0xFF0D1B2A), borderRadius: BorderRadius.circular(999)),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('PS', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                  SizedBox(width: 6),
                  Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 16),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 8, offset: Offset(0, 2))],
              ),
              child: const Icon(Icons.volume_up_rounded, color: Color(0xFF2FA84F), size: 18),
            ),
          ],
        ),
      ],
    );
  }
}

/// Reusable frosted-glass container.
class _GlassCard extends StatelessWidget {
  final Widget child;
  final BorderRadius radius;
  final Color tint;
  final Color borderColor;
  final List<BoxShadow>? shadow;
  const _GlassCard({
    required this.child,
    required this.radius,
    this.tint = const Color(0x73FFFFFF),
    this.borderColor = const Color(0x99FFFFFF),
    this.shadow,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: BoxDecoration(
            color: tint,
            borderRadius: radius,
            border: Border.all(color: borderColor, width: 1),
            boxShadow: shadow ??
                const [BoxShadow(color: Color(0x14142819), blurRadius: 24, offset: Offset(0, 8))],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _ProfileCvBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      radius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(color: Color(0xE5E3F5E7), shape: BoxShape.circle),
              child: const Icon(Icons.person, color: Color(0xFF2FA84F), size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Text('!kdksk ،بۀ راغلاست',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF16211C))),
                  Text('kakao, Deutschland', style: TextStyle(fontSize: 11, color: Color(0xFF7C8A80))),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(color: const Color(0xE5EAF8EE), borderRadius: BorderRadius.circular(999)),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.description, size: 12, color: Color(0xFF2FA84F)),
                  SizedBox(width: 5),
                  Text('CV ✓', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF218A3B))),
                ],
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_left_rounded, size: 18, color: Color(0xFF7C8A80)),
          ],
        ),
      ),
    );
  }
}

class _SearchPill extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xD90D1B2A),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0x1FFFFFFF)),
          ),
          child: Row(
            children: [
              const Icon(Icons.volume_up_rounded, color: Color(0xFF2FA84F), size: 18),
              const Expanded(
                child: Text(
                  'نژدي کارونه پیدا کړئ',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(color: Color(0x1AFFFFFF), shape: BoxShape.circle),
                child: const Icon(Icons.search_rounded, color: Color(0xFF2FA84F), size: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final KarYabAction action;
  const _ActionTile(this.action);

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      radius: BorderRadius.circular(24),
      shadow: [BoxShadow(color: const Color(0xFF2A5729).withOpacity(0.15), blurRadius: 12, offset: const Offset(4, 4))],
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
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF16211C), height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
