import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:karyab/models/document_template.dart';
import 'package:karyab/widgets/document_template_picker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpPickerHarness(
    WidgetTester tester,
    ValueChanged<DocumentTemplate> onResult,
  ) {
    return tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              final chosen = await showDocumentTemplatePicker(context,
                  current: DocumentTemplate.atsBlue);
              onResult(chosen);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
  }

  testWidgets(
      'tapping a template selects it on a short viewport (regression for '
      'the old unreachable-confirm-button bug)', (tester) async {
    // A short/small-phone-ish viewport is exactly what made the old
    // non-scrolling sheet overflow far enough to push its controls outside
    // the tappable area. Tapping a template now selects it directly.
    tester.view.physicalSize = const Size(360, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    DocumentTemplate? returned;
    await pumpPickerHarness(tester, (t) => returned = t);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // The card must be reachable (and actually hit); ensureVisible only
    // scrolls the ancestor Scrollable into position.
    await tester.ensureVisible(find.text('Dark Sidebar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark Sidebar'), warnIfMissed: true);
    await tester.pumpAndSettle();

    expect(returned, DocumentTemplate.darkSidebar);
  });

  testWidgets('picker returns the tapped template on a normal viewport',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    DocumentTemplate? returned;
    await pumpPickerHarness(tester, (t) => returned = t);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Blue Triangle'));
    await tester.pumpAndSettle();

    expect(returned, DocumentTemplate.blueTriangle);
  });

  test('load/save round-trip is scoped to the caller-supplied key', () async {
    SharedPreferences.setMockInitialValues({});

    await saveSelectedDocumentTemplate(
        'selected_cv_template_regular', DocumentTemplate.darkSidebar);
    await saveSelectedDocumentTemplate(
        'selected_cv_template_ausbildung', DocumentTemplate.navyHeader);

    final regular =
        await loadSelectedDocumentTemplate('selected_cv_template_regular');
    final ausbildung = await loadSelectedDocumentTemplate(
        'selected_cv_template_ausbildung');
    final untouched =
        await loadSelectedDocumentTemplate('some_other_unused_key');

    expect(regular, DocumentTemplate.darkSidebar);
    expect(ausbildung, DocumentTemplate.navyHeader);
    expect(untouched, DocumentTemplate.atsBlue,
        reason: 'unrelated keys must default to atsBlue, not leak state');
  });
}
