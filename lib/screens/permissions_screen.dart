import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/analytics_service.dart';
import '../services/tts_service.dart';

// Shown once per install, right before Introduction — after Education for
// Pashto/Dari (voiceMode is known by then), or right after Welcome for
// English (which skips Education and is always voiceMode == false). Gated
// by the 'permissions_onboarding_shown' SharedPreferences flag, checked by
// whichever screen precedes this one in the flow.
class PermissionsScreen extends StatefulWidget {
  final String language;
  final bool voiceMode;

  const PermissionsScreen({
    super.key,
    required this.language,
    required this.voiceMode,
  });

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  static const Color navy  = Color(0xFF091733);
  static const Color green = Color(0xFF39EA2B);

  bool _cameraGranted   = false;
  bool _locationGranted = false;
  bool _continuing      = false;

  bool get _isRtl => widget.language == 'ps' || widget.language == 'fa';

  @override
  void initState() {
    super.initState();
    AnalyticsService().logScreen('permissions');
    _loadStatuses();
  }

  Future<void> _loadStatuses() async {
    final cameraStatus = await Permission.camera.status;
    final locationPermission = await Geolocator.checkPermission();
    if (!mounted) return;
    setState(() {
      _cameraGranted = cameraStatus.isGranted;
      _locationGranted = locationPermission == LocationPermission.whileInUse ||
          locationPermission == LocationPermission.always;
    });
  }

  Future<void> _requestCamera() async {
    final status = await Permission.camera.request();
    if (!mounted) return;
    setState(() => _cameraGranted = status.isGranted);
  }

