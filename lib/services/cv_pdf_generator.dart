import 'dart:convert';
import 'dart:io';
import 'dart:math' show Random;
import 'dart:typed_data';

import 'package:flutter/services.dart' show ByteData, rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/document_template.dart';
import '../models/user_profile.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Template-aware CV PDF generation.
//
// generateCv() is the single entry point every screen should call. Each
// _buildXxx() renders one of the 4 visual templates natively with the pdf
// package (no external service, no scraping) using only UserProfile data,
// plus the Ausbildung questionnaire's data (see _loadAusbildungData() below)
// merged in when present — the dummy content in the reference designs under
// /Templates is never read.
//
// isAusbildungCv controls which Job-CV-only fields are shown. Job CV:
// p.skill, p.workExperience, p.workType, p.tools, p.educationLevel all
// render. Ausbildung CV: none of those render - it shows only personal
// data, the shared Berufserfahrung/IT-Kenntnisse/Sprachkenntnisse sections,
// its own Bildung/Schulabschluss (ausbildungEdu*), and its own ESCO skills
// (ausbildungEscoSkills). Callers that generate an Ausbildung CV must pass
// isAusbildungCv: true. It defaults to false so the existing Job CV caller
// (cv_preview_screen.dart) needs no change; the Ausbildung CV caller
// (ausbildung_document_preview_screen.dart) needs a one-line update to pass
// isAusbildungCv: true - see the report for details, that file is outside
// today's edit scope.
// ─────────────────────────────────────────────────────────────────────────────

Future<Uint8List> generateCv(
  UserProfile profile,
  DocumentTemplate template, {
  bool isAusbildungCv = false,
}) async {
  // UserProfile has no fields for the Ausbildung CV questionnaire's data
  // (education Ort/type/Abschluss/grades, IT-Kenntnisse, ESCO skills) -
  // ausbildung_cv_questionnaire_screen.dart writes it into 'saved_profile'
  // under ausbildungEdu*/sharedItSkills/ausbildungEscoSkills keys, but
  // UserProfile.fromMap() silently drops any key it doesn't know about, so
  // that data never survives being wrapped into a UserProfile object. Read
  // it back directly here instead, so it reaches the PDF regardless of what
  // UserProfile carries.
  final ausbildung = await _loadAusbildungData();
  switch (template) {
    case DocumentTemplate.atsBlue:
      return _buildAtsBlue(profile, ausbildung, isAusbildungCv);
    case DocumentTemplate.darkSidebar:
      return _buildDarkSidebar(profile, ausbildung, isAusbildungCv);
    case DocumentTemplate.navyHeader:
      return _buildNavyHeader(profile, ausbildung, isAusbildungCv);
    case DocumentTemplate.blueTriangle:
      return _buildBlueTriangle(profile, ausbildung, isAusbildungCv);
    case DocumentTemplate.braunIconSet:
      return _buildBraunIconSet(profile, ausbildung, isAusbildungCv);
    case DocumentTemplate.weissBraunSchlicht:
      return _buildWeissBraunSchlicht(profile, ausbildung, isAusbildungCv);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// generateAnschreiben() / generateDeckblatt() — companion entry points for
// the Anschreiben (Cover Letter) and Deckblatt document families,
// following the exact same "single entry point + per-template _buildXxx()"
// pattern as generateCv() above. Both resolve their own target-position/
// attachments data internally (via _targetPosition()/_loadAttachments()),
// same as generateCv() resolving its own Ausbildung data via
// _loadAusbildungData() - callers only pass the UserProfile and template.
// ─────────────────────────────────────────────────────────────────────────────

// The four editable text sections of an Anschreiben. Salutation, closing
// greeting, signature and sender/recipient blocks are not part of this and
// stay fixed in every template.
class AnschreibenTexts {
  final String subject;
  final String opening;
  final String middle;
  final String closing;

  const AnschreibenTexts({
    required this.subject,
    required this.opening,
    required this.middle,
    required this.closing,
  });

  // Paragraphs in print order; a section the user emptied is skipped so it
  // leaves no blank gap in the letter.
  List<String> get body =>
      [opening, middle, closing].where((s) => s.trim().isNotEmpty).toList();
}

// Composes one fresh random phrase-bank pick per section, using the same
// position/company resolution as generateAnschreiben(). Every call rolls new
// variants, which is what the editor's "Regenerate" button relies on.
Future<AnschreibenTexts> composeAnschreibenTexts(
  UserProfile profile, {
  bool isAusbildungCv = false,
  String? jobTitleOverride,
}) async {
  final ausbildung = await _loadAusbildungData();
  final position = _resolveAnschreibenPosition(
      profile, ausbildung, isAusbildungCv, jobTitleOverride);
  return _composeAnschreibenTexts(profile, ausbildung, position, isAusbildungCv);
}

String _resolveAnschreibenPosition(UserProfile profile, _AusbildungData ausbildung,
    bool isAusbildungCv, String? jobTitleOverride) {
  return (jobTitleOverride != null && jobTitleOverride.trim().isNotEmpty)
      ? jobTitleOverride.trim()
      : _targetPosition(profile, ausbildung, isAusbildungCv);
}

AnschreibenTexts _composeAnschreibenTexts(UserProfile profile,
    _AusbildungData ausbildung, String position, bool isAusbildungCv) {
  final rng = Random();
  final body = _anschreibenBody(profile, ausbildung, position, isAusbildungCv, rng);
  return AnschreibenTexts(
    subject: _anschreibenSubject(position, isAusbildungCv, rng),
    opening: body[0],
    middle: body[1],
    closing: body[2],
  );
}

Future<Uint8List> generateAnschreiben(
  UserProfile profile,
  AnschreibenTemplate template, {
  bool isAusbildungCv = false,
  // Optional pre-composed (and possibly user-edited) section texts. When all
  // four are null the letter composes its own random phrase-bank text as
  // before; when any is set, that section is used verbatim and the others
  // are composed as usual.
  String? subjectText,
  String? openingText,
  String? middleText,
  String? closingText,
  // Optional per-job overrides - set when the letter is opened from a
  // specific job posting (e.g. an Ausbildung listing's "Cover Letter
  // erstellen" button) so the generated text is relevant to that exact
  // posting instead of the user's generic saved target position. Null/empty
  // falls back to the existing profile-derived behavior unchanged.
  String? jobTitleOverride,
  String? companyNameOverride,
}) async {
  final ausbildung = await _loadAusbildungData();
  final resolvedPosition = _targetPosition(profile, ausbildung, isAusbildungCv);
  final position = (jobTitleOverride != null && jobTitleOverride.trim().isNotEmpty)
      ? jobTitleOverride.trim()
      : resolvedPosition;
  final companyName = companyNameOverride?.trim() ?? '';
  final attachments = await _loadAttachments();
  AnschreibenTexts? texts;
  if (subjectText != null ||
      openingText != null ||
      middleText != null ||
      closingText != null) {
    final base =
        _composeAnschreibenTexts(profile, ausbildung, position, isAusbildungCv);
    texts = AnschreibenTexts(
      subject: subjectText ?? base.subject,
      opening: openingText ?? base.opening,
      middle: middleText ?? base.middle,
      closing: closingText ?? base.closing,
    );
  }
  switch (template) {
    case AnschreibenTemplate.blauMinimal:
      return _buildAnschreibenBlauMinimal(profile, ausbildung, position, isAusbildungCv, attachments, companyName, texts);
    case AnschreibenTemplate.beigeEleganz:
      return _buildAnschreibenBeigeEleganz(profile, ausbildung, position, isAusbildungCv, attachments, companyName, texts);
    case AnschreibenTemplate.boldHeadlineGrau:
      return _buildAnschreibenBoldHeadlineGrau(profile, ausbildung, position, isAusbildungCv, attachments, companyName, texts);
    case AnschreibenTemplate.braunIconSet:
      return _buildAnschreibenBraunIconSet(profile, ausbildung, position, isAusbildungCv, attachments, companyName, texts);
    case AnschreibenTemplate.grauSchlicht:
      return _buildAnschreibenGrauSchlicht(profile, ausbildung, position, isAusbildungCv, attachments, companyName, texts);
    case AnschreibenTemplate.weissBraunSchlicht:
      return _buildAnschreibenWeissBraunSchlicht(profile, ausbildung, position, isAusbildungCv, attachments, companyName, texts);
  }
}

Future<Uint8List> generateDeckblatt(
  UserProfile profile,
  DeckblattTemplate template, {
  bool isAusbildungCv = false,
}) async {
  final ausbildung = await _loadAusbildungData();
  final position = _targetPosition(profile, ausbildung, isAusbildungCv);
  final attachments = await _loadAttachments();
  switch (template) {
    case DeckblattTemplate.braunIconSet:
      return _buildDeckblattBraunIconSet(profile, position, attachments);
    case DeckblattTemplate.weissBraunSchlicht:
      return _buildDeckblattWeissBraunSchlicht(profile, position, attachments);
  }
}

// ── Ausbildung questionnaire data (read directly from SharedPreferences) ───

class _AusbildungData {
  final List<_CvJob> jobs;
  final List<_AusbildungEduLine> eduLines;
  final List<String> itSkills;
  final List<String> escoSkills;
  // ESCO-selected target occupation title (e.g. "Elektroniker/in") - used by
  // the Anschreiben/Deckblatt generators as the "target role/Beruf" for
  // Ausbildung applicants. Empty when no occupation was selected.
  final String targetOccupation;

  const _AusbildungData({
    this.jobs = const [],
    this.eduLines = const [],
    this.itSkills = const [],
    this.escoSkills = const [],
    this.targetOccupation = '',
  });
}

// One Bildung/Schulabschluss entry, laid out as: heading line (what was
// done + institution), then address left / date range right on the line
// below it.
class _AusbildungEduLine {
  final String heading;
  final String address;
  final String dateRange;
  // Raw institution name (distinct from `heading`, which also carries the
  // Abschluss/degree prefix) - needed as-is for the Anschreiben's
  // "{schulname}" sentence.
  final String institutionName;
  const _AusbildungEduLine({
    required this.heading,
    this.address = '',
    this.dateRange = '',
    this.institutionName = '',
  });
}

List<String> _splitCsv(String raw) =>
    raw.isEmpty ? const [] : raw.split(',');

Future<_AusbildungData> _loadAusbildungData() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('saved_profile');
    if (raw == null || raw.isEmpty) {
      return const _AusbildungData();
    }
    final map = jsonDecode(raw) as Map<String, dynamic>;
    String s(String key) => (map[key] as String?) ?? '';

    // NOTE: work-experience entries (Berufserfahrung) are shared between
    // the Job CV and Ausbildung CV questionnaires via previousEmployers/
    // previousJobTitles/previousJobDurations, which UserProfile.fromMap()
    // already reads - so they arrive through _jobs(p) below, not through
    // this function.

    final institutions  = _splitCsv(s('ausbildungEduInstitutions'));
    final eduOrts       = _splitCsv(s('ausbildungEduOrts'));
    final eduTypes      = _splitCsv(s('ausbildungEduTypes'));
    final abschluesse   = _splitCsv(s('ausbildungEduAbschluss'));
    final eduDurations  = _splitCsv(s('ausbildungEduDurations'));
    final grades        = _splitCsv(s('ausbildungEduGrades'));

    // Heading = Abschluss (or, absent that, the school type) + institution
    // name; address/date range render on their own line - see
    // _eduEntryContent() in each template for the two-line layout.
    final eduLines = <_AusbildungEduLine>[];
    for (var i = 0; i < institutions.length; i++) {
      if (institutions[i].isEmpty) continue;
      final degree = abschluesse.length > i && abschluesse[i].isNotEmpty
          ? abschluesse[i]
          : (eduTypes.length > i ? eduTypes[i] : '');
      var heading =
          degree.isNotEmpty ? '$degree — ${institutions[i]}' : institutions[i];
      final grade = grades.length > i ? grades[i] : '';
      if (grade.isNotEmpty) heading = '$heading · Note: $grade';
      eduLines.add(_AusbildungEduLine(
        heading: heading,
        address: eduOrts.length > i ? eduOrts[i] : '',
        dateRange: eduDurations.length > i ? eduDurations[i] : '',
        institutionName: institutions[i],
      ));
    }

    // IT-Kenntnisse (shared, both CV types) and ESCO skills (Ausbildung CV
    // only) are two distinct fields now - item 2/4 need them separable.
    // 'sharedItSkills' is the current key both questionnaire screens write
    // (questionnaire_screen.dart and ausbildung_cv_questionnaire_screen.dart)
    // - this used to read the now-dead 'ausbildungItSkills' key, which is
    // why IT-Kenntnisse never appeared in either CV.
    final itSkills   = _splitCsv(s('sharedItSkills'));
    final escoSkills = _splitCsv(s('ausbildungEscoSkills'));
    final targetOccupation = s('ausbildungTargetOccupation').trim();

    return _AusbildungData(
      jobs: const [],
      eduLines: eduLines,
      itSkills: itSkills,
      escoSkills: escoSkills,
      targetOccupation: targetOccupation,
    );
  } catch (_) {
    return const _AusbildungData();
  }
}

// Best-effort "target role/Beruf" for the Anschreiben/Deckblatt generators:
// the Ausbildung ESCO occupation when present, else the Job CV's workType
// translated to German. Never blocks generation when both are empty.
String _targetPosition(UserProfile p, _AusbildungData ausbildung, bool isAusbildungCv) {
  if (isAusbildungCv && ausbildung.targetOccupation.isNotEmpty) {
    return ausbildung.targetOccupation;
  }
  if (!isAusbildungCv && p.workType != null && p.workType!.isNotEmpty) {
    return _resolve(p.workType, _workTypeDe);
  }
  return ausbildung.targetOccupation.isNotEmpty
      ? ausbildung.targetOccupation
      : (p.workType != null ? _resolve(p.workType, _workTypeDe) : '');
}

// "Anlagen" (attachments) list for Anschreiben/Deckblatt - only lists
// documents this app actually knows the user has generated. 'cv_created' is
// the one persisted signal available (set by both the Job CV and Ausbildung
// CV flows) - Zeugnisse/certificates aren't tracked anywhere in the app, so
// they're never fabricated into this list.
Future<List<String>> _loadAttachments() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final cvCreated = prefs.getBool('cv_created') ?? false;
    return cvCreated ? const ['Lebenslauf'] : const [];
  } catch (_) {
    return const [];
  }
}

// ── German key-label maps ────────────────────────────────────────────────────
// Copied from cv_preview_screen.dart so PDF output stays consistent
// regardless of which template/screen triggers generation.

