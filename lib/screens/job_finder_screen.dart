import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/language_provider.dart';
import '../services/analytics_service.dart';
import '../services/tts_service.dart';
import '../utils/location_helpers.dart';
import '../utils/navigation_helpers.dart';

// ── Data models ───────────────────────────────────────────────────────────────

class _Job {
  final String title;
  final String company;
  final String ort;
  final String plz;
  final String strasseHausnummer;
  final String refnr;

  const _Job({
    required this.title,
    required this.company,
    required this.ort,
    required this.plz,
    required this.strasseHausnummer,
    required this.refnr,
  });

  String get locationDisplay {
    if (plz.isNotEmpty && ort.isNotEmpty) return '$plz $ort';
    return ort;
  }

  factory _Job.fromJson(Map<String, dynamic> j) {
    final locs = j['stellenlokationen'] as List<dynamic>? ?? [];
    final loc  = locs.isNotEmpty ? locs.first as Map<String, dynamic> : {};
    final ao   = loc['adresse'] as Map<String, dynamic>? ?? {};
    return _Job(
      title:             j['stellenangebotsTitel'] as String? ?? '',
      company:           j['firma']                as String? ?? '',
      ort:               ao['ort']                 as String? ?? '',
      plz:               ao['plz']                 as String? ?? '',
      strasseHausnummer: ao['strasseHausnummer']   as String? ?? '',
      refnr:             j['referenznummer']       as String? ?? '',
    );
  }

}

class _JobDetail {
  final String description;
  final String? email;
  final String? applicationUrl;
  final String phone;
  final String website;

  const _JobDetail({
    required this.description,
    this.email,
    this.applicationUrl,
    this.phone = '',
    this.website = '',
  });

  factory _JobDetail.fromJson(Map<String, dynamic> j) {
    Map<String, dynamic> bew = {};
    for (final k in j.keys) {
      if (k.toLowerCase().startsWith('bewerbung')) {
        bew = (j[k] as Map<String, dynamic>?) ?? {};
        break;
      }
    }
    final firma = j['firma'] as Map<String, dynamic>? ?? {};
    final applicationUrl = (bew['url'] as String?)?.isNotEmpty == true
        ? bew['url'] as String
        : (j['externeURL'] as String?)?.isNotEmpty == true
            ? j['externeURL'] as String
            : j['allianzpartnerUrl'] as String?;
    final email = (bew['email'] as String?)?.isNotEmpty == true
        ? bew['email'] as String
        : (firma['email'] as String?)?.isNotEmpty == true
            ? firma['email'] as String
            : null;
    return _JobDetail(
      description:    j['stellenbeschreibung'] as String? ?? '',
      email:          email,
      applicationUrl: applicationUrl,
      phone:          firma['telefon']  as String? ?? '',
      website:        firma['homepage'] as String? ?? '',
    );
  }
}

// ── Category descriptor ───────────────────────────────────────────────────────

class _Cat {
  final String key;
  final String searchTerm;
  final IconData icon;
  final String en;
  final String ps;
  final String fa;
  final String psTts;
  final String faTts;

  const _Cat(this.key, this.searchTerm, this.icon, this.en, this.ps, this.fa,
      this.psTts, this.faTts);

  String label(String lang) {
    if (lang == 'ps') return ps;
    if (lang == 'fa') return fa;
    return en;
  }

  String tts(String lang) {
    if (lang == 'ps') return psTts;
    if (lang == 'fa') return faTts;
    return '';
  }
}

// ── Screen ────────────────────────────────────────────────────────────────────

class JobFinderScreen extends StatefulWidget {
  final String language;
  final bool voiceMode;

  const JobFinderScreen({
    super.key,
    required this.language,
    this.voiceMode = false,
  });

  @override
  State<JobFinderScreen> createState() => _JobFinderScreenState();
}

class _JobFinderScreenState extends State<JobFinderScreen> {
  // ── Design tokens ──────────────────────────────────────────────────────────

  static const Color _navy  = Color(0xFF091733);
  static const Color _green = Color(0xFF39EA2B);
  static const Color _muted = Color(0xFF65738A);

  // ── API constants ──────────────────────────────────────────────────────────

  static const _kApiKey   = 'jobboerse-jobsuche';
  static const _kBaseUrl  =
      'https://rest.arbeitsagentur.de/jobboerse/jobsuche-service/pc/v6/jobs';
  static const _kDetailBase =
      'https://rest.arbeitsagentur.de/jobboerse/jobsuche-service/pc/v4/jobdetails';

  static const _kRadii = [5, 10, 25, 50, 100];

