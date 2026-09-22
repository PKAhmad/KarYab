import 'package:firebase_analytics/firebase_analytics.dart';

class AnalyticsService {
  static final AnalyticsService _instance =
      AnalyticsService._internal();
  factory AnalyticsService() => _instance;
  AnalyticsService._internal();

  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  Future<void> logScreen(String screenName) async {
    await _analytics.logScreenView(screenName: screenName);
  }

  Future<void> logLanguageSelected(String language) async {
    await _analytics.logEvent(
      name: 'language_selected',
      parameters: {'language': language},
    );
  }

  Future<void> logEducationLevel(bool educated) async {
    await _analytics.logEvent(
      name: 'education_level',
      parameters: {'educated': educated.toString()},
    );
  }

  Future<void> logCVCreated() async {
    await _analytics.logEvent(name: 'cv_created');
  }

  Future<void> logCVDownloaded() async {
    await _analytics.logEvent(name: 'cv_downloaded');
  }

  Future<void> logJobSearch(String city, String category) async {
    await _analytics.logEvent(
      name: 'job_search',
      parameters: {
        'city': city,
        'category': category,
      },
    );
  }

  Future<void> logJobApply(String method) async {
    await _analytics.logEvent(
      name: 'job_apply',
      parameters: {'method': method},
    );
  }

  Future<void> logCoverLetterDownloaded() async {
    await _analytics.logEvent(name: 'cover_letter_downloaded');
  }

  Future<void> logAppOpen() async {
    await _analytics.logAppOpen();
  }
}