const Map<String, String> _skillDe = {
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

const Map<String, String> _workExpDe = {
  'more2': 'Mehr als 2 Jahre Erfahrung',
  'less2': 'Weniger als 2 Jahre Erfahrung',
  'small': 'Nur einfache Tätigkeiten',
  'never': 'Keine Berufserfahrung',
};

const Map<String, String> _workTypeDe = {
  'construction': 'Baugewerbe',
  'cleaning': 'Gebäudereinigung',
  'kitchen': 'Küche / Gastronomie',
  'driving': 'Fahrertätigkeit',
};

const Map<String, String> _toolsDe = {
  'power_tools': 'Elektrowerkzeuge',
  'kitchen_equip': 'Küchengeräte',
  'tractor': 'Traktor / Schwere Fahrzeuge',
  'no_tools': 'Keine Werkzeugerfahrung',
};

const Map<String, String> _licenseDe = {
  'german_license': 'Deutscher Führerschein',
  'foreign_license': 'Ausländischer Führerschein',
  'want_license': 'Kein Führerschein (möchte erwerben)',
  'no_license': 'Kein Führerschein',
};

const Map<String, String> _eduDe = {
  'primary': 'Grundschule',
  'secondary': 'Sekundarschule',
  'highschool': 'Abitur / Gymnasium',
  'vocational': 'Berufsausbildung',
  'university': 'Hochschulabschluss',
  'masters': 'Master / Promotion',
};

// Ausbildung-flow only (schulabschluss_screen.dart) — school qualification
// preset keys. 'auslaendisch' (foreign qualification) stores the user's own
// free text directly instead of a key, so it isn't listed here and falls
// through to _resolve()'s raw-string fallback.
const Map<String, String> _schulabschlussDe = {
  'hauptschule': 'Hauptschulabschluss',
  'realschule': 'Realschulabschluss / Mittlere Reife',
  'fachhochschulreife': 'Fachhochschulreife',
  'abitur': 'Abitur / Allgemeine Hochschulreife',
};

// "None"/"No tools"/"No license" style sentinels must never render as a
// negative line item — same rule cv_preview_screen.dart already applies.
const Set<String> _negativeSentinels = {
  'no_tools', 'no_license', 'never', 'no_ref', 'kein_abschluss',
};

bool _isNegative(String? value) =>
    value != null && _negativeSentinels.contains(value);

String _resolve(String? key, Map<String, String> map) {
  if (key == null || key.isEmpty) return '';
  return map[key] ?? key;
}

String _skillsText(UserProfile p) {
  final s = p.skill;
  if (s == null || s.isEmpty) return '';
  return s
      .split(',')
      .map((k) => _resolve(k.trim(), _skillDe))
      .where((s) => s.isNotEmpty)
      .join(', ');
}

// Item 4 — Job CV shows only p.skill (job-related skill tags); Ausbildung CV
// shows only ausbildung.escoSkills. p.tools is also Job-CV-only (see prompt
// 2), so it's gated alongside p.skill; driving license isn't CV-type
// specific in the existing data model, so it keeps showing here unchanged.
List<String> _genericSkillsList(
    UserProfile p, _AusbildungData ausbildung, bool isAusbildungCv) {
  return [
    if (!isAusbildungCv && p.skill != null && p.skill!.isNotEmpty)
      ..._skillsText(p).split(', ').where((s) => s.isNotEmpty),
    if (!isAusbildungCv && p.tools != null && !_isNegative(p.tools))
      _resolve(p.tools, _toolsDe),
    if (p.drivingLicense != null && !_isNegative(p.drivingLicense))
      _resolve(p.drivingLicense, _licenseDe),
    if (isAusbildungCv) ...ausbildung.escoSkills,
  ];
}

// One entry per language, preferring the CEFR-level map (educated flow);
// falls back to the plain language list (uneducated flow / older profiles)
// with a null level.
List<MapEntry<String, String?>> _langEntries(UserProfile p) {
  if (p.languageProficiency.isNotEmpty) {
    return p.languageProficiency.entries
        .map((e) => MapEntry(e.key, e.value))
        .toList();
  }
  return p.languages
      .where((l) => l.trim().isNotEmpty)
      .map((l) => MapEntry(l.trim(), null))
      .toList();
}

// Item 3 — "Language > Level" on one line; falls back to just the language
// name when no level is set.
String _langLine(MapEntry<String, String?> e) =>
    e.value != null ? '${e.key} > ${e.value}' : e.key;

class _CvJob {
  final String title;
  final String company;
  final String duration;
  const _CvJob(this.title, this.company, this.duration);
}

// previousEmployers is already newest-first by the questionnaire's own
// entry-order convention (see user_profile.dart) — no reversal needed.
// Shared between the Job CV and Ausbildung CV questionnaires (both write
// into previousEmployers/previousJobTitles/previousJobDurations), so this
// alone already covers Berufserfahrung entries from either flow.
List<_CvJob> _jobs(UserProfile p) {
  final employers = p.previousEmployers;
  final titles = p.previousJobTitles;
  final durations = p.previousJobDurations;
  return [
    for (var i = 0; i < employers.length; i++)
      _CvJob(
        i < titles.length ? titles[i] : '',
        employers[i],
        i < durations.length ? durations[i] : '',
      ),
  ];
}

// Short synthesized summary paragraph for the "Profil"/"About Me" sections —
// UserProfile has no free-text bio field, so this composes one from the
// structured fields that do exist rather than inventing content. All three
// source fields (workExperience, skill, tools) are Job-CV-only, so the
// Ausbildung CV gets no Profil section at all.
String _profileSummary(UserProfile p, bool isAusbildungCv) {
  if (isAusbildungCv) return '';
  final parts = <String>[];
  if (p.workExperience != null && !_isNegative(p.workExperience)) {
    parts.add(_resolve(p.workExperience, _workExpDe));
  }
  final skills = _skillsText(p);
  if (skills.isNotEmpty) parts.add('Erfahrung in: $skills');
  if (p.tools != null && !_isNegative(p.tools)) {
    parts.add(_resolve(p.tools, _toolsDe));
  }
  if (parts.isEmpty) return '';
  return '${parts.join('. ')}.';
}

// Job-CV-only field — the Ausbildung CV's education data comes entirely
// from ausbildung.eduLines/_schulabschlussText instead (ausbildungEdu* keys).
String _educationText(UserProfile p, bool isAusbildungCv) {
  if (isAusbildungCv) return '';
  if (p.educationLevel == null || p.educationLevel!.isEmpty) return '';
  return _eduDe[p.educationLevel] ?? p.educationLevel!;
}

// Role/title line shown under the name in the sidebar templates - derived
// from p.workType and p.skill, both Job-CV-only fields.
String _roleText(UserProfile p, bool isAusbildungCv) {
  if (isAusbildungCv) return '';
  return p.workType != null && p.workType!.isNotEmpty
      ? _resolve(p.workType, _workTypeDe)
      : (_skillsText(p).isNotEmpty ? _skillsText(p) : '');
}

// Ausbildung-flow only — appended alongside _educationText()'s existing
// educationLevel line in each template's AUSBILDUNG/education section, not
// a replacement for it (a profile can carry both regular-flow educationLevel
// and Ausbildung-flow schulabschluss).
String _schulabschlussText(UserProfile p) {
  if (p.schulabschluss == null || p.schulabschluss!.isEmpty) return '';
  if (_isNegative(p.schulabschluss)) return '';
  final label = _schulabschlussDe[p.schulabschluss] ?? p.schulabschluss!;
  final note = p.schulabschlussNote;
  if (note != null && note.isNotEmpty) return '$label · Note: $note';
  return label;
}

// ── Fonts (bundled TTF, loaded once and cached) ──────────────────────────────
// pw.Font.helvetica() lacks full Unicode coverage (existing known issue) and
// PdfGoogleFonts requires network access (previously caused silent
// failures offline) — Roboto is bundled under assets/fonts/ and loaded via
// pw.Font.ttf() so PDF generation works fully offline.

class _Fonts {
  final pw.Font regular;
  final pw.Font bold;
  final pw.Font italic;
  const _Fonts(this.regular, this.bold, this.italic);
}

Future<_Fonts>? _fontsFuture;

Future<_Fonts> _loadFonts() {
  return _fontsFuture ??= () async {
    final ByteData regularData =
        await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
    final ByteData boldData =
        await rootBundle.load('assets/fonts/Roboto-Bold.ttf');
    final ByteData italicData =
        await rootBundle.load('assets/fonts/Roboto-Italic.ttf');
    return _Fonts(
      pw.Font.ttf(regularData),
      pw.Font.ttf(boldData),
      pw.Font.ttf(italicData),
    );
  }();
}

// Photo section only renders if photoPath exists AND the file is present —
// every template below degrades gracefully (colored placeholder circle
// instead of crashing/omitting the design element) when it isn't.
Future<pw.MemoryImage?> _loadPhoto(UserProfile p) async {
  if (p.photoPath == null || p.photoPath!.isEmpty) return null;
  try {
    final file = File(p.photoPath!);
    if (!await file.exists()) return null;
    return pw.MemoryImage(await file.readAsBytes());
  } catch (_) {
    return null;
  }
}

pw.Widget _photoCircle({
  required pw.MemoryImage? photo,
  required double size,
  PdfColor ringColor = PdfColors.white,
  double ringWidth = 3.5,
  PdfColor placeholderColor = const PdfColor.fromInt(0xFFB7C0CC),
}) {
  return pw.Container(
    width: size,
    height: size,
    decoration: pw.BoxDecoration(
      shape: pw.BoxShape.circle,
      color: photo == null ? placeholderColor : null,
      image: photo != null
          ? pw.DecorationImage(image: photo, fit: pw.BoxFit.cover)
          : null,
      border: pw.Border.all(color: ringColor, width: ringWidth),
    ),
  );
}

// Shared two-line Bildung entry layout used by all four templates: heading
// (Abschluss/degree — institution) on top, then address left-aligned with
// the date range right-aligned on the line below it.
pw.Widget _eduEntryContent(
  _AusbildungEduLine e,
  _Fonts fonts, {
  required double headingSize,
  required PdfColor headingColor,
  required double addressSize,
  required PdfColor addressColor,
}) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(e.heading,
          style: pw.TextStyle(
              font: fonts.bold, fontSize: headingSize, color: headingColor)),
      if (e.address.isNotEmpty || e.dateRange.isNotEmpty) ...[
        pw.SizedBox(height: 2),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Text(e.address,
                  style: pw.TextStyle(
                      font: fonts.regular,
                      fontSize: addressSize,
                      color: addressColor)),
            ),
            if (e.dateRange.isNotEmpty) ...[
              pw.SizedBox(width: 8),
              pw.Text(e.dateRange,
                  style: pw.TextStyle(
                      font: fonts.regular,
                      fontSize: addressSize,
                      color: addressColor)),
            ],
          ],
        ),
      ],
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// "Braun Icon-Set" shared visual identity — used by the CV's braunIconSet
// template, the Anschreiben's braunIconSet template, and
// generateDeckblattBraunIconSet(). Small line-icon glyphs (pin/phone/mail)
// are drawn as simple vector shapes via pw.CustomPaint rather than an icon
// font or SVG asset, following this file's existing "icon = plain drawn
// shape" convention (see iconSectionHeader()/rightHeader() above, which
// already stand in for icons with a plain colored circle).
// ─────────────────────────────────────────────────────────────────────────────

const PdfColor _brownPanelBg = PdfColor(0.929, 0.902, 0.867);
final PdfColor _brownAccent = PdfColor.fromHex('#6B4226');

pw.Widget _brownIconPin({double size = 11, PdfColor? color}) {
  final c = color ?? _brownAccent;
  return pw.CustomPaint(
    size: PdfPoint(size, size),
    painter: (canvas, s) {
      final cx = s.x / 2;
      final cy = s.y * 0.68;
      final r = s.x * 0.32;
      canvas
        ..setColor(c)
        ..drawEllipse(cx, cy, r, r)
        ..fillPath()
        ..moveTo(cx - r * 0.8, cy - r * 0.25)
        ..lineTo(cx + r * 0.8, cy - r * 0.25)
        ..lineTo(cx, 0)
        ..closePath()
        ..fillPath();
    },
  );
}

pw.Widget _brownIconPhone({double size = 11, PdfColor? color}) {
  final c = color ?? _brownAccent;
  return pw.Container(
    width: size,
    height: size,
    decoration: pw.BoxDecoration(
      color: c,
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2.5)),
    ),
    child: pw.Center(
      child: pw.Container(
        width: size * 0.4,
        height: size * 0.4,
        decoration: const pw.BoxDecoration(
          color: PdfColors.white,
          shape: pw.BoxShape.circle,
        ),
      ),
    ),
  );
}

pw.Widget _brownIconMail({double size = 11, PdfColor? color}) {
  final c = color ?? _brownAccent;
  return pw.CustomPaint(
    size: PdfPoint(size, size * 0.72),
    painter: (canvas, s) {
      canvas
        ..setColor(c)
        ..setLineWidth(1.0)
        ..drawRect(0, 0, s.x, s.y)
        ..strokePath()
        ..moveTo(0, s.y)
        ..lineTo(s.x / 2, s.y * 0.35)
        ..lineTo(s.x, s.y)
        ..strokePath();
    },
  );
}

