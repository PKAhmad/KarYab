import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:printing/printing.dart';

import 'package:karyab/models/document_template.dart';
import 'package:karyab/models/user_profile.dart';
import 'package:karyab/services/cv_pdf_generator.dart';

// Focused check on the one genuinely new element used by
// ausbildung_document_preview_screen.dart — PdfPreview wired to
// generateCv() — without the Firebase-mocking overhead of a full-screen
// pump (AnalyticsService needs Firebase.initializeApp(), unrelated to what
// this test is checking).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const profile = UserProfile(
    fullName: 'Test User',
    phone: '123',
    email: 'a@b.com',
    street: 'Str 1',
    city: 'Berlin',
    languages: [],
    schulabschluss: 'hauptschule',
  );

  testWidgets('PdfPreview builds without throwing for each template',
      (tester) async {
    for (final template in DocumentTemplate.values) {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 440,
            child: PdfPreview(
              key: ValueKey(template),
              build: (format) => generateCv(profile, template),
              canChangeOrientation: false,
              canChangePageFormat: false,
              canDebug: false,
            ),
          ),
        ),
      ));
      // Bounded pump (not pumpAndSettle) — native rasterization has no
      // platform channel in this host test environment, so it may never
      // fully settle; we're only confirming construction + the build()
      // callback don't throw, not that on-device rendering completes.
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    }
  });
}
