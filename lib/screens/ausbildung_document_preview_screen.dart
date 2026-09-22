import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../models/document_template.dart';
import '../models/user_profile.dart';
import '../services/analytics_service.dart';
import '../services/cv_pdf_generator.dart';
import '../utils/navigation_helpers.dart';
import '../widgets/document_template_picker.dart';

import 'ausbildung_cv_questionnaire_screen.dart';

// Deliberately independent from the regular home-screen CV flow's
// 'selected_cv_template_regular' key — the Ausbildung flow's template
// choice must never share state with it.
const String kAusbildungCvTemplatePrefsKey = 'selected_cv_template_ausbildung';

// ─────────────────────────────────────────────────────────────────────────────
// Ausbildung document preview — shown after the questionnaire/saved profile
// + Schulabschluss step are complete. CV section only (fully functional —
// inline "Choose Template" + live preview + download); Cover Letter and
// Deckblatt moved to ChooseCvTypeScreen as their own top-level, type-agnostic
// creation options (see letter_document_screen.dart).
// ─────────────────────────────────────────────────────────────────────────────

class AusbildungDocumentPreviewScreen extends StatefulWidget {
  final UserProfile profile;
  final String language;
  // True when embedded inside the "My CV" toggle screen
  // (introduction_screen.dart's _MyCvScreen), which supplies its own
  // shared header/background - this screen then renders only its body
  // content (edit bar + CV section), no duplicate header/background.
  final bool embedded;

  const AusbildungDocumentPreviewScreen({
    super.key,
    required this.profile,
    required this.language,
    this.embedded = false,
  });

  @override
  State<AusbildungDocumentPreviewScreen> createState() =>
      _AusbildungDocumentPreviewScreenState();
}

