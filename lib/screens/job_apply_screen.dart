import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'in_app_browser_screen.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';

import '../models/user_profile.dart';
import '../services/analytics_service.dart';
import '../services/tts_service.dart';
import '../utils/navigation_helpers.dart';
import 'letter_document_screen.dart';

// ── Screen ────────────────────────────────────────────────────────────────────

class JobApplyScreen extends StatefulWidget {
  final String jobTitle;
  final String companyName;
  final String jobLocation;
  final String formUrl;
  final String companyPhone;
  final String companyEmail;
  final String companyWebsite;
  final String refnr;
  final String language;
  final bool voiceMode;
  final String jobType;
  // True when this screen was opened for an Ausbildung posting (currently
  // only ausbildung_screen.dart sets this) - swaps the static inline cover
  // letter preview for a "Cover Letter erstellen" button that routes into
  // the app's real Cover Letter Creation flow (LetterDocumentScreen),
  // pre-filled with this posting's title/company. Regular Job Finder
  // postings leave this false and keep the existing inline letter.
  final bool isAusbildung;

  const JobApplyScreen({
    super.key,
    required this.jobTitle,
    required this.companyName,
    required this.jobLocation,
    required this.formUrl,
    this.companyPhone = '',
    this.companyEmail = '',
    this.companyWebsite = '',
    this.refnr = '',
    required this.language,
    this.voiceMode = false,
    this.jobType = '',
    this.isAusbildung = false,
  });

  @override
  State<JobApplyScreen> createState() => _JobApplyScreenState();
}

