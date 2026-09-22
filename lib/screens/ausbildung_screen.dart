import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../providers/language_provider.dart';
import '../services/analytics_service.dart';
import '../services/tts_service.dart';
import '../utils/location_helpers.dart';
import '../utils/navigation_helpers.dart';

// ── Data model ────────────────────────────────────────────────────────────────

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

// ── Category descriptor ───────────────────────────────────────────────────────

class _Cat {
  final String key;
  final String searchTerm;
  final IconData icon;
  final String en;
  final String ps;
  final String fa;

  const _Cat(this.key, this.searchTerm, this.icon, this.en, this.ps, this.fa);

  String label(String lang) {
    if (lang == 'ps') return ps;
    if (lang == 'fa') return fa;
    return en;
  }
}

// ── Screen ────────────────────────────────────────────────────────────────────

class AusbildungScreen extends StatefulWidget {
  final String language;
  final bool voiceMode;

  const AusbildungScreen({
    super.key,
    required this.language,
    this.voiceMode = false,
  });

  @override
  State<AusbildungScreen> createState() => _AusbildungScreenState();
}

class _AusbildungScreenState extends State<AusbildungScreen> {
  static const Color _navy  = Color(0xFF091733);
  static const Color _green = Color(0xFF39EA2B);
  static const Color _muted = Color(0xFF65738A);

  static const _kApiKey  = 'jobboerse-jobsuche';
  static const _kBaseUrl =
      'https://rest.arbeitsagentur.de/jobboerse/jobsuche-service/pc/v6/jobs';

  static const _kRadii = [5, 10, 25, 50, 100];

  static const _kCats = <_Cat>[
    _Cat('All',          '',                        Icons.apps_rounded,              'All',          'ټول',      'همه'),
    _Cat('IT',           'Fachinformatiker',         Icons.computer_rounded,          'IT / Tech',    'IT / ټیک', 'IT / فناوری'),
    _Cat('Handwerk',     'Handwerk Ausbildung',      Icons.build_rounded,             'Trades',       'کسب',      'صنعت'),
    _Cat('Einzelhandel', 'Kaufmann Einzelhandel',    Icons.store_rounded,             'Retail',       'پلور',     'خرده‌فروشی'),
    _Cat('Gesundheit',   'Pflege Ausbildung',        Icons.health_and_safety_rounded, 'Health',       'روغتیا',   'بهداشت'),
    _Cat('Buero',        'Kaufmann Büromanagement',  Icons.business_center_rounded,   'Office',       'دفتر',     'اداری'),
    _Cat('Gastro',       'Koch Ausbildung',          Icons.restaurant_rounded,        'Gastronomy',   'هوتل',     'هتل‌داری'),
    _Cat('Bau',          'Bauhandwerk Ausbildung',   Icons.construction_rounded,      'Construction', 'ساختمان',  'ساختمان'),
    _Cat('Logistik',     'Fachlagerist',             Icons.local_shipping_rounded,    'Logistics',    'لوجستیک',  'لجستیک'),
  ];

  String _lang           = 'en';
  String _city           = '';
  int    _selectedRadius = 25;
  String _selectedCatKey = 'All';
  bool   _editingCity    = false;
  bool   _locating       = false;
  Future<List<_Job>>? _jobsFuture;

  final _cityCtrl   = TextEditingController();
  final _searchCtrl = TextEditingController();
  final _cityFocus  = FocusNode();

  void _onSoundChange() { if (mounted) setState(() {}); }