class _AusbildungDocumentPreviewScreenState
    extends State<AusbildungDocumentPreviewScreen> {
  static const Color _navy  = Color(0xFF091733);
  static const Color _green = Color(0xFF39EA2B);

  late String _lang;
  DocumentTemplate _cvTemplate = DocumentTemplate.atsBlue;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _lang = widget.language;
    AnalyticsService().logScreen('ausbildung_documents');
    _loadCvTemplate();
  }

  Future<void> _loadCvTemplate() async {
    final t = await loadSelectedDocumentTemplate(kAusbildungCvTemplatePrefsKey);
    if (mounted) setState(() => _cvTemplate = t);
  }

  Future<void> _pickCvTemplate() async {
    final chosen = await showDocumentTemplatePicker(context, current: _cvTemplate);
    if (!mounted || chosen == _cvTemplate) return;
    setState(() => _cvTemplate = chosen);
    await saveSelectedDocumentTemplate(kAusbildungCvTemplatePrefsKey, chosen);
  }

  // Same destination every other "Home" button in the app uses — clears the
  // back stack (questionnaire/preview chain included) down to Introduction.
  void _goHome() =>
      goHomeToIntroduction(context, language: _lang, voiceMode: false);

  void _goAusbildungPostings() => Navigator.pushNamed(
        context,
        '/ausbildung',
        arguments: {'language': _lang, 'voiceMode': false},
      );

  // Pushes a fresh questionnaire instance rather than relying on Navigator.pop
  // back to a still-alive previous route, so this works regardless of how
  // this preview screen was reached (just-submitted flow or "View CV" from
  // Home). AusbildungCvQuestionnaireScreen re-reads 'saved_profile' itself on
  // init, so no data needs to be passed through here.
  void _editAnswers() => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AusbildungCvQuestionnaireScreen(
              language: _lang, isEditMode: true),
        ),
      );

  Future<Uint8List> _buildCvBytes(PdfPageFormat format) =>
      generateCv(widget.profile, _cvTemplate, isAusbildungCv: true);

  String get _pdfFilename {
    final name = widget.profile.fullName.replaceAll(' ', '_');
    return 'Ausbildung_Lebenslauf_$name.pdf';
  }

  Future<void> _download() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final bytes =
          await generateCv(widget.profile, _cvTemplate, isAusbildungCv: true);
      bool saved = false;
      try {
        final dir = Directory('/storage/emulated/0/Download');
        if (!await dir.exists()) await dir.create(recursive: true);
        await File('${dir.path}/$_pdfFilename').writeAsBytes(bytes);
        saved = true;
      } catch (_) {}

      if (!mounted) return;
      if (saved) {
        _snack(_savedMsg);
      } else {
        await Printing.sharePdf(bytes: bytes, filename: _pdfFilename);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: _navy,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  String get _titleLabel {
    switch (_lang) {
      case 'ps': return 'د زده کړې کار اسناد';
      case 'fa': return 'اسناد کارآموزی';
      default:   return 'Ausbildung Documents';
    }
  }

  String get _cvSectionTitle {
    switch (_lang) {
      case 'ps': return 'CV';
      case 'fa': return 'CV';
      default:   return 'CV';
    }
  }

  String get _chooseTemplateLabel {
    switch (_lang) {
      case 'ps': return 'کینډۍ وټاکئ';
      case 'fa': return 'انتخاب قالب';
      default:   return 'Choose Template';
    }
  }

  String get _downloadLabel {
    switch (_lang) {
      case 'ps': return 'ډاونلوډ کړئ';
      case 'fa': return 'دانلود';
      default:   return 'Download CV (PDF)';
    }
  }

  String get _savedMsg {
    switch (_lang) {
      case 'ps': return 'CV په ډاونلوډ کې خوندي شو';
      case 'fa': return 'CV در دانلودها ذخیره شد';
      default:   return 'CV saved to Downloads';
    }
  }

  String get _editLabel {
    switch (_lang) {
      case 'ps': return 'ځوابونه سمول';
      case 'fa': return 'ویرایش پاسخ‌ها';
      default:   return 'Edit answers';
    }
  }

  String get _postingsLabel {
    switch (_lang) {
      case 'ps': return 'د زده کړې دندې وګورئ';
      case 'fa': return 'مشاهده آگهی‌های کارآموزی';
      default:   return 'Ausbildung Postings';
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = SafeArea(
      top: !widget.embedded,
      child: Column(
        children: [
          if (!widget.embedded) _buildHeader(),
          const SizedBox(height: 4),
          _buildEditBar(),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: Column(
                children: [
                  _buildCvSection(),
                  const SizedBox(height: 14),
                  _buildAusbildungPostingsButton(),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    if (widget.embedded) {
      return body;
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFF),
      body: Stack(
        children: [
          const _BackgroundGlow(),
          body,
        ],
      ),
    );
  }

  Widget _buildHeader() {
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
              _titleLabel,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _navy,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          _NavBtn(icon: Icons.home_rounded, onTap: _goHome),
        ],
      ),
    );
  }

  // ── Edit bar (reopens the questionnaire, pre-filled) ──────────────────────

  Widget _buildEditBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        onTap: _editAnswers,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFEAFBE9),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _green.withOpacity(0.5), width: 1.2),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.edit_rounded, color: Color(0xFF0E7A20), size: 18),
              const SizedBox(width: 8),
              Text(
                _editLabel,
                style: const TextStyle(
                  color: Color(0xFF0E7A20),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── CV section (fully functional) ─────────────────────────────────────────

  Widget _buildCvSection() {
    return _GlassSurface(
      borderRadius: 20,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  color: Color(0xFFEAFBE9),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.description_rounded,
                    color: _green, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _cvSectionTitle,
                  style: const TextStyle(
                    color: _navy,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              GestureDetector(
                onTap: _pickCvTemplate,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAFBE9),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _green.withOpacity(0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$_chooseTemplateLabel: ${_cvTemplate.displayName}',
                        style: const TextStyle(
                          color: _navy,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 3),
                      const Icon(Icons.keyboard_arrow_down_rounded,
                          color: _green, size: 15),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              height: 440,
              child: PdfPreview(
                key: ValueKey(_cvTemplate),
                build: _buildCvBytes,
                canChangeOrientation: false,
                canChangePageFormat: false,
                canDebug: false,
                pdfFileName: _pdfFilename,
                loadingWidget: const Center(
                  child: CircularProgressIndicator(color: _green),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _saving ? null : _download,
            child: Container(
              width: double.infinity,
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                gradient: const LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [Color(0xFF081532), Color(0xFF07112B)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF07112B).withOpacity(0.30),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_saving)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: _green, strokeWidth: 2.5),
                    )
                  else
                    const Icon(Icons.download_rounded,
                        color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    _downloadLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Ausbildung Postings (bottom CTA, relocated from the header) ───────────

  Widget _buildAusbildungPostingsButton() {
    return GestureDetector(
      onTap: _goAusbildungPostings,
      child: Container(
        width: double.infinity,
        height: 52,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          color: _green,
          boxShadow: [
            BoxShadow(
              color: _green.withOpacity(0.35),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.school_rounded, color: _navy, size: 18),
            const SizedBox(width: 8),
            Text(
              _postingsLabel,
              style: const TextStyle(
                color: _navy,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
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
