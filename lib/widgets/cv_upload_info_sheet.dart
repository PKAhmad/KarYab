import 'package:flutter/material.dart';

import '../services/tts_service.dart';

/// Bottom sheet collecting name/phone/email after a user picks a CV file to
/// upload, so the cover-letter flow has contact details to work with.
class CvUploadInfoSheet extends StatefulWidget {
  final String language;
  final bool voiceMode;
  final void Function(String name, String phone, String email) onComplete;

  const CvUploadInfoSheet({
    super.key,
    required this.language,
    required this.voiceMode,
    required this.onComplete,
  });

  @override
  State<CvUploadInfoSheet> createState() => _CvUploadInfoSheetState();
}

class _CvUploadInfoSheetState extends State<CvUploadInfoSheet> {
  static const Color _navy = Color(0xFF091733);
  static const Color _green = Color(0xFF39EA2B);
  static const Color _muted = Color(0xFF65738A);

  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  bool get _isRtl => widget.language == 'ps' || widget.language == 'fa';

  @override
  void initState() {
    super.initState();
    if (_isRtl) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        TtsService().speak(_titleText, widget.language);
      });
    }
  }

  @override
  void dispose() {
    TtsService().stop();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  String get _titleText {
    switch (widget.language) {
      case 'ps':
        return 'د کور لیک لپاره یو څو معلومات';
      case 'fa':
        return 'چند جزئیات برای نامه پوششی';
      default:
        return 'A few details for your cover letter';
    }
  }

  String get _nameLabelText {
    switch (widget.language) {
      case 'ps':
        return 'بشپړ نوم';
      case 'fa':
        return 'نام کامل';
      default:
        return 'Full Name';
    }
  }

  String get _phoneLabelText {
    switch (widget.language) {
      case 'ps':
        return 'تیلیفون';
      case 'fa':
        return 'تلفن';
      default:
        return 'Phone';
    }
  }

  String get _emailLabelText {
    switch (widget.language) {
      case 'ps':
        return 'ایمیل';
      case 'fa':
        return 'ایمیل';
      default:
        return 'Email';
    }
  }

  String get _confirmLabel {
    switch (widget.language) {
      case 'ps':
        return 'خوندي کړئ او دوام ورکړئ';
      case 'fa':
        return 'ذخیره و ادامه';
      default:
        return 'Save & Continue';
    }
  }

  String get _cancelLabel {
    switch (widget.language) {
      case 'ps':
        return 'لغوه کړئ';
      case 'fa':
        return 'لغو';
      default:
        return 'Cancel';
    }
  }

  void _confirm() {
    final name = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    if (name.isEmpty || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          widget.language == 'ps'
              ? 'نوم او تیلیفون ډک کړئ'
              : widget.language == 'fa'
                  ? 'نام و تلفن را وارد کنید'
                  : 'Please enter your name and phone number',
        ),
        backgroundColor: _navy,
      ));
      return;
    }
    widget.onComplete(name, phone, email);
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    TextInputType keyboardType = TextInputType.text,
  }) {
    final double vertPad = widget.voiceMode ? 18.0 : 14.0;
    final double fontSize = widget.voiceMode ? 16.0 : 14.0;
    return Column(
      crossAxisAlignment:
          _isRtl ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Row(
          textDirection: _isRtl ? TextDirection.rtl : TextDirection.ltr,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: _navy,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (widget.voiceMode && _isRtl) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => TtsService().speak(label, widget.language),
                child: const Icon(Icons.volume_up_rounded,
                    color: _green, size: 18),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          textDirection: _isRtl ? TextDirection.rtl : TextDirection.ltr,
          style: TextStyle(color: _navy, fontSize: fontSize),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            contentPadding:
                EdgeInsets.symmetric(horizontal: 16, vertical: vertPad),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300, width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _green, width: 2),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: _isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF7FAFF),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            MediaQuery.of(context).viewInsets.bottom + 32,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD1D9E6),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                textDirection: _isRtl ? TextDirection.rtl : TextDirection.ltr,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(
                      color: Color(0xFFEAFBE9),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.description_rounded,
                        color: _green, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _titleText,
                      style: const TextStyle(
                        color: _navy,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        height: 1.3,
                      ),
                    ),
                  ),
                  if (_isRtl) ...[
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () =>
                          TtsService().speak(_titleText, widget.language),
                      child: const Icon(Icons.volume_up_rounded,
                          color: _green, size: 22),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 24),
              _buildField(controller: _nameCtrl, label: _nameLabelText),
              const SizedBox(height: 16),
              _buildField(
                controller: _phoneCtrl,
                label: _phoneLabelText,
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              _buildField(
                controller: _emailCtrl,
                label: _emailLabelText,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 28),
              GestureDetector(
                onTap: _confirm,
                child: Container(
                  width: double.infinity,
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF081532), Color(0xFF07112B)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF07112B).withOpacity(0.30),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      _confirmLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Center(
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Text(
                    _cancelLabel,
                    style: TextStyle(
                      color: _muted,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      decoration: TextDecoration.underline,
                      decorationColor: _muted,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