// One "[icon]  LABEL: value" contact row, used by all three Braun Icon-Set
// documents (CV sidebar, Anschreiben sender block, Deckblatt panel).
pw.Widget _brownIconContactLine(
    pw.Widget icon, String value, _Fonts fonts, PdfColor textColor) {
  if (value.isEmpty) return pw.SizedBox();
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 7),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        icon,
        pw.SizedBox(width: 7),
        pw.Expanded(
          child: pw.Text(value,
              style: pw.TextStyle(font: fonts.regular, fontSize: 8.7, color: textColor)),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// atsBlue — German ATS style, blue section header labels, single column,
// dates left-aligned, no photo. (reference: Blau_Weiß ATS)
// ─────────────────────────────────────────────────────────────────────────────

Future<Uint8List> _buildAtsBlue(
    UserProfile p, _AusbildungData ausbildung, bool isAusbildungCv) async {
  final fonts = await _loadFonts();
  final blue = PdfColor.fromHex('#1B4CA1');
  const darkText = PdfColor.fromInt(0xFF1A1A1A);

  pw.Widget sectionHeader(String label) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          color: blue,
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          child: pw.Text(
            label,
            style: pw.TextStyle(
              font: fonts.bold,
              fontSize: 9.5,
              color: PdfColors.white,
              letterSpacing: 0.6,
            ),
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Container(height: 1.1, color: blue),
        pw.SizedBox(height: 8),
      ],
    );
  }

  pw.Widget row(String date, pw.Widget content) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 9),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 68,
            child: pw.Text(
              date,
              style: pw.TextStyle(
                  font: fonts.regular, fontSize: 8.5, color: PdfColors.grey600),
            ),
          ),
          pw.Expanded(child: content),
        ],
      ),
    );
  }

  // Item 1 — each field's label renders as a small heading, with the value
  // listed below it (one per line), instead of the old inline bullet row.
  pw.Widget contactField(String label, String value) {
    if (value.isEmpty) return pw.SizedBox();
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label,
              style: pw.TextStyle(
                  font: fonts.bold,
                  fontSize: 7.5,
                  color: blue,
                  letterSpacing: 0.4)),
          pw.SizedBox(height: 2),
          pw.Text(value,
              style: pw.TextStyle(
                  font: fonts.regular, fontSize: 9.5, color: PdfColors.grey800)),
        ],
      ),
    );
  }

  final profile = _profileSummary(p, isAusbildungCv);
  final education = _educationText(p, isAusbildungCv);
  final schulabschluss = _schulabschlussText(p);
  final jobs = [..._jobs(p), ...ausbildung.jobs];
  final skillsList = _genericSkillsList(p, ausbildung, isAusbildungCv);
  final langEntries = _langEntries(p);

  final doc = pw.Document(title: 'Lebenslauf – ${p.fullName}', author: 'KarYab');

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(42, 40, 42, 40),
      build: (context) => [
        pw.Text(
          p.fullName,
          style: pw.TextStyle(font: fonts.bold, fontSize: 24, color: darkText),
        ),
        pw.SizedBox(height: 12),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            contactField('TELEFON', p.phone),
            contactField('E-MAIL', p.email),
            contactField('ADRESSE', p.fullAddress == '—' ? '' : p.fullAddress),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Container(height: 1.6, color: blue),
        pw.SizedBox(height: 18),

        if (profile.isNotEmpty) ...[
          sectionHeader('PROFIL'),
          pw.Text(profile,
              style:
                  pw.TextStyle(font: fonts.regular, fontSize: 9.5, color: darkText)),
          pw.SizedBox(height: 16),
        ],

        if (education.isNotEmpty ||
            schulabschluss.isNotEmpty ||
            ausbildung.eduLines.isNotEmpty) ...[
          sectionHeader('AUSBILDUNG'),
          if (education.isNotEmpty)
            row('', pw.Text(education,
                style: pw.TextStyle(
                    font: fonts.bold, fontSize: 10, color: darkText))),
          if (schulabschluss.isNotEmpty)
            row('', pw.Text(schulabschluss,
                style: pw.TextStyle(
                    font: fonts.bold, fontSize: 10, color: darkText))),
          for (final line in ausbildung.eduLines)
            row(
              '',
              _eduEntryContent(
                line,
                fonts,
                headingSize: 10,
                headingColor: darkText,
                addressSize: 8.5,
                addressColor: PdfColors.grey600,
              ),
            ),
          pw.SizedBox(height: 8),
        ],

        if (jobs.isNotEmpty ||
            (!isAusbildungCv && p.workType != null && p.workType!.isNotEmpty)) ...[
          sectionHeader('BERUFSERFAHRUNG'),
          if (!isAusbildungCv && p.workType != null && p.workType!.isNotEmpty)
            row(
              '',
              pw.Text(_resolve(p.workType, _workTypeDe),
                  style: pw.TextStyle(
                      font: fonts.regular, fontSize: 9.5, color: PdfColors.grey700)),
            ),
          for (final job in jobs)
            row(
              job.duration,
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(job.title.isNotEmpty ? job.title : job.company,
                      style: pw.TextStyle(
                          font: fonts.bold, fontSize: 10.5, color: darkText)),
                  if (job.title.isNotEmpty && job.company.isNotEmpty)
                    pw.Text(job.company,
                        style: pw.TextStyle(
                            font: fonts.regular, fontSize: 9.5, color: blue)),
                ],
              ),
            ),
          pw.SizedBox(height: 8),
        ],

        if (skillsList.isNotEmpty) ...[
          sectionHeader('KENNTNISSE'),
          pw.Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in skillsList)
                pw.SizedBox(
                  width: (PdfPageFormat.a4.width - 84 - 18) / 4,
                  child: pw.Text(s,
                      style: pw.TextStyle(
                          font: fonts.regular, fontSize: 9, color: darkText)),
                ),
            ],
          ),
          pw.SizedBox(height: 16),
        ],

        // Item 2 — dedicated IT-Kenntnisse section (shared, both CV types).
        if (ausbildung.itSkills.isNotEmpty) ...[
          sectionHeader('IT-KENNTNISSE'),
          pw.Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in ausbildung.itSkills)
                pw.SizedBox(
                  width: (PdfPageFormat.a4.width - 84 - 18) / 4,
                  child: pw.Text(s,
                      style: pw.TextStyle(
                          font: fonts.regular, fontSize: 9, color: darkText)),
                ),
            ],
          ),
          pw.SizedBox(height: 16),
        ],

        // Item 3 — one language per line, vertical, "Language > Level".
        if (langEntries.isNotEmpty) ...[
          sectionHeader('SPRACHEN'),
          for (final e in langEntries)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 6),
              child: pw.Text(_langLine(e),
                  style: pw.TextStyle(
                      font: fonts.regular, fontSize: 9.5, color: darkText)),
            ),
        ],
      ],
    ),
  );

  return doc.save();
}

// ─────────────────────────────────────────────────────────────────────────────
// darkSidebar — full-height dark navy left sidebar (Kontakt + Sprachen only);
// everything else (Ausbildung, Berufserfahrung, Kenntnisse, IT-Kenntnisse,
// Referenz) in the main body on the right. (reference: Black_White_Minimalist)
// ─────────────────────────────────────────────────────────────────────────────

