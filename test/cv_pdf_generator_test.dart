import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:karyab/models/document_template.dart';
import 'package:karyab/models/user_profile.dart';
import 'package:karyab/services/cv_pdf_generator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const fullProfile = UserProfile(
    fullName: 'Ahmad Rahimi',
    phone: '+49 151 23456789',
    email: 'ahmad.rahimi@example.com',
    street: 'Musterstraße 12',
    city: '12345 Berlin',
    languages: ['pashto', 'german'],
    country: 'af',
    skill: 'cleaning,driving',
    workExperience: 'more2',
    workType: 'cleaning',
    tools: 'power_tools',
    drivingLicense: 'german_license',
    availability: 'fulltime',
    startDate: 'immediately',
    educationLevel: 'vocational',
    previousEmployers: ['Muster GmbH', 'Beispiel AG'],
    previousJobTitles: ['Reinigungskraft', 'Lagerhelfer'],
    previousJobDurations: ['2022–2024', '2020–2022'],
    languageProficiency: {'Deutsch': 'B1', 'Paschtu': 'Muttersprache'},
    refName: 'Herr Schmidt',
    refPhone: '+49 170 9998877',
  );

  // Minimal profile: no photo, no jobs, no languageProficiency, negative
  // sentinels present — exercises every "graceful when data is missing"
  // path across all 4 templates.
  const minimalProfile = UserProfile(
    fullName: 'Sara Ahmadi',
    phone: '',
    email: '',
    street: '',
    city: '',
    languages: [],
    tools: 'no_tools',
    drivingLicense: 'no_license',
    workExperience: 'never',
  );

  for (final template in DocumentTemplate.values) {
    test('generateCv (${template.name}) renders full profile offline', () async {
      final bytes = await generateCv(fullProfile, template);
      expect(bytes, isNotEmpty);
      // %PDF header confirms a real PDF document was produced.
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test('generateCv (${template.name}) renders minimal profile gracefully',
        () async {
      final bytes = await generateCv(minimalProfile, template);
      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });
  }

  test('negative sentinels never leak into the PDF text stream', () async {
    final bytes = await generateCv(minimalProfile, DocumentTemplate.atsBlue);
    // Crude but effective: none of the raw sentinel codes (as opposed to
    // their resolved German labels) should appear as literal bytes.
    final raw = String.fromCharCodes(bytes);
    expect(raw.contains('no_tools'), isFalse);
    expect(raw.contains('no_license'), isFalse);
  });

  test('missing photo file path degrades gracefully instead of throwing',
      () async {
    final profileWithBadPhoto = fullProfile.copyWith();
    final broken = UserProfile(
      fullName: profileWithBadPhoto.fullName,
      phone: profileWithBadPhoto.phone,
      email: profileWithBadPhoto.email,
      street: profileWithBadPhoto.street,
      city: profileWithBadPhoto.city,
      languages: profileWithBadPhoto.languages,
      photoPath: '${Directory.systemTemp.path}/does_not_exist_${DateTime.now().microsecondsSinceEpoch}.png',
    );
    for (final template in DocumentTemplate.values) {
      final bytes = await generateCv(broken, template);
      expect(bytes, isNotEmpty);
    }
  });
}
