import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/app_colors.dart';

class ApplyScreen extends StatelessWidget {
  final String jobTitle;
  final String companyName;
  final String companyAddress;
  final String redirectUrl;
  final String language;
  final bool voiceMode;
  final String? userName;

  const ApplyScreen({
    super.key,
    required this.jobTitle,
    required this.companyName,
    this.companyAddress = '',
    this.redirectUrl = '',
    required this.language,
    this.voiceMode = false,
    this.userName,
  });

  bool get _isRtl => language == 'ps' || language == 'fa';

  // ── Localised strings ──────────────────────────────────────────────────────

  String get _noEmailMsg {
    switch (language) {
      case 'ps':
        return 'ایمیل ونه موندل شو. تاسو کولی شئ مستقیم دی کمپنی ادرس ته لاړ شی او هلته غوښتنه وکړئ';
      case 'fa':
        return 'ایمیل یافت نشد. می‌توانید مستقیماً در این مکان درخواست دهید.';
      default:
        return 'No email available. Go to this company in person with your printed CV.';
    }
  }

  String get _openMapsLabel {
    switch (language) {
      case 'ps': return 'په ګوګل نقشه کې پرانیستل';
      case 'fa': return 'باز کردن در Google Maps';
      default:   return 'Open in Google Maps';
    }
  }

  String get _printCvLabel {
    switch (language) {
      case 'ps': return 'زما CV پرینټ کړئ';
      case 'fa': return 'CV من را چاپ کنید';
      default:   return 'Print My CV';
    }
  }

  String get _applyOnlineLabel {
    switch (language) {
      case 'ps': return 'آنلاین غوښتنه وکړئ';
      case 'fa': return 'درخواست آنلاین';
      default:   return 'Apply Online';
    }
  }

  String get _viewOnMapLabel {
    switch (language) {
      case 'ps': return 'نقشه کې وګورئ';
      case 'fa': return 'مشاهده روی نقشه';
      default:   return 'View on Map';
    }
  }

  String get _tipsTitleLabel {
    switch (language) {
      case 'ps': return 'د مستقیم غوښتنې لپاره لارښوونې:';
      case 'fa': return 'نکات برای درخواست حضوری:';
      default:   return 'Tips for applying in person:';
    }
  }

  List<String> get _tips {
    switch (language) {
      case 'ps':
        return [
          'د خپل CV چاپ شوې کاپیګانې راوړئ',
          'سمه او مسلکي جامې واغوندئ',
          'د مدیر سره د خبرو غوښتنه وکړئ',
          'سهار د ۹-۱۱ بجو ترمنځ لاړ شئ',
        ];
      case 'fa':
        return [
          'نسخه‌های چاپ شده CV خود را بیاورید',
          'لباس مرتب و حرفه‌ای بپوشید',
          'بخواهید با مدیر صحبت کنید',
          'صبح بین ساعت ۹ تا ۱۱ بروید',
        ];
      default:
        return [
          'Bring printed copies of your CV',
          'Dress neatly and professionally',
          'Ask to speak with the manager',
          'Go in the morning between 9-11am',
        ];
    }
  }

  String get _coverLetter {
    final name = (userName != null && userName!.isNotEmpty)
        ? userName!
        : 'Ihr Bewerber';
    return 'Sehr geehrte Damen und Herren,\n\n'
        'hiermit bewerbe ich mich auf die ausgeschriebene \n'
        'Stelle als $jobTitle in Ihrem Unternehmen.\n\n'
        'Ich bin motiviert, zuverlässig und lernbereit. \n'
        'Ich freue mich auf die Möglichkeit, mich \n'
        'persönlich vorzustellen.\n\n'
        'Mit freundlichen Grüßen,\n'
        '$name';
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Uri get _mapsUri {
    final q = Uri.encodeComponent('$companyName $companyAddress');
    return Uri.parse('https://www.google.com/maps/search/$q');
  }

  Future<void> _launchMaps(BuildContext context) async {
    if (!await launchUrl(_mapsUri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) _snack(context, 'Could not open Maps');
    }
  }

  Future<void> _launchRedirectUrl(BuildContext context) async {
    if (redirectUrl.isEmpty) {
      _snack(context, 'No online application link available');
      return;
    }
    final uri = Uri.tryParse(redirectUrl);
    if (uri == null ||
        !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) _snack(context, 'Could not open URL');
    }
  }