Future<Uint8List> _buildDarkSidebar(
    UserProfile p, _AusbildungData ausbildung, bool isAusbildungCv) async {
  final fonts = await _loadFonts();
  final photo = await _loadPhoto(p);
  final navy = PdfColor.fromHex('#3C4858');
  const darkText = PdfColor.fromInt(0xFF1A1A1A);

  final pageW = PdfPageFormat.a4.width;
  final pageH = PdfPageFormat.a4.height;
  final sidebarW = pageW * 0.33;

  pw.Widget sidebarHeader(String label) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label,
              style: pw.TextStyle(
                  font: fonts.bold, fontSize: 11, color: PdfColors.white)),
          pw.SizedBox(height: 3),
          pw.Container(height: 0.8, color: const PdfColor(1, 1, 1, 0.5)),
          pw.SizedBox(height: 6),
        ],
      );

  pw.Widget sidebarLine(String text) {
    if (text.isEmpty) return pw.SizedBox();
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Text(text,
          style: pw.TextStyle(
              font: fonts.regular, fontSize: 8.7, color: PdfColors.grey200)),
    );
  }

  // Item 1 — small heading label above the value, one per line.
  pw.Widget sidebarLabeledLine(String label, String value) {
    if (value.isEmpty) return pw.SizedBox();
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label,
              style: pw.TextStyle(
                  font: fonts.bold,
                  fontSize: 7.5,
                  color: PdfColors.grey400,
                  letterSpacing: 0.4)),
          pw.SizedBox(height: 1.5),
          pw.Text(value,
              style: pw.TextStyle(
                  font: fonts.regular, fontSize: 8.7, color: PdfColors.grey200)),
        ],
      ),
    );
  }

  pw.Widget bodyHeader(String label) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 10),
        child: pw.Text(label,
            style:
                pw.TextStyle(font: fonts.bold, fontSize: 13, color: darkText)),
      );

  final education = _educationText(p, isAusbildungCv);
  final schulabschluss = _schulabschlussText(p);
  final skillsList = _genericSkillsList(p, ausbildung, isAusbildungCv);
  final langEntries = _langEntries(p);
  final jobs = [..._jobs(p), ...ausbildung.jobs];
  final profile = _profileSummary(p, isAusbildungCv);
  final role = _roleText(p, isAusbildungCv);

  final doc = pw.Document(title: 'Lebenslauf – ${p.fullName}', author: 'KarYab');

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.zero,
      build: (context) => pw.SizedBox(
        width: pageW,
        height: pageH,
        child: pw.Stack(
          children: [
            pw.Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: pw.Container(width: sidebarW, height: pageH, color: navy),
            ),
            pw.Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: pw.SizedBox(
                width: sidebarW,
                child: pw.Padding(
                padding: const pw.EdgeInsets.all(20),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Center(
                      child: _photoCircle(photo: photo, size: 76),
                    ),
                    pw.SizedBox(height: 20),
                    // Item 5 — sidebar restricted to Kontakt + Sprachen only.
                    sidebarHeader('Kontakt'),
                    sidebarLabeledLine('TELEFON', p.phone),
                    sidebarLabeledLine('E-MAIL', p.email),
                    sidebarLabeledLine(
                        'ADRESSE', p.fullAddress == '—' ? '' : p.fullAddress),
                    if (langEntries.isNotEmpty) ...[
                      pw.SizedBox(height: 8),
                      sidebarHeader('Sprachen'),
                      for (final e in langEntries) sidebarLine(_langLine(e)),
                    ],
                  ],
                ),
                ),
              ),
            ),
            pw.Positioned(
              left: sidebarW,
              top: 0,
              right: 0,
              bottom: 0,
              child: pw.Padding(
                padding: const pw.EdgeInsets.fromLTRB(30, 40, 30, 30),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(p.fullName,
                        style: pw.TextStyle(
                            font: fonts.bold, fontSize: 26, color: darkText)),
                    if (role.isNotEmpty) ...[
                      pw.SizedBox(height: 4),
                      pw.Text(role.toUpperCase(),
                          style: pw.TextStyle(
                              font: fonts.regular,
                              fontSize: 10.5,
                              color: PdfColors.grey600,
                              letterSpacing: 1.4)),
                    ],
                    if (profile.isNotEmpty) ...[
                      pw.SizedBox(height: 14),
                      pw.Text(profile,
                          style: pw.TextStyle(
                              font: fonts.regular, fontSize: 9.5, color: darkText)),
                    ],
                    pw.SizedBox(height: 20),

                    // Item 5 — Ausbildung moved out of the sidebar.
                    if (education.isNotEmpty ||
                        schulabschluss.isNotEmpty ||
                        ausbildung.eduLines.isNotEmpty) ...[
                      bodyHeader('Ausbildung'),
                      if (education.isNotEmpty)
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(bottom: 4),
                          child: pw.Text(education,
                              style: pw.TextStyle(
                                  font: fonts.bold, fontSize: 9.5, color: darkText)),
                        ),
                      if (schulabschluss.isNotEmpty)
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(bottom: 4),
                          child: pw.Text(schulabschluss,
                              style: pw.TextStyle(
                                  font: fonts.bold, fontSize: 9.5, color: darkText)),
                        ),
                      for (final line in ausbildung.eduLines)
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(bottom: 8),
                          child: _eduEntryContent(
                            line,
                            fonts,
                            headingSize: 9.5,
                            headingColor: darkText,
                            addressSize: 8.3,
                            addressColor: PdfColors.grey600,
                          ),
                        ),
                      pw.SizedBox(height: 16),
                    ],

                    if (jobs.isNotEmpty) ...[
                      bodyHeader('Berufserfahrung'),
                      for (final job in jobs)
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(bottom: 14),
                          child: pw.Row(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Column(
                                children: [
                                  pw.Container(
                                    width: 8,
                                    height: 8,
                                    decoration: pw.BoxDecoration(
                                        shape: pw.BoxShape.circle, color: navy),
                                  ),
                                  pw.Container(
                                      width: 1.2, height: 34, color: PdfColors.grey400),
                                ],
                              ),
                              pw.SizedBox(width: 12),
                              pw.Expanded(
                                child: pw.Column(
                                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                                  children: [
                                    if (job.duration.isNotEmpty)
                                      pw.Text(job.duration,
                                          style: pw.TextStyle(
                                              font: fonts.bold,
                                              fontSize: 9.5,
                                              color: darkText)),
                                    if (job.company.isNotEmpty)
                                      pw.Text(job.company,
                                          style: pw.TextStyle(
                                              font: fonts.regular,
                                              fontSize: 9,
                                              color: PdfColors.grey600)),
                                    if (job.title.isNotEmpty)
                                      pw.Text(job.title,
                                          style: pw.TextStyle(
                                              font: fonts.bold,
                                              fontSize: 10,
                                              color: darkText)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      pw.SizedBox(height: 6),
                    ],

                    // Item 5 — Kenntnisse moved out of the sidebar.
                    if (skillsList.isNotEmpty) ...[
                      bodyHeader('Kenntnisse'),
                      for (final s in skillsList)
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(bottom: 4),
                          child: pw.Text(s,
                              style: pw.TextStyle(
                                  font: fonts.regular, fontSize: 9.5, color: darkText)),
                        ),
                      pw.SizedBox(height: 16),
                    ],

                    // Item 2 — dedicated IT-Kenntnisse section.
                    if (ausbildung.itSkills.isNotEmpty) ...[
                      bodyHeader('IT-Kenntnisse'),
                      for (final s in ausbildung.itSkills)
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(bottom: 4),
                          child: pw.Text(s,
                              style: pw.TextStyle(
                                  font: fonts.regular, fontSize: 9.5, color: darkText)),
                        ),
                      pw.SizedBox(height: 16),
                    ],

                    if (p.refName != null && p.refName!.isNotEmpty) ...[
                      bodyHeader('Referenz'),
                      pw.Text(p.refName!,
                          style: pw.TextStyle(
                              font: fonts.bold,
                              fontSize: 9.5,
                              color: darkText)),
                      if (p.refPhone != null && p.refPhone!.isNotEmpty)
                        pw.Text(p.refPhone!,
                            style: pw.TextStyle(
                                font: fonts.regular,
                                fontSize: 9,
                                color: PdfColors.grey600)),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  return doc.save();
}

// ─────────────────────────────────────────────────────────────────────────────
// navyHeader — navy header band across the top with photo overlapping,
// light grey left sidebar (Kontakt + Sprachen only); everything else in the
// right column with icon section headers. (reference: Blue_and_Gray)
// ─────────────────────────────────────────────────────────────────────────────

Future<Uint8List> _buildNavyHeader(
    UserProfile p, _AusbildungData ausbildung, bool isAusbildungCv) async {
  final fonts = await _loadFonts();
  final photo = await _loadPhoto(p);
  final navy = PdfColor.fromHex('#2E3E50');
  const darkText = PdfColor.fromInt(0xFF1A1A1A);
  final lightGrey = PdfColor.fromHex('#EDEFF2');

  final pageW = PdfPageFormat.a4.width;
  final pageH = PdfPageFormat.a4.height;
  const headerH = 128.0;
  final sidebarW = pageW * 0.32;

  pw.Widget sidebarHeader(String label) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label,
              style: pw.TextStyle(
                  font: fonts.bold, fontSize: 10.5, color: darkText)),
          pw.SizedBox(height: 3),
          pw.Container(height: 0.8, color: PdfColors.grey500),
          pw.SizedBox(height: 6),
        ],
      );

  pw.Widget sidebarLine(String text) {
    if (text.isEmpty) return pw.SizedBox();
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 5),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: 5,
            height: 5,
            margin: const pw.EdgeInsets.only(top: 2.5, right: 6),
            decoration:
                pw.BoxDecoration(shape: pw.BoxShape.circle, color: navy),
          ),
          pw.Expanded(
            child: pw.Text(text,
                style: pw.TextStyle(
                    font: fonts.regular, fontSize: 8.7, color: PdfColors.grey800)),
          ),
        ],
      ),
    );
  }

  // Item 1 — small heading label above the value, one per line.
  pw.Widget sidebarLabeledLine(String label, String value) {
    if (value.isEmpty) return pw.SizedBox();
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label,
              style: pw.TextStyle(
                  font: fonts.bold,
                  fontSize: 7,
                  color: PdfColors.grey600,
                  letterSpacing: 0.4)),
          pw.SizedBox(height: 1.5),
          pw.Text(value,
              style: pw.TextStyle(
                  font: fonts.regular, fontSize: 8.7, color: darkText)),
        ],
      ),
    );
  }

  pw.Widget iconSectionHeader(String label) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Container(
          width: 22,
          height: 22,
          decoration: pw.BoxDecoration(shape: pw.BoxShape.circle, color: navy),
        ),
        pw.SizedBox(width: 8),
        pw.Text(label,
            style: pw.TextStyle(font: fonts.bold, fontSize: 12, color: darkText)),
        pw.SizedBox(width: 8),
        pw.Expanded(child: pw.Container(height: 0.8, color: PdfColors.grey400)),
      ],
    );
  }

  final education = _educationText(p, isAusbildungCv);
  final schulabschluss = _schulabschlussText(p);
  final skillsList = _genericSkillsList(p, ausbildung, isAusbildungCv);
  final langEntries = _langEntries(p);
  final jobs = [..._jobs(p), ...ausbildung.jobs];
  final profile = _profileSummary(p, isAusbildungCv);
  final role = _roleText(p, isAusbildungCv);

  final doc = pw.Document(title: 'Lebenslauf – ${p.fullName}', author: 'KarYab');

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.zero,
      build: (context) => pw.SizedBox(
        width: pageW,
        height: pageH,
        child: pw.Stack(
          children: [
            pw.Positioned(
              left: 0,
              top: 0,
              right: 0,
              child: pw.Container(height: headerH, color: navy),
            ),
            pw.Positioned(
              left: sidebarW + 16,
              top: 30,
              right: 24,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(p.fullName.toUpperCase(),
                      style: pw.TextStyle(
                          font: fonts.bold, fontSize: 22, color: PdfColors.white)),
                  if (role.isNotEmpty) ...[
                    pw.SizedBox(height: 5),
                    pw.Text(role,
                        style: pw.TextStyle(
                            font: fonts.regular,
                            fontSize: 10.5,
                            color: PdfColors.grey200)),
                  ],
                ],
              ),
            ),
            pw.Positioned(
              left: 24,
              top: headerH - 34,
              child: _photoCircle(photo: photo, size: 68),
            ),
            pw.Positioned(
              left: 0,
              top: headerH,
              bottom: 0,
              child: pw.Container(
                width: sidebarW,
                color: lightGrey,
                padding: const pw.EdgeInsets.all(18),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    // Item 5 — sidebar restricted to Kontakt + Sprachen only.
                    sidebarHeader('KONTAKT'),
                    sidebarLabeledLine('TELEFON', p.phone),
                    sidebarLabeledLine('E-MAIL', p.email),
                    sidebarLabeledLine(
                        'ADRESSE', p.fullAddress == '—' ? '' : p.fullAddress),
                    if (langEntries.isNotEmpty) ...[
                      pw.SizedBox(height: 8),
                      sidebarHeader('SPRACHEN'),
                      for (final e in langEntries) sidebarLine(_langLine(e)),
                    ],
                  ],
                ),
              ),
            ),
            pw.Positioned(
              left: sidebarW + 16,
              top: headerH + 24,
              right: 24,
              bottom: 24,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (profile.isNotEmpty) ...[
                    iconSectionHeader('PROFIL'),
                    pw.SizedBox(height: 8),
                    pw.Text(profile,
                        style: pw.TextStyle(
                            font: fonts.regular, fontSize: 9.5, color: darkText)),
                    pw.SizedBox(height: 16),
                  ],
                  if (jobs.isNotEmpty) ...[
                    iconSectionHeader('BERUFSERFAHRUNG'),
                    pw.SizedBox(height: 10),
                    for (final job in jobs)
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(bottom: 12),
                        child: pw.Row(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Column(
                              children: [
                                pw.Container(
                                  width: 7,
                                  height: 7,
                                  decoration: pw.BoxDecoration(
                                      shape: pw.BoxShape.circle, color: navy),
                                ),
                                pw.Container(
                                    width: 1.2, height: 30, color: PdfColors.grey400),
                              ],
                            ),
                            pw.SizedBox(width: 10),
                            pw.Expanded(
                              child: pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                children: [
                                  pw.Row(
                                    mainAxisAlignment:
                                        pw.MainAxisAlignment.spaceBetween,
                                    children: [
                                      pw.Text(
                                          job.company.isNotEmpty
                                              ? job.company
                                              : job.title,
                                          style: pw.TextStyle(
                                              font: fonts.bold,
                                              fontSize: 10.5,
                                              color: darkText)),
                                      if (job.duration.isNotEmpty)
                                        pw.Text(job.duration,
                                            style: pw.TextStyle(
                                                font: fonts.regular,
                                                fontSize: 8.5,
                                                color: PdfColors.grey600)),
                                    ],
                                  ),
                                  if (job.title.isNotEmpty && job.company.isNotEmpty)
                                    pw.Text(job.title,
                                        style: pw.TextStyle(
                                            font: fonts.regular,
                                            fontSize: 9,
                                            color: PdfColors.grey700)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    pw.SizedBox(height: 6),
                  ],
                  if (education.isNotEmpty ||
                      schulabschluss.isNotEmpty ||
                      ausbildung.eduLines.isNotEmpty) ...[
                    iconSectionHeader('AUSBILDUNG'),
                    pw.SizedBox(height: 8),
                    if (education.isNotEmpty)
                      pw.Text(education,
                          style: pw.TextStyle(
                              font: fonts.bold, fontSize: 10, color: darkText)),
                    if (education.isNotEmpty && schulabschluss.isNotEmpty)
                      pw.SizedBox(height: 4),
                    if (schulabschluss.isNotEmpty)
                      pw.Text(schulabschluss,
                          style: pw.TextStyle(
                              font: fonts.bold, fontSize: 10, color: darkText)),
                    for (final line in ausbildung.eduLines)
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(top: 6),
                        child: _eduEntryContent(
                          line,
                          fonts,
                          headingSize: 9.5,
                          headingColor: darkText,
                          addressSize: 8.3,
                          addressColor: PdfColors.grey600,
                        ),
                      ),
                    pw.SizedBox(height: 16),
                  ],

                  // Item 5 — FÄHIGKEITEN moved out of the sidebar.
                  if (skillsList.isNotEmpty) ...[
                    iconSectionHeader('FÄHIGKEITEN'),
                    pw.SizedBox(height: 8),
                    for (final s in skillsList)
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(bottom: 4),
                        child: pw.Text(s,
                            style: pw.TextStyle(
                                font: fonts.regular, fontSize: 9.5, color: darkText)),
                      ),
                    pw.SizedBox(height: 16),
                  ],

                  // Item 2 — dedicated IT-Kenntnisse section.
                  if (ausbildung.itSkills.isNotEmpty) ...[
                    iconSectionHeader('IT-KENNTNISSE'),
                    pw.SizedBox(height: 8),
                    for (final s in ausbildung.itSkills)
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(bottom: 4),
                        child: pw.Text(s,
                            style: pw.TextStyle(
                                font: fonts.regular, fontSize: 9.5, color: darkText)),
                      ),
                    pw.SizedBox(height: 16),
                  ],

                  // Item 5 — REFERENZ moved out of the sidebar.
                  if (p.refName != null && p.refName!.isNotEmpty) ...[
                    iconSectionHeader('REFERENZ'),
                    pw.SizedBox(height: 8),
                    pw.Text(p.refName!,
                        style: pw.TextStyle(
                            font: fonts.bold, fontSize: 9.5, color: darkText)),
                    if (p.refPhone != null && p.refPhone!.isNotEmpty)
                      pw.Text(p.refPhone!,
                          style: pw.TextStyle(
                              font: fonts.regular,
                              fontSize: 9,
                              color: PdfColors.grey600)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  return doc.save();
}

// ─────────────────────────────────────────────────────────────────────────────
// blueTriangle — blue triangle filling the top-left corner, large circular
// photo overlapping it, name in blue below, left sidebar (Kontakt + Sprachen
// only), right column with icon section headers. (reference: Modern_Professional)
// ─────────────────────────────────────────────────────────────────────────────

Future<Uint8List> _buildBlueTriangle(
    UserProfile p, _AusbildungData ausbildung, bool isAusbildungCv) async {
  final fonts = await _loadFonts();
  final photo = await _loadPhoto(p);
  final blue = PdfColor.fromHex('#6B8DD6');
  const darkText = PdfColor.fromInt(0xFF1A1A1A);

  final pageW = PdfPageFormat.a4.width;
  final pageH = PdfPageFormat.a4.height;
  final sidebarW = pageW * 0.34;

  pw.Widget sidebarHeader(String label) => pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Container(
            width: 14,
            height: 14,
            decoration: pw.BoxDecoration(shape: pw.BoxShape.circle, color: blue),
          ),
          pw.SizedBox(width: 6),
          pw.Expanded(
            child: pw.Text(label,
                style: pw.TextStyle(
                    font: fonts.bold, fontSize: 10.5, color: darkText)),
          ),
        ],
      );

  pw.Widget sidebarLine(String text) {
    if (text.isEmpty) return pw.SizedBox();
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4, top: 3),
      child: pw.Text(text,
          style: pw.TextStyle(
              font: fonts.regular, fontSize: 8.7, color: PdfColors.grey800)),
    );
  }

  // Item 1 — small heading label above the value, one per line.
  pw.Widget sidebarLabeledLine(String label, String value) {
    if (value.isEmpty) return pw.SizedBox();
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label,
              style: pw.TextStyle(
                  font: fonts.bold,
                  fontSize: 7,
                  color: blue,
                  letterSpacing: 0.4)),
          pw.SizedBox(height: 1.5),
          pw.Text(value,
              style: pw.TextStyle(
                  font: fonts.regular, fontSize: 8.7, color: PdfColors.grey800)),
        ],
      ),
    );
  }

  pw.Widget rightHeader(String label) => pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Container(
            width: 20,
            height: 20,
            decoration: pw.BoxDecoration(shape: pw.BoxShape.circle, color: blue),
          ),
          pw.SizedBox(width: 8),
          pw.Text(label,
              style: pw.TextStyle(font: fonts.bold, fontSize: 12, color: darkText)),
          pw.SizedBox(width: 8),
          pw.Expanded(child: pw.Container(height: 0.8, color: blue)),
        ],
      );

  final education = _educationText(p, isAusbildungCv);
  final schulabschluss = _schulabschlussText(p);
  final skillsList = _genericSkillsList(p, ausbildung, isAusbildungCv);
  final langEntries = _langEntries(p);
  final jobs = [..._jobs(p), ...ausbildung.jobs];
  final profile = _profileSummary(p, isAusbildungCv);
  final role = _roleText(p, isAusbildungCv);

  final doc = pw.Document(title: 'Lebenslauf – ${p.fullName}', author: 'KarYab');

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.zero,
      build: (context) => pw.SizedBox(
        width: pageW,
        height: pageH,
        child: pw.Stack(
          children: [
            pw.Positioned(
              left: 0,
              top: 0,
              child: pw.CustomPaint(
                size: const PdfPoint(190, 130),
                painter: (canvas, size) {
                  canvas
                    ..setColor(blue)
                    ..moveTo(0, size.y)
                    ..lineTo(size.x, size.y)
                    ..lineTo(0, 0)
                    ..closePath()
                    ..fillPath();
                },
              ),
            ),
            pw.Positioned(
              left: 24,
              top: 24,
              child: _photoCircle(photo: photo, size: 84),
            ),
            pw.Positioned(
              left: 24,
              top: 118,
              right: 24,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(p.fullName,
                      style:
                          pw.TextStyle(font: fonts.bold, fontSize: 22, color: blue)),
                  if (role.isNotEmpty) ...[
                    pw.SizedBox(height: 4),
                    pw.Text(role,
                        style: pw.TextStyle(
                            font: fonts.regular,
                            fontSize: 10.5,
                            color: PdfColors.grey600)),
                  ],
                ],
              ),
            ),
            pw.Positioned(
              left: 24,
              top: 172,
              bottom: 24,
              child: pw.SizedBox(
                width: sidebarW,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    // Item 5 — sidebar restricted to Kontakt + Sprachen only
                    // ("Über mich" and "Fähigkeiten" moved to the main body).
                    sidebarHeader('Kontakt'),
                    sidebarLabeledLine('TELEFON', p.phone),
                    sidebarLabeledLine('E-MAIL', p.email),
                    sidebarLabeledLine(
                        'ADRESSE', p.fullAddress == '—' ? '' : p.fullAddress),
                    if (langEntries.isNotEmpty) ...[
                      pw.SizedBox(height: 10),
                      sidebarHeader('Sprachen'),
                      for (final e in langEntries) sidebarLine(_langLine(e)),
                    ],
                  ],
                ),
              ),
            ),
            pw.Positioned(
              left: 24 + sidebarW + 20,
              top: 172,
              right: 24,
              bottom: 24,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // Item 5 — "Über mich" (profile) moved from the sidebar.
                  if (profile.isNotEmpty) ...[
                    rightHeader('Über mich'),
                    pw.SizedBox(height: 8),
                    pw.Text(profile,
                        textAlign: pw.TextAlign.justify,
                        style: pw.TextStyle(
                            font: fonts.regular, fontSize: 9.5, color: darkText)),
                    pw.SizedBox(height: 16),
                  ],
                  if (education.isNotEmpty ||
                      schulabschluss.isNotEmpty ||
                      ausbildung.eduLines.isNotEmpty) ...[
                    rightHeader('Ausbildung'),
                    pw.SizedBox(height: 8),
                    if (education.isNotEmpty)
                      pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Column(children: [
                            pw.Container(
                              width: 6,
                              height: 6,
                              decoration: pw.BoxDecoration(
                                  shape: pw.BoxShape.circle, color: blue),
                            ),
                          ]),
                          pw.SizedBox(width: 10),
                          pw.Expanded(
                            child: pw.Text(education,
                                textAlign: pw.TextAlign.justify,
                                style: pw.TextStyle(
                                    font: fonts.regular,
                                    fontSize: 9.5,
                                    color: darkText)),
                          ),
                        ],
                      ),
                    if (education.isNotEmpty && schulabschluss.isNotEmpty)
                      pw.SizedBox(height: 6),
                    if (schulabschluss.isNotEmpty)
                      pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Column(children: [
                            pw.Container(
                              width: 6,
                              height: 6,
                              decoration: pw.BoxDecoration(
                                  shape: pw.BoxShape.circle, color: blue),
                            ),
                          ]),
                          pw.SizedBox(width: 10),
                          pw.Expanded(
                            child: pw.Text(schulabschluss,
                                textAlign: pw.TextAlign.justify,
                                style: pw.TextStyle(
                                    font: fonts.regular,
                                    fontSize: 9.5,
                                    color: darkText)),
                          ),
                        ],
                      ),
                    for (final line in ausbildung.eduLines)
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(top: 6),
                        child: pw.Row(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Column(children: [
                              pw.Container(
                                width: 6,
                                height: 6,
                                decoration: pw.BoxDecoration(
                                    shape: pw.BoxShape.circle, color: blue),
                              ),
                            ]),
                            pw.SizedBox(width: 10),
                            pw.Expanded(
                              child: _eduEntryContent(
                                line,
                                fonts,
                                headingSize: 9.5,
                                headingColor: darkText,
                                addressSize: 8.3,
                                addressColor: PdfColors.grey600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    pw.SizedBox(height: 16),
                  ],
                  if (jobs.isNotEmpty) ...[
                    rightHeader('Erfahrung'),
                    pw.SizedBox(height: 8),
                    for (final job in jobs)
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(bottom: 12),
                        child: pw.Row(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Column(
                              children: [
                                pw.Container(
                                  width: 6,
                                  height: 6,
                                  decoration: pw.BoxDecoration(
                                      shape: pw.BoxShape.circle, color: blue),
                                ),
                                pw.Container(
                                    width: 1, height: 30, color: PdfColors.grey300),
                              ],
                            ),
                            pw.SizedBox(width: 10),
                            pw.Expanded(
                              child: pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                children: [
                                  pw.Text(
                                      job.title.isNotEmpty
                                          ? job.title
                                          : job.company,
                                      style: pw.TextStyle(
                                          font: fonts.bold,
                                          fontSize: 10,
                                          color: darkText)),
                                  if (job.company.isNotEmpty)
                                    pw.Text(
                                        job.duration.isNotEmpty
                                            ? '${job.company} · ${job.duration}'
                                            : job.company,
                                        style: pw.TextStyle(
                                            font: fonts.regular,
                                            fontSize: 8.7,
                                            color: PdfColors.grey600)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    pw.SizedBox(height: 6),
                  ],

                  // Item 5 — Fähigkeiten moved from the sidebar.
                  if (skillsList.isNotEmpty) ...[
                    rightHeader('Fähigkeiten'),
                    pw.SizedBox(height: 8),
                    for (final s in skillsList) sidebarLine(s),
                    pw.SizedBox(height: 16),
                  ],

                  // Item 2 — dedicated IT-Kenntnisse section.
                  if (ausbildung.itSkills.isNotEmpty) ...[
                    rightHeader('IT-Kenntnisse'),
                    pw.SizedBox(height: 8),
                    for (final s in ausbildung.itSkills) sidebarLine(s),
                    pw.SizedBox(height: 16),
                  ],

                  if (p.refName != null && p.refName!.isNotEmpty) ...[
                    rightHeader('Referenzen'),
                    pw.SizedBox(height: 8),
                    pw.Text(p.refName!,
                        style: pw.TextStyle(
                            font: fonts.bold, fontSize: 9.5, color: darkText)),
                    if (p.refPhone != null && p.refPhone!.isNotEmpty)
                      pw.Text(p.refPhone!,
                          style: pw.TextStyle(
                              font: fonts.regular,
                              fontSize: 9,
                              color: PdfColors.grey600)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  return doc.save();
}

// ─────────────────────────────────────────────────────────────────────────────
// braunIconSet — left-third light grey/beige panel: bold brown headline
// name, icon-labeled contact block (Kontakt); right side (white) grouped
// into Persönliche Daten, Schulbildung, Praktika & Berufserfahrung,
// Fähigkeiten & Kenntnisse (Sprachen / IT & Technik / Führerschein
// sub-groups - Hobbys omitted, UserProfile has no such field anywhere in
// the app to source it from). Shares its visual identity with
// AnschreibenTemplate.braunIconSet and generateDeckblattBraunIconSet().
// ─────────────────────────────────────────────────────────────────────────────

Future<Uint8List> _buildBraunIconSet(
    UserProfile p, _AusbildungData ausbildung, bool isAusbildungCv) async {
  final fonts = await _loadFonts();
  final photo = await _loadPhoto(p);
  const darkText = PdfColor.fromInt(0xFF1A1A1A);

  final pageW = PdfPageFormat.a4.width;
  final pageH = PdfPageFormat.a4.height;
  final panelW = pageW * 0.33;

  pw.Widget bodyHeader(String label) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 8, top: 4),
        child: pw.Row(
          children: [
            pw.Container(width: 4, height: 14, color: _brownAccent),
            pw.SizedBox(width: 8),
            pw.Text(label,
                style: pw.TextStyle(
                    font: fonts.bold, fontSize: 12, color: darkText)),
          ],
        ),
      );

  pw.Widget subGroup(String label, List<String> items) {
    if (items.isEmpty) return pw.SizedBox();
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 10),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label,
              style: pw.TextStyle(
                  font: fonts.bold,
                  fontSize: 9,
                  color: _brownAccent,
                  letterSpacing: 0.4)),
          pw.SizedBox(height: 4),
          pw.Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in items)
                pw.Text(s,
                    style: pw.TextStyle(
                        font: fonts.regular, fontSize: 9, color: darkText)),
            ],
          ),
        ],
      ),
    );
  }

  final education = _educationText(p, isAusbildungCv);
  final schulabschluss = _schulabschlussText(p);
  final jobs = [..._jobs(p), ...ausbildung.jobs];
  final langLines = [for (final e in _langEntries(p)) _langLine(e)];
  final itTechnik = <String>[
    ...ausbildung.itSkills,
    if (!isAusbildungCv && p.tools != null && !_isNegative(p.tools))
      _resolve(p.tools, _toolsDe),
  ];
  final fuehrerschein = p.drivingLicense != null && !_isNegative(p.drivingLicense)
      ? [_resolve(p.drivingLicense, _licenseDe)]
      : <String>[];
  final fachkenntnisse = <String>[
    if (!isAusbildungCv) ..._skillsText(p).split(', ').where((s) => s.isNotEmpty),
    if (isAusbildungCv) ...ausbildung.escoSkills,
  ];
  final role = isAusbildungCv && ausbildung.targetOccupation.isNotEmpty
      ? ausbildung.targetOccupation
      : _roleText(p, isAusbildungCv);

  final doc = pw.Document(title: 'Lebenslauf – ${p.fullName}', author: 'KarYab');

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.zero,
      build: (context) => [
        pw.Stack(
          children: [
            pw.Container(
              width: panelW,
              constraints: pw.BoxConstraints(minHeight: pageH),
              color: _brownPanelBg,
              padding: const pw.EdgeInsets.fromLTRB(20, 40, 16, 24),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (photo != null) ...[
                    _photoCircle(photo: photo, size: 78, ringColor: PdfColors.white),
                    pw.SizedBox(height: 14),
                  ],
                  pw.Text(p.fullName,
                      style: pw.TextStyle(
                          font: fonts.bold, fontSize: 19, color: _brownAccent, height: 1.15)),
                  if (role.isNotEmpty) ...[
                    pw.SizedBox(height: 4),
                    pw.Text(role,
                        style: pw.TextStyle(
                            font: fonts.regular, fontSize: 9.5, color: PdfColors.grey700)),
                  ],
                  pw.SizedBox(height: 18),
                  pw.Text('KONTAKT',
                      style: pw.TextStyle(
                          font: fonts.bold, fontSize: 9, color: _brownAccent, letterSpacing: 0.6)),
                  pw.SizedBox(height: 8),
                  _brownIconContactLine(_brownIconPin(),
                      p.fullAddress == '—' ? '' : p.fullAddress, fonts, darkText),
                  _brownIconContactLine(_brownIconPhone(), p.phone, fonts, darkText),
                  _brownIconContactLine(_brownIconMail(), p.email, fonts, darkText),
                ],
              ),
            ),
            pw.Padding(
              padding: pw.EdgeInsets.fromLTRB(panelW + 24, 40, 32, 24),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  bodyHeader('PERSÖNLICHE DATEN'),
                  pw.Text('Geburtsdatum: ${p.dobFormatted}',
                      style: pw.TextStyle(font: fonts.regular, fontSize: 9.5, color: darkText)),
                  if (p.country != null && p.country!.isNotEmpty)
                    pw.Text('Nationalität: ${p.country}',
                        style: pw.TextStyle(font: fonts.regular, fontSize: 9.5, color: darkText)),
                  pw.SizedBox(height: 16),

                  if (education.isNotEmpty || schulabschluss.isNotEmpty || ausbildung.eduLines.isNotEmpty) ...[
                    bodyHeader('SCHULBILDUNG'),
                    if (education.isNotEmpty)
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(bottom: 6),
                        child: pw.Text(education,
                            style: pw.TextStyle(font: fonts.bold, fontSize: 10, color: darkText)),
                      ),
                    if (schulabschluss.isNotEmpty)
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(bottom: 6),
                        child: pw.Text(schulabschluss,
                            style: pw.TextStyle(font: fonts.bold, fontSize: 10, color: darkText)),
                      ),
                    for (final line in ausbildung.eduLines)
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(bottom: 8),
                        child: _eduEntryContent(line, fonts,
                            headingSize: 10, headingColor: darkText,
                            addressSize: 8.5, addressColor: PdfColors.grey600),
                      ),
                    pw.SizedBox(height: 8),
                  ],

                  if (jobs.isNotEmpty) ...[
                    bodyHeader('PRAKTIKA & BERUFSERFAHRUNG'),
                    for (final job in jobs)
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(bottom: 10),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(job.title.isNotEmpty ? job.title : job.company,
                                style: pw.TextStyle(font: fonts.bold, fontSize: 10, color: darkText)),
                            if (job.title.isNotEmpty && job.company.isNotEmpty)
                              pw.Text(
                                  job.duration.isNotEmpty
                                      ? '${job.company} · ${job.duration}'
                                      : job.company,
                                  style: pw.TextStyle(
                                      font: fonts.regular, fontSize: 8.7, color: _brownAccent)),
                          ],
                        ),
                      ),
                    pw.SizedBox(height: 8),
                  ],

                  if (fachkenntnisse.isNotEmpty ||
                      langLines.isNotEmpty ||
                      itTechnik.isNotEmpty ||
                      fuehrerschein.isNotEmpty) ...[
                    bodyHeader('FÄHIGKEITEN & KENNTNISSE'),
                    if (fachkenntnisse.isNotEmpty)
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(bottom: 10),
                        child: pw.Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final s in fachkenntnisse)
                              pw.Text(s,
                                  style: pw.TextStyle(
                                      font: fonts.regular, fontSize: 9, color: darkText)),
                          ],
                        ),
                      ),
                    subGroup('SPRACHEN', langLines),
                    subGroup('IT & TECHNIK', itTechnik),
                    subGroup('FÜHRERSCHEIN', fuehrerschein),
                  ],
                ],
              ),
            ),
          ],
        ),
      ],
    ),
  );

  return doc.save();
}