  @override
  void initState() {
    super.initState();
    AnalyticsService().logScreen('ausbildung');
    TtsService().addListener(_onSoundChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<LanguageProvider>().syncFromNav(
          widget.language,
          voiceMode: widget.voiceMode,
        );
      }
    });
    // No default city — pre-fill from a previously-detected location if one
    // was saved (by this screen or job_finder_screen.dart), otherwise wait
    // for the user to type a city or tap "use my location".
    _loadSavedCity();
  }

  Future<void> _loadSavedCity() async {
    final saved = await loadLastKnownCity();
    if (saved == null || !mounted || _city.isNotEmpty) return;
    setState(() {
      _city = saved;
      _cityCtrl.text = saved;
    });
    _refetch();
  }

  @override
  void dispose() {
    TtsService().removeListener(_onSoundChange);
    _cityCtrl.dispose();
    _searchCtrl.dispose();
    _cityFocus.dispose();
    super.dispose();
  }

  // ── API ───────────────────────────────────────────────────────────────────

  Future<List<_Job>> _fetch() async {
    final cat = _kCats.firstWhere(
      (c) => c.key == _selectedCatKey,
      orElse: () => _kCats.first,
    );
    final typed = _searchCtrl.text.trim();
    final searchTerm = typed.isNotEmpty ? typed : cat.searchTerm;
    final params = <String, String>{
      'wo':          _city,
      'umkreis':     _selectedRadius.toString(),
      'page':        '1',
      'size':        '25',
      'angebotsart': '4',
      'pav':         'false',
    };
    if (searchTerm.isNotEmpty) params['was'] = searchTerm;

    final uri      = Uri.parse(_kBaseUrl).replace(queryParameters: params);
    final response = await http
        .get(uri, headers: {'X-API-Key': _kApiKey})
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      final data  = jsonDecode(response.body) as Map<String, dynamic>;
      final items = data['ergebnisliste'] as List<dynamic>? ?? [];
      return items.map((j) => _Job.fromJson(j as Map<String, dynamic>)).toList();
    }
    throw Exception('HTTP ${response.statusCode}');
  }

  void _refetch() {
    if (_city.isEmpty) return;
    setState(() { _jobsFuture = _fetch(); });
  }

  void _commitCity(String v) {
    final s = v.trim();
    setState(() {
      if (s.isNotEmpty) _city = s;
      _editingCity = false;
    });
    if (s.isNotEmpty) _refetch();
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

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF1A2B3C),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // Same destination every other "Home" button in the app uses (see
  // ausbildung_document_preview_screen.dart's _goHome()).
  void _goHome() {
    TtsService().stop();
    goHomeToIntroduction(context, language: _lang, voiceMode: widget.voiceMode);
  }

  void _openJob(_Job job) async {
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    final addrParts = <String>[];
    if (job.strasseHausnummer.isNotEmpty) addrParts.add(job.strasseHausnummer);
    final cityPart = [job.plz, job.ort].where((s) => s.isNotEmpty).join(' ');
    if (cityPart.isNotEmpty) addrParts.add(cityPart);
    Navigator.pushNamed(
      context,
      '/job_apply',
      arguments: <String, String>{
        'jobTitle':       job.title,
        'companyName':    job.company,
        'companyAddress': addrParts.join(', '),
        'jobLocation':    job.locationDisplay,
        'formUrl':        'https://www.arbeitsagentur.de/jobsuche/jobdetail/${job.refnr}',
        'companyPhone':   '',
        'companyEmail':   '',
        'companyWebsite': '',
        'refnr':          job.refnr,
        'language':       _lang,
        'voiceMode':      widget.voiceMode.toString(),
        'isAusbildung':   'true',
      },
    );
  }

  // ── Localised strings ─────────────────────────────────────────────────────

  String get _titleLabel {
    switch (_lang) {
      case 'ps': return 'د زده کړې کار ومومئ';
      case 'fa': return 'کارآموزی پیدا کنید';
      default:   return 'Find Ausbildung';
    }
  }

  String get _cityHint {
    switch (_lang) {
      case 'ps': return 'دلته د ښار نوم ولیکئ';
      case 'fa': return 'نام شهر را بنویسید';
      default:   return 'Enter city name';
    }
  }


  String get _loadingLbl {
    switch (_lang) {
      case 'ps': return 'د زده کړې کارونه پلټل کیږي...';
      case 'fa': return 'در حال جستجوی کارآموزی...';
      default:   return 'Searching apprenticeships...';
    }
  }

  String get _errorLbl {
    switch (_lang) {
      case 'ps': return 'کارونه لوډ نشول. انټرنیټ وګورئ.';
      case 'fa': return 'بارگذاری ناموفق. اتصال را بررسی کنید.';
      default:   return 'Could not load. Check your connection.';
    }
  }

  String get _emptyLbl {
    switch (_lang) {
      case 'ps': return 'د زده کړې کارونه ونه موندل شول';
      case 'fa': return 'کارآموزی یافت نشد';
      default:   return 'No apprenticeships found';
    }
  }

  String get _retryLbl {
    switch (_lang) {
      case 'ps': return 'بیا هڅه وکړئ';
      case 'fa': return 'دوباره تلاش کنید';
      default:   return 'Retry';
    }
  }

  String get _applyLbl {
    switch (_lang) {
      case 'ps': return 'غوښتنلیک';
      case 'fa': return 'ثبت نام';
      default:   return 'Apply';
    }
  }

  String get _searchHint {
    switch (_lang) {
      case 'ps': return 'د زده کړې کار ولټوئ...';
      case 'fa': return 'جستجوی کارآموزی...';
      default:   return 'Search apprenticeships...';
    }
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

  String get _cityPromptLabel {
    switch (_lang) {
      case 'ps': return 'د زده کړې کارونو د موندلو لپاره خپل ښار ولیکئ یا خپل موقعیت وکاروئ';
      case 'fa': return 'برای یافتن کارآموزی، نام شهر خود را بنویسید یا از موقعیت مکانی خود استفاده کنید';
      default:   return 'Enter your city or use your location to find apprenticeships near you';
    }
  }

  String get _useMyLocationLabel {
    switch (_lang) {
      case 'ps': return 'زما موقعیت وکاروئ';
      case 'fa': return 'استفاده از موقعیت من';
      default:   return 'Use my location';
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    _lang = context.watch<LanguageProvider>().language;
    final isRtl = _lang == 'ps' || _lang == 'fa';

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
                _buildHeader(),
                const SizedBox(height: 8),
                _buildLocationCard(),
                const SizedBox(height: 10),
                _buildSearchBar(isRtl),
                const SizedBox(height: 10),
                _buildFilterDropdownRow(),
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
                            return _buildList(jobs, isRtl);
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

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          _NavBtn(
            icon: Icons.arrow_back_ios_new_rounded,
            onTap: () {
              TtsService().stop();
              Navigator.pop(context);
            },
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

  // ── Location card ─────────────────────────────────────────────────────────

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
                          color: _navy, fontSize: 14, fontWeight: FontWeight.w600),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        hintText: _cityHint,
                        hintStyle: const TextStyle(color: _muted, fontSize: 14),
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
                child: const Icon(Icons.check_rounded, color: _green, size: 22),
              )
            else
              const Icon(Icons.search_rounded, color: _green, size: 22),
          ],
        ),
      ),
    );
  }

  // ── City prompt (no default city — shown until the user provides one) ─────

  Widget _buildCityPrompt() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: _GlassSurface(
          borderRadius: 20,
          padding: const EdgeInsets.all(28),
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

  // ── Search bar (free-text keyword search) ──────────────────────────────────

  Widget _buildSearchBar(bool isRtl) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.85),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.9), width: 1.2),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8),
          ],
        ),
        child: Row(
          textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
          children: [
            const Icon(Icons.search_rounded, color: _muted, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
                style: const TextStyle(color: _navy, fontSize: 14),
                decoration: InputDecoration(
                  hintText: _searchHint,
                  hintStyle: const TextStyle(color: _muted, fontSize: 14),
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
                onTap: () =>
                    TtsService().speak('د زده کړې کار ولټوئ', 'ps'),
                child: const Icon(Icons.volume_up_rounded,
                    color: _green, size: 18),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Filter dropdown row (Category | Distance) ─────────────────────────────
  //
  // Same compact pill-dropdown pattern as job_finder_screen.dart's
  // _buildFilterDropdownRow/_dropdownPill/_openFilterSheet/_sheetOption —
  // copied precisely for visual and behavioral consistency between the two
  // screens. Same underlying state and refetch logic as the chip rows they
  // replace — this is a UI-only change.

  Widget _buildFilterDropdownRow() {
    final categoryLabel = _kCats
        .firstWhere((c) => c.key == _selectedCatKey, orElse: () => _kCats.first)
        .label(_lang);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
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
    _openFilterSheet(_kCats.map((cat) {
      final selected = cat.key == _selectedCatKey;
      return _sheetOption(
        label: cat.label(_lang),
        selected: selected,
        icon: cat.icon,
        onTap: () {
          Navigator.pop(context);
          if (!selected) {
            _searchCtrl.clear();
            setState(() => _selectedCatKey = cat.key);
            _refetch();
          }
        },
      );
    }).toList());
  }

  // ── Loading / error / empty ───────────────────────────────────────────────

  Widget _buildLoading() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: _GlassSurface(
          borderRadius: 20,
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: _green, strokeWidth: 2.5),
              const SizedBox(height: 20),
              Text(_loadingLbl,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _navy, fontSize: 14, height: 1.5)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: _GlassSurface(
          borderRadius: 20,
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_rounded, color: Colors.redAccent, size: 48),
              const SizedBox(height: 16),
              Text(_errorLbl,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _navy, fontSize: 14, height: 1.5)),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: _refetch,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  decoration: BoxDecoration(
                    color: _green,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(_retryLbl,
                      style: const TextStyle(
                          color: _navy, fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: _GlassSurface(
          borderRadius: 20,
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off_rounded, color: _muted, size: 52),
              const SizedBox(height: 16),
              Text(_emptyLbl,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: _navy, fontSize: 14, fontWeight: FontWeight.w600, height: 1.5)),
            ],
          ),
        ),
      ),
    );
  }

  // ── Job list ──────────────────────────────────────────────────────────────

  Widget _buildList(List<_Job> jobs, bool isRtl) {
    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: jobs.length,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _buildCard(jobs[i], isRtl),
      ),
    );
  }

  Widget _buildCard(_Job job, bool isRtl) {
    return GestureDetector(
      onTap: () => _openJob(job),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.9), width: 1.2),
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
        child: Row(
          textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: const Color(0xFFEAFBE9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _green.withOpacity(0.3), width: 1),
              ),
              child: const Icon(Icons.school_rounded, color: _green, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment:
                    isRtl ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  Text(job.company,
                      style: const TextStyle(
                          color: _navy, fontSize: 15, fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(job.title,
                      style: const TextStyle(color: _muted, fontSize: 13, height: 1.3),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(
                    textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
                    children: [
                      const Icon(Icons.location_on_rounded, color: _muted, size: 12),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(job.locationDisplay,
                            style: const TextStyle(color: _muted, fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(_applyLbl,
                style: const TextStyle(
                    color: _green, fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_forward_ios_rounded, color: _green, size: 14),
          ],
        ),
      ),
    );
  }
}

// ── Nav button ────────────────────────────────────────────────────────────────

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
          child: Icon(icon, color: active ? _green : _navy, size: 20),
        ),
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
              colors: [Color(0xFFF9FBFF), Color(0xFFEFF6FF), Color(0xFFF7FFF2)],
            ),
          ),
          child: SizedBox.expand(),
        ),
        Positioned(top: 70,    left: -42,  child: _Orb(size: 170, color: Color(0x6639EA2B))),
        Positioned(top: 135,   right: -65, child: _Orb(size: 170, color: Color(0x44FFB86B))),
        Positioned(bottom: 95, left: -60,  child: _Orb(size: 210, color: Color(0x3339EA2B))),
        Positioned(bottom: -30,right: 14,  child: _Orb(size: 145, color: Color(0x5539EA2B))),
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

// ── Glass surface ─────────────────────────────────────────────────────────────

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
