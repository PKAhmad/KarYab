import 'package:flutter/material.dart';

class LanguageProvider extends ChangeNotifier {
  String _language;
  bool _voiceMode;

  LanguageProvider({String language = 'en', bool voiceMode = false})
      : _language = language,
        _voiceMode = voiceMode;

  String get language => _language;
  bool get voiceMode => _voiceMode;

  void setLanguage(String lang) {
    if (_language == lang) return;
    _language = lang;
    notifyListeners();
  }

  void setVoiceMode(bool value) {
    if (_voiceMode == value) return;
    _voiceMode = value;
    notifyListeners();
  }

  // Called from screen initState to sync from navigation arg.
  // Does NOT override if same value (avoids unnecessary rebuild).
  void syncFromNav(String lang, {bool? voiceMode}) {
    bool changed = false;
    if (_language != lang) {
      _language = lang;
      changed = true;
    }
    if (voiceMode != null && _voiceMode != voiceMode) {
      _voiceMode = voiceMode;
      changed = true;
    }
    if (changed) notifyListeners();
  }
}
