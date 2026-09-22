import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_profile.dart';
import 'ausbildung_document_preview_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Ausbildung-flow only — a single lightweight extra question (Schulabschluss
// + optional grade) appended after the regular questionnaire/saved profile,
// before generating an Ausbildung CV. Persists into the same 'saved_profile'
// map (additive keys) so it's asked once and reused for every later
// Ausbildung CV — completely separate from the regular CV flow, which never
// touches these fields.
// ─────────────────────────────────────────────────────────────────────────────

class SchulabschlussScreen extends StatefulWidget {
  final UserProfile profile;
  final String language;
  final bool voiceMode;

  const SchulabschlussScreen({
    super.key,
    required this.profile,
    required this.language,
    this.voiceMode = false,
  });

  @override
  State<SchulabschlussScreen> createState() => _SchulabschlussScreenState();
}

class _SchulabschlussScreenState extends State<SchulabschlussScreen> {
  static const Color _navy  = Color(0xFF091733);
  static const Color _green = Color(0xFF39EA2B);

  late String _lang;
  bool _forwarding = false;

  String? _selected;
  final _foreignCtrl = TextEditingController();
  final _gradeCtrl = TextEditingController();

  static const List<(String key, String label)> _options = [
    ('hauptschule', 'Hauptschulabschluss'),
    ('realschule', 'Realschulabschluss / Mittlere Reife'),
    ('fachhochschulreife', 'Fachhochschulreife'),
    ('abitur', 'Abitur / Allgemeine Hochschulreife'),
    ('auslaendisch', 'Ausländischer Schulabschluss'),
    ('kein_abschluss', 'Kein Schulabschluss'),
  ];