// ─────────────────────────────────────────────────────────────────────────────
// weissBraunSchlicht — light grey top band with a large bold brown
// "LEBENSLAUF" headline; single-column body below with brown section
// headers, icon-prefixed Persönliche Daten contact lines (address/phone/
// email icons, matching the shared Braun Icon-Set glyphs), and
// date-left/content-right rows for Schulbildung, Praktika & Berufserfahrung
// and Fähigkeiten & Kenntnisse. Shares its visual identity with
// AnschreibenTemplate.weissBraunSchlicht and
// DeckblattTemplate.weissBraunSchlicht. (Reference design's vertical divider
// line between date and content isn't reproduced - this pdf package has no
// IntrinsicHeight-equivalent to stretch a divider to match variable content
// height, so this follows atsBlue's existing date/content row pattern above
// instead, which needs no such divider.)
// ─────────────────────────────────────────────────────────────────────────────

Future<Uint8List> _buildWeissBraunSchlicht(
    UserProfile p, _AusbildungData ausbildung, bool isAusbildungCv) async {
  final fonts = await _loadFonts();
  const darkText = PdfColor.fromInt(0xFF1A1A1A);
  final bandGrey = PdfColor.fromHex('#EFEFEF');

  final pageW = PdfPageFormat.a4.width;

  pw.Widget sectionHeader(String label) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 10, top: 6),
        child: pw.Text(label,
            style: pw.TextStyle(
                font: fonts.bold, fontSize: 14, color: _brownAccent, letterSpacing: 0.3)),
      );

  pw.Widget row(String left, pw.Widget content) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 12),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 96,
            child: pw.Text(left,
                style: pw.TextStyle(font: fonts.bold, fontSize: 9.5, color: darkText)),
          ),
          pw.SizedBox(width: 12),
          pw.Expanded(child: content),
        ],
      ),
    );
  }

  final education = _educationText(p, isAusbildungCv);
  final schulabschluss = _schulabschlussText(p);
  final jobs = [..._jobs(p), ...ausbildung.jobs];
  final langLines = [for (final e in _langEntries(p)) _langLine(e)];
  final itTechnik = <String>[
    ...ausbildung.itSkills,
    if (!isAusbildungCv && p.tools != null && !_isNegative(p.tools))
      _resolve(p.tools, _toolsDe),
  ];
  final fuehrerschein = p.drivingLicense != null && !_isNegative(p.drivingLicense)
      ? [_resolve(p.drivingLicense, _licenseDe)]
      : <String>[];
  final fachkenntnisse = <String>[
    if (!isAusbildungCv) ..._skillsText(p).split(', ').where((s) => s.isNotEmpty),
    if (isAusbildungCv) ...ausbildung.escoSkills,
  ];

  final doc = pw.Document(title: 'Lebenslauf – ${p.fullName}', author: 'KarYab');

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.zero,
      build: (context) => [
        pw.Container(
          width: pageW,
          color: bandGrey,
          padding: const pw.EdgeInsets.symmetric(vertical: 34),
          alignment: pw.Alignment.center,
          child: pw.Text('LEBENSLAUF',
              style: pw.TextStyle(
                  font: fonts.bold, fontSize: 34, color: _brownAccent, letterSpacing: 6)),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.fromLTRB(42, 28, 42, 36),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              sectionHeader('PERSÖNLICHE DATEN'),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(p.fullName,
                            style: pw.TextStyle(font: fonts.bold, fontSize: 11, color: darkText)),
                        pw.SizedBox(height: 4),
                        _brownIconContactLine(_brownIconPin(),
                            p.fullAddress == '—' ? '' : p.fullAddress, fonts, darkText),
                        _brownIconContactLine(_brownIconPhone(), p.phone, fonts, darkText),
                        _brownIconContactLine(_brownIconMail(), p.email, fonts, darkText),
                      ],
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Geboren: ${p.dobFormatted}',
                            style: pw.TextStyle(font: fonts.regular, fontSize: 9.5, color: darkText)),
                        if (p.country != null && p.country!.isNotEmpty) ...[
                          pw.SizedBox(height: 4),
                          pw.Text('Staatsangehörigkeit: ${p.country}',
                              style: pw.TextStyle(font: fonts.regular, fontSize: 9.5, color: darkText)),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 20),

              if (education.isNotEmpty || schulabschluss.isNotEmpty || ausbildung.eduLines.isNotEmpty) ...[
                sectionHeader('SCHULBILDUNG'),
                if (education.isNotEmpty)
                  row('', pw.Text(education,
                      style: pw.TextStyle(font: fonts.bold, fontSize: 10, color: darkText))),
                if (schulabschluss.isNotEmpty)
                  row('', pw.Text(schulabschluss,
                      style: pw.TextStyle(font: fonts.bold, fontSize: 10, color: darkText))),
                for (final line in ausbildung.eduLines)
                  row(
                    line.dateRange,
                    _eduEntryContent(line, fonts,
                        headingSize: 10, headingColor: darkText,
                        addressSize: 8.7, addressColor: PdfColors.grey600),
                  ),
                pw.SizedBox(height: 8),
              ],

              if (jobs.isNotEmpty) ...[
                sectionHeader('PRAKTIKA & BERUFSERFAHRUNG'),
                for (final job in jobs)
                  row(
                    job.duration,
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(job.title.isNotEmpty ? job.title : job.company,
                            style: pw.TextStyle(font: fonts.bold, fontSize: 10, color: darkText)),
                        if (job.title.isNotEmpty && job.company.isNotEmpty)
                          pw.Text(job.company,
                              style: pw.TextStyle(font: fonts.regular, fontSize: 9, color: _brownAccent)),
                      ],
                    ),
                  ),
                pw.SizedBox(height: 8),
              ],

              if (fachkenntnisse.isNotEmpty ||
                  langLines.isNotEmpty ||
                  itTechnik.isNotEmpty ||
                  fuehrerschein.isNotEmpty) ...[
                sectionHeader('FÄHIGKEITEN & KENNTNISSE'),
                if (fachkenntnisse.isNotEmpty)
                  row('',
                      pw.Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final s in fachkenntnisse)
                            pw.Text(s,
                                style: pw.TextStyle(
                                    font: fonts.regular, fontSize: 9, color: darkText)),
                        ],
                      )),
                if (langLines.isNotEmpty)
                  row('Sprachen',
                      pw.Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final s in langLines)
                            pw.Text(s,
                                style: pw.TextStyle(
                                    font: fonts.regular, fontSize: 9, color: darkText)),
                        ],
                      )),
                if (itTechnik.isNotEmpty)
                  row('IT & Technik',
                      pw.Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final s in itTechnik)
                            pw.Text(s,
                                style: pw.TextStyle(
                                    font: fonts.regular, fontSize: 9, color: darkText)),
                        ],
                      )),
                if (fuehrerschein.isNotEmpty)
                  row('Führerschein',
                      pw.Text(fuehrerschein.first,
                          style: pw.TextStyle(font: fonts.regular, fontSize: 9, color: darkText))),
              ],
            ],
          ),
        ),
      ],
    ),
  );

  return doc.save();
}