  void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.surface,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: _isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textPrimary,
          automaticallyImplyLeading: false,
          leading: IconButton(
            icon: const Icon(Icons.home_rounded, color: AppColors.accent),
            onPressed: () => Navigator.pushNamedAndRemoveUntil(
              context,
              '/',
              (_) => false,
            ),
          ),
          title: Text(
            jobTitle,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        body: voiceMode
            ? _buildVoiceMode(context)
            : _buildEducatedMode(context),
      ),
    );
  }

  // ── Voice mode (uneducated) ────────────────────────────────────────────────

  Widget _buildVoiceMode(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
      child: Column(
        crossAxisAlignment:
            _isRtl ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          // Info icon
          Center(
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.accentGlow,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.accent, width: 2),
              ),
              child: const Icon(
                Icons.info_outline_rounded,
                color: AppColors.accent,
                size: 40,
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Message card with speaker button
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.accent.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Row(
              textDirection:
                  _isRtl ? TextDirection.rtl : TextDirection.ltr,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    _noEmailMsg,
                    textDirection:
                        _isRtl ? TextDirection.rtl : TextDirection.ltr,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      height: 1.6,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () => _snack(context, _noEmailMsg),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.accentGlow,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: AppColors.accentDim, width: 1),
                    ),
                    child: const Icon(
                      Icons.volume_up_rounded,
                      color: AppColors.accent,
                      size: 22,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Company info card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0x1AFFFFFF), width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  companyName,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                    color: AppColors.accent,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (companyAddress.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    textDirection: TextDirection.ltr,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.location_on_rounded,
                          color: AppColors.textMuted, size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          companyAddress,
                          textDirection: TextDirection.ltr,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Open in Google Maps — neon green filled, full width
          GestureDetector(
            onTap: () => _launchMaps(context),
            child: Container(
              width: double.infinity,
              height: 60,
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.map_rounded,
                      color: Colors.black, size: 22),
                  const SizedBox(width: 10),
                  Text(
                    _openMapsLabel,
                    textDirection:
                        _isRtl ? TextDirection.rtl : TextDirection.ltr,
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Print My CV — outlined, full width
          GestureDetector(
            onTap: () => Navigator.pushNamed(context, '/cv_preview'),
            child: Container(
              width: double.infinity,
              height: 60,
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.accentDim, width: 1.5),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.print_rounded,
                      color: AppColors.accent, size: 22),
                  const SizedBox(width: 10),
                  Text(
                    _printCvLabel,
                    textDirection:
                        _isRtl ? TextDirection.rtl : TextDirection.ltr,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),

          // Tips card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0x1AFFFFFF), width: 1),
            ),
            child: Column(
              crossAxisAlignment:
                  _isRtl ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Text(
                  _tipsTitleLabel,
                  textDirection:
                      _isRtl ? TextDirection.rtl : TextDirection.ltr,
                  style: const TextStyle(
                    color: AppColors.accent,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                ..._tips.map(
                  (tip) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      textDirection:
                          _isRtl ? TextDirection.rtl : TextDirection.ltr,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '• ',
                          style: TextStyle(
                              color: AppColors.accent, fontSize: 14),
                        ),
                        Expanded(
                          child: Text(
                            tip,
                            textDirection: _isRtl
                                ? TextDirection.rtl
                                : TextDirection.ltr,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 14,
                              height: 1.4,
                            ),
                          ),
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

  // ── Educated mode ──────────────────────────────────────────────────────────

  Widget _buildEducatedMode(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Company + job title
          Text(
            companyName,
            style: const TextStyle(
              color: AppColors.accent,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            jobTitle,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 28),

          // Apply Online + View on Map side by side
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _launchRedirectUrl(context),
                  child: Container(
                    height: 54,
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.open_in_browser_rounded,
                            color: Colors.black, size: 20),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            _applyOnlineLabel,
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () => _launchMaps(context),
                  child: Container(
                    height: 54,
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: AppColors.accentDim, width: 1.5),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.map_rounded,
                            color: AppColors.accent, size: 20),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            _viewOnMapLabel,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),

          // Cover letter card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0x1AFFFFFF), width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Anschreiben',
                        style: TextStyle(
                          color: AppColors.accent,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(
                            ClipboardData(text: _coverLetter));
                        _snack(context, 'Copied to clipboard');
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.accentGlow,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: AppColors.accentDim, width: 1),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.copy_rounded,
                                color: AppColors.accent, size: 14),
                            SizedBox(width: 4),
                            Text(
                              'Copy',
                              style: TextStyle(
                                color: AppColors.accent,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  _coverLetter,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    height: 1.7,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
