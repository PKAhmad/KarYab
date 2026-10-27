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
import '../utils/pdf_save_helper.dart';
import '../widgets/document_template_picker.dart';
import '../ui/karyab_ui.dart';

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
  static const Color _navy  = KColors.navy;
  static const Color _green = KColors.green;

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
      final saved = await savePdfToDownloads(bytes, _pdfFilename);

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
    kSnack(context, msg);
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
      backgroundColor: KColors.pageBase,
      body: Stack(
        children: [
          const KBackgroundGlow(),
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
          KNavButton(
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
          KNavButton(icon: Icons.home_rounded, onTap: _goHome),
        ],
      ),
    );
  }

  // ── Edit bar (reopens the questionnaire, pre-filled) ──────────────────────

  Widget _buildEditBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        width: double.infinity,
        child: KGlassCard(
          borderRadius: 16,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          onTap: _editAnswers,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.edit_rounded, color: KColors.greenDark, size: 18),
              const SizedBox(width: 8),
              Text(
                _editLabel,
                style: const TextStyle(
                  color: KColors.greenDark,
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
    return KGlassSurface(
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
                  color: KColors.mint,
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
              KGlassCard(
                borderRadius: 20,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                onTap: _pickCvTemplate,
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
          Stack(
            children: [
              KPrimaryCta(
                icon: Icons.download_rounded,
                label: _downloadLabel,
                isRtl: (_lang == 'ps' || _lang == 'fa'),
                isSelected: false,
                onTap: () {
                if (!_saving) _download();
              },
              ),
              if (_saving)
                Positioned.directional(
                  textDirection: (_lang == 'ps' || _lang == 'fa') ? TextDirection.rtl : TextDirection.ltr,
                  start: 8,
                  top: 13,
                  child: Container(
                    width: 38,
                    height: 38,
                    padding: const EdgeInsets.all(9),
                    decoration: const BoxDecoration(
                      color: KColors.ctaStart,
                      shape: BoxShape.circle,
                    ),
                    child: const CircularProgressIndicator(
                        color: KColors.green, strokeWidth: 2.5),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Ausbildung Postings (bottom CTA, relocated from the header) ───────────

  Widget _buildAusbildungPostingsButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: KGlassCard(
        borderRadius: 22,
        onTap: _goAusbildungPostings,
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
