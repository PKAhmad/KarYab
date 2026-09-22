import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/language_provider.dart';

/// Continues the flow after a language has been chosen — English skips the
/// Education (literate/illiterate) question entirely and goes straight to
/// Introduction in educated mode; Pashto/Dari go to Education.
///
/// Shared by welcome_screen.dart (when the permissions onboarding has
/// already been shown) and permissions_screen.dart (right after the user
/// taps Continue there for the first time), so the branching logic only
/// lives in one place.
Future<void> proceedAfterLanguageSelection(
  BuildContext context,
  String langCode,
) async {
  if (langCode == 'en') {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('voice_mode', false);
    await prefs.setString('app_language', langCode);
    if (!context.mounted) return;
    context.read<LanguageProvider>().setVoiceMode(false);
    Navigator.pushNamed(
      context,
      '/introduction',
      arguments: {
        'language': langCode,
        'voiceMode': false,
      },
    );
    return;
  }

  Navigator.pushNamed(
    context,
    '/education',
    arguments: {
      'language': langCode,
      'voiceMode': true,
    },
  );
}

/// Navigates to Introduction the way every "home" button across the app
/// should.
///
/// Pashto/Dari: clears the stack down to Education (or rebuilds
/// [Education, Introduction] if Education isn't present) so a system back
/// press from Introduction lands on Education, not on whatever screen the
/// user was deep in when they tapped "home".
///
/// English: Introduction has no Education screen in its flow (welcome_screen
/// skips straight to it) and uses double-back-to-exit instead of a normal
/// back target, so "home" clears the whole stack down to Introduction alone
/// rather than inserting an Education screen the user never saw.
void goHomeToIntroduction(
  BuildContext context, {
  required String language,
  required bool voiceMode,
}) {
  final arguments = {'language': language, 'voiceMode': voiceMode};

  if (language == 'en') {
    Navigator.of(context).pushNamedAndRemoveUntil(
      '/introduction',
      (route) => false,
      arguments: arguments,
    );
    return;
  }

  bool sawEducation = false;
  Navigator.of(context).pushNamedAndRemoveUntil(
    '/introduction',
    (route) {
      if (route.settings.name == '/education') sawEducation = true;
      return route.settings.name == '/education' || route.isFirst;
    },
    arguments: arguments,
  );

  if (!sawEducation) {
    Navigator.of(context).pushNamedAndRemoveUntil(
      '/education',
      (route) => false,
      arguments: arguments,
    );
    Navigator.of(context).pushNamed('/introduction', arguments: arguments);
  }
}
