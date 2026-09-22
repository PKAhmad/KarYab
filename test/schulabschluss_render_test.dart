import 'package:flutter_test/flutter_test.dart';
import 'package:karyab/models/document_template.dart';
import 'package:karyab/models/user_profile.dart';
import 'package:karyab/services/cv_pdf_generator.dart';

// Structural checks only — PDF content streams here are compressed and, for
// the embedded TTF, glyph-indexed rather than literal ASCII text, so
// searching raw bytes for e.g. "Hauptschulabschluss" cannot reliably prove
// (or disprove) what's actually rendered. Real visual confirmation of the
// schulabschluss/grade rendering was done by generating sample PDFs and
// having them opened directly (see the sample files sent alongside this
// change) rather than via string-matching here.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const baseProfile = UserProfile(
    fullName: 'Sahar Karimi',
    phone: '+49 160 1112233',
    email: 'sahar.karimi@example.com',
    street: 'Beispielweg 3',
    city: '10115 Berlin',
    languages: ['dari'],
    educationLevel: 'vocational',
  );

  for (final template in DocumentTemplate.values) {
    test('${template.name}: generates with preset schulabschluss + grade '
        'alongside existing educationLevel', () async {
      final profile = baseProfile.copyWith(
        schulabschluss: 'hauptschule',
        schulabschlussNote: '1,8',
      );
      final bytes = await generateCv(profile, template);
      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test('${template.name}: generates with foreign-qualification free text',
        () async {
      final profile = baseProfile.copyWith(
        schulabschluss: 'Abschlusszeugnis Klasse 12, Iran',
      );
      final bytes = await generateCv(profile, template);
      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test('${template.name}: generates with kein_abschluss without throwing',
        () async {
      final profile = baseProfile.copyWith(schulabschluss: 'kein_abschluss');
      final bytes = await generateCv(profile, template);
      expect(bytes, isNotEmpty);
    });

    test('${template.name}: generates unaffected when schulabschluss is '
        'absent (regular-flow profile)', () async {
      final bytes = await generateCv(baseProfile, template);
      expect(bytes, isNotEmpty);
    });
  }
}