  @override
  void initState() {
    super.initState();
    _lang = widget.language;
    // Already answered on a previous Ausbildung CV creation — skip straight
    // to template selection / generation instead of re-asking.
    if (widget.profile.schulabschluss != null &&
        widget.profile.schulabschluss!.isNotEmpty) {
      _forwarding = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _goToPreview(widget.profile));
    }
  }

  @override
  void dispose() {
    _foreignCtrl.dispose();
    _gradeCtrl.dispose();
    super.dispose();
  }

  bool get _isRtl => _lang == 'ps' || _lang == 'fa';

  bool get _canContinue {
    if (_selected == null) return false;
    if (_selected == 'auslaendisch') return _foreignCtrl.text.trim().isNotEmpty;
    return true;
  }

  String get _title {
    switch (_lang) {
      case 'ps': return 'ستاسو تر ټولو لوړه زده کړیزه سویه کومه ده؟';
      case 'fa': return 'بالاترین مدرک تحصیلی شما در مکتب چیست؟';
      default:   return 'What is your highest school qualification?';
    }
  }

  String get _subtitle {
    switch (_lang) {
      case 'ps': return 'دا به موږ سره ستاسو د زده کړې کار CV بشپړولو کې مرسته وکړي';
      case 'fa': return 'این به تکمیل رزومه کارآموزی شما کمک می‌کند';
      default:   return 'This helps us complete your Ausbildung CV';
    }
  }

  String get _foreignHint {
    switch (_lang) {
      case 'ps': return 'خپل سند دلته وضاحت کړئ';
      case 'fa': return 'مدرک خود را اینجا مشخص کنید';
      default:   return 'Specify your qualification';
    }
  }

  String get _gradeLabel {
    switch (_lang) {
      case 'ps': return 'نمره (اختیاري)';
      case 'fa': return 'نمره (اختیاری)';
      default:   return 'Grade (optional)';
    }
  }

  String get _gradeHint {
    switch (_lang) {
      case 'ps': return 'لکه ۱٫۸ یا ښه';
      case 'fa': return 'مثلاً ۱٫۸ یا خوب';
      default:   return 'e.g. 1.8 or Good';
    }
  }

  String get _continueLabel {
    switch (_lang) {
      case 'ps': return 'دوام →';
      case 'fa': return 'ادامه →';
      default:   return 'Continue →';
    }
  }

  Future<void> _submit() async {
    if (!_canContinue) return;
    final schulabschluss = _selected == 'auslaendisch'
        ? _foreignCtrl.text.trim()
        : _selected!;
    final note = _gradeCtrl.text.trim();

    final updated = widget.profile.copyWith(
      schulabschluss: schulabschluss,
      schulabschlussNote: note.isNotEmpty ? note : null,
    );

    await _persist(schulabschluss, note);

    if (!mounted) return;
    _goToPreview(updated);
  }

  // Merges the two new keys into the existing 'saved_profile' map without
  // disturbing anything else already stored there.
  Future<void> _persist(String schulabschluss, String note) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('saved_profile');
      final map = raw != null && raw.isNotEmpty
          ? jsonDecode(raw) as Map<String, dynamic>
          : <String, dynamic>{};
      map['schulabschluss'] = schulabschluss;
      map['schulabschlussNote'] = note;
      await prefs.setString('saved_profile', jsonEncode(map));
    } catch (_) {}
  }

  void _goToPreview(UserProfile profile) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => AusbildungDocumentPreviewScreen(
          profile: profile,
          language: _lang,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_forwarding) {
      return const Scaffold(
        backgroundColor: Color(0xFFF7FAFF),
        body: Center(
          child: CircularProgressIndicator(color: _green),
        ),
      );
    }

    return Scaffold(
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
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    child: Column(
                      children: [
                        _QCard(
                          question: _title,
                          subtitle: _subtitle,
                          isRtl: _isRtl,
                          child: _chipChoices(),
                        ),
                        if (_selected != null) ...[
                          const SizedBox(height: 14),
                          _QCard(
                            question: _gradeLabel,
                            isRtl: _isRtl,
                            child: _TxtField(
                              controller: _gradeCtrl,
                              hint: _gradeHint,
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        _BigButton(
                          label: _continueLabel,
                          enabled: _canContinue,
                          onTap: _submit,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final title = _lang == 'ps'
        ? 'د زده کړې کار CV'
        : _lang == 'fa'
            ? 'رزومه کارآموزی'
            : 'Ausbildung CV';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          _NavBtn(
            icon: Icons.arrow_back_ios_new_rounded,
            onTap: () => Navigator.pop(context),
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _navy,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 44),
        ],
      ),
    );
  }

  Widget _chipChoices() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _options.map((opt) {
            final sel = _selected == opt.$1;
            return GestureDetector(
              onTap: () => setState(() => _selected = opt.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: sel ? const Color(0xFFEAFBE9) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: sel ? _green : const Color(0xFFDDE4EF),
                    width: sel ? 2.0 : 1.2,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(opt.$2,
                        style: const TextStyle(
                          color: _navy,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        )),
                    if (sel) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.check_rounded,
                          color: _green, size: 13),
                    ],
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        if (_selected == 'auslaendisch') ...[
          const SizedBox(height: 10),
          _TxtField(controller: _foreignCtrl, hint: _foreignHint),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small local widgets mirroring the glass/chip style used throughout the app
// (questionnaire_screen.dart's _QCard/_TxtField/_BigButton), kept private to
// this file per this codebase's existing per-screen convention.
// ─────────────────────────────────────────────────────────────────────────────

class _QCard extends StatelessWidget {
  static const Color _navy = Color(0xFF091733);
  static const Color _muted = Color(0xFF65738A);

  final String question;
  final String? subtitle;
  final bool isRtl;
  final Widget child;

  const _QCard({
    required this.question,
    this.subtitle,
    required this.isRtl,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return _GlassSurface(
      borderRadius: 20,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment:
            isRtl ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text(
            question,
            textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
            style: const TextStyle(
              color: _navy,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              height: 1.4,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
              style: const TextStyle(
                color: _muted,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _TxtField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;

  const _TxtField({required this.controller, required this.hint});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.9)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10),
        ],
      ),
      child: TextField(
        controller: controller,
        textDirection: TextDirection.ltr,
        style: const TextStyle(color: Color(0xFF091733)),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFF65738A), fontSize: 14),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(14),
        ),
      ),
    );
  }
}

class _BigButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  const _BigButton({
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
        height: 58,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(29),
          color: const Color(0xFF39EA2B),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF39EA2B).withOpacity(0.35),
              blurRadius: 22,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(29),
            onTap: enabled ? onTap : null,
            child: Center(
              child: Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF091733),
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavBtn extends StatelessWidget {
  static const Color _navy = Color(0xFF091733);

  final IconData icon;
  final VoidCallback onTap;

  const _NavBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: _GlassSurface(
        width: 44,
        height: 44,
        borderRadius: 14,
        padding: EdgeInsets.zero,
        child: Icon(icon, color: _navy, size: 20),
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
              colors: [Color(0xFFF9FBFF), Color(0xFFEFF6FF), Color(0xFFF7FFF2)],
            ),
          ),
          child: SizedBox.expand(),
        ),
        Positioned(top: 70,   left: -42,  child: _Orb(size: 170, color: Color(0x6639EA2B))),
        Positioned(top: 135,  right: -65, child: _Orb(size: 170, color: Color(0x44FFB86B))),
        Positioned(bottom: 95, left: -60, child: _Orb(size: 210, color: Color(0x3339EA2B))),
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
            border: Border.all(color: Colors.white.withOpacity(0.85), width: 1.2),
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