// ─────────────────────────────────────────────────────────────────────────────
// Anschreiben (Cover Letter) — shared content composer, reused by all 6
// templates below so subject/body phrasing differs only in wording/
// typography per template, never in what real data it draws from (name,
// contact, target position, skills, most-recent job, Bildung) - never
// placeholder/lorem-ipsum text. The one exception is the recipient
// (Firma/Empfänger) block: no target-company field exists anywhere in the
// data model (confirmed - Anschreiben is generated with no extra
// questionnaire step), so it renders bracketed placeholder lines the user
// fills in by hand, same as any blank German Bewerbung letter template - the
// same "[Platzhalter]" convention is reused below for a missing {beruf}.
//
// Each section (Betreff, opening, skills, closing) has exactly 2 fixed
// German phrasing variants; the caller passes in a single shared `Random`
// (one per document/builder call, NOT one per call site) so that when a
// template renders the subject line twice (e.g. braunIconSet's sidebar +
// Betreff), both call sites must reuse the SAME already-picked string
// instead of re-rolling - see each _buildAnschreibenXxx() below, which
// computes `subject`/`body` once and reuses the variables.
// ─────────────────────────────────────────────────────────────────────────────

String _anschreibenSubject(String position, bool isAusbildungCv, Random rng) {
  final beruf = position.trim().isNotEmpty ? position.trim() : '[Position]';
  final variants = isAusbildungCv
      ? [
          'Bewerbung um einen Ausbildungsplatz als $beruf',
          'Bewerbung für die Ausbildung zum/zur $beruf',
        ]
      : [
          'Bewerbung als $beruf',
          'Meine Bewerbung für die Stelle als $beruf',
        ];
  return variants[rng.nextInt(variants.length)];
}

// Top 2 skills for the "middle paragraph" skill slots — ESCO skills for the
// Ausbildung CV, the general skill field for the Job CV, matching
// _genericSkillsList()'s own per-CV-type source split above.
List<String> _anschreibenSkillSlots(
    UserProfile p, _AusbildungData ausbildung, bool isAusbildungCv) {
  return isAusbildungCv
      ? ausbildung.escoSkills
      : _skillsText(p).split(', ').where((s) => s.isNotEmpty).toList();
}

List<String> _anschreibenBody(
  UserProfile p,
  _AusbildungData ausbildung,
  String position,
  bool isAusbildungCv,
  Random rng,
) {
  final beruf = position.trim().isNotEmpty ? position.trim() : '[Position]';
  final jobs = [..._jobs(p), ...ausbildung.jobs];

  // 1) Opening paragraph — 2 variants with prior Berufserfahrung/Praktika,
  // 2 different variants without.
  String letzterJob = '';
  if (jobs.isNotEmpty) {
    final latest = jobs.first;
    letzterJob = latest.title.isNotEmpty && latest.company.isNotEmpty
        ? '${latest.title} bei ${latest.company}'
        : (latest.title.isNotEmpty ? latest.title : latest.company);
  }
  final String opening;
  if (letzterJob.isNotEmpty) {
    final variants = [
      'mit großem Interesse habe ich Ihre Stellenausschreibung gelesen und bewerbe mich hiermit als $beruf. Durch meine bisherige Erfahrung als $letzterJob konnte ich bereits wertvolle praktische Kenntnisse in diesem Bereich sammeln.',
      'Ihre Ausschreibung hat mein Interesse sofort geweckt, da sie genau zu meinem bisherigen beruflichen Werdegang passt. Ich bewerbe mich hiermit als $beruf und bringe Erfahrung aus meiner Tätigkeit als $letzterJob mit.',
    ];
    opening = variants[rng.nextInt(variants.length)];
  } else {
    final variants = [
      'mit großem Interesse habe ich von der Möglichkeit erfahren, mich bei Ihnen als $beruf zu bewerben. Auch wenn ich noch am Anfang meines beruflichen Weges stehe, bin ich hoch motiviert und lernbereit.',
      'ich bewerbe mich hiermit um einen Ausbildungsplatz als $beruf. Der Beruf entspricht genau meinen Interessen, und ich freue mich darauf, mein Wissen in der Praxis anzuwenden und weiter auszubauen.',
    ];
    opening = variants[rng.nextInt(variants.length)];
  }

  // 2) Middle paragraph — skills, 2 variants with 2 skill slots each;
  // gracefully degrades to 1 slot or a generic fallback phrase (never a
  // broken/empty {skill2} slot) when fewer than 2 skills exist. Plus, for
  // the Ausbildung CV with Bildung data, one appended schulname sentence.
  final skillSlots = _anschreibenSkillSlots(p, ausbildung, isAusbildungCv);
  String middle;
  if (skillSlots.length >= 2) {
    final skill1 = skillSlots[0], skill2 = skillSlots[1];
    final variants = [
      'Zu meinen Stärken zählen unter anderem $skill1 und $skill2. Ich bin zuverlässig, arbeite gerne im Team und bringe die nötige Motivation mit, mich in neue Aufgaben einzuarbeiten.',
      'Besonders im Bereich $skill1 sowie $skill2 konnte ich bereits Erfahrungen sammeln. Ich arbeite strukturiert, bin lernbereit und freue mich auf neue Herausforderungen in Ihrem Unternehmen.',
    ];
    middle = variants[rng.nextInt(variants.length)];
  } else if (skillSlots.length == 1) {
    final skill1 = skillSlots[0];
    final variants = [
      'Zu meinen Stärken zählt unter anderem $skill1. Ich bin zuverlässig, arbeite gerne im Team und bringe die nötige Motivation mit, mich in neue Aufgaben einzuarbeiten.',
      'Besonders im Bereich $skill1 konnte ich bereits Erfahrungen sammeln. Ich arbeite strukturiert, bin lernbereit und freue mich auf neue Herausforderungen in Ihrem Unternehmen.',
    ];
    middle = variants[rng.nextInt(variants.length)];
  } else {
    final variants = [
      'Zu meinen Stärken zählen Zuverlässigkeit und Teamfähigkeit. Ich arbeite gerne im Team und bringe die nötige Motivation mit, mich in neue Aufgaben einzuarbeiten.',
      'Ich bin motiviert, zuverlässig und lernbereit und freue mich auf neue Herausforderungen in Ihrem Unternehmen.',
    ];
    middle = variants[rng.nextInt(variants.length)];
  }
  if (isAusbildungCv && ausbildung.eduLines.isNotEmpty) {
    final schulname = ausbildung.eduLines.first.institutionName;
    if (schulname.isNotEmpty) {
      middle =
          '$middle Meine schulische Ausbildung an der $schulname hat mich zusätzlich auf diesen Beruf vorbereitet.';
    }
  }

  // 3) Closing paragraph — 2 variants.
  const closingVariants = [
    'Über die Möglichkeit eines persönlichen Gesprächs würde ich mich sehr freuen. Gerne stehe ich Ihnen für weitere Fragen zur Verfügung.',
    'Ich freue mich darauf, Sie in einem persönlichen Gespräch von meiner Motivation zu überzeugen, und stehe Ihnen jederzeit für Rückfragen zur Verfügung.',
  ];
  final closing = closingVariants[rng.nextInt(closingVariants.length)];

  return [opening, middle, closing];
}

String _anschreibenDate() {
  final now = DateTime.now();
  return '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}';
}

pw.Widget _anschreibenAttachments(
    List<String> attachments, _Fonts fonts, PdfColor color) {
  if (attachments.isEmpty) return pw.SizedBox();
  return pw.Padding(
    padding: const pw.EdgeInsets.only(top: 24),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Anlagen:',
            style: pw.TextStyle(font: fonts.bold, fontSize: 9, color: color)),
        pw.SizedBox(height: 3),
        pw.Text(attachments.join(', '),
            style: pw.TextStyle(font: fonts.regular, fontSize: 9, color: color)),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// blauMinimal — sender block top-right in blue bold, recipient top-left
// plain black below it, right-aligned date, bold blue Betreff line.
// ─────────────────────────────────────────────────────────────────────────────

Future<Uint8List> _buildAnschreibenBlauMinimal(UserProfile p, _AusbildungData ausbildung,
    String position, bool isAusbildungCv, List<String> attachments, String companyName,
    [AnschreibenTexts? texts]) async {
  final fonts = await _loadFonts();
  final blue = PdfColor.fromHex('#1A4A8A');
  final doc = pw.Document(title: 'Anschreiben – ${p.fullName}', author: 'KarYab');
  final rng = Random();
  final subject = texts?.subject ?? _anschreibenSubject(position, isAusbildungCv, rng);
  final body = texts?.body ?? _anschreibenBody(p, ausbildung, position, isAusbildungCv, rng);
  final companyLine = companyName.isNotEmpty ? companyName : '[Unternehmen]';

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(48, 56, 48, 56),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(p.fullName,
                    style: pw.TextStyle(font: fonts.bold, fontSize: 13, color: blue)),
                if (p.fullAddress != '—')
                  pw.Text(p.fullAddress,
                      style: pw.TextStyle(font: fonts.bold, fontSize: 9.5, color: blue)),
                if (p.phone.isNotEmpty)
                  pw.Text(p.phone,
                      style: pw.TextStyle(font: fonts.bold, fontSize: 9.5, color: blue)),
                if (p.email.isNotEmpty)
                  pw.Text(p.email,
                      style: pw.TextStyle(font: fonts.bold, fontSize: 9.5, color: blue)),
              ],
            ),
          ),
          pw.SizedBox(height: 34),
          pw.Text(companyLine,
              style: pw.TextStyle(font: fonts.regular, fontSize: 10, color: PdfColors.black)),
          pw.Text('[Straße, PLZ Ort]',
              style: pw.TextStyle(font: fonts.regular, fontSize: 10, color: PdfColors.black)),
          pw.SizedBox(height: 26),
          pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(_anschreibenDate(),
                  style: pw.TextStyle(font: fonts.regular, fontSize: 10, color: PdfColors.grey700))),
          pw.SizedBox(height: 22),
          pw.Text(subject.toUpperCase(),
              style: pw.TextStyle(font: fonts.bold, fontSize: 12, color: blue, letterSpacing: 0.4)),
          pw.SizedBox(height: 18),
          pw.Text('Sehr geehrte Damen und Herren,',
              style: pw.TextStyle(font: fonts.regular, fontSize: 11, color: PdfColors.black)),
          pw.SizedBox(height: 12),
          for (final para in body) ...[
            pw.Text(para,
                style: pw.TextStyle(
                    font: fonts.regular, fontSize: 10.5, color: PdfColors.black, height: 1.5)),
            pw.SizedBox(height: 10),
          ],
          pw.SizedBox(height: 10),
          pw.Text('Mit freundlichen Grüßen',
              style: pw.TextStyle(font: fonts.regular, fontSize: 11, color: PdfColors.black)),
          pw.SizedBox(height: 28),
          pw.Text(p.fullName, style: pw.TextStyle(font: fonts.bold, fontSize: 11, color: blue)),
          _anschreibenAttachments(attachments, fonts, PdfColors.grey700),
        ],
      ),
    ),
  );
  return doc.save();
}