class _JobApplyScreenState extends State<JobApplyScreen>
    with SingleTickerProviderStateMixin {
  // ── Design tokens ──────────────────────────────────────────────────────────

  static const Color _navy  = Color(0xFF091733);
  static const Color _green = Color(0xFF39EA2B);
  static const Color _muted = Color(0xFF65738A);

  // ── Highlight animation ────────────────────────────────────────────────────
  late AnimationController _highlightController;
  late Animation<double>   _highlightAnimation;
  bool _showHighlight = true;

  // ── User data from shared_preferences ─────────────────────────────────────

  String _userName   = '';
  String _userPhone  = '';
  String _userEmail  = '';
  String _userStreet = '';
  String _userCity   = '';
  String _userPostal = '';

  // ── Active language ────────────────────────────────────────────────────────

  late String _language;

  // ── From route arguments ───────────────────────────────────────────────────

  String _companyAddress = '';

  void _onSoundChange() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    AnalyticsService().logScreen('job_apply');
    TtsService().addListener(_onSoundChange);
    _language = widget.language;
    _loadUserData();

    _highlightController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..repeat(reverse: true);

    // FIX 8: minimum opacity raised from 0.5 so the dashed border stays
    // clearly visible throughout the pulse instead of nearly disappearing
    // at its low point.
    _highlightAnimation = Tween<double>(
      begin: 0.65,
      end: 1.0,
    ).animate(_highlightController);

    // The highlight loops indefinitely — no timed shutoff.

    // Only the PS/FA "how to apply" description voice plays automatically
    // on this screen; the job title/company name is not read aloud.
    if (_language == 'ps' || _language == 'fa') {
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted && TtsService().soundEnabled) {
          final text = _language == 'ps'
              ? 'تاسو کولای شئ له دوو لارو غوښتنه وکړئ: د آنلاین فورم له لارې یا مستقیم شرکت ادرس ته لاړ شئ'
              : 'می‌توانید به دو روش درخواست دهید: از طریق فرم آنلاین یا مستقیم به شرکت مراجعه کنید';
          TtsService().speak(text, _language);
        }
      });
    }
  }

  @override
  void dispose() {
    _highlightController.dispose();
    TtsService().stop();
    TtsService().removeListener(_onSoundChange);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, String>?;
    _companyAddress = args?['companyAddress'] ?? '';
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      final qName = prefs.getString('questionnaire_full_name') ?? '';
      _userName        = qName.isNotEmpty ? qName : (prefs.getString('user_name') ?? '');
      _userPhone       = prefs.getString('user_phone')       ?? '';
      _userEmail       = prefs.getString('user_email')       ?? '';
      _userStreet      = prefs.getString('user_street')      ?? '';
      _userCity        = prefs.getString('user_city')        ?? '';
      _userPostal      = prefs.getString('user_postal')      ?? '';
    });
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  bool get _isRtl => _language == 'ps' || _language == 'fa';

  // Inserted into the cover letter's opening paragraph right after the job
  // title, e.g. "... als Lagerhelfer in Vollzeit bei ...". Empty when no
  // job type was selected on the finder screen (Alle / null).
  String get _jobTypeSuffix {
    switch (widget.jobType) {
      case 'Vollzeit': return ' in Vollzeit';
      case 'Teilzeit': return ' in Teilzeit';
      case 'Minijob':  return ' auf Minijob-Basis';
      default:         return '';
    }
  }

  static const _germanMonths = [
    'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni',
    'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember',
  ];

  String get _germanDate {
    final now = DateTime.now();
    return '${now.day}. ${_germanMonths[now.month - 1]} ${now.year}';
  }

  String get _postalCity =>
      [_userPostal, _userCity].where((s) => s.isNotEmpty).join(' ');

  // FIX 5: never show a literal "[Stadt]" placeholder. Prefer the user's
  // own city; if their profile has none, fall back to the job listing's
  // own city rather than a bracketed placeholder.
  String get _displayCity =>
      _userCity.isNotEmpty ? _userCity : widget.jobLocation;

  // Date/city line for the cover letter — omits the city (and its comma)
  // entirely only if neither the user's city nor the job's location is
  // known, instead of ever showing an empty/placeholder city.
  String get _dateLine =>
      _displayCity.isEmpty ? _germanDate : '$_displayCity, $_germanDate';

  String get _displayName   => _userName.isEmpty   ? '[Ihr Name]'            : _userName;
  String get _displayPhone  => _userPhone.isEmpty  ? '[Telefonnummer]'       : _userPhone;
  String get _displayEmail  => _userEmail.isEmpty  ? '[E-Mail-Adresse]'      : _userEmail;
  String get _displayStreet => _userStreet.isEmpty ? '[Straße und Hausnummer]' : _userStreet;

  static String _safeUrl(String url) {
    if (url.isEmpty) return url;
    if (!url.startsWith('http')) return 'https://$url';
    return url;
  }

  static String _cleanPhone(String phone) {
    String clean = phone.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    if (clean.startsWith('0')) clean = '+49${clean.substring(1)}';
    return clean;
  }

  // ── Localised strings ──────────────────────────────────────────────────────

  String get _screenTitle {
    switch (_language) {
      case 'ps': return 'د کار غوښتنه';
      case 'fa': return 'درخواست کار';
      default:   return 'Apply for Job';
    }
  }

  String get _howToApplyTitle {
    switch (_language) {
      case 'ps': return 'تاسو غواړئ څنګه غوښتنه وکړئ؟';
      case 'fa': return 'چگونه می‌خواهید درخواست دهید؟';
      default:   return 'How would you like to apply?';
    }
  }

  String get _formTitle {
    switch (_language) {
      case 'ps': return 'د آنلاین فورم له لارې غوښتنه';
      case 'fa': return 'درخواست از طریق فرم آنلاین';
      default:   return 'Apply via Online Form';
    }
  }

  String get _formDesc {
    switch (_language) {
      case 'ps': return 'دا بټن تاسو د کار آنلاین فورم ته بیایي';
      case 'fa': return 'فرم درخواست رسمی را باز کنید';
      default:   return 'Open the official application form';
    }
  }

  String get _emailTitle {
    switch (_language) {
      case 'ps': return 'د بریښنالیک له لارې غوښتنه';
      case 'fa': return 'درخواست از طریق ایمیل';
      default:   return 'Apply via Email';
    }
  }

  String get _emailDesc {
    switch (_language) {
      case 'ps': return 'ستاسو CV بریښنالیک ته واستوئ';
      case 'fa': return 'CV و نامه پوششی خود را ایمیل کنید';
      default:   return 'Send your CV and cover letter by email';
    }
  }

  String get _phoneTitle {
    switch (_language) {
      case 'ps': return 'شرکت ته زنګ ووهئ';
      case 'fa': return 'تماس با شرکت';
      default:   return 'Call the Company';
    }
  }

  String get _phoneDesc {
    switch (_language) {
      case 'ps': return 'زنګ ووهئ او د دندې په اړه پوښتنه وکړئ';
      case 'fa': return 'زنگ بزنید و درباره موقعیت بپرسید';
      default:   return 'Call and ask about the position';
    }
  }

  String get _waTitle {
    switch (_language) {
      case 'ps': return 'د واټساپ له لارې CV واستوئ';
      case 'fa': return 'ارسال CV از طریق واتساپ';
      default:   return 'Send CV via WhatsApp';
    }
  }

  String get _waDesc {
    switch (_language) {
      case 'ps': return 'مستقیم يې واټساپ پيغام ورکړئ';
      case 'fa': return 'مستقیم در واتساپ پیام بدهید';
      default:   return 'Message them directly on WhatsApp';
    }
  }

  String get _waMessage {
    switch (_language) {
      case 'ps':
        return 'سلام، زه د ${widget.companyName} کمپني کې د ${widget.jobTitle} '
            'دندې لپاره لیوالتیا لرم. ایا کولی شئ د مرکې وخت راته وټاکئ؟';
      default:
        return 'Hello, I am interested in the position ${widget.jobTitle} at '
            '${widget.companyName}. I have attached my CV. '
            'When can I come for an interview?';
    }
  }

  String get _personTitle {
    switch (_language) {
      case 'ps': return 'د ادرس له لاری غوښتنه وکړی';
      case 'fa': return 'درخواست حضوری';
      default:   return 'Go to The Company Address';
    }
  }

  String get _personDesc {
    switch (_language) {
      case 'ps':
        return 'تاسو کولی شئ مستقیم دی کمپنی ادرس ته لاړ شی';
      case 'fa':
        return 'با CV چاپ شده مستقیماً به شرکت مراجعه کنید';
      default:
        return 'Go directly to the company with your printed CV and apply in person';
    }
  }

  String get _tipsTitle {
    switch (_language) {
      case 'ps': return 'لارښوونې:';
      case 'fa': return 'نکات:';
      default:   return 'Tips for applying in person:';
    }
  }

  List<String> get _tips {
    switch (_language) {
      case 'ps':
        return [
          'د خپل CV چاپ شوې کاپیګانې راوړئ',
          'سمه او مسلکي جامې واغوندئ',
          'د مدیر سره د خبرو غوښتنه وکړئ',
          'سهار د ۹-۱۱ بجو ترمنځ لاړ شئ',
        ];
      case 'fa':
        return [
          'نسخه‌های چاپی CV خود را بیاورید',
          'لباس مرتب بپوشید',
          'بخواهید با مدیر صحبت کنید',
          'صبح بین ۹ تا ۱۱ بروید',
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

  String get _coverLetterSectionTitle {
    switch (_language) {
      case 'ps': return 'د کار غوښتنې لیک';
      case 'fa': return 'نامه پوششی';
      default:   return 'Cover Letter (Anschreiben)';
    }
  }

  String get _copyLabel {
    switch (_language) {
      case 'ps': return 'کاپي';
      case 'fa': return 'کاپی';
      default:   return 'Copy';
    }
  }

  String get _copiedMsg {
    switch (_language) {
      case 'ps': return 'کاپي شو!';
      case 'fa': return 'کاپی شد!';
      default:   return 'Copied!';
    }
  }

  String get _downloadLabel {
    switch (_language) {
      case 'ps': return 'PDF ډاونلوډ';
      case 'fa': return 'دانلود PDF';
      default:   return 'Download PDF';
    }
  }

  String get _savedMsg {
    switch (_language) {
      case 'ps': return 'د غوښتنې لیک ډاونلوډ فولډر ته خوندي شو';
      case 'fa': return 'نامه پوششی در دانلودها ذخیره شد';
      default:   return 'Cover letter saved to Downloads';
    }
  }

  // ── isAusbildung cover-letter button strings ───────────────────────────────

  String get _coverLetterButtonDesc {
    switch (_language) {
      case 'ps': return 'د دې دندې لپاره خپل شخصي د پوښتنلیک لیک جوړ کړئ';
      case 'fa': return 'برای این موقعیت، نامه پوششی شخصی خود را بسازید';
      default:   return 'Create your own cover letter for this position.';
    }
  }

  String get _coverLetterButtonLabel {
    switch (_language) {
      case 'ps': return 'د دې دندې لپاره د پوښتنلیک لیک جوړ کړئ';
      case 'fa': return 'ایجاد نامه پوششی برای این شغل';
      case 'de': return 'Anschreiben für diese Stelle erstellen';
      default:   return 'Create cover letter for this job';
    }
  }

  String get _noProfileForLetterMsg {
    switch (_language) {
      case 'ps': return 'لومړی خپل شخصي معلومات د CV په جوړولو سره اضافه کړئ';
      case 'fa': return 'ابتدا با ساختن یک رزومه، اطلاعات شخصی خود را اضافه کنید';
      default:   return 'Please create a Job CV or Ausbildung CV first to add your details';
    }
  }

  // ── Cover letter plain text ────────────────────────────────────────────────

  String get _coverLetterPlainText {
    final postalCity = _postalCity;
    final addrLine   = _companyAddress.isNotEmpty ? '\n$_companyAddress' : '';
    return '${widget.companyName}\n'
        'z.Hd. Personalabteilung$addrLine\n\n'
        '$_displayName\n'
        '$_displayStreet\n'
        '${postalCity.isNotEmpty ? "$postalCity\n" : ""}'
        '$_displayPhone\n'
        '$_displayEmail\n\n'
        '$_dateLine\n\n'
        'Bewerbung als ${widget.jobTitle}\n\n'
        'Anschreiben\n\n'
        'Sehr geehrte Damen und Herren,\n\n'
        'mit großem Interesse habe ich Ihre Stellenanzeige für die Position '
        'als ${widget.jobTitle}$_jobTypeSuffix bei ${widget.companyName} gelesen. Hiermit '
        'bewerbe ich mich auf diese ausgeschriebene Stelle.\n\n'
        'Ich bin ein motivierter und zuverlässiger Mitarbeiter. Ich bringe '
        'praktische Erfahrung mit, arbeite gerne im Team und bin bereit, '
        'mich schnell in neue Aufgabenbereiche einzuarbeiten. Körperlich '
        'anspruchsvolle Tätigkeiten sind mir vertraut.\n\n'
        'Über eine Einladung zu einem persönlichen Vorstellungsgespräch '
        'würde ich mich sehr freuen. Meine Bewerbungsunterlagen, '
        'einschließlich meines Lebenslaufs, füge ich dieser Bewerbung bei.\n\n'
        'Mit freundlichen Grüßen,\n\n'
        '$_displayName';
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _preCoverLetterToTemp() async {
    try {
      final prefs  = await SharedPreferences.getInstance();
      final street = prefs.getString('user_street') ?? '';
      final postal = prefs.getString('user_postal') ?? '';
      final city   = prefs.getString('user_city')   ?? '';

      final font     = pw.Font.helvetica();
      final boldFont = pw.Font.helveticaBold();
      pw.TextStyle normal(double size) => pw.TextStyle(font: font, fontSize: size);
      pw.TextStyle bold(double size)   => pw.TextStyle(
          font: boldFont, fontSize: size, fontWeight: pw.FontWeight.bold);

      final postalCity    = [postal, city].where((s) => s.isNotEmpty).join(' ');
      final displayName   = _userName.isEmpty  ? '[Ihr Name]'             : _userName;
      final displayStreet = street.isEmpty     ? '[Straße und Hausnummer]': street;
      final displayPhone  = _userPhone.isEmpty ? '[Telefonnummer]'        : _userPhone;
      final displayEmail  = _userEmail.isEmpty ? '[E-Mail-Adresse]'       : _userEmail;
      // FIX 5: fall back to the job's own location rather than a
      // "[Stadt]" placeholder when the profile has no city saved.
      final displayCity = city.isNotEmpty ? city : widget.jobLocation;

      final now = DateTime.now();
      const months = [
        'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni',
        'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember',
      ];
      final germanDate = '${now.day}. ${months[now.month - 1]} ${now.year}';
      final dateLine =
          displayCity.isEmpty ? germanDate : '$displayCity, $germanDate';

      final doc = pw.Document();
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(48),
          build: (pw.Context ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(widget.companyName, style: bold(11)),
                        pw.Text('z.Hd. Personalabteilung', style: normal(10)),
                      ],
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(displayName,   style: bold(11)),
                        pw.Text(displayStreet, style: normal(10)),
                        if (postalCity.isNotEmpty)
                          pw.Text(postalCity,  style: normal(10)),
                        pw.Text(displayPhone,  style: normal(10)),
                        pw.Text(displayEmail,  style: normal(10)),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 20),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(dateLine, style: normal(10)),
              ),
              pw.SizedBox(height: 14),
              pw.Text('Bewerbung als ${widget.jobTitle}', style: bold(12)),
              pw.SizedBox(height: 10),
              pw.Center(child: pw.Text('Anschreiben', style: bold(16))),
              pw.SizedBox(height: 16),
              pw.Text(
                'Sehr geehrte Damen und Herren,\n\n'
                'mit großem Interesse habe ich Ihre Stellenanzeige für die '
                'Position als ${widget.jobTitle}$_jobTypeSuffix bei ${widget.companyName} '
                'gelesen. Hiermit bewerbe ich mich auf diese ausgeschriebene '
                'Stelle.\n\n'
                'Ich bin ein motivierter und zuverlässiger Mitarbeiter. Ich '
                'bringe praktische Erfahrung mit, arbeite gerne im Team und '
                'bin bereit, mich schnell in neue Aufgabenbereiche '
                'einzuarbeiten. Körperlich anspruchsvolle Tätigkeiten sind '
                'mir vertraut.\n\n'
                'Über eine Einladung zu einem persönlichen Vorstellungsgespräch '
                'würde ich mich sehr freuen. Meine Bewerbungsunterlagen, '
                'einschließlich meines Lebenslaufs, füge ich dieser Bewerbung '
                'bei.\n\n'
                'Mit freundlichen Grüßen,\n\n'
                '$displayName',
                style: normal(11).copyWith(lineSpacing: 3),
              ),
            ],
          ),
        ),
      );

      final bytes        = await doc.save();
      final tempDir      = await getTemporaryDirectory();
      final cleanCompany = widget.companyName
          .replaceAll(' ', '_')
          .replaceAll(RegExp(r'[^\w]'), '');
      final cleanJob = widget.jobTitle
          .replaceAll(RegExp(r'[^\w\s]'), '')
          .replaceAll(' ', '_');
      final coverPath =
          '${tempDir.path}/Anschreiben_${cleanCompany}_${cleanJob}.pdf';
      await File(coverPath).writeAsBytes(bytes);
      await prefs.setString('temp_cover_path', coverPath);
    } catch (_) {}
  }

  Future<void> _openForm(BuildContext context) async {
    AnalyticsService().logJobApply('online_form');
    _preCoverLetterToTemp();
    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _CaptchaGuideSheet(
        formUrl: widget.formUrl,
        jobTitle: widget.jobTitle,
        companyName: widget.companyName,
        userName: _userName,
        userPhone: _userPhone,
        userEmail: _userEmail,
        language: _language,
        jobType: widget.jobType,
        jobLocation: widget.jobLocation,
      ),
    );
  }

  Future<void> _openEmail(BuildContext context) async {
    final subject = Uri.encodeComponent(
        'Bewerbung: ${widget.jobTitle} - ${widget.companyName}');
    final body = Uri.encodeComponent(_coverLetterPlainText);
    final uri  = Uri.parse(
        'mailto:${widget.companyEmail}?subject=$subject&body=$body');
    if (!await launchUrl(uri)) {
      if (context.mounted) _snack(context, 'Could not open email app');
    }
  }

  Future<void> _callPhone(BuildContext context) async {
    AnalyticsService().logJobApply('phone');
    final uri = Uri.parse('tel:${widget.companyPhone}');
    if (!await launchUrl(uri)) {
      if (context.mounted) _snack(context, 'Could not open phone app');
    }
  }

  Future<void> _openWhatsApp(BuildContext context) async {
    AnalyticsService().logJobApply('whatsapp');
    final phone = _cleanPhone(widget.companyPhone).replaceAll('+', '');
    final msg   = Uri.encodeComponent(_waMessage);
    final uri   = Uri.parse('https://wa.me/$phone?text=$msg');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) _snack(context, 'Could not open WhatsApp');
    }
  }

  Future<void> _openMaps(BuildContext context) async {
    AnalyticsService().logJobApply('in_person');
    // FIX 6: lead with the precise street/PLZ/city when we have one,
    // rather than the company name. Google Maps' free-text /search/
    // endpoint can match a well-known business name to its own indexed
    // location (e.g. a chain's HQ) and ignore an address appended after
    // it — putting the specific job-site address first makes that the
    // dominant signal instead.
    final mapsQuery = _companyAddress.isNotEmpty
        ? '$_companyAddress ${widget.companyName}'
        : widget.companyName;
    final uri = Uri.parse(
        'https://www.google.com/maps/search/${Uri.encodeComponent(mapsQuery)}');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) _snack(context, 'Could not open Maps');
    }
  }

  void _copyToClipboard(BuildContext context) {
    Clipboard.setData(ClipboardData(text: _coverLetterPlainText));
    _snack(context, _copiedMsg);
  }

  String get _pdfErrorMsg {
    switch (_language) {
      case 'ps': return 'PDF خوندي نشو. بیا هڅه وکړئ.';
      case 'fa': return 'PDF ذخیره نشد. دوباره تلاش کنید.';
      default:   return 'Could not save PDF. Please try again.';
    }
  }

  static String _cleanFilename(String s) => s
      .replaceAll('/', '-')
      .replaceAll('\\', '-')
      .replaceAll('(', '')
      .replaceAll(')', '')
      .replaceAll(' ', '_')
      .replaceAll('*', '')
      .replaceAll(':', '')
      .replaceAll('?', '')
      .replaceAll('"', '')
      .replaceAll('<', '')
      .replaceAll('>', '')
      .replaceAll('|', '');

  Future<void> _downloadPdf() async {
    AnalyticsService().logCoverLetterDownloaded();
    try {
      final font     = pw.Font.helvetica();
      final boldFont = pw.Font.helveticaBold();

      pw.TextStyle normal(double size) =>
          pw.TextStyle(font: font, fontSize: size);
      pw.TextStyle bold(double size) =>
          pw.TextStyle(font: boldFont, fontSize: size,
              fontWeight: pw.FontWeight.bold);

      final doc        = pw.Document();
      final postalCity = _postalCity;

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(48),
          build: (pw.Context ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(widget.companyName, style: bold(11)),
                        pw.Text('z.Hd. Personalabteilung', style: normal(10)),
                        if (_companyAddress.isNotEmpty)
                          pw.Text(_companyAddress, style: normal(10)),
                      ],
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(_displayName, style: bold(11)),
                        pw.Text(_displayStreet, style: normal(10)),
                        if (postalCity.isNotEmpty)
                          pw.Text(postalCity, style: normal(10)),
                        pw.Text(_displayPhone, style: normal(10)),
                        pw.Text(_displayEmail, style: normal(10)),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 20),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(_dateLine, style: normal(10)),
              ),
              pw.SizedBox(height: 14),
              pw.Text('Bewerbung als ${widget.jobTitle}', style: bold(12)),
              pw.SizedBox(height: 10),
              pw.Center(
                child: pw.Text('Anschreiben', style: bold(16)),
              ),
              pw.SizedBox(height: 16),
              pw.Text(
                'Sehr geehrte Damen und Herren,\n\n'
                    'mit großem Interesse habe ich Ihre Stellenanzeige für die '
                    'Position als ${widget.jobTitle}$_jobTypeSuffix bei ${widget.companyName} '
                    'gelesen. Hiermit bewerbe ich mich auf diese ausgeschriebene '
                    'Stelle.\n\n'
                    'Ich bin ein motivierter und zuverlässiger Mitarbeiter. Ich '
                    'bringe praktische Erfahrung mit, arbeite gerne im Team und '
                    'bin bereit, mich schnell in neue Aufgabenbereiche '
                    'einzuarbeiten. Körperlich anspruchsvolle Tätigkeiten sind '
                    'mir vertraut.\n\n'
                    'Über eine Einladung zu einem persönlichen Vorstellungsgespräch '
                    'würde ich mich sehr freuen. Meine Bewerbungsunterlagen, '
                    'einschließlich meines Lebenslaufs, füge ich dieser Bewerbung '
                    'bei.\n\n'
                    'Mit freundlichen Grüßen,\n\n'
                    '$_displayName',
                style: normal(11).copyWith(lineSpacing: 3),
              ),
            ],
          ),
        ),
      );

      final bytes = await doc.save();

      const downloadPath = '/storage/emulated/0/Download';
      final downloadDir  = Directory(downloadPath);
      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
      }

      final cleanCompany = _cleanFilename(widget.companyName);
      final cleanJob     = _cleanFilename(widget.jobTitle);
      final filename     = 'Anschreiben_${cleanCompany}_${cleanJob}.pdf';
      final filePath     = '$downloadPath/$filename';
      final file = File(filePath);
      await file.writeAsBytes(bytes);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _savedMsg,
              style: const TextStyle(color: _navy, fontWeight: FontWeight.w600),
            ),
            duration: const Duration(seconds: 3),
            backgroundColor: _green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e, stackTrace) {
      print('PDF ERROR: $e');
      print('PDF STACKTRACE: $stackTrace');
      if (context.mounted) _snack(context, _pdfErrorMsg);
    }
  }

  void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: _navy, fontWeight: FontWeight.w600)),
        backgroundColor: _green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // Routes into the app's existing Cover Letter Creation flow
  // (LetterDocumentScreen, same screen reached from ChooseCvTypeScreen),
  // pre-filled with this posting's title/company so the generated Anschreiben
  // is relevant to this exact job rather than the user's generic saved
  // target position. Mirrors ChooseCvTypeScreen._openLetterDocument()'s own
  // 'saved_profile' load + no-data gating.
  Future<void> _openCoverLetterCreation(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('saved_profile');
    UserProfile? profile;
    if (raw != null && raw.isNotEmpty) {
      try {
        profile = UserProfile.fromMap(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        profile = null;
      }
    }
    if (profile == null) {
      if (context.mounted) _snack(context, _noProfileForLetterMsg);
      return;
    }
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LetterDocumentScreen(
          profile: profile!,
          language: _language,
          docType: LetterDocType.coverLetter,
          jobTitle: widget.jobTitle,
          companyName: widget.companyName,
          isAusbildungCv: true,
        ),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: _isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: PopScope(
        canPop: true,
        onPopInvokedWithResult: (didPop, result) {
          TtsService().stop();
        },
        child: Scaffold(
        backgroundColor: const Color(0xFFF7FAFF),
        body: Stack(
          children: [
            const _BackgroundGlow(),
            SafeArea(
              child: Column(
                children: [
                  _buildHeader(context),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildJobInfoCard(),
                          const SizedBox(height: 20),
                          _buildOptionsSection(context),
                          if (widget.voiceMode) ...[
                            const SizedBox(height: 16),
                            _buildTipsCard(),
                          ],
                          const SizedBox(height: 24),
                          _buildCoverLetterSection(context),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        // Fixed LTR regardless of app language — Back must stay isolated
        // on the physical far left with Home+Sound grouped on the far
        // right; without this, the ambient RTL Directionality (Pashto/
        // Dari) mirrors the Row and puts Back on the right instead.
        textDirection: TextDirection.ltr,
        children: [
          _NavBtn(
            icon: Icons.arrow_back_ios_new_rounded,
            onTap: () {
              TtsService().stop();
              Navigator.pop(context);
            },
          ),
          Expanded(
            child: Center(
              child: Text(
                _screenTitle,
                textDirection: _isRtl ? TextDirection.rtl : TextDirection.ltr,
                style: const TextStyle(
                  color: _navy,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          _NavBtn(
            icon: Icons.home_rounded,
            onTap: () {
              TtsService().stop();
              goHomeToIntroduction(
                context,
                language: _language,
                voiceMode: widget.voiceMode,
              );
            },
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              TtsService().toggleSound();
              setState(() {});
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              decoration: BoxDecoration(
                color: TtsService().hintPulseActive
                    ? const Color(0xFF091733).withOpacity(0.85)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: _GlassSurface(
                width: 44,
                height: 44,
                borderRadius: 14,
                padding: EdgeInsets.zero,
                shadowOpacity: 0.08,
                child: Icon(
                  TtsService().soundEnabled
                      ? Icons.volume_up_rounded
                      : Icons.volume_off_rounded,
                  color: TtsService().soundEnabled ? _green : _muted,
                  size: 20,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Job info card ──────────────────────────────────────────────────────────

  Widget _buildJobInfoCard() {
    return _GlassSurface(
      borderRadius: 20,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.companyName,
            textDirection: TextDirection.ltr,
            style: const TextStyle(
              color: _navy,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.jobTitle,
            textDirection: TextDirection.ltr,
            style: const TextStyle(color: _muted, fontSize: 14),
          ),
          if (widget.jobLocation.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              textDirection: TextDirection.ltr,
              children: [
                const Icon(Icons.location_on_rounded, color: _green, size: 14),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    widget.jobLocation,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── Options section ────────────────────────────────────────────────────────

  Widget _buildOptionsSection(BuildContext context) {
    return Column(
      crossAxisAlignment:
          _isRtl ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          _howToApplyTitle,
          textDirection: _isRtl ? TextDirection.rtl : TextDirection.ltr,
          style: const TextStyle(
            color: _navy,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),

        // 1 — Apply via Form (always shown)
        AnimatedBuilder(
          animation: _highlightAnimation,
          builder: (context, child) => _showHighlight
              ? CustomPaint(
                  // foregroundPainter (not painter) so the dashed border
                  // draws on top of the card's opaque background instead
                  // of being partly hidden behind it — otherwise only the
                  // portion of the stroke that overflows the card's own
                  // bounds (mainly the right/bottom edges) stays visible.
                  foregroundPainter: _DashedBorderPainter(
                    opacity: _highlightAnimation.value,
                    color: Colors.red,
                  ),
                  child: child,
                )
              : child!,
          child: _OptionCard(
            icon: Icons.assignment_rounded,
            iconBgColor: const Color(0xFFEAFBE9),
            iconColor: _green,
            title: _formTitle,
            desc: _formDesc,
            isRtl: _isRtl,
            onTap: () => _openForm(context),
            onSpeak: _isRtl
                ? () => TtsService().speak(
                      _language == 'ps'
                          ? 'دا بټن تاسو د کار آنلاین فورم ته بیایي'
                          : 'این دکمه شما را به فرم آنلاین درخواست می‌برد',
                      _language)
                : null,
          ),
        ),
        const SizedBox(height: 10),

        // 2 — Apply via Email (only if email available)
        if (widget.companyEmail.isNotEmpty) ...[
          _OptionCard(
            icon: Icons.email_rounded,
            iconBgColor: const Color(0xFFEBF3FF),
            iconColor: const Color(0xFF2D6BE4),
            title: _emailTitle,
            desc: _emailDesc,
            isRtl: _isRtl,
            onTap: () => _openEmail(context),
            onSpeak: _isRtl
                ? () => TtsService().speak(
                      _language == 'ps'
                          ? 'ستاسو CV بریښنالیک ته واستوئ'
                          : 'CV خود را از طریق ایمیل ارسال کنید',
                      _language)
                : null,
          ),
          const SizedBox(height: 10),
        ],

        // 3 — Call the Company (only if phone available)
        if (widget.companyPhone.isNotEmpty) ...[
          _OptionCard(
            icon: Icons.phone_rounded,
            iconBgColor: const Color(0xFFFFF3E0),
            iconColor: const Color(0xFFFF9800),
            title: _phoneTitle,
            desc: _phoneDesc,
            isRtl: _isRtl,
            onTap: () => _callPhone(context),
            onSpeak: _isRtl
                ? () => TtsService().speak(
                      _language == 'ps'
                          ? 'شرکت ته زنګ ووهئ'
                          : 'با شرکت تماس بگیرید',
                      _language)
                : null,
          ),
          const SizedBox(height: 10),
        ],

        // 4 — WhatsApp (only if phone available)
        if (widget.companyPhone.isNotEmpty) ...[
          _OptionCard(
            icon: Icons.chat_rounded,
            iconBgColor: const Color(0xFFE8F5E9),
            iconColor: const Color(0xFF25D366),
            title: _waTitle,
            desc: _waDesc,
            isRtl: _isRtl,
            onTap: () => _openWhatsApp(context),
            onSpeak: _isRtl
                ? () => TtsService().speak(
                      _language == 'ps'
                          ? 'د واټساپ له لارې CV واستوئ'
                          : 'CV خود را از طریق واتساپ ارسال کنید',
                      _language)
                : null,
          ),
          const SizedBox(height: 10),
        ],

        // 5 — Apply in Person (always shown)
        AnimatedBuilder(
          animation: _highlightAnimation,
          builder: (context, child) => _showHighlight
              ? CustomPaint(
                  // foregroundPainter (not painter) so the dashed border
                  // draws on top of the card's opaque background instead
                  // of being partly hidden behind it — otherwise only the
                  // portion of the stroke that overflows the card's own
                  // bounds (mainly the right/bottom edges) stays visible.
                  foregroundPainter: _DashedBorderPainter(
                    opacity: _highlightAnimation.value,
                    color: Colors.red,
                  ),
                  child: child,
                )
              : child!,
          child: _OptionCard(
            icon: Icons.location_on_rounded,
            iconBgColor: const Color(0xFFFCE4EC),
            iconColor: const Color(0xFFE91E63),
            title: _personTitle,
            desc: _personDesc,
            isRtl: _isRtl,
            onTap: () => _openMaps(context),
            onSpeak: _isRtl
                ? () => TtsService().speak(
                      _language == 'ps'
                          ? 'تاسو کولی شئ مستقیم دی کمپنی ادرس ته لاړ شی'
                          : 'مستقیماً به آدرس شرکت مراجعه کنید',
                      _language)
                : null,
          ),
        ),
      ],
    );
  }

  // ── Tips card ──────────────────────────────────────────────────────────────

  Widget _buildTipsCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDE7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFF176), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment:
            _isRtl ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            textDirection: _isRtl ? TextDirection.rtl : TextDirection.ltr,
            children: [
              const Icon(Icons.lightbulb_rounded,
                  color: Color(0xFFFBC02D), size: 20),
              const SizedBox(width: 8),
              Text(
                _tipsTitle,
                textDirection: _isRtl ? TextDirection.rtl : TextDirection.ltr,
                style: const TextStyle(
                  color: _navy,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ..._tips.map(
            (tip) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                textDirection:
                    _isRtl ? TextDirection.rtl : TextDirection.ltr,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '• ',
                    style: TextStyle(color: Color(0xFFFBC02D), fontSize: 14),
                  ),
                  Expanded(
                    child: Text(
                      tip,
                      textDirection:
                          _isRtl ? TextDirection.rtl : TextDirection.ltr,
                      style: const TextStyle(
                        color: _navy,
                        fontSize: 13,
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
    );
  }

  // ── Cover letter section ───────────────────────────────────────────────────

  Widget _buildCoverLetterSection(BuildContext context) {
    if (widget.isAusbildung) {
      return _buildCoverLetterButtonSection(context);
    }
    final postalCity = _postalCity;

    return Column(
      crossAxisAlignment:
          _isRtl ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        // Section title row
        Row(
          textDirection: _isRtl ? TextDirection.rtl : TextDirection.ltr,
          children: [
            const Icon(Icons.article_rounded, color: _green, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _coverLetterSectionTitle,
                textDirection: _isRtl ? TextDirection.rtl : TextDirection.ltr,
                style: const TextStyle(
                  color: _navy,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (_isRtl) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => TtsService().speak(
                  _language == 'ps'
                      ? 'د دې کار لپاره تاسو کولی شئ د کار غوښتنې لیک ډاونلوډ کړئ'
                      : 'برای این شغل می‌توانید نامه پوششی را دانلود کنید',
                  _language,
                ),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(
                    color: Color(0xFFEAFBE9),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.volume_up_rounded,
                      color: _green, size: 17),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),

        // Explanatory text
        Text(
          _language == 'ps'
              ? 'د دې کار لپاره چمتو شوی د کار غوښتنې لیک لاندې ډاونلوډ تڼۍ په کلیک کولو ډاونلوډ کړئ'
              : _language == 'fa'
                  ? 'با کلیک روی دکمه دانلود در زیر، می‌توانید یک نامه پوششی آماده دانلود کنید'
                  : 'Download a ready-made cover letter for this job below.',
          textDirection: _isRtl ? TextDirection.rtl : TextDirection.ltr,
          style: const TextStyle(
            color: _muted,
            fontSize: 12,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 12),

        // Cover letter preview — white document card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.07),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Two-column header
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // LEFT — company
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.companyName,
                          style: const TextStyle(
                            color: _navy,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Text(
                          'z.Hd. Personalabteilung',
                          style:
                              TextStyle(color: Color(0xFF555555), fontSize: 11),
                        ),
                        if (_companyAddress.isNotEmpty)
                          Text(
                            _companyAddress,
                            style: const TextStyle(
                                color: Color(0xFF555555), fontSize: 11),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // RIGHT — applicant
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _displayName,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            color: _navy,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          _displayStreet,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                              color: Color(0xFF555555), fontSize: 11),
                        ),
                        if (postalCity.isNotEmpty)
                          Text(
                            postalCity,
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                                color: Color(0xFF555555), fontSize: 11),
                          ),
                        Text(
                          _displayPhone,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                              color: Color(0xFF555555), fontSize: 11),
                        ),
                        Text(
                          _displayEmail,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                              color: Color(0xFF555555), fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Date — right aligned
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  _dateLine,
                  style: const TextStyle(
                      color: Color(0xFF555555), fontSize: 11),
                ),
              ),
              const SizedBox(height: 14),

              // Subject
              Text(
                'Bewerbung als ${widget.jobTitle}',
                style: const TextStyle(
                  color: _navy,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),

              // Title — centered bold
              const Center(
                child: Text(
                  'Anschreiben',
                  style: TextStyle(
                    color: _navy,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Salutation
              const Text(
                'Sehr geehrte Damen und Herren,',
                style: TextStyle(
                    color: _navy, fontSize: 12, height: 1.6),
              ),
              const SizedBox(height: 8),

              // Paragraph 1
              Text(
                'mit großem Interesse habe ich Ihre Stellenanzeige für die '
                'Position als ${widget.jobTitle}$_jobTypeSuffix bei ${widget.companyName} '
                'gelesen. Hiermit bewerbe ich mich auf diese ausgeschriebene '
                'Stelle.',
                style: const TextStyle(
                    color: _navy, fontSize: 12, height: 1.6),
              ),
              const SizedBox(height: 12),

              // Paragraph 2
              const Text(
                'Ich bin ein motivierter und zuverlässiger Mitarbeiter. Ich '
                'bringe praktische Erfahrung mit, arbeite gerne im Team und '
                'bin bereit, mich schnell in neue Aufgabenbereiche '
                'einzuarbeiten. Körperlich anspruchsvolle Tätigkeiten sind '
                'mir vertraut.',
                style: TextStyle(
                    color: _navy, fontSize: 12, height: 1.6),
              ),
              const SizedBox(height: 12),

              // Paragraph 3
              const Text(
                'Über eine Einladung zu einem persönlichen Vorstellungsgespräch '
                'würde ich mich sehr freuen. Meine Bewerbungsunterlagen, '
                'einschließlich meines Lebenslaufs, füge ich dieser Bewerbung '
                'bei.',
                style: TextStyle(
                    color: _navy, fontSize: 12, height: 1.6),
              ),
              const SizedBox(height: 16),

              // Sign-off
              const Text(
                'Mit freundlichen Grüßen,',
                style: TextStyle(
                    color: _navy, fontSize: 12, height: 1.6),
              ),
              const SizedBox(height: 12),
              Text(
                _displayName,
                style: const TextStyle(
                  color: _navy,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Buttons row
        Row(
          children: [
            // Copy — outlined
            Expanded(
              child: GestureDetector(
                onTap: () => _copyToClipboard(context),
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _green, width: 1.5),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.copy_rounded, color: _green, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        _copyLabel,
                        style: const TextStyle(
                          color: _navy,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Download PDF — navy gradient
            Expanded(
              child: GestureDetector(
                onTap: () => _downloadPdf(),
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: const LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [Color(0xFF081532), Color(0xFF07112B)],
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.download_rounded,
                          color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        _downloadLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // Ausbildung postings: compact "Cover Letter erstellen" card that routes
  // into the real Cover Letter Creation flow instead of showing a static
  // inline letter preview (item 2/3 of the Ausbildung posting cover-letter
  // fix - see _openCoverLetterCreation() above for the navigation).
  Widget _buildCoverLetterButtonSection(BuildContext context) {
    return Column(
      crossAxisAlignment:
          _isRtl ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Row(
          textDirection: _isRtl ? TextDirection.rtl : TextDirection.ltr,
          children: [
            const Icon(Icons.article_rounded, color: _green, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _coverLetterSectionTitle,
                textDirection: _isRtl ? TextDirection.rtl : TextDirection.ltr,
                style: const TextStyle(
                  color: _navy,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _coverLetterButtonDesc,
          textDirection: _isRtl ? TextDirection.rtl : TextDirection.ltr,
          style: const TextStyle(
            color: _muted,
            fontSize: 12,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () => _openCoverLetterCreation(context),
          child: Container(
            width: double.infinity,
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [Color(0xFF081532), Color(0xFF07112B)],
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.description_rounded,
                    color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    _coverLetterButtonLabel,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Dashed border painter ─────────────────────────────────────────────────────

class _DashedBorderPainter extends CustomPainter {
  final double opacity;
  final Color color;

  const _DashedBorderPainter({required this.opacity, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(opacity)
      ..strokeWidth = 5.5
      ..style = PaintingStyle.stroke;

    const dashWidth = 10.0;
    const dashSpace = 5.0;
    const radius = 20.0;

    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      const Radius.circular(radius),
    );

    final path = Path()..addRRect(rect);

    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(distance, distance + dashWidth),
          paint,
        );
        distance += dashWidth + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.opacity != opacity || old.color != color;
}

// ── Option card ───────────────────────────────────────────────────────────────

class _OptionCard extends StatelessWidget {
  final IconData icon;
  final Color iconBgColor;
  final Color iconColor;
  final String title;
  final String desc;
  final bool isRtl;
  final VoidCallback onTap;
  final VoidCallback? onSpeak;

  const _OptionCard({
    required this.icon,
    required this.iconBgColor,
    required this.iconColor,
    required this.title,
    required this.desc,
    required this.isRtl,
    required this.onTap,
    this.onSpeak,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.85),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white, width: 1.2),
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
        child: Row(
          textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconBgColor,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: isRtl
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    textDirection:
                        isRtl ? TextDirection.rtl : TextDirection.ltr,
                    style: const TextStyle(
                      color: Color(0xFF091733),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    desc,
                    textDirection:
                        isRtl ? TextDirection.rtl : TextDirection.ltr,
                    style: const TextStyle(
                      color: Color(0xFF65738A),
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onSpeak != null) ...[
                  GestureDetector(
                    onTap: onSpeak,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: const BoxDecoration(
                        color: Color(0xFFEAFBE9),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.volume_up_rounded,
                          color: Color(0xFF39EA2B), size: 16),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                const Icon(Icons.chevron_right_rounded,
                    color: Color(0xFF65738A), size: 20),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Nav button ────────────────────────────────────────────────────────────────

class _NavBtn extends StatelessWidget {
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
        shadowOpacity: 0.08,
        child: Icon(icon, color: const Color(0xFF091733), size: 20),
      ),
    );
  }
}

// ── Background glow ───────────────────────────────────────────────────────────

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
        Positioned(top: 70,    left: -42, child: _Orb(size: 170, color: Color(0x6639EA2B))),
        Positioned(top: 135,   right: -65, child: _Orb(size: 170, color: Color(0x44FFB86B))),
        Positioned(bottom: 95, left: -60,  child: _Orb(size: 210, color: Color(0x3339EA2B))),
        Positioned(bottom: -30, right: 14, child: _Orb(size: 145, color: Color(0x5539EA2B))),
        Positioned(top: 20,    left: 30,   child: _Orb(size: 170, color: Color(0x30FF8FA3))),
      ],
    );
  }
}

// ── Orb ───────────────────────────────────────────────────────────────────────

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

// ── CAPTCHA guidance bottom sheet ────────────────────────────────────────────

class _CaptchaGuideSheet extends StatefulWidget {
  final String formUrl;
  final String jobTitle;
  final String companyName;
  final String userName;
  final String userPhone;
  final String userEmail;
  final String language;
  final String jobType;
  // FIX 5 fallback: used for the cover letter's date/city line when the
  // user's own profile has no saved city.
  final String jobLocation;

  const _CaptchaGuideSheet({
    required this.formUrl,
    required this.jobTitle,
    required this.companyName,
    required this.userName,
    required this.userPhone,
    required this.userEmail,
    required this.language,
    this.jobType = '',
    this.jobLocation = '',
  });

  @override
  State<_CaptchaGuideSheet> createState() => _CaptchaGuideSheetState();
}

class _CaptchaGuideSheetState extends State<_CaptchaGuideSheet> {
  static const Color _navy  = Color(0xFF091733);
  static const Color _green = Color(0xFF39EA2B);
  static const Color _muted = Color(0xFF65738A);

  final _emailController = TextEditingController();
  late final Future<Map<String, File?>> _docsFuture;
  bool _isGenerating = false;

  bool get _isRtl => widget.language == 'ps' || widget.language == 'fa';

  String get _jobTypeSuffix {
    switch (widget.jobType) {
      case 'Vollzeit': return ' in Vollzeit';
      case 'Teilzeit': return ' in Teilzeit';
      case 'Minijob':  return ' auf Minijob-Basis';
      default:         return '';
    }
  }

  @override
  void initState() {
    super.initState();
    _docsFuture = _findCurrentFiles();
    if (_isRtl) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _speakGuidance());
    }
  }

  @override
  void dispose() {
    TtsService().stop();
    _emailController.dispose();
    super.dispose();
  }

  void _speakGuidance() {
    final text = widget.language == 'ps'
        ? 'دغه توره بټن په کلیک کولو سره تاسو ته به دغه تصویر پشان کوډ ښکاره شی،هغه کوډ هلته ولیکئ او له هغه ځایه ایمیل کاپی کړئ  او بیرته یی دلته ولیکئ'
        : 'ابتدا صفحه کار را باز کنید، کد امنیتی را وارد کنید و ایمیل شرکت را کپی کنید، سپس برگردید و ایمیل را اینجا بچسبانید';
    TtsService().speak(text, widget.language);
  }

  Future<Map<String, File?>> _findCurrentFiles() async {
    final prefs = await SharedPreferences.getInstance();
    File? cvFile;
    File? coverFile;

    final tempCvPath    = prefs.getString('temp_cv_path')    ?? '';
    final tempCoverPath = prefs.getString('temp_cover_path') ?? '';

    if (tempCvPath.isNotEmpty) {
      final f = File(tempCvPath);
      if (await f.exists()) cvFile = f;
    }

    if (tempCoverPath.isNotEmpty) {
      final f = File(tempCoverPath);
      if (await f.exists()) coverFile = f;
    }

    // Generate cover letter if not pre-cached
    if (coverFile == null) {
      final cleanCompany = widget.companyName
          .replaceAll(' ', '_')
          .replaceAll(RegExp(r'[^\w]'), '');
      final cleanJob = widget.jobTitle
          .replaceAll(RegExp(r'[^\w\s]'), '')
          .replaceAll(' ', '_');
      final tempDir   = await getTemporaryDirectory();
      final coverPath =
          '${tempDir.path}/Anschreiben_${cleanCompany}_${cleanJob}.pdf';
      try {
        final bytes = await _generateCoverLetterBytes();
        coverFile = File(coverPath);
        await coverFile.writeAsBytes(bytes);
        await prefs.setString('temp_cover_path', coverPath);
      } catch (_) {}
    }

    // Fallback for CV: uploaded file
    if (cvFile == null) {
      final uploadedPath = prefs.getString('uploaded_cv_path') ?? '';
      final cvType       = prefs.getString('cv_type')          ?? '';
      if (cvType == 'uploaded' && uploadedPath.isNotEmpty) {
        final f = File(uploadedPath);
        if (await f.exists()) cvFile = f;
      }
    }

    return {'cv': cvFile, 'cover': coverFile};
  }

  String get _title {
    switch (widget.language) {
      case 'ps': return 'آنلاین فورم ډکول';
      case 'fa': return 'تکمیل فرم آنلاین';
      default:   return 'Apply via Online Form';
    }
  }

  String get _step1 {
    switch (widget.language) {
      case 'ps': return '۱. لاندې تڼۍ فشار کړئ ترڅو فورم پرانستل شي';
      case 'fa': return '۱. دکمه زیر را بزنید تا فرم باز شود';
      default:   return '1. Tap the button below to open the form';
    }
  }

  String get _step2 {
    switch (widget.language) {
      case 'ps': return '۲. که Code وویني،هغه کوډ هلته ولیکئ';
      case 'fa': return '۲. اگر CAPTCHA دیدید، تصاویر خواسته‌شده را انتخاب کنید';
      default:   return '2. If you see a CAPTCHA, Fil the Code as Shown';
    }
  }

  String get _step3 {
    switch (widget.language) {
      case 'ps': return '۳. د شرکت بریښنالیک کاپي کړئ، بیا دلته راستانه شئ';
      case 'fa': return '۳. ایمیل شرکت را کپی کنید، سپس برگردید';
      default:   return '3. Copy the company email, then return here';
    }
  }

  String get _openFormLabel {
    switch (widget.language) {
      case 'ps': return 'فورم پرانستل';
      case 'fa': return 'باز کردن فرم';
      default:   return 'Open Application Form';
    }
  }

  String get _orSendEmail {
    switch (widget.language) {
      case 'ps': return 'بیا دلته د شرکت بریښنالیک پیسټ کړئ';
      case 'fa': return 'سپس ایمیل شرکت را اینجا بچسبانید';
      default:   return 'Then paste the company email below and send';
    }
  }

  String get _gmailLabel {
    switch (widget.language) {
      case 'ps': return 'Gmail له لارې ولیږئ';
      case 'fa': return 'ارسال از Gmail';
      default:   return 'Send via Gmail';
    }
  }

  Future<void> _launchForm() async {
    final url = widget.formUrl.trim();
    if (url.isEmpty) return;
    if (!context.mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InAppBrowserScreen(
          url: url,
          title: widget.companyName,
          language: widget.language,
        ),
      ),
    );
  }

  Future<void> _showGmailInstructions() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          widget.language == 'ps'
              ? 'مهرباني وکړئ د شرکت بریښنالیک ولیکئ'
              : widget.language == 'fa'
                  ? 'لطفاً ایمیل شرکت را وارد کنید'
                  : 'Please paste the company email first',
        ),
      ));
      return;
    }
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _GmailInstructionSheet(
        email: email,
        jobTitle: widget.jobTitle,
        companyName: widget.companyName,
        userName: widget.userName,
        language: widget.language,
      ),
    );
  }

  Future<void> _sendWithIntent() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.language == 'ps'
                ? 'لومړی بریښنالیک پیسټ کړئ'
                : widget.language == 'fa'
                ? 'لطفاً ابتدا ایمیل را وارد کنید'
                : 'Please paste the company email first',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isGenerating = true);
    try {
      await Clipboard.setData(ClipboardData(text: email));

      final docs      = await _findCurrentFiles();
      final coverFile = docs['cover'];
      final cvFile    = docs['cv'];

      final xfiles = <XFile>[
        if (coverFile != null)
          XFile(coverFile.path, mimeType: 'application/pdf'),
        if (cvFile != null)
          XFile(cvFile.path, mimeType: 'application/pdf'),
      ];

      if (xfiles.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                widget.language == 'ps'
                    ? 'اسناد رامینځته نه شول'
                    : widget.language == 'fa'
                    ? 'خطا در ایجاد اسناد'
                    : 'Could not prepare documents',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final subject = 'Bewerbung: ${widget.jobTitle} - ${widget.companyName}';
      final body    =
          'Sehr geehrte Damen und Herren,\n\n'
          'ich bewerbe mich als ${widget.jobTitle} '
          'bei ${widget.companyName}.\n'
          'Anbei: Lebenslauf und Anschreiben.\n\n'
          'Mit freundlichen Grüßen,\n${widget.userName}';

      if (mounted) setState(() => _isGenerating = false);

      await Share.shareXFiles(xfiles, subject: subject, text: body);

      if (!mounted) return;
      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.language == 'ps'
                ? 'Gmail غوره کړئ → To: کې بریښنالیک پیسټ کړئ (کاپي شوی دی)'
                : widget.language == 'fa'
                ? 'Gmail را انتخاب کنید → ایمیل را در To: جای‌گذاری کنید (کپی شده)'
                : 'Select Gmail → Paste email in To: field (already copied)',
          ),
          duration: const Duration(seconds: 6),
          backgroundColor: const Color(0xFF091733),
        ),
      );
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<Uint8List> _generateCoverLetterBytes() async {
    final prefs = await SharedPreferences.getInstance();
    final street = prefs.getString('user_street') ?? '';
    final postal = prefs.getString('user_postal') ?? '';
    final city   = prefs.getString('user_city')   ?? '';

    final font     = pw.Font.helvetica();
    final boldFont = pw.Font.helveticaBold();

    pw.TextStyle normal(double size) =>
        pw.TextStyle(font: font, fontSize: size);
    pw.TextStyle bold(double size) =>
        pw.TextStyle(font: boldFont, fontSize: size,
            fontWeight: pw.FontWeight.bold);

    final postalCity   = [postal, city].where((s) => s.isNotEmpty).join(' ');
    final displayName  = widget.userName.isEmpty  ? '[Ihr Name]'             : widget.userName;
    final displayStreet= street.isEmpty           ? '[Straße und Hausnummer]': street;
    final displayPhone = widget.userPhone.isEmpty ? '[Telefonnummer]'        : widget.userPhone;
    final displayEmail = widget.userEmail.isEmpty ? '[E-Mail-Adresse]'       : widget.userEmail;
    // FIX 5: fall back to the job's own location rather than a "[Stadt]"
    // placeholder when the profile has no city saved.
    final displayCity = city.isNotEmpty ? city : widget.jobLocation;

    final now = DateTime.now();
    const months = [
      'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni',
      'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember',
    ];
    final germanDate = '${now.day}. ${months[now.month - 1]} ${now.year}';
    final dateLine =
        displayCity.isEmpty ? germanDate : '$displayCity, $germanDate';

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(48),
        build: (pw.Context ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(widget.companyName, style: bold(11)),
                      pw.Text('z.Hd. Personalabteilung', style: normal(10)),
                    ],
                  ),
                ),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(displayName,   style: bold(11)),
                      pw.Text(displayStreet, style: normal(10)),
                      if (postalCity.isNotEmpty)
                        pw.Text(postalCity,  style: normal(10)),
                      pw.Text(displayPhone,  style: normal(10)),
                      pw.Text(displayEmail,  style: normal(10)),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 20),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(dateLine, style: normal(10)),
            ),
            pw.SizedBox(height: 14),
            pw.Text('Bewerbung als ${widget.jobTitle}', style: bold(12)),
            pw.SizedBox(height: 10),
            pw.Center(child: pw.Text('Anschreiben', style: bold(16))),
            pw.SizedBox(height: 16),
            pw.Text(
              'Sehr geehrte Damen und Herren,\n\n'
              'mit großem Interesse habe ich Ihre Stellenanzeige für die '
              'Position als ${widget.jobTitle}$_jobTypeSuffix bei ${widget.companyName} '
              'gelesen. Hiermit bewerbe ich mich auf diese ausgeschriebene '
              'Stelle.\n\n'
              'Ich bin ein motivierter und zuverlässiger Mitarbeiter. Ich '
              'bringe praktische Erfahrung mit, arbeite gerne im Team und '
              'bin bereit, mich schnell in neue Aufgabenbereiche '
              'einzuarbeiten. Körperlich anspruchsvolle Tätigkeiten sind '
              'mir vertraut.\n\n'
              'Über eine Einladung zu einem persönlichen Vorstellungsgespräch '
              'würde ich mich sehr freuen. Meine Bewerbungsunterlagen, '
              'einschließlich meines Lebenslaufs, füge ich dieser Bewerbung '
              'bei.\n\n'
              'Mit freundlichen Grüßen,\n\n'
              '$displayName',
              style: normal(11).copyWith(lineSpacing: 3),
            ),
          ],
        ),
      ),
    );

    return await doc.save();
  }

  Future<Uint8List> _generateCvBytes(Map<String, dynamic> profile) async {
    const skillDe = <String, String>{
      'lifting': 'Schwere Lasten tragen',
      'cooking': 'Kochen',
      'driving': 'Fahren / Transport',
      'cleaning': 'Reinigung',
      'fixing': 'Reparatur / Instandhaltung',
      'packing': 'Packen / Lagerhaltung',
      'security': 'Sicherheitsdienst',
      'forklift': 'Gabelstapler',
      'farming': 'Landwirtschaft',
      'sales': 'Verkauf / Handel',
      'sewing': 'Nähen / Schneiderei',
      'construction': 'Bauarbeiten',
      'mobile_repair': 'Handy-Reparatur',
      'amazon_packing': 'Lagerlogistik',
      'dhl': 'Paketdienst / Auslieferung',
    };
    const workExpDe = <String, String>{
      'more2': 'Mehr als 2 Jahre Erfahrung',
      'less2': 'Weniger als 2 Jahre Erfahrung',
      'small': 'Nur einfache Tätigkeiten',
      'never': 'Keine Berufserfahrung',
    };
    const workTypeDe = <String, String>{
      'construction': 'Baugewerbe',
      'cleaning': 'Gebäudereinigung',
      'kitchen': 'Küche / Gastronomie',
      'driving': 'Fahrertätigkeit',
    };
    const toolsDe = <String, String>{
      'power_tools': 'Elektrowerkzeuge',
      'kitchen_equip': 'Küchengeräte',
      'tractor': 'Traktor / Schwere Fahrzeuge',
      'no_tools': 'Keine Werkzeugerfahrung',
    };
    const licenseDe = <String, String>{
      'german_license': 'Deutsches Führerschein (vorhanden)',
      'foreign_license': 'Ausländisches Führerschein',
      'want_license': 'Kein Führerschein (möchte erwerben)',
      'no_license': 'Kein Führerschein',
    };
    const langDe = <String, String>{
      'pashto': 'Paschtu',
      'dari': 'Dari / Farsi',
      'urdu': 'Urdu',
      'arabic': 'Arabisch',
      'english': 'Englisch',
      'german': 'Deutsch',
      'other': 'Andere',
    };
    const availDe = <String, String>{
      'fulltime': 'Vollzeit (40 Std./Woche)',
      'parttime': 'Teilzeit (20 Std./Woche)',
      'flexible': 'Flexibel',
      'weekends': 'Nur Wochenende',
    };
    const startDe = <String, String>{
      'immediately': 'Sofort',
      'two_weeks': 'Innerhalb von 2 Wochen',
      'one_month': 'Innerhalb eines Monats',
      'unsure': 'Noch nicht festgelegt',
    };
    const countryDe = <String, String>{
      'af': 'Afghanistan', 'pk': 'Pakistan', 'ir': 'Iran',
      'iq': 'Iraq', 'sy': 'Syria', 'so': 'Somalia',
      'er': 'Eritrea', 'other': 'Other',
    };

    String lu(String? key, Map<String, String> map) =>
        (key == null || key.isEmpty) ? '—' : (map[key] ?? key);

    // Extract fields
    final fullName  = (profile['fullName']  as String?) ??
                      (profile['name']      as String?) ?? '';
    final phone     = (profile['phone']     as String?) ?? '';
    final email     = (profile['email']     as String?) ?? '';
    final street    = (profile['street']    as String?) ?? '';
    final city      = (profile['city']      as String?) ?? '';
    final postal    = (profile['postal']    as String?) ?? '';
    final country   = (profile['country']   as String?) ?? '';
    final dob       = (profile['dobFormatted'] as String?) ??
                      (profile['dob']          as String?) ?? '';
    final photoPath = (profile['photoPath'] as String?) ?? '';
    final skillRaw  = (profile['skill']     as String?) ?? '';
    final workType  = (profile['workType']        as String?) ?? '';
    final workExp   = (profile['workExperience']  as String?) ?? '';
    final tools     = (profile['tools']           as String?) ?? '';
    final license   = (profile['drivingLicense']  as String?) ?? '';
    final startDate = (profile['startDate']       as String?) ?? '';
    final avail     = (profile['availability']    as String?) ?? '';
    final refName   = (profile['refName']   as String?) ?? '';
    final refPhone  = (profile['refPhone']  as String?) ?? '';
    final langList  = (profile['languages'] as List<dynamic>?)
        ?.map((e) => e.toString()).toList() ?? [];

    final fullAddress = [street, postal, city]
        .where((s) => s.isNotEmpty).join(', ');
    final skillsText = skillRaw.isEmpty ? '—'
        : skillRaw.split(',').map((k) => lu(k.trim(), skillDe)).join(', ');
    final langsText = langList.isEmpty ? '—'
        : langList.map((k) => lu(k, langDe)).join(', ');

    // Rows as [label, value] pairs
    final personalRows = <MapEntry<String, String>>[
      if (dob.isNotEmpty)     MapEntry('Geburtsdatum', dob),
      if (country.isNotEmpty) MapEntry('Geburtsort',   countryDe[country] ?? country),
      if (country.isNotEmpty) MapEntry('Nationalität', countryDe[country] ?? country),
    ];
    final contactRows = <MapEntry<String, String>>[
      if (fullAddress.isNotEmpty) MapEntry('Adresse', fullAddress),
      if (phone.isNotEmpty)       MapEntry('Telefon', phone),
      if (email.isNotEmpty)       MapEntry('E-Mail',  email),
    ];
    final experienceRows = <MapEntry<String, String>>[
      if (workType.isNotEmpty) MapEntry('Tätigkeitsbereich', lu(workType, workTypeDe)),
      if (workExp.isNotEmpty)  MapEntry('Berufserfahrung',   lu(workExp,  workExpDe)),
    ];
    final skillRows = <MapEntry<String, String>>[
      if (skillRaw.isNotEmpty) MapEntry('Tätigkeiten',       skillsText),
      MapEntry('Sprachen', langsText),
      if (tools.isNotEmpty)    MapEntry('Werkzeugkenntnisse', lu(tools,   toolsDe)),
      if (license.isNotEmpty)  MapEntry('Führerschein',       lu(license, licenseDe)),
    ];
    final availRows = <MapEntry<String, String>>[
      if (startDate.isNotEmpty) MapEntry('Arbeitsbeginn', lu(startDate, startDe)),
      if (avail.isNotEmpty)     MapEntry('Arbeitszeit',   lu(avail,     availDe)),
    ];
    final refRows = <MapEntry<String, String>>[
      if (refName.isNotEmpty)  MapEntry('Name',    refName),
      if (refPhone.isNotEmpty) MapEntry('Telefon', refPhone),
    ];

    pw.MemoryImage? photo;
    if (photoPath.isNotEmpty) {
      try {
        photo = pw.MemoryImage(await File(photoPath).readAsBytes());
      } catch (_) {}
    }

    final bold    = pw.Font.helveticaBold();
    final regular = pw.Font.helvetica();
    final italic  = pw.Font.helveticaOblique();

    pw.Widget cvSection(String title, List<MapEntry<String, String>> rows) {
      if (rows.isEmpty) return pw.Container();
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title,
              style: pw.TextStyle(font: bold, fontSize: 12, color: PdfColors.black)),
          pw.SizedBox(height: 2),
          pw.Divider(color: PdfColors.grey500, thickness: 0.5),
          pw.SizedBox(height: 5),
          ...rows.map((row) => pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 4),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.SizedBox(
                      width: 130,
                      child: pw.Text('${row.key}:',
                          style: pw.TextStyle(
                              font: bold, fontSize: 10, color: PdfColors.grey700)),
                    ),
                    pw.Expanded(
                      child: pw.Text(row.value,
                          style: pw.TextStyle(
                              font: regular, fontSize: 10, color: PdfColors.black)),
                    ),
                  ],
                ),
              )),
          pw.SizedBox(height: 14),
        ],
      );
    }

    final doc = pw.Document(title: 'Lebenslauf – $fullName', author: 'KarYab');
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(48),
        build: (ctx) => [
          if (photo != null) ...[
            pw.Center(
              child: pw.Container(
                width: 88, height: 88,
                decoration: pw.BoxDecoration(
                  shape: pw.BoxShape.circle,
                  image: pw.DecorationImage(image: photo, fit: pw.BoxFit.cover),
                ),
              ),
            ),
            pw.SizedBox(height: 10),
          ],
          pw.Center(
            child: pw.Text(fullName,
                style: pw.TextStyle(font: bold, fontSize: 22, color: PdfColors.black)),
          ),
          if (skillsText != '—') ...[
            pw.SizedBox(height: 4),
            pw.Center(
              child: pw.Text(skillsText,
                  style: pw.TextStyle(font: italic, fontSize: 10, color: PdfColors.grey700)),
            ),
          ],
          pw.SizedBox(height: 8),
          pw.Divider(color: PdfColors.grey700, thickness: 1.5),
          pw.SizedBox(height: 14),
          cvSection('Persönliche Informationen', personalRows),
          cvSection('Kontaktinformationen', contactRows),
          if (experienceRows.isNotEmpty) cvSection('Berufserfahrung', experienceRows),
          cvSection('Fähigkeiten', skillRows),
          if (availRows.isNotEmpty) cvSection('Verfügbarkeit', availRows),
          if (refRows.isNotEmpty)   cvSection('Referenz', refRows),
          pw.SizedBox(height: 20),
          pw.Center(
            child: pw.Text(
              'Erstellt mit KarYab – Die Job-App für Geflüchtete',
              style: pw.TextStyle(font: italic, fontSize: 8, color: PdfColors.grey500),
            ),
          ),
        ],
      ),
    );
    return await doc.save();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: _isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20, 16, 20,
              MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0E0E0),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Title row + speaker
                Row(
                  textDirection:
                      _isRtl ? TextDirection.rtl : TextDirection.ltr,
                  children: [
                    Expanded(
                      child: Text(
                        _title,
                        style: const TextStyle(
                          color: _navy,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (_isRtl)
                      IconButton(
                        onPressed: _speakGuidance,
                        icon: const Icon(Icons.volume_up_rounded,
                            color: _green, size: 22),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                  ],
                ),
                const SizedBox(height: 14),

                // CAPTCHA reference image
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.asset(
                    'assets/images/captcha_reference.png',
                    fit: BoxFit.contain,
                    height: 120,
                    width: double.infinity,
                    errorBuilder: (context, error, stack) => Container(
                      height: 120,
                      color: Colors.grey.shade200,
                      child: const Center(child: Text('Reference image')),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Steps
                _StepRow(text: _step1, isRtl: _isRtl),
                const SizedBox(height: 10),
                _StepRow(text: _step2, isRtl: _isRtl),
                const SizedBox(height: 10),
                _StepRow(text: _step3, isRtl: _isRtl),
                const SizedBox(height: 20),

                // Open Form button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _launchForm,
                    icon: const Icon(Icons.open_in_browser_rounded,
                        size: 18),
                    label: Text(_openFormLabel),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _navy,
                      foregroundColor: Colors.white,
                      padding:
                          const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      textStyle: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // "Paste email" label
                Text(
                  _orSendEmail,
                  style: const TextStyle(
                      color: _muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),

                // Email paste field + copy button
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        style: const TextStyle(
                            color: _navy, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'company@email.com',
                          hintStyle: TextStyle(
                              color: Colors.grey.shade400,
                              fontSize: 14),
                          prefixIcon: const Icon(
                              Icons.email_outlined,
                              color: _green),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                                color: Colors.grey.shade300, width: 1),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                                color: _green, width: 2),
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, color: _green),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(
                            text: _emailController.text));
                        ScaffoldMessenger.of(context)
                            .showSnackBar(const SnackBar(
                          content: Text('Email copied!'),
                        ));
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Files to attach section
                const Text(
                  'Files ready to attach:',
                  style: TextStyle(
                    color: _navy,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 6),
                FutureBuilder<Map<String, File?>>(
                  future: _docsFuture,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const SizedBox(
                        height: 20,
                        child: Center(
                          child: SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2),
                          ),
                        ),
                      );
                    }
                    final cvFile = snapshot.data!['cv'];
                    final coverFile = snapshot.data!['cover'];
                    if (cvFile == null && coverFile == null) {
                      return Text(
                        widget.language == 'ps'
                            ? 'مهرباني وکړئ لومړی خپل CV جوړ کړئ یا ډاونلوډ کړئ'
                            : widget.language == 'fa'
                                ? 'لطفاً ابتدا CV خود را بسازید یا دانلود کنید'
                                : 'Please create or download your CV first',
                        style: TextStyle(
                          color: Colors.red.shade400,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      );
                    }
                    return Column(
                      children: [
                        _FileStatusRow(
                          found: cvFile != null,
                          label: cvFile != null
                              ? cvFile.path.split('/').last
                              : 'No CV found - download first',
                        ),
                        const SizedBox(height: 4),
                        _FileStatusRow(
                          found: coverFile != null,
                          label: coverFile != null
                              ? coverFile.path.split('/').last
                              : 'No cover letter found',
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),

                // Send button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isGenerating ? null : _sendWithIntent,
                    icon: _isGenerating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _navy,
                            ),
                          )
                        : const Icon(Icons.send_rounded, size: 18),
                    label: Text(
                      _isGenerating
                          ? (widget.language == 'ps'
                              ? 'چمتو کول...'
                              : widget.language == 'fa'
                                  ? 'در حال آماده‌سازی...'
                                  : 'Preparing...')
                          : _gmailLabel,
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isGenerating
                          ? _green.withOpacity(0.6)
                          : _green,
                      foregroundColor: _navy,
                      padding:
                          const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      textStyle: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Gmail Instruction Sheet ───────────────────────────────────────────────────

class _GmailInstructionSheet extends StatefulWidget {
  final String email;
  final String jobTitle;
  final String companyName;
  final String userName;
  final String language;

  const _GmailInstructionSheet({
    required this.email,
    required this.jobTitle,
    required this.companyName,
    required this.userName,
    required this.language,
  });

  @override
  State<_GmailInstructionSheet> createState() =>
      _GmailInstructionSheetState();
}

class _GmailInstructionSheetState extends State<_GmailInstructionSheet> {
  static const Color _navy  = Color(0xFF091733);
  static const Color _green = Color(0xFF39EA2B);
  static const Color _muted = Color(0xFF65738A);

  late final Future<Map<String, File?>> _docsFuture;

  bool get _isRtl => widget.language == 'ps' || widget.language == 'fa';

  @override
  void initState() {
    super.initState();
    _docsFuture = _findCurrentFiles();
    Clipboard.setData(ClipboardData(text: widget.email));
  }

  Future<Map<String, File?>> _findCurrentFiles() async {
    final prefs = await SharedPreferences.getInstance();
    File? cvFile;
    File? coverFile;

    final tempCvPath    = prefs.getString('temp_cv_path')    ?? '';
    final tempCoverPath = prefs.getString('temp_cover_path') ?? '';

    if (tempCvPath.isNotEmpty) {
      final f = File(tempCvPath);
      if (await f.exists()) cvFile = f;
    }

    if (tempCoverPath.isNotEmpty) {
      final f = File(tempCoverPath);
      if (await f.exists()) coverFile = f;
    }

    // Fallback for CV: uploaded file
    if (cvFile == null) {
      final uploadedPath = prefs.getString('uploaded_cv_path') ?? '';
      final cvType       = prefs.getString('cv_type')          ?? '';
      if (cvType == 'uploaded' && uploadedPath.isNotEmpty) {
        final f = File(uploadedPath);
        if (await f.exists()) cvFile = f;
      }
    }

    return {'cv': cvFile, 'cover': coverFile};
  }

  Future<void> _openGmail() async {
    final subject = 'Bewerbung: ${widget.jobTitle} - ${widget.companyName}';
    final body =
        'Sehr geehrte Damen und Herren,\n\n'
        'ich bewerbe mich als ${widget.jobTitle}.\n'
        'Anbei: Lebenslauf und Anschreiben.\n\n'
        'Mit freundlichen Grüßen,\n${widget.userName}';

    final mailtoUrl = 'mailto:${widget.email}'
        '?subject=${Uri.encodeComponent(subject)}'
        '&body=${Uri.encodeComponent(body)}';
    await launchUrl(
      Uri.parse(mailtoUrl),
      mode: LaunchMode.externalApplication,
    );

    await Future.delayed(const Duration(seconds: 1));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.language == 'ps'
                ? 'اوس خپل CV د ضمیمه تڼۍ سره ضمیمه کړئ'
                : 'Now attach your CV using the attachment button in Gmail',
          ),
          duration: const Duration(seconds: 5),
          backgroundColor: const Color(0xFF39EA2B),
        ),
      );
    }
  }

  Widget _buildStep(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        textDirection: _isRtl ? TextDirection.rtl : TextDirection.ltr,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: const BoxDecoration(
              color: Color(0xFFEAFBE9),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: _green, size: 15),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                text,
                textDirection:
                    _isRtl ? TextDirection.rtl : TextDirection.ltr,
                style: const TextStyle(
                  color: _navy,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: _isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20, 16, 20,
            MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0E0E0),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Email copied confirmation
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAFBE9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _green, width: 1),
                ),
                child: Column(
                  crossAxisAlignment: _isRtl
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    Row(
                      textDirection:
                          _isRtl ? TextDirection.rtl : TextDirection.ltr,
                      children: [
                        const Icon(Icons.check_circle_rounded,
                            color: _green, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.language == 'ps'
                                ? 'د شرکت بریښنالیک کاپي شو!'
                                : widget.language == 'fa'
                                    ? 'ایمیل شرکت کپی شد!'
                                    : 'Company email copied to clipboard!',
                            style: const TextStyle(
                              color: _navy,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: _green.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        widget.email,
                        style: const TextStyle(
                          color: Color(0xFF147C20),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Steps
              _buildStep(
                Icons.check_circle_outline_rounded,
                widget.language == 'ps'
                    ? 'بریښنالیک اتوماتیک کاپي شو ✓'
                    : widget.language == 'fa'
                        ? 'ایمیل به‌صورت خودکار کپی شد ✓'
                        : 'Email copied automatically ✓',
              ),
              _buildStep(
                Icons.open_in_new_rounded,
                widget.language == 'ps'
                    ? 'لاندې Gmail خلاص کړئ تڼۍ کلیک کړئ'
                    : widget.language == 'fa'
                        ? 'دکمه «باز کردن Gmail» را بزنید'
                        : "Tap 'Open Gmail' button below",
              ),
              _buildStep(
                Icons.share_rounded,
                widget.language == 'ps'
                    ? 'د شریکولو پاڼه کې Gmail غوره کړئ'
                    : widget.language == 'fa'
                        ? 'Gmail را از صفحه اشتراک‌گذاری انتخاب کنید'
                        : 'Select Gmail from share sheet',
              ),
              _buildStep(
                Icons.content_paste_rounded,
                widget.language == 'ps'
                    ? 'Gmail کې To: ساحه کې بریښنالیک پیسټ کړئ (کاپي شوی دی)'
                    : widget.language == 'fa'
                        ? 'در Gmail ایمیل را در فیلد To: جای‌گذاری کنید (کپی شده)'
                        : 'In Gmail paste email in To: field (already copied to your clipboard)',
              ),
              _buildStep(
                Icons.attach_file_rounded,
                widget.language == 'ps'
                    ? 'ستاسو CV او د کار غوښتنې لیک ضمیمه دي'
                    : widget.language == 'fa'
                        ? 'CV و نامه پوششی شما ضمیمه شده‌اند'
                        : 'Your CV and cover letter are attached',
              ),

              // Files available
              const SizedBox(height: 12),
              Text(
                widget.language == 'ps'
                    ? 'ضمیمه کیدونکي فایلونه:'
                    : widget.language == 'fa'
                        ? 'فایل‌های آماده برای ضمیمه:'
                        : 'Files available to attach:',
                style: const TextStyle(
                  color: _navy,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              FutureBuilder<Map<String, File?>>(
                future: _docsFuture,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const CircularProgressIndicator();
                  }
                  final cv    = snapshot.data!['cv'];
                  final cover = snapshot.data!['cover'];
                  return Column(
                    children: [
                      _FileRow(
                        found: cv != null,
                        name: cv != null
                            ? cv.path.split('/').last
                            : 'Lebenslauf (not found)',
                        hint: 'Download CV first',
                      ),
                      const SizedBox(height: 4),
                      _FileRow(
                        found: cover != null,
                        name: cover != null
                            ? cover.path.split('/').last
                            : 'Anschreiben (not found)',
                        hint: 'Download cover letter first',
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),

              // Open Gmail button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _openGmail,
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: Text(
                    widget.language == 'ps'
                        ? 'Gmail خلاص کړئ'
                        : widget.language == 'fa'
                            ? 'باز کردن Gmail'
                            : 'Open Gmail',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _navy,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    textStyle: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Note
              Text(
                widget.language == 'ps'
                    ? 'بریښنالیک د Gmail To: ساحه کې پیسټ کړئ، بیا خپل CV د ډاونلوډ فولډر څخه ضمیمه کړئ'
                    : widget.language == 'fa'
                        ? 'ایمیل را در فیلد To: Gmail بچسبانید، سپس CV خود را از Downloads ضمیمه کنید'
                        : "Paste the email in Gmail's To: field, then attach your CV from Downloads",
                style: const TextStyle(
                  color: _muted,
                  fontSize: 11,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),

              // Done button
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(
                    widget.language == 'ps'
                        ? 'سم دی'
                        : widget.language == 'fa'
                            ? 'باشه'
                            : 'Done',
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FileStatusRow extends StatelessWidget {
  final bool found;
  final String label;
  const _FileStatusRow({required this.found, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          found ? Icons.check_circle_rounded : Icons.cancel_rounded,
          color: found ? const Color(0xFF39EA2B) : Colors.red.shade400,
          size: 16,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: found
                  ? const Color(0xFF091733)
                  : Colors.red.shade400,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _FileRow extends StatelessWidget {
  final bool found;
  final String name;
  final String hint;
  const _FileRow({required this.found, required this.name, required this.hint});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          found ? Icons.check_circle_rounded : Icons.cancel_rounded,
          color: found ? const Color(0xFF39EA2B) : Colors.red.shade400,
          size: 16,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF091733),
                  fontSize: 12,
                ),
              ),
              if (!found)
                Text(
                  hint,
                  style: const TextStyle(
                    color: Color(0xFF65738A),
                    fontSize: 11,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  final String text;
  final bool isRtl;
  const _StepRow({required this.text, required this.isRtl});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      children: [
        const Icon(Icons.circle, size: 7, color: Color(0xFF39EA2B)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
                color: Color(0xFF091733),
                fontSize: 14,
                fontWeight: FontWeight.w500,
                height: 1.4),
          ),
        ),
      ],
    );
  }
}

// ── Glass surface ─────────────────────────────────────────────────────────────

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
