class UserProfile {
  final String fullName;
  final int? dobDay;
  final int? dobMonth;
  final int? dobYear;
  final String? country;
  final String phone;
  final String email;
  final String street;
  final String city;
  final String? skill;
  final String? workExperience;
  final String? workType;
  final String? tools;
  final String? drivingLicense;
  final List<String> languages;
  final String? availability;
  final String? startDate;
  final String? photoPath;
  final String? educationLevel;
  // Ordered, most-recent-first — index i of previousJobTitles/
  // previousJobDurations describes the same job as index i of
  // previousEmployers (padded with '' when a title/duration wasn't given).
  final List<String> previousEmployers;
  final List<String> previousJobTitles;
  final List<String> previousJobDurations;
  // Language -> CEFR level ('A1'..'C2' or 'Muttersprache'), keyed by the
  // German display name (e.g. 'Deutsch', 'Englisch', 'Paschtu') so
  // cv_preview_screen.dart can render it directly.
  final Map<String, String> languageProficiency;
  // Reference contact, stored separately under 'refName'/'refPhone' in
  // saved_profile (see cv_preview_screen.dart._loadRefData) — surfaced here
  // too so template builders that only receive a UserProfile (e.g. the CV
  // PDF generator) can render a Reference section from it.
  final String? refName;
  final String? refPhone;
  // Ausbildung-flow only (schulabschluss_screen.dart): highest school
  // qualification and optional final grade, asked once and then reused for
  // every subsequent Ausbildung CV — not part of the regular questionnaire.
  final String? schulabschluss;
  final String? schulabschlussNote;

  const UserProfile({
    required this.fullName,
    required this.phone,
    required this.email,
    required this.street,
    required this.city,
    required this.languages,
    this.dobDay,
    this.dobMonth,
    this.dobYear,
    this.country,
    this.skill,
    this.workExperience,
    this.workType,
    this.tools,
    this.drivingLicense,
    this.availability,
    this.startDate,
    this.photoPath,
    this.educationLevel,
    this.previousEmployers = const [],
    this.previousJobTitles = const [],
    this.previousJobDurations = const [],
    this.languageProficiency = const {},
    this.refName,
    this.refPhone,
    this.schulabschluss,
    this.schulabschlussNote,
  });

  UserProfile copyWith({
    List<String>? previousEmployers,
    List<String>? previousJobTitles,
    List<String>? previousJobDurations,
    String? refName,
    String? refPhone,
    String? schulabschluss,
    String? schulabschlussNote,
  }) {
    return UserProfile(
      fullName: fullName,
      phone: phone,
      email: email,
      street: street,
      city: city,
      languages: languages,
      dobDay: dobDay,
      dobMonth: dobMonth,
      dobYear: dobYear,
      country: country,
      skill: skill,
      workExperience: workExperience,
      workType: workType,
      tools: tools,
      drivingLicense: drivingLicense,
      availability: availability,
      startDate: startDate,
      photoPath: photoPath,
      educationLevel: educationLevel,
      previousEmployers: previousEmployers ?? this.previousEmployers,
      previousJobTitles: previousJobTitles ?? this.previousJobTitles,
      previousJobDurations: previousJobDurations ?? this.previousJobDurations,
      languageProficiency: languageProficiency,
      refName: refName ?? this.refName,
      refPhone: refPhone ?? this.refPhone,
      schulabschluss: schulabschluss ?? this.schulabschluss,
      schulabschlussNote: schulabschlussNote ?? this.schulabschlussNote,
    );
  }

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    String? opt(String k) {
      final v = map[k] as String? ?? '';
      return v.isEmpty ? null : v;
    }

    return UserProfile(
      fullName: map['fullName'] as String? ?? '',
      phone: map['phone'] as String? ?? '',
      email: map['email'] as String? ?? '',
      street: map['street'] as String? ?? '',
      city: map['city'] as String? ?? '',
      languages: (map['languages'] as String? ?? '').isEmpty
          ? []
          : (map['languages'] as String).split(','),
      dobDay: int.tryParse(map['dobDay'] as String? ?? ''),
      dobMonth: int.tryParse(map['dobMonth'] as String? ?? ''),
      dobYear: int.tryParse(map['dobYear'] as String? ?? ''),
      country: opt('country'),
      skill: opt('skill'),
      workExperience: opt('workExperience'),
      workType: opt('workType'),
      tools: opt('tools'),
      drivingLicense: opt('drivingLicense'),
      availability: opt('availability'),
      startDate: opt('startDate'),
      photoPath: opt('photoPath'),
      educationLevel: opt('educationLevel'),
      previousEmployers: (map['previousEmployers'] as String? ?? '').isEmpty
          ? const []
          : (map['previousEmployers'] as String).split(','),
      previousJobTitles: (map['previousJobTitles'] as String? ?? '').isEmpty
          ? const []
          : (map['previousJobTitles'] as String).split(','),
      previousJobDurations:
          (map['previousJobDurations'] as String? ?? '').isEmpty
              ? const []
              : (map['previousJobDurations'] as String).split(','),
      languageProficiency: _decodeProficiency(
          map['languageProficiency'] as String? ?? ''),
      refName: opt('refName'),
      refPhone: opt('refPhone'),
      schulabschluss: opt('schulabschluss'),
      schulabschlussNote: opt('schulabschlussNote'),
    );
  }

  static Map<String, String> _decodeProficiency(String raw) {
    if (raw.isEmpty) return const {};
    final result = <String, String>{};
    for (final pair in raw.split(',')) {
      final idx = pair.indexOf(':');
      if (idx == -1) continue;
      final lang = pair.substring(0, idx);
      final level = pair.substring(idx + 1);
      if (lang.isNotEmpty && level.isNotEmpty) result[lang] = level;
    }
    return result;
  }

  static String encodeProficiency(Map<String, String> map) =>
      map.entries.map((e) => '${e.key}:${e.value}').join(',');

  String get dobFormatted {
    if (dobDay == null || dobMonth == null || dobYear == null) return '—';
    return '${dobDay.toString().padLeft(2, '0')}.'
        '${dobMonth.toString().padLeft(2, '0')}.'
        '$dobYear';
  }

  String get fullAddress {
    final parts = [street, city].where((s) => s.isNotEmpty).toList();
    return parts.isEmpty ? '—' : parts.join(', ');
  }
}