// ─────────────────────────────────────────────────────────────────────────────
// beigeEleganz — cream/beige top tint, small grey sender contact top-right,
// left-aligned recipient block, bold black subject line, faint neutral
// briefcase watermark bottom-right corner.
// ─────────────────────────────────────────────────────────────────────────────

Future<Uint8List> _buildAnschreibenBeigeEleganz(UserProfile p, _AusbildungData ausbildung,
    String position, bool isAusbildungCv, List<String> attachments, String companyName,
    [AnschreibenTexts? texts]) async {
  final fonts = await _loadFonts();
  final beige = PdfColor.fromHex('#F3ECDF');
  final doc = pw.Document(title: 'Anschreiben – ${p.fullName}', author: 'KarYab');
  final rng = Random();
  final subject = texts?.subject ?? _anschreibenSubject(position, isAusbildungCv, rng);
  final body = texts?.body ?? _anschreibenBody(p, ausbildung, position, isAusbildungCv, rng);
  final companyLine = companyName.isNotEmpty ? companyName : '[Unternehmen]';
  final pageW = PdfPageFormat.a4.width;

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.zero,
      build: (context) => pw.Stack(
        children: [
          pw.Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: pw.Container(width: pageW, height: 104, color: beige),
          ),
          // Faint neutral briefcase watermark - a simple, profession-agnostic
          // "application" symbol, kept generic since this template is reused
          // across every profession rather than industry-specific.
          pw.Positioned(
            right: 32,
            bottom: 40,
            child: pw.Opacity(
              opacity: 0.12,
              child: pw.CustomPaint(
                size: const PdfPoint(90, 70),
                painter: (canvas, s) {
                  canvas
                    ..setColor(PdfColor.fromHex('#8A7A5C'))
                    ..drawRRect(0, 0, s.x, s.y * 0.72, 6, 6)
                    ..fillPath()
                    ..drawRRect(s.x * 0.32, s.y * 0.72, s.x * 0.36, s.y * 0.16, 3, 3)
                    ..fillPath();
                },
              ),
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.fromLTRB(48, 32, 48, 56),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(p.fullName,
                          style: pw.TextStyle(font: fonts.bold, fontSize: 11, color: PdfColors.grey700)),
                      if (p.fullAddress != '—')
                        pw.Text(p.fullAddress,
                            style: pw.TextStyle(font: fonts.regular, fontSize: 8.7, color: PdfColors.grey600)),
                      if (p.phone.isNotEmpty)
                        pw.Text(p.phone,
                            style: pw.TextStyle(font: fonts.regular, fontSize: 8.7, color: PdfColors.grey600)),
                      if (p.email.isNotEmpty)
                        pw.Text(p.email,
                            style: pw.TextStyle(font: fonts.regular, fontSize: 8.7, color: PdfColors.grey600)),
                    ],
                  ),
                ),
                pw.SizedBox(height: 44),
                pw.Text(companyLine,
                    style: pw.TextStyle(font: fonts.regular, fontSize: 10, color: PdfColors.black)),
                pw.Text('[Straße, PLZ Ort]',
                    style: pw.TextStyle(font: fonts.regular, fontSize: 10, color: PdfColors.black)),
                pw.SizedBox(height: 20),
                pw.Text(_anschreibenDate(),
                    style: pw.TextStyle(font: fonts.regular, fontSize: 9.5, color: PdfColors.grey600)),
                pw.SizedBox(height: 20),
                pw.Text(subject,
                    style: pw.TextStyle(font: fonts.bold, fontSize: 12, color: PdfColors.black)),
                pw.SizedBox(height: 18),
                pw.Text('Sehr geehrte Damen und Herren,',
                    style: pw.TextStyle(font: fonts.regular, fontSize: 11, color: PdfColors.black)),
                pw.SizedBox(height: 12),
                for (final para in body) ...[
                  pw.Text(para,
                      style: pw.TextStyle(
                          font: fonts.regular, fontSize: 10.5, color: PdfColors.black, height: 1.5)),
                  pw.SizedBox(height: 10),
                ],
                pw.SizedBox(height: 10),
                pw.Text('Mit freundlichen Grüßen',
                    style: pw.TextStyle(font: fonts.regular, fontSize: 11, color: PdfColors.black)),
                pw.SizedBox(height: 28),
                pw.Text(p.fullName,
                    style: pw.TextStyle(font: fonts.bold, fontSize: 11, color: PdfColors.black)),
                _anschreibenAttachments(attachments, fonts, PdfColors.grey600),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  return doc.save();
}

// ─────────────────────────────────────────────────────────────────────────────
// boldHeadlineGrau — large bold 2-line sender-name headline (not boxed),
// plain recipient block, right-aligned date, bold subject, "Anlagen:" list
// at the very bottom dynamically populated from the user's generated docs.
// ─────────────────────────────────────────────────────────────────────────────

Future<Uint8List> _buildAnschreibenBoldHeadlineGrau(UserProfile p, _AusbildungData ausbildung,
    String position, bool isAusbildungCv, List<String> attachments, String companyName,
    [AnschreibenTexts? texts]) async {
  final fonts = await _loadFonts();
  const darkGrey = PdfColor.fromInt(0xFF2E2E2E);
  final doc = pw.Document(title: 'Anschreiben – ${p.fullName}', author: 'KarYab');
  final rng = Random();
  final subject = texts?.subject ?? _anschreibenSubject(position, isAusbildungCv, rng);
  final body = texts?.body ?? _anschreibenBody(p, ausbildung, position, isAusbildungCv, rng);
  final companyLine = companyName.isNotEmpty ? companyName : '[Unternehmen]';

  final nameParts = p.fullName.trim().split(RegExp(r'\s+'));
  final firstLine = nameParts.isNotEmpty ? nameParts.first : p.fullName;
  final secondLine = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(48, 48, 48, 48),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(firstLine.toUpperCase(),
              style: pw.TextStyle(font: fonts.bold, fontSize: 30, color: darkGrey, height: 1.0)),
          if (secondLine.isNotEmpty)
            pw.Text(secondLine.toUpperCase(),
                style: pw.TextStyle(font: fonts.bold, fontSize: 30, color: darkGrey, height: 1.0)),
          pw.SizedBox(height: 6),
          pw.Wrap(
            spacing: 12,
            children: [
              if (p.phone.isNotEmpty)
                pw.Text(p.phone, style: pw.TextStyle(font: fonts.regular, fontSize: 9.5, color: PdfColors.grey600)),
              if (p.email.isNotEmpty)
                pw.Text(p.email, style: pw.TextStyle(font: fonts.regular, fontSize: 9.5, color: PdfColors.grey600)),
              if (p.fullAddress != '—')
                pw.Text(p.fullAddress, style: pw.TextStyle(font: fonts.regular, fontSize: 9.5, color: PdfColors.grey600)),
            ],
          ),
          pw.SizedBox(height: 32),
          pw.Text(companyLine,
              style: pw.TextStyle(font: fonts.regular, fontSize: 10, color: PdfColors.black)),
          pw.Text('[Straße, PLZ Ort]',
              style: pw.TextStyle(font: fonts.regular, fontSize: 10, color: PdfColors.black)),
          pw.SizedBox(height: 22),
          pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(_anschreibenDate(),
                  style: pw.TextStyle(font: fonts.regular, fontSize: 10, color: PdfColors.grey600))),
          pw.SizedBox(height: 20),
          pw.Text(subject,
              style: pw.TextStyle(font: fonts.bold, fontSize: 12, color: darkGrey)),
          pw.SizedBox(height: 18),
          pw.Text('Sehr geehrte Damen und Herren,',
              style: pw.TextStyle(font: fonts.regular, fontSize: 11, color: PdfColors.black)),
          pw.SizedBox(height: 12),
          for (final para in body) ...[
            pw.Text(para,
                style: pw.TextStyle(
                    font: fonts.regular, fontSize: 10.5, color: PdfColors.black, height: 1.5)),
            pw.SizedBox(height: 10),
          ],
          pw.SizedBox(height: 10),
          pw.Text('Mit freundlichen Grüßen',
              style: pw.TextStyle(font: fonts.regular, fontSize: 11, color: PdfColors.black)),
          pw.SizedBox(height: 28),
          pw.Text(p.fullName, style: pw.TextStyle(font: fonts.bold, fontSize: 11, color: darkGrey)),
          pw.Spacer(),
          _anschreibenAttachments(attachments, fonts, PdfColors.grey700),
        ],
      ),
    ),
  );
  return doc.save();
}

// ─────────────────────────────────────────────────────────────────────────────
// braunIconSet — left-third grey/beige panel with the CV/Deckblatt's shared
// brown identity: bold brown 2-line name headline, subtitle line, icon
// contact block; right side (white) recipient/date/subject/body/closing.
// ─────────────────────────────────────────────────────────────────────────────