  static const _kCategories = <_Cat>[
    _Cat('All',          '',                       Icons.apps_rounded,             'All',          'ټول',     'همه',      'ټول کارونه',        'همه کارها'),
    _Cat('Construction', 'Bauhelfer',              Icons.construction_rounded,     'Construction', 'جوړونه',  'ساختمان',  'ساختمانی کار',      'ساختمان'),
    _Cat('Cleaning',     'Reinigungskraft',        Icons.cleaning_services_rounded,'Cleaning',     'پاکوالی', 'نظافت',    'پاک کاری',          'نظافت'),
    _Cat('Kitchen',      'Küchenhilfe',            Icons.restaurant_rounded,       'Kitchen',      'آشپزخانه','آشپزخانه', 'پخلی یا اشپزی',    'آشپزی'),
    _Cat('Driving',      'Fahrer',                 Icons.local_shipping_rounded,   'Driving',      'چلونه',   'رانندگی',  'موټر چلول',         'رانندگی'),
    _Cat('Warehouse',    'Lagerhelfer',            Icons.warehouse_rounded,        'Warehouse',    'ګودام',   'انبار',    'ګودام کار',         'انبار'),
    _Cat('Security',     'Sicherheitsmitarbeiter', Icons.security_rounded,         'Security',     'امنیت',   'امنیت',    'سیکیورټی یا امنیت', 'امنیت'),
    _Cat('Packing',      'Packer',                 Icons.inventory_2_rounded,      'Packing',      'پیکینګ',  'بسته‌بندی','بسته بندي',         'بسته‌بندی'),
    _Cat('DHL',          'DHL Paketzusteller',     Icons.local_post_office_rounded,'DHL',          'DHL',     'DHL',      'ډي ایچ ایل',        'دی اچ ال'),
    _Cat('Amazon',       'Lagermitarbeiter',       Icons.shopping_bag_rounded,     'Amazon',       'ایمازون', 'آمازون',   'امازون',            'آمازون'),
  ];

  // ── Skill → BA search-term mapping ────────────────────────────────────────

  // Job-type chip labels are always German (Vollzeit/Teilzeit/Minijob),
  // regardless of app language — these are not translated. No "Alle" option:
  // a specific job type is always selected.
  static const _kJobTypes = <(String, String)>[
    ('vz',  'Vollzeit'),
    ('tz',  'Teilzeit'),
    ('mj',  'Minijob'),
  ];

  static const _kSkillToSearch = <String, String>{
    'cleaning':       'Reinigungskraft',
    'driving':        'Fahrer',
    'cooking':        'Küchenhilfe',
    'construction':   'Bauhelfer',
    'amazon_packing': 'Lagerhelfer',
    'packing':        'Packer',
    'security':       'Sicherheitsmitarbeiter',
    'dhl':            'DHL Paketzusteller',
    'farming':        'Gärtner',
    'forklift':       'Gabelstaplerfahrer',
  };

  // ── Auto-play guard (static = per class, reset on dispose) ────────────────

  static bool _hasAutoPlayed = false;

  // ── State ──────────────────────────────────────────────────────────────────

  String _lang            = 'en';
  String _city            = '';
  int    _selectedRadius      = 25;
  String _selectedCategoryKey = 'All';
  bool   _editingCity         = false;
  bool   _skillFiltered       = false;
  String _skillFilterTerm     = '';
  String _selectedJobType     = 'vz';
  bool   _locating            = false;
  Future<List<_Job>>? _jobsFuture;

  final _cityCtrl   = TextEditingController();
  final _searchCtrl = TextEditingController();
  final _cityFocus  = FocusNode();