  Future<void> _requestLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (!mounted) return;
    setState(() {
      _locationGranted = permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always;
    });
  }

  Future<void> _onContinue() async {
    if (_continuing) return;
    setState(() => _continuing = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('permissions_onboarding_shown', true);
    if (!mounted) return;
    // By the time we reach Permissions, voiceMode is already known — either
    // decided on Education (Pashto/Dari) or fixed to false (English, which
    // skips Education) — so Continue always goes straight to Introduction.
    Navigator.pushNamed(
      context,
      '/introduction',
      arguments: {
        'language': widget.language,
        'voiceMode': widget.voiceMode,
      },
    );
  }

  // ── Strings ─────────────────────────────────────────────────────────────

  String get _title {
    switch (widget.language) {
      case 'ps': return 'د اپلیکیشن اجازې';
      case 'fa': return 'مجوزهای برنامه';
      default:   return 'App Permissions';
    }
  }

  String get _subtitle {
    switch (widget.language) {
      case 'ps': return 'KarYab ته د سم کار لپاره یو څو اجازو ته اړتیا ده';
      case 'fa': return 'KarYab برای کار درست به چند مجوز نیاز دارد';
      default:   return 'KarYab needs a few permissions to work properly';
    }
  }

  String get _cameraTitle {
    switch (widget.language) {
      case 'ps': return 'د کیمرې لاسرسی';
      case 'fa': return 'دسترسی به دوربین';
      default:   return 'Camera Access';
    }
  }

  String get _cameraDesc {
    switch (widget.language) {
      case 'ps': return 'ستاسو د CV لپاره د عکس اخیستلو لپاره';
      case 'fa': return 'برای گرفتن عکس برای CV شما';
      default:   return 'To take a photo for your CV';
    }
  }

  String get _locationTitle {
    switch (widget.language) {
      case 'ps': return 'د موقعیت لاسرسی';
      case 'fa': return 'دسترسی به موقعیت مکانی';
      default:   return 'Location Access';
    }
  }

  String get _locationDesc {
    switch (widget.language) {
      case 'ps': return 'ستاسو نژدې کارونو او کورسونو موندلو لپاره';
      case 'fa': return 'برای یافتن کارها و دوره‌های نزدیک شما';
      default:   return 'To find jobs and courses near you';
    }
  }

  String get _continueLabel {
    switch (widget.language) {
      case 'ps': return 'دوام';
      case 'fa': return 'ادامه';
      default:   return 'Continue';
    }
  }

  String get _allowLabel {
    switch (widget.language) {
      case 'ps': return 'اجازه';
      case 'fa': return 'اجازه';
      default:   return 'Allow';
    }
  }

  // Spoken explanations for the simplified uneducated (voiceMode == true)
  // buttons below — voiceMode is only ever true for Pashto/Dari (English
  // always forces the educated interface), so no English fallback is
  // needed here.
  String get _cameraSpeakText {
    switch (widget.language) {
      case 'ps': return 'دا تڼۍ کیمرې ته اجازه ورکوي';
      case 'fa': return 'این دکمه اجازه دوربین را می‌دهد';
      default:   return _cameraTitle;
    }
  }

  String get _locationSpeakText {
    switch (widget.language) {
      case 'ps': return 'دا تڼۍ ستاسو موقعیت ته اجازه ورکوي';
      case 'fa': return 'این دکمه اجازه موقعیت مکانی را می‌دهد';
      default:   return _locationTitle;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      child: Scaffold(
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
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 430),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              width: 72,
                              height: 72,
                              alignment: Alignment.center,
                              decoration: const BoxDecoration(
                                color: Color(0xFFEAFBE9),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.shield_outlined,
                                color: green,
                                size: 40,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Directionality(
                              textDirection:
                                  _isRtl ? TextDirection.rtl : TextDirection.ltr,
                              child: Text(
                                _title,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: navy,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  height: 1.2,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Directionality(
                              textDirection:
                                  _isRtl ? TextDirection.rtl : TextDirection.ltr,
                              child: Text(
                                _subtitle,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFF65738A),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  height: 1.4,
                                ),
                              ),
                            ),
                            const SizedBox(height: 22),
                            if (widget.voiceMode) ...[
                              _BigPermissionButton(
                                icon: Icons.camera_alt_rounded,
                                label: _cameraTitle,
                                granted: _cameraGranted,
                                speakText: _cameraSpeakText,
                                language: widget.language,
                                onTap: _requestCamera,
                              ),
                              const SizedBox(height: 14),
                              _BigPermissionButton(
                                icon: Icons.location_on_rounded,
                                label: _locationTitle,
                                granted: _locationGranted,
                                speakText: _locationSpeakText,
                                language: widget.language,
                                onTap: _requestLocation,
                              ),
                            ] else ...[
                              _PermissionCard(
                                icon: Icons.camera_alt_rounded,
                                title: _cameraTitle,
                                description: _cameraDesc,
                                allowLabel: _allowLabel,
                                granted: _cameraGranted,
                                isRtl: _isRtl,
                                onTap: _requestCamera,
                              ),
                              const SizedBox(height: 12),
                              _PermissionCard(
                                icon: Icons.location_on_rounded,
                                title: _locationTitle,
                                description: _locationDesc,
                                allowLabel: _allowLabel,
                                granted: _locationGranted,
                                isRtl: _isRtl,
                                onTap: _requestLocation,
                              ),
                            ],
                            const SizedBox(height: 24),
                            _ContinueButton(
                              label: _continueLabel,
                              onTap: _onContinue,
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
      ),
    );
  }
}

// ── Permission card ───────────────────────────────────────────────────────────

class _PermissionCard extends StatelessWidget {
  static const Color navy  = Color(0xFF091733);
  static const Color green = Color(0xFF39EA2B);

  final IconData icon;
  final String title;
  final String description;
  final String allowLabel;
  final bool granted;
  final bool isRtl;
  final VoidCallback onTap;

  const _PermissionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.allowLabel,
    required this.granted,
    required this.isRtl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _GlassSurface(
      borderRadius: 20,
      padding: const EdgeInsets.all(14),
      shadowOpacity: 0.08,
      child: Row(
        textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: granted ? const Color(0xFFEAFBE9) : const Color(0xFFEBF3FF),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: granted ? green : const Color(0xFF2D6BE4),
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  isRtl ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
                  style: const TextStyle(
                    color: navy,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
                  style: const TextStyle(
                    color: Color(0xFF65738A),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: granted ? null : onTap,
            child: granted
                ? const CircleAvatar(
                    radius: 15,
                    backgroundColor: green,
                    child: Icon(Icons.check_rounded,
                        color: Colors.white, size: 18),
                  )
                : Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: navy,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(
                      allowLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Big permission button (uneducated / voiceMode == true) ────────────────────
// One-tap, icon-only, no paragraph description — matches the simplified,
// highly-visual pattern already used elsewhere for uneducated users.

class _BigPermissionButton extends StatelessWidget {
  static const Color navy  = Color(0xFF091733);
  static const Color green = Color(0xFF39EA2B);

  final IconData icon;
  final String label;
  final bool granted;
  final String speakText;
  final String language;
  final VoidCallback onTap;

  const _BigPermissionButton({
    required this.icon,
    required this.label,
    required this.granted,
    required this.speakText,
    required this.language,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: granted ? null : onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 104,
              decoration: BoxDecoration(
                color: granted
                    ? const Color(0xFFEAFBE9)
                    : Colors.white.withOpacity(0.85),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: granted ? green : Colors.white.withOpacity(0.9),
                  width: granted ? 2.2 : 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.10),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    granted ? Icons.check_circle_rounded : icon,
                    color: granted ? green : navy,
                    size: 42,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: navy,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: () => TtsService().speak(speakText, language),
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFFEAFBE9),
              shape: BoxShape.circle,
              border: Border.all(color: green.withOpacity(0.4)),
            ),
            child: const Icon(Icons.volume_up_rounded, color: green, size: 24),
          ),
        ),
      ],
    );
  }
}

// ── Continue button ───────────────────────────────────────────────────────────

class _ContinueButton extends StatelessWidget {
  static const Color green = Color(0xFF39EA2B);

  final String label;
  final VoidCallback onTap;

  const _ContinueButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
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
          onTap: onTap,
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
    );
  }
}

// ── Background glow (matches other onboarding screens) ────────────────────────

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

// ── Glass surface (matches other onboarding screens) ──────────────────────────

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