Future<Uint8List> _buildAnschreibenBraunIconSet(UserProfile p, _AusbildungData ausbildung,
    String position, bool isAusbildungCv, List<String> attachments, String companyName,
    [AnschreibenTexts? texts]) async {
  final fonts = await _loadFonts();
  const darkText = PdfColor.fromInt(0xFF1A1A1A);
  final doc = pw.Document(title: 'Anschreiben – ${p.fullName}', author: 'KarYab');
  final rng = Random();
  final subject = texts?.subject ?? _anschreibenSubject(position, isAusbildungCv, rng);
  final body = texts?.body ?? _anschreibenBody(p, ausbildung, position, isAusbildungCv, rng);
  final companyLine = companyName.isNotEmpty ? companyName : '[Unternehmen]';

  final pageW = PdfPageFormat.a4.width;
  final pageH = PdfPageFormat.a4.height;
  final panelW = pageW * 0.33;

  final nameParts = p.fullName.trim().split(RegExp(r'\s+'));
  final firstLine = nameParts.isNotEmpty ? nameParts.first : p.fullName;
  final secondLine = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.zero,
      build: (context) => pw.Stack(
        children: [
          pw.Container(
            width: panelW,
            height: pageH,
            color: _brownPanelBg,
            padding: const pw.EdgeInsets.fromLTRB(20, 48, 16, 24),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(firstLine,
                    style: pw.TextStyle(font: fonts.bold, fontSize: 18, color: _brownAccent, height: 1.15)),
                if (secondLine.isNotEmpty)
                  pw.Text(secondLine,
                      style: pw.TextStyle(font: fonts.bold, fontSize: 18, color: _brownAccent, height: 1.15)),
                pw.SizedBox(height: 6),
                pw.Text(subject,
                    style: pw.TextStyle(font: fonts.regular, fontSize: 9, color: PdfColors.grey700)),
                pw.SizedBox(height: 20),
                _brownIconContactLine(_brownIconPin(),
                    p.fullAddress == '—' ? '' : p.fullAddress, fonts, darkText),
                _brownIconContactLine(_brownIconPhone(), p.phone, fonts, darkText),
                _brownIconContactLine(_brownIconMail(), p.email, fonts, darkText),
              ],
            ),
          ),
          pw.Padding(
            padding: pw.EdgeInsets.fromLTRB(panelW + 24, 48, 40, 40),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(companyLine,
                    style: pw.TextStyle(font: fonts.regular, fontSize: 10, color: PdfColors.black)),
                pw.Text('[Straße, PLZ Ort]',
                    style: pw.TextStyle(font: fonts.regular, fontSize: 10, color: PdfColors.black)),
                pw.SizedBox(height: 22),
                pw.Align(
                    alignment: pw.Alignment.centerRight,
                    child: pw.Text(_anschreibenDate(),
                        style: pw.TextStyle(font: fonts.regular, fontSize: 10, color: PdfColors.grey600))),
                pw.SizedBox(height: 18),
                pw.Text(subject,
                    style: pw.TextStyle(font: fonts.bold, fontSize: 12, color: _brownAccent)),
                pw.SizedBox(height: 16),
                pw.Text('Sehr geehrte Damen und Herren,',
                    style: pw.TextStyle(font: fonts.regular, fontSize: 10.5, color: PdfColors.black)),
                pw.SizedBox(height: 10),
                for (final para in body) ...[
                  pw.Text(para,
                      style: pw.TextStyle(
                          font: fonts.regular, fontSize: 10, color: PdfColors.black, height: 1.45)),
                  pw.SizedBox(height: 8),
                ],
                pw.SizedBox(height: 8),
                pw.Text('Mit freundlichen Grüßen',
                    style: pw.TextStyle(font: fonts.regular, fontSize: 10.5, color: PdfColors.black)),
                pw.SizedBox(height: 24),
                pw.Text(p.fullName,
                    style: pw.TextStyle(font: fonts.bold, fontSize: 10.5, color: _brownAccent)),
                _anschreibenAttachments(attachments, fonts, PdfColors.grey600),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  return doc.save();
}

// ─────────────────────────────────────────────────────────────────────────────
// grauSchlicht — thin divider bar near the top; sender name/contact in a
// small bordered box with contact icons; italic right-aligned date.
// ─────────────────────────────────────────────────────────────────────────────

Future<Uint8List> _buildAnschreibenGrauSchlicht(UserProfile p, _AusbildungData ausbildung,
    String position, bool isAusbildungCv, List<String> attachments, String companyName,
    [AnschreibenTexts? texts]) async {
  final fonts = await _loadFonts();
  const darkText = PdfColor.fromInt(0xFF1A1A1A);
  final doc = pw.Document(title: 'Anschreiben – ${p.fullName}', author: 'KarYab');
  final rng = Random();
  final subject = texts?.subject ?? _anschreibenSubject(position, isAusbildungCv, rng);
  final body = texts?.body ?? _anschreibenBody(p, ausbildung, position, isAusbildungCv, rng);
  final companyLine = companyName.isNotEmpty ? companyName : '[Unternehmen]';
  // Explicit bounded width (page width minus this function's own 48+48
  // left/right margin) instead of `double.infinity` - a pw.Container with
  // width: double.infinity becomes a *tight* infinite-width constraint, and
  // this package's Column gives children unbounded width in the cross axis,
  // so enforce() has nothing finite to clamp it to. That's what threw
  // "Flex Children have non-zero flex, but incoming width constraints are
  // unbounded" from the Row/Expanded below. A concrete width also fixes the
  // divider bar just below, which previously had no width at all and could
  // collapse to zero instead of spanning the page for the same reason.
  final contentWidth = PdfPageFormat.a4.width - 96;

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(48, 48, 48, 48),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(width: contentWidth, height: 2, color: PdfColors.grey400),
          pw.SizedBox(height: 16),
          pw.Container(
            width: contentWidth,
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400, width: 0.8),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Text(p.fullName,
                      style: pw.TextStyle(font: fonts.bold, fontSize: 12, color: darkText)),
                ),
                // Bounded explicitly: this Column is a non-flex sibling of
                // the pw.Expanded above, so the outer Row measures it at its
                // natural (unbounded) width - that unboundedness would
                // otherwise reach _brownIconContactLine()'s own internal
                // pw.Expanded and throw the same "unbounded width" error
                // one level deeper. A SizedBox here stops it locally without
                // touching the shared helper other (already-bounded) call
                // sites rely on.
                pw.SizedBox(
                  width: contentWidth * 0.38,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      _brownIconContactLine(
                          _brownIconPin(color: PdfColors.grey700),
                          p.fullAddress == '—' ? '' : p.fullAddress,
                          fonts,
                          PdfColors.grey700),
                      _brownIconContactLine(
                          _brownIconPhone(color: PdfColors.grey700), p.phone, fonts, PdfColors.grey700),
                      _brownIconContactLine(
                          _brownIconMail(color: PdfColors.grey700), p.email, fonts, PdfColors.grey700),
                    ],
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 30),
          pw.Text(companyLine,
              style: pw.TextStyle(font: fonts.regular, fontSize: 10, color: PdfColors.black)),
          pw.Text('[Straße, PLZ Ort]',
              style: pw.TextStyle(font: fonts.regular, fontSize: 10, color: PdfColors.black)),
          pw.SizedBox(height: 22),
          pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(_anschreibenDate(),
                  style: pw.TextStyle(
                      font: fonts.italic, fontSize: 10, color: PdfColors.grey600))),
          pw.SizedBox(height: 20),
          pw.Text(subject,
              style: pw.TextStyle(font: fonts.bold, fontSize: 12, color: darkText)),
          pw.SizedBox(height: 18),
          pw.Text('Sehr geehrte Damen und Herren,',
              style: pw.TextStyle(font: fonts.regular, fontSize: 11, color: PdfColors.black)),
          pw.SizedBox(height: 12),
          for (final para in body) ...[
            pw.Text(para,
                style: pw.TextStyle(
                    font: fonts.regular, fontSize: 10.5, color: PdfColors.black, height: 1.5)),
            pw.SizedBox(height: 10),
          ],
          pw.SizedBox(height: 10),
          pw.Text('Mit freundlichen Grüßen',
              style: pw.TextStyle(font: fonts.regular, fontSize: 11, color: PdfColors.black)),
          pw.SizedBox(height: 28),
          pw.Text(p.fullName, style: pw.TextStyle(font: fonts.bold, fontSize: 11, color: darkText)),
          _anschreibenAttachments(attachments, fonts, PdfColors.grey700),
        ],
      ),
    ),
  );
  return doc.save();
}

// ─────────────────────────────────────────────────────────────────────────────
// weissBraunSchlicht — grey vertical panel on the right (sender contact +
// date), large bold brown 2-line "Hallo, ich bin..." headline spanning the
// full width near the top; recipient/subject/body/closing in the white
// area on the left. Shares its visual identity with
// DocumentTemplate.weissBraunSchlicht and
// DeckblattTemplate.weissBraunSchlicht. Positions below are estimated from
// the reference design image, not pixel-measured from it.
// ─────────────────────────────────────────────────────────────────────────────

Future<Uint8List> _buildAnschreibenWeissBraunSchlicht(UserProfile p, _AusbildungData ausbildung,
    String position, bool isAusbildungCv, List<String> attachments, String companyName,
    [AnschreibenTexts? texts]) async {
  final fonts = await _loadFonts();
  const darkText = PdfColor.fromInt(0xFF1A1A1A);
  final panelGrey = PdfColor.fromHex('#EFEFEF');
  final doc = pw.Document(title: 'Anschreiben – ${p.fullName}', author: 'KarYab');
  final rng = Random();
  final subject = texts?.subject ?? _anschreibenSubject(position, isAusbildungCv, rng);
  final body = texts?.body ?? _anschreibenBody(p, ausbildung, position, isAusbildungCv, rng);
  final companyLine = companyName.isNotEmpty ? companyName : '[Unternehmen]';

  final pageW = PdfPageFormat.a4.width;
  final pageH = PdfPageFormat.a4.height;
  final panelW = pageW * 0.3;

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.zero,
      build: (context) => pw.Stack(
        children: [
          pw.Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: pw.Container(width: panelW, height: pageH, color: panelGrey),
          ),
          pw.Positioned(
            left: 40,
            right: 40,
            top: 44,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('HALLO, ICH BIN',
                    style: pw.TextStyle(
                        font: fonts.bold, fontSize: 20, color: _brownAccent, letterSpacing: 1.5)),
                pw.Text(p.fullName.toUpperCase(),
                    style: pw.TextStyle(
                        font: fonts.bold, fontSize: 20, color: _brownAccent, letterSpacing: 1.5)),
              ],
            ),
          ),
          pw.Positioned(
            right: 24,
            left: pageW - panelW,
            top: 150,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                if (p.fullAddress != '—')
                  pw.Text(p.fullAddress,
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(font: fonts.regular, fontSize: 9, color: darkText)),
                if (p.phone.isNotEmpty)
                  pw.Text(p.phone,
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(font: fonts.regular, fontSize: 9, color: darkText)),
                if (p.email.isNotEmpty)
                  pw.Text(p.email,
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(font: fonts.regular, fontSize: 9, color: darkText)),
              ],
            ),
          ),
          pw.Positioned(
            right: 24,
            left: pageW - panelW,
            top: 260,
            child: pw.Text(_anschreibenDate(),
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(font: fonts.bold, fontSize: 10, color: darkText)),
          ),
          pw.Positioned(
            left: 40,
            right: panelW + 24,
            top: 160,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(companyLine,
                    style: pw.TextStyle(font: fonts.bold, fontSize: 11, color: _brownAccent)),
                pw.Text('[Straße, PLZ Ort]',
                    style: pw.TextStyle(font: fonts.regular, fontSize: 10, color: PdfColors.black)),
                pw.SizedBox(height: 26),
                pw.Text(subject,
                    style: pw.TextStyle(font: fonts.bold, fontSize: 12, color: _brownAccent)),
                pw.SizedBox(height: 18),
                pw.Text('Sehr geehrte Damen und Herren,',
                    style: pw.TextStyle(font: fonts.regular, fontSize: 10.5, color: PdfColors.black)),
                pw.SizedBox(height: 12),
                for (final para in body) ...[
                  pw.Text(para,
                      style: pw.TextStyle(
                          font: fonts.regular, fontSize: 10, color: PdfColors.black, height: 1.5)),
                  pw.SizedBox(height: 10),
                ],
                pw.SizedBox(height: 8),
                pw.Text('Mit freundlichen Grüßen',
                    style: pw.TextStyle(font: fonts.regular, fontSize: 10.5, color: PdfColors.black)),
                pw.SizedBox(height: 24),
                pw.Text(p.fullName,
                    style: pw.TextStyle(font: fonts.italic, fontSize: 13, color: _brownAccent)),
                _anschreibenAttachments(attachments, fonts, PdfColors.grey700),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  return doc.save();
}

// ─────────────────────────────────────────────────────────────────────────────
// Deckblatt (application cover page) — braunIconSet identity only (the one
// design requested). Left-panel name headline + subtitle + icon contact
// block, "Anlagen:" list on the lower-right area.
// ─────────────────────────────────────────────────────────────────────────────

Future<Uint8List> _buildDeckblattBraunIconSet(
    UserProfile p, String position, List<String> attachments) async {
  final fonts = await _loadFonts();
  final photo = await _loadPhoto(p);
  const darkText = PdfColor.fromInt(0xFF1A1A1A);
  final doc = pw.Document(title: 'Deckblatt – ${p.fullName}', author: 'KarYab');

  final pageW = PdfPageFormat.a4.width;
  final pageH = PdfPageFormat.a4.height;
  final panelW = pageW * 0.36;

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.zero,
      build: (context) => pw.Stack(
        children: [
          pw.Container(
            width: panelW,
            height: pageH,
            color: _brownPanelBg,
            padding: const pw.EdgeInsets.fromLTRB(20, 56, 16, 24),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (photo != null) ...[
                  _photoCircle(photo: photo, size: 96, ringColor: PdfColors.white),
                  pw.SizedBox(height: 20),
                ],
                pw.Text(p.fullName,
                    style: pw.TextStyle(
                        font: fonts.bold, fontSize: 20, color: _brownAccent, height: 1.15)),
                if (position.isNotEmpty) ...[
                  pw.SizedBox(height: 6),
                  pw.Text(position,
                      style: pw.TextStyle(font: fonts.regular, fontSize: 10, color: PdfColors.grey700)),
                ],
                pw.SizedBox(height: 24),
                _brownIconContactLine(_brownIconPin(),
                    p.fullAddress == '—' ? '' : p.fullAddress, fonts, darkText),
                _brownIconContactLine(_brownIconPhone(), p.phone, fonts, darkText),
                _brownIconContactLine(_brownIconMail(), p.email, fonts, darkText),
              ],
            ),
          ),
          pw.Positioned(
            left: panelW + 32,
            right: 32,
            bottom: 48,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Bewerbungsunterlagen',
                    style: pw.TextStyle(font: fonts.bold, fontSize: 12, color: darkText)),
                pw.SizedBox(height: 10),
                pw.Text('Anlagen:',
                    style: pw.TextStyle(font: fonts.bold, fontSize: 9.5, color: _brownAccent)),
                pw.SizedBox(height: 4),
                pw.Text(
                    ['Anschreiben', 'Lebenslauf', ...attachments.where((a) => a != 'Lebenslauf')]
                        .join(', '),
                    style: pw.TextStyle(font: fonts.regular, fontSize: 10, color: darkText)),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  return doc.save();
}

// ─────────────────────────────────────────────────────────────────────────────
// weissBraunSchlicht — grey panel on the left; name headline + subtitle
// straddle the panel/white boundary; icon contact block and "Anlagen:" list
// below, fully in the white area. Shares its visual identity with
// DocumentTemplate.weissBraunSchlicht and
// AnschreibenTemplate.weissBraunSchlicht. Positions below are estimated
// from the reference design image, not pixel-measured from it.
// ─────────────────────────────────────────────────────────────────────────────

Future<Uint8List> _buildDeckblattWeissBraunSchlicht(
    UserProfile p, String position, List<String> attachments) async {
  final fonts = await _loadFonts();
  const darkText = PdfColor.fromInt(0xFF1A1A1A);
  final panelGrey = PdfColor.fromHex('#EFEFEF');
  final doc = pw.Document(title: 'Deckblatt – ${p.fullName}', author: 'KarYab');

  final pageW = PdfPageFormat.a4.width;
  final pageH = PdfPageFormat.a4.height;
  final panelW = pageW * 0.32;

  final nameParts = p.fullName.trim().split(RegExp(r'\s+'));
  final firstLine = nameParts.isNotEmpty ? nameParts.first : p.fullName;
  final secondLine = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.zero,
      build: (context) => pw.Stack(
        children: [
          pw.Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: pw.Container(width: panelW, height: pageH, color: panelGrey),
          ),
          pw.Positioned(
            left: panelW - 30,
            right: 40,
            top: 140,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(firstLine.toUpperCase(),
                    style: pw.TextStyle(
                        font: fonts.bold,
                        fontSize: 26,
                        color: _brownAccent,
                        letterSpacing: 1.2,
                        height: 1.15)),
                if (secondLine.isNotEmpty)
                  pw.Text(secondLine.toUpperCase(),
                      style: pw.TextStyle(
                          font: fonts.bold,
                          fontSize: 26,
                          color: _brownAccent,
                          letterSpacing: 1.2,
                          height: 1.15)),
                if (position.isNotEmpty) ...[
                  pw.SizedBox(height: 14),
                  pw.Text(position,
                      style: pw.TextStyle(
                          font: fonts.regular, fontSize: 12, color: PdfColors.black, height: 1.4)),
                ],
              ],
            ),
          ),
          pw.Positioned(
            left: panelW + 40,
            right: 40,
            top: 340,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _brownIconContactLine(_brownIconPin(),
                    p.fullAddress == '—' ? '' : p.fullAddress, fonts, darkText),
                _brownIconContactLine(_brownIconPhone(), p.phone, fonts, darkText),
                _brownIconContactLine(_brownIconMail(), p.email, fonts, darkText),
              ],
            ),
          ),
          pw.Positioned(
            left: panelW + 40,
            right: 40,
            bottom: 48,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Anlagen:',
                    style: pw.TextStyle(font: fonts.bold, fontSize: 10, color: _brownAccent)),
                pw.SizedBox(height: 4),
                pw.Text(
                    ['Lebenslauf', ...attachments.where((a) => a != 'Lebenslauf')].join(', '),
                    style: pw.TextStyle(font: fonts.regular, fontSize: 10.5, color: darkText)),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  return doc.save();
}