  void _onSoundChange() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    AnalyticsService().logScreen('job_finder');
    TtsService().addListener(_onSoundChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<LanguageProvider>().syncFromNav(
          widget.language,
          voiceMode: widget.voiceMode,
        );
      }
    });
    // No default city anymore — wait for the user to type one or tap
    // "use my location" before running the first search.
    _scheduleAutoPlay();
    _loadUserSkillFilter();
    _loadSavedCity();
  }

  // Pre-fills the city from a previously-detected location (saved by
  // "use my location" on this screen or on ausbildung_screen.dart) so the
  // user isn't asked to re-detect or re-type it on every visit.
  Future<void> _loadSavedCity() async {
    final saved = await loadLastKnownCity();
    if (saved == null || !mounted || _city.isNotEmpty) return;
    setState(() {
      _city = saved;
      _cityCtrl.text = saved;
    });
    _refetch();
  }

  Future<void> _loadUserSkillFilter() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('saved_profile');
      if (raw == null || raw.isEmpty) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final skillStr = (map['skill'] as String?) ?? '';
      if (skillStr.isEmpty) return;
      for (final skill in skillStr.split(',').map((s) => s.trim())) {
        final term = _kSkillToSearch[skill];
        if (term != null) {
          if (!mounted) return;
          setState(() {
            _skillFiltered   = true;
            _skillFilterTerm = term;
          });
          if (_city.isNotEmpty) _refetch();
          return;
        }
      }
    } catch (_) {}
  }

  void _scheduleAutoPlay() {
    Future.delayed(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      if (_hasAutoPlayed) return;
      if (!TtsService().soundEnabled) return;

      final lang = _lang;
      _hasAutoPlayed = true;

      if (lang == 'ps') {
        TtsService().speak(
          'تاسی کولای شی دلته د خپلی خوښی کار وګورئ،'
              'اول د ښار نوم ولیکئ او د خپلی خوښی کار پیدا '
              'یا انتخاب کړئ',
          'ps',
        );
      } else if (lang == 'fa') {
        TtsService().speak(
          'اینجا کار مورد نظر خود را پیدا کنید، '
              'نام شهر را بنویسید و کار پیدا کنید',
          'fa',
        );
      }
    });
  }

  @override
  void dispose() {
    _hasAutoPlayed = false;
    TtsService().stop();
    TtsService().removeListener(_onSoundChange);
    _cityCtrl.dispose();
    _searchCtrl.dispose();
    _cityFocus.dispose();
    super.dispose();
  }

  // ── API — job list ─────────────────────────────────────────────────────────

  Future<List<_Job>> _fetchJobs() => _fetchJobsGermany();

  Future<List<_Job>> _fetchJobsGermany() async {
    final cat = _kCategories.firstWhere(
      (c) => c.key == _selectedCategoryKey,
      orElse: () => _kCategories.first,
    );
    final typed = _searchCtrl.text.trim();
    final String searchTerm;
    if (typed.isNotEmpty) {
      searchTerm = typed;
    } else if (_skillFiltered && _selectedCategoryKey == 'All') {
      searchTerm = _skillFilterTerm;
    } else {
      searchTerm = cat.searchTerm;
    }

    final params = <String, String>{
      'wo':          _city,
      'umkreis':     _selectedRadius.toString(),
      'page':        '1',
      'size':        '25',
      'angebotsart': '1',
      'pav':         'false',
    };
    if (searchTerm.isNotEmpty) params['was'] = searchTerm;
    params['arbeitszeit'] = _selectedJobType;

    final uri      = Uri.parse(_kBaseUrl).replace(queryParameters: params);
    final response = await http
        .get(uri, headers: {'X-API-Key': _kApiKey})
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      final data  = jsonDecode(response.body) as Map<String, dynamic>;
      final items = data['ergebnisliste'] as List<dynamic>? ?? [];
      return items
          .map((j) => _Job.fromJson(j as Map<String, dynamic>))
          .toList();
    }
    throw Exception('HTTP ${response.statusCode}');
  }

  void _refetch() {
    if (_city.isEmpty) return;
    setState(() { _jobsFuture = _fetchJobs(); });
    AnalyticsService().logJobSearch(_city, _selectedCategoryKey);
  }

  // ── API — job detail ───────────────────────────────────────────────────────

  Future<_JobDetail> _fetchJobDetail(String refnr) async {
    final encoded  = base64.encode(utf8.encode(refnr));
    final uri      = Uri.parse('$_kDetailBase/$encoded');
    final response = await http
        .get(uri, headers: {'X-API-Key': _kApiKey})
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return _JobDetail.fromJson(data);
    }
    throw Exception('HTTP ${response.statusCode}');
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _distanceLabel(_Job job) => job.locationDisplay;

  String _buildAddress(_Job job) =>
      [job.strasseHausnummer, job.plz, job.ort]
          .where((s) => s.isNotEmpty)
          .join(' ');

  static IconData _jobTypeIcon(String title) {
    final t = title.toLowerCase();
    if (t.contains('fahrer') || t.contains('driver') ||
        t.contains('transport') || t.contains('liefer')) {
      return Icons.local_shipping_rounded;
    }
    if (t.contains('küchen') || t.contains('koch') ||
        t.contains('kitchen') || t.contains('gastro')) {
      return Icons.restaurant_rounded;
    }
    if (t.contains('reinig') || t.contains('clean') ||
        t.contains('hauswirt')) {
      return Icons.cleaning_services_rounded;
    }
    if (t.contains('bau') || t.contains('construct') ||
        t.contains('maurer') || t.contains('helfer')) {
      return Icons.construction_rounded;
    }
    if (t.contains('lager') || t.contains('warehouse') ||
        t.contains('kommission')) {
      return Icons.warehouse_rounded;
    }
    if (t.contains('sicherheit') || t.contains('security') ||
        t.contains('wachmann')) {
      return Icons.security_rounded;
    }
    if (t.contains('pack') || t.contains('amazon') ||
        t.contains('dhl') || t.contains('versand')) {
      return Icons.inventory_2_rounded;
    }
    return Icons.work_rounded;
  }

  // ── Localised strings ──────────────────────────────────────────────────────

  String get _titleLabel {
    switch (_lang) {
      case 'ps': return 'کارونه پیدا کړئ';
      case 'fa': return 'کار پیدا کنید';
      default:   return 'Find Jobs';
    }
  }

  String get _cityHint {
    switch (_lang) {
      case 'ps': return 'دلته د ښار نوم ولیکئ';
      case 'fa': return 'نام شهر را بنویسید';
      default:   return 'Enter city name';
    }
  }

  String get _loadingLabel {
    switch (_lang) {
      case 'ps': return 'ستاسو سره نږدې کارونه پلټل کیږي...';
      case 'fa': return 'در حال جستجوی کارهای نزدیک شما...';
      default:   return 'Finding jobs near you...';
    }
  }

  String get _errorLabel {
    switch (_lang) {
      case 'ps': return 'کارونه لوډ نشول. خپل انټرنیټ وګورئ.';
      case 'fa': return 'بارگذاری ناموفق بود. اتصال را بررسی کنید.';
      default:   return 'Could not load jobs. Check your connection.';
    }
  }

  String get _emptyLabel {
    switch (_lang) {
      case 'ps': return 'په دې سیمه کې کارونه ونه موندل شول';
      case 'fa': return 'در این منطقه کاری یافت نشد';
      default:   return 'No jobs found in this area';
    }
  }

  String get _emptySuggestion {
    switch (_lang) {
      case 'ps': return 'بل ښار یا لوی واټن هڅه وکړئ';
      case 'fa': return 'شهر دیگری یا شعاع بیشتر امتحان کنید';
      default:   return 'Try a different city or a larger radius';
    }
  }

  String get _retryLabel {
    switch (_lang) {
      case 'ps': return 'بیا هڅه وکړئ';
      case 'fa': return 'دوباره تلاش کنید';
      default:   return 'Retry';
    }
  }

  String get _applyLabel {
    switch (_lang) {
      case 'ps': return 'غوښتنلیک';
      case 'fa': return 'ثبت نام';
      default:   return 'Apply';
    }
  }

  String get _applyNowLabel {
    switch (_lang) {
      case 'ps': return 'غوښتنه وکړئ';
      case 'fa': return 'درخواست دهید';
      default:   return 'Apply Now';
    }
  }

  String get _applyEmailLabel {
    switch (_lang) {
      case 'ps': return 'د ایمیل له لارې غوښتنه';
      case 'fa': return 'درخواست از طریق ایمیل';
      default:   return 'Apply via Email';
    }
  }

  String get _skipLabel {
    switch (_lang) {
      case 'ps': return 'رد کړئ';
      case 'fa': return 'رد کردن';
      default:   return 'Skip';
    }
  }

  String get _searchHint {
    switch (_lang) {
      case 'ps': return 'کار ولټوئ...';
      case 'fa': return 'جستجوی کار...';
      default:   return 'Search jobs...';
    }
  }

  String get _noEmailMessage {
    switch (_lang) {
      case 'ps':
        return 'ایمیل ونه موندل شو. تاسو کولی شئ مستقیم دی کمپنی ادرس ته لاړ شی او هلته غوښتنه وکړئ';
      case 'fa':
        return 'ایمیل یافت نشد. می‌توانید مستقیماً در این مکان درخواست دهید.';
      default:
        return 'No email found. You can apply in person at this location.';
    }
  }

  String get _openMapsLabel {
    switch (_lang) {
      case 'ps': return 'په ګوګل نقشه کې پرانیستل';
      case 'fa': return 'باز کردن در Google Maps';
      default:   return 'Find on Google Maps';
    }
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  void _goHome() {
    TtsService().stop();
    goHomeToIntroduction(context, language: _lang, voiceMode: widget.voiceMode);
  }

  void _commitCity(String value) {
    final v = value.trim();
    setState(() {
      if (v.isNotEmpty) _city = v;
      _editingCity = false;
    });
    if (v.isNotEmpty) _refetch();
  }

  String get _locationServiceDisabledMsg {
    switch (_lang) {
      case 'ps': return 'د لوکیشن خدمت غیرفعال دی. مهرباني وکړئ يې فعال کړئ.';
      case 'fa': return 'سرویس موقعیت‌مکانی غیرفعال است. لطفاً آن را فعال کنید.';
      default:   return 'Location services are disabled. Please enable them.';
    }
  }

  String get _locationPermissionDeniedMsg {
    switch (_lang) {
      case 'ps': return 'د لوکیشن اجازه ونه درکړل شوه. مهرباني وکړئ ښار پخپله ولیکئ.';
      case 'fa': return 'اجازه دسترسی به موقعیت داده نشد. لطفاً شهر را دستی وارد کنید.';
      default:   return 'Location permission denied. Please enter your city manually.';
    }
  }

  String get _locationLookupFailedMsg {
    switch (_lang) {
      case 'ps': return 'ستاسو ښار ونه موندل شو. مهرباني وکړئ يې پخپله ولیکئ.';
      case 'fa': return 'شهر شما پیدا نشد. لطفاً آن را به‌صورت دستی وارد کنید.';
      default:   return 'Could not detect your city. Please enter it manually.';
    }
  }

  Future<void> _useMyLocation() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      final result = await detectCurrentCity();
      if (result.city == null) {
        if (!mounted) return;
        switch (result.error!) {
          case LocationLookupError.serviceDisabled:
            _snack(_locationServiceDisabledMsg);
            break;
          case LocationLookupError.permissionDenied:
            _snack(_locationPermissionDeniedMsg);
            break;
          case LocationLookupError.lookupFailed:
            _snack(_locationLookupFailedMsg);
            break;
        }
        return;
      }

      if (!mounted) return;
      setState(() {
        _city = result.city!;
        _cityCtrl.text = result.city!;
        _editingCity = false;
      });
      _refetch();
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _launchGmail(String email, String jobTitle) async {
    final subject = 'Bewerbung: $jobTitle';
    final body =
        'Sehr geehrte Damen und Herren,\n\n'
        'hiermit bewerbe ich mich auf die ausgeschriebene \n'
        'Stelle als $jobTitle in Ihrem Unternehmen.\n\n'
        'Ich bin motiviert, zuverlässig und lernbereit. \n'
        'Ich freue mich auf die Möglichkeit, mich \n'
        'persönlich vorzustellen.\n\n'
        'Mit freundlichen Grüßen,\n'
        'Ihr Bewerber';
    final uri = Uri.parse(
      'mailto:$email'
      '?subject=${Uri.encodeComponent(subject)}'
      '&body=${Uri.encodeComponent(body)}',
    );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) _snack('Could not open email app');
    }
  }

  Future<void> _launchMaps(_Job job) async {
    final q = '${job.company} ${job.strasseHausnummer} ${job.ort}'.trim();
    final uri = Uri.parse(
      'https://www.google.com/maps/search/${Uri.encodeComponent(q)}',
    );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) _snack('Could not open Maps');
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF1A2B3C),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // Maps the selected job-type filter key to the German label used on the
  // apply screen's cover letter; empty when 'Alle' (no filter) is selected.
  String get _selectedJobTypeLabel {
    switch (_selectedJobType) {
      case 'vz': return 'Vollzeit';
      case 'tz': return 'Teilzeit';
      case 'mj': return 'Minijob';
      default:   return '';
    }
  }

  void _openJobDirect(_Job job) {
    final addrParts = <String>[];
    if (job.strasseHausnummer.isNotEmpty) addrParts.add(job.strasseHausnummer);
    final cityPart = [job.plz, job.ort].where((s) => s.isNotEmpty).join(' ');
    if (cityPart.isNotEmpty) addrParts.add(cityPart);

    final formUrl = 'https://www.arbeitsagentur.de/jobsuche/jobdetail/${job.refnr}';

    Navigator.pushNamed(
      context,
      '/job_apply',
      arguments: <String, String>{
        'jobTitle':       job.title,
        'companyName':    job.company,
        'companyAddress': addrParts.join(', '),
        'jobLocation':    job.locationDisplay,
        'formUrl':        formUrl,
        'companyPhone':   '',
        'companyEmail':   '',
        'companyWebsite': '',
        'refnr':          job.refnr,
        'language':       _lang,
        'voiceMode':      widget.voiceMode.toString(),
        'jobType':        _selectedJobTypeLabel,
      },
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    _lang = context.watch<LanguageProvider>().language;
    final isRtl       = _lang == 'ps' || _lang == 'fa';
    final showSpeaker = _lang == 'ps' || _lang == 'fa';

    return PopScope(
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
                // Filter order: city, then job search text, then the
                // Job Type | Sort (category) | Distance dropdown row.
                _buildHeader(showSpeaker),
                const SizedBox(height: 8),
                _buildLocationCard(),
                if (!widget.voiceMode) ...[
                  const SizedBox(height: 10),
                  _buildSearchBar(isRtl),
                ],
                const SizedBox(height: 10),
                _buildFilterDropdownRow(),
                if (_skillFiltered) ...[
                  const SizedBox(height: 6),
                  _buildSkillFilterBanner(),
                ],
                const SizedBox(height: 8),
                Expanded(
                  child: _jobsFuture == null
                      ? _buildCityPrompt()
                      : FutureBuilder<List<_Job>>(
                          future: _jobsFuture,
                          builder: (_, snap) {
                            if (snap.connectionState ==
                                ConnectionState.waiting) {
                              return _buildLoading();
                            }
                            if (snap.hasError) return _buildError();
                            final jobs = snap.data ?? [];
                            if (jobs.isEmpty) return _buildEmpty();
                            return _buildJobList(jobs, isRtl);
                          },
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────

  Widget _buildHeader(bool showSpeaker) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          _NavBtn(icon: Icons.home_rounded, onTap: _goHome),
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
          _LangPill(
            lang: _lang,
            onLanguageChanged: (_, __) {
              if (mounted) setState(() {});
            },
          ),
          const SizedBox(width: 8),
          _NavBtn(
            icon: TtsService().soundEnabled
                ? Icons.volume_up_rounded
                : Icons.volume_off_rounded,
            active: TtsService().soundEnabled,
            hintPulse: TtsService().hintPulseActive,
            onTap: () {
              TtsService().toggleSound();
              setState(() {});
            },
          ),
        ],
      ),
    );
  }

  // ── Location card ──────────────────────────────────────────────────────────

  Widget _buildLocationCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.85),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.9), width: 1.2),
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
          children: [
            const Icon(Icons.location_on_rounded, color: _green, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: _editingCity
                  ? TextField(
                      controller: _cityCtrl,
                      focusNode: _cityFocus,
                      autofocus: true,
                      style: const TextStyle(
                        color: _navy,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        hintText: _cityHint,
                        hintStyle:
                            const TextStyle(color: _muted, fontSize: 14),
                      ),
                      onSubmitted: _commitCity,
                    )
                  : GestureDetector(
                      onTap: () {
                        _cityCtrl.text = _city;
                        setState(() => _editingCity = true);
                        Future.delayed(const Duration(milliseconds: 50), () {
                          _cityFocus.requestFocus();
                        });
                      },
                      child: Text(
                        _city.isEmpty ? _cityHint : _city,
                        style: TextStyle(
                          color: _city.isEmpty ? _muted : _navy,
                          fontSize: 14,
                          fontWeight:
                              _city.isEmpty ? FontWeight.w500 : FontWeight.w600,
                        ),
                      ),
                    ),
            ),
            if (!_editingCity && _lang == 'ps') ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () =>
                    TtsService().speak('دلته د ښار نوم ولیکئ', 'ps'),
                child: const Icon(Icons.volume_up_rounded,
                    color: _green, size: 16),
              ),
            ],
            const SizedBox(width: 6),
            GestureDetector(
              onTap: _locating ? null : _useMyLocation,
              child: _locating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: _green),
                    )
                  : const Icon(Icons.my_location_rounded,
                      color: _green, size: 20),
            ),
            const SizedBox(width: 6),
            if (_editingCity)
              GestureDetector(
                onTap: () => _commitCity(_cityCtrl.text),
                child: const Icon(Icons.check_rounded,
                    color: _green, size: 22),
              )
            else
              const Icon(Icons.search_rounded, color: _green, size: 22),
          ],
        ),
      ),
    );
  }

  // ── Filter dropdown row (Job Type | Sort/Category | Distance) ─────────────
  //
  // Replaces the old horizontal chip rows with three compact dropdown pills
  // that open a bottom sheet of options. Same underlying state and refetch
  // logic as the chips they replace — this is a UI-only change.

  Widget _buildFilterDropdownRow() {
    final jobTypeLabel = _kJobTypes
        .firstWhere((t) => t.$1 == _selectedJobType, orElse: () => _kJobTypes.first)
        .$2;
    final categoryLabel = _kCategories
        .firstWhere((c) => c.key == _selectedCategoryKey, orElse: () => _kCategories.first)
        .label(_lang);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: _dropdownPill(label: jobTypeLabel, onTap: _showJobTypeSheet),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _dropdownPill(label: categoryLabel, onTap: _showCategorySheet),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _dropdownPill(
                label: '${_selectedRadius}km', onTap: _showRadiusSheet),
          ),
        ],
      ),
    );
  }

  Widget _dropdownPill({required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.85),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: Colors.white.withOpacity(0.9), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _navy,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.keyboard_arrow_down_rounded,
                color: _muted, size: 18),
          ],
        ),
      ),
    );
  }

  // ── Filter bottom sheets ────────────────────────────────────────────────

  void _openFilterSheet(List<Widget> options) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.7,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD1D9E6),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Flexible(
              child: SingleChildScrollView(
                child: Column(children: options),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sheetOption({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? _green.withOpacity(0.10) : const Color(0xFFF7FAFF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? _green : const Color(0xFFE4EAF5),
            width: selected ? 2.0 : 1.2,
          ),
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: selected ? _green : _muted),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: _navy,
                  fontSize: 15,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle_rounded, color: _green, size: 20),
          ],
        ),
      ),
    );
  }

  void _showJobTypeSheet() {
    _openFilterSheet(_kJobTypes.map((t) {
      final selected = t.$1 == _selectedJobType;
      return _sheetOption(
        label: t.$2, // always German — not translated
        selected: selected,
        onTap: () {
          Navigator.pop(context);
          if (!selected) {
            setState(() => _selectedJobType = t.$1);
            _refetch();
          }
        },
      );
    }).toList());
  }

  void _showRadiusSheet() {
    _openFilterSheet(_kRadii.map((r) {
      final selected = r == _selectedRadius;
      return _sheetOption(
        label: '${r}km',
        selected: selected,
        onTap: () {
          Navigator.pop(context);
          if (!selected) {
            setState(() => _selectedRadius = r);
            _refetch();
          }
        },
      );
    }).toList());
  }

  void _showCategorySheet() {
    _openFilterSheet(_kCategories.map((cat) {
      final selected = cat.key == _selectedCategoryKey;
      return _sheetOption(
        label: cat.label(_lang),
        selected: selected,
        icon: cat.icon,
        onTap: () {
          Navigator.pop(context);
          if (_lang == 'ps' || _lang == 'fa') {
            final t = cat.tts(_lang);
            if (t.isNotEmpty) TtsService().speak(t, _lang);
          }
          if (!selected) {
            _searchCtrl.clear();
            setState(() {
              _selectedCategoryKey = cat.key;
              _skillFiltered = false;
            });
            _refetch();
          }
        },
      );
    }).toList());
  }

  // ── Search bar (educated only) ─────────────────────────────────────────────

  Widget _buildSearchBar(bool isRtl) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.85),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: Colors.white.withOpacity(0.9), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
            ),
          ],
        ),
        child: Row(
          textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
          children: [
            Icon(Icons.search_rounded, color: _muted, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                textDirection:
                    isRtl ? TextDirection.rtl : TextDirection.ltr,
                style: const TextStyle(color: _navy, fontSize: 14),
                decoration: InputDecoration(
                  hintText: _searchHint,
                  hintStyle:
                      const TextStyle(color: _muted, fontSize: 14),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                onSubmitted: (_) => _refetch(),
              ),
            ),
            GestureDetector(
              onTap: _refetch,
              child: const Icon(Icons.arrow_forward_rounded,
                  color: _green, size: 20),
            ),
            if (_lang == 'ps') ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => TtsService().speak(
                    'دلته د خپلی خوښی کار وګورئ', 'ps'),
                child: const Icon(Icons.volume_up_rounded,
                    color: _green, size: 18),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Skill filter banner ────────────────────────────────────────────────────

  Widget _buildSkillFilterBanner() {
    final label = _lang == 'ps'
        ? 'ستاسو د مهارتونو سره سم کارونه ښودل کیږي'
        : _lang == 'fa'
            ? 'مشاغل مطابق با مهارت‌های شما نمایش داده می‌شود'
            : 'Showing jobs matching your skills';
    final showAllLabel = _lang == 'ps' ? 'ټول کارونه'
        : _lang == 'fa' ? 'همه مشاغل'
        : 'Show All Jobs';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFEAFBE9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _green.withOpacity(0.4)),
        ),
        child: Row(
          children: [
            const Icon(Icons.auto_awesome_rounded, color: _green, size: 14),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: _navy, fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                setState(() {
                  _skillFiltered = false;
                  _selectedCategoryKey = 'All';
                });
                _refetch();
              },
              child: Text(
                showAllLabel,
                style: const TextStyle(
                  color: _green,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.underline,
                  decorationColor: _green,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Loading state ──────────────────────────────────────────────────────────

  Widget _buildLoading() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: _GlassSurface(
          borderRadius: 20,
          padding: const EdgeInsets.all(32),
          shadowOpacity: 0.10,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(
                  color: _green, strokeWidth: 2.5),
              const SizedBox(height: 20),
              Text(
                _loadingLabel,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _navy,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Error state ────────────────────────────────────────────────────────────

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: _GlassSurface(
          borderRadius: 20,
          padding: const EdgeInsets.all(28),
          shadowOpacity: 0.10,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_rounded,
                  color: Colors.redAccent, size: 48),
              const SizedBox(height: 16),
              Text(
                _errorLabel,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _navy,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: _refetch,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 32, vertical: 14),
                  decoration: BoxDecoration(
                    color: _green,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: _green.withOpacity(0.30),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Text(
                    _retryLabel,
                    style: const TextStyle(
                      color: _navy,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
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

  // ── City prompt (no default city — shown until the user provides one) ─────

  String get _cityPromptLabel {
    switch (_lang) {
      case 'ps': return 'د کارونو د موندلو لپاره خپل ښار ولیکئ یا خپل موقعیت وکاروئ';
      case 'fa': return 'برای یافتن کارها، نام شهر خود را بنویسید یا از موقعیت مکانی خود استفاده کنید';
      default:   return 'Enter your city or use your location to find jobs near you';
    }
  }

  String get _useMyLocationLabel {
    switch (_lang) {
      case 'ps': return 'زما موقعیت وکاروئ';
      case 'fa': return 'استفاده از موقعیت من';
      default:   return 'Use my location';
    }
  }

  Widget _buildCityPrompt() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: _GlassSurface(
          borderRadius: 20,
          padding: const EdgeInsets.all(28),
          shadowOpacity: 0.10,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.location_searching_rounded, color: _muted, size: 52),
              const SizedBox(height: 16),
              Text(
                _cityPromptLabel,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _navy,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: _locating ? null : _useMyLocation,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: _green,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: _green.withOpacity(0.30),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_locating)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: _navy),
                        )
                      else
                        const Icon(Icons.my_location_rounded,
                            color: _navy, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        _useMyLocationLabel,
                        style: const TextStyle(
                          color: _navy,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Empty state ────────────────────────────────────────────────────────────

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: _GlassSurface(
          borderRadius: 20,
          padding: const EdgeInsets.all(28),
          shadowOpacity: 0.10,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off_rounded, color: _muted, size: 52),
              const SizedBox(height: 16),
              Text(
                _emptyLabel,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _navy,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _emptySuggestion,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _muted,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Job list ───────────────────────────────────────────────────────────────

  Widget _buildJobList(List<_Job> jobs, bool isRtl) {
    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: jobs.length,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _buildJobCard(jobs[i], isRtl),
      ),
    );
  }

  Widget _buildJobCard(_Job job, bool isRtl) {
    final dist           = _distanceLabel(job);
    final icon           = _jobTypeIcon(job.title);
    final voice          = widget.voiceMode;
    final showSpeakerOnCard = voice && (_lang == 'ps' || _lang == 'fa');

    return GestureDetector(
      onTap: () => _openJobDirect(job),
      child: Container(
        padding: EdgeInsets.all(voice ? 16 : 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: Colors.white.withOpacity(0.9), width: 1.2),
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
        child: voice
            ? _buildVoiceCard(job, dist, icon, showSpeakerOnCard, isRtl)
            : _buildCompactCard(job, dist, icon, isRtl),
      ),
    );
  }

  // ── Compact card (educated) ────────────────────────────────────────────────

  Widget _buildCompactCard(
      _Job job, String dist, IconData icon, bool isRtl) {
    return Row(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: const Color(0xFFEAFBE9),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: _green.withOpacity(0.3), width: 1),
          ),
          child: Icon(icon, color: _green, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment:
                isRtl ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Text(
                job.company,
                textDirection:
                    isRtl ? TextDirection.rtl : TextDirection.ltr,
                style: const TextStyle(
                  color: _navy,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                job.title,
                textDirection:
                    isRtl ? TextDirection.rtl : TextDirection.ltr,
                style: const TextStyle(
                  color: _muted,
                  fontSize: 13,
                  height: 1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Row(
                textDirection:
                    isRtl ? TextDirection.rtl : TextDirection.ltr,
                children: [
                  const Icon(Icons.location_on_rounded,
                      color: _muted, size: 12),
                  const SizedBox(width: 3),
                  Expanded(
                    child: Text(
                      dist,
                      textDirection:
                          isRtl ? TextDirection.rtl : TextDirection.ltr,
                      style: const TextStyle(
                          color: _muted, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        const Icon(Icons.arrow_forward_ios_rounded, color: _green, size: 16),
      ],
    );
  }

  // ── Voice card (uneducated) ────────────────────────────────────────────────

  Widget _buildVoiceCard(
      _Job job, String dist, IconData icon, bool showSpeaker, bool isRtl) {
    return Column(
      crossAxisAlignment:
          isRtl ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Row(
          textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFFEAFBE9),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: _green.withOpacity(0.3), width: 1),
              ),
              child: Icon(icon, color: _green, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: isRtl
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  Text(
                    job.company,
                    textDirection:
                        isRtl ? TextDirection.rtl : TextDirection.ltr,
                    style: const TextStyle(
                      color: _navy,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    job.title,
                    textDirection:
                        isRtl ? TextDirection.rtl : TextDirection.ltr,
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 13,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (showSpeaker) ...[
              const SizedBox(width: 10),
              GestureDetector(
                onTap: () => TtsService().speak(
                  'د ${job.company} شرکت کې ${job.title} دنده', 'ps'),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAFBE9),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: _green.withOpacity(0.3), width: 1),
                  ),
                  child: const Icon(Icons.volume_up_rounded,
                      color: _green, size: 18),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        Row(
          textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
          children: [
            const Icon(Icons.location_on_rounded,
                color: _muted, size: 14),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                dist,
                textDirection:
                    isRtl ? TextDirection.rtl : TextDirection.ltr,
                style: const TextStyle(color: _muted, fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: GestureDetector(
            onTap: () => _openJobDirect(job),
            child: Container(
              height: 50,
              decoration: BoxDecoration(
                color: _green,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: _green.withOpacity(0.30),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  _applyLabel,
                  style: const TextStyle(
                    color: _navy,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Language pill — same style/behavior as introduction_screen.dart's _LangPill
// ─────────────────────────────────────────────────────────────────────────────

class _LangPill extends StatelessWidget {
  static const Color _navy = Color(0xFF091733);

  final String lang;
  final void Function(String newLang, bool voiceMode)? onLanguageChanged;

  const _LangPill({required this.lang, this.onLanguageChanged});

  String get _label {
    switch (lang) {
      case 'ps': return 'PS';
      case 'fa': return 'FA';
      default:   return 'EN';
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        final provider = context.read<LanguageProvider>();
        final currentVoiceMode = provider.voiceMode;
        showModalBottomSheet(
          context: context,
          backgroundColor: Colors.transparent,
          isScrollControlled: true,
          builder: (ctx) => _LanguagePicker(
            currentLang: lang,
            onSelect: (newLang) async {
              Navigator.pop(ctx);
              // Switching TO English always forces the educated interface;
              // switching between Pashto/Dari leaves voiceMode untouched.
              final voiceMode = newLang == 'en' ? false : currentVoiceMode;
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('voice_mode', voiceMode);
              await prefs.setString('app_language', newLang);
              provider.syncFromNav(newLang, voiceMode: voiceMode);
              onLanguageChanged?.call(newLang, voiceMode);
            },
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: _navy,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: _navy.withOpacity(0.20),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _label,
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

// ─────────────────────────────────────────────────────────────────────────────
// Language picker bottom sheet — same as introduction_screen.dart's
// ─────────────────────────────────────────────────────────────────────────────

class _LanguagePicker extends StatelessWidget {
  static const Color _navy  = Color(0xFF091733);
  static const Color _green = Color(0xFF39EA2B);

  final String currentLang;
  final ValueChanged<String> onSelect;

  const _LanguagePicker({
    required this.currentLang,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final langs = [
      {'code': 'ps', 'native': 'پښتو',    'roman': 'Pashto'},
      {'code': 'fa', 'native': 'دری',     'roman': 'Dari'},
      {'code': 'en', 'native': 'English', 'roman': 'English'},
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD1D9E6),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Language / ژبه / زبان',
            style: TextStyle(
              color: _navy,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          ...langs.map((e) {
            final isSelected = e['code'] == currentLang;
            return GestureDetector(
              onTap: () => onSelect(e['code']!),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: isSelected
                      ? _green.withOpacity(0.08)
                      : const Color(0xFFF7FAFF),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected ? _green : const Color(0xFFE4EAF5),
                    width: isSelected ? 2.0 : 1.2,
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      e['native']!,
                      style: TextStyle(
                        color: _navy,
                        fontSize: 16,
                        fontWeight: isSelected
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      e['roman']!,
                      style: const TextStyle(
                        color: Color(0xFF65738A),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    if (isSelected)
                      const Icon(Icons.check_circle_rounded,
                          color: _green, size: 20),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Nav button (glass surface)
// ─────────────────────────────────────────────────────────────────────────────

class _NavBtn extends StatelessWidget {
  static const Color _navy  = Color(0xFF091733);
  static const Color _green = Color(0xFF39EA2B);

  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  final bool hintPulse;

  const _NavBtn({
    required this.icon,
    required this.onTap,
    this.active = false,
    this.hintPulse = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        decoration: BoxDecoration(
          color: hintPulse
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
          child: Icon(icon, color: active ? _green : _navy, size: 20),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Background glow — copied from welcome_screen.dart
// ─────────────────────────────────────────────────────────────────────────────

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
        Positioned(top: 70,    left: -42,  child: _Orb(size: 170, color: Color(0x6639EA2B))),
        Positioned(top: 135,   right: -65, child: _Orb(size: 170, color: Color(0x44FFB86B))),
        Positioned(bottom: 95, left: -60,  child: _Orb(size: 210, color: Color(0x3339EA2B))),
        Positioned(bottom: -30,right: 14,  child: _Orb(size: 145, color: Color(0x5539EA2B))),
        Positioned(top: 20,    left: 30,   child: _Orb(size: 170, color: Color(0x30FF8FA3))),
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

// ─────────────────────────────────────────────────────────────────────────────
// Glass surface — copied from welcome_screen.dart
// ─────────────────────────────────────────────────────────────────────────────

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
