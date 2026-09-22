import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/secrets.dart';

class TtsService {
  static final TtsService _instance = TtsService._internal();
  factory TtsService() => _instance;
  TtsService._internal() {
    _player.onPlayerComplete.listen((_) {
      _isPlaying = false;
      _notifyListeners();
    });
    _loadSoundPref();
  }

  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;
  bool _soundEnabled = true;
  bool _hintPulseActive = false;
  final _listeners = <void Function()>[];

  // Bumped every time stop() runs. speak() captures the value right after
  // its own opening stop() call and re-checks it before actually starting
  // playback, so a stop() issued while the network request is still in
  // flight (e.g. a screen's dispose() firing mid-request) discards the
  // response instead of letting audio start after the screen is gone.
  int _requestId = 0;

  // ── Azure credentials ──────────────────────────────────────────────────────
  static const String _apiKey = Secrets.azureTtsKey;
  static const String _region = 'westeurope';

  static const Map<String, String> _voices = {
    'ps': 'ps-AF-GulNawazNeural',
    'fa': 'fa-IR-FaridNeural',
    'en': 'de-DE-KatjaNeural',
    'de': 'de-DE-KatjaNeural',
  };

  static const Map<String, String> _langCodes = {
    'ps': 'ps-AF',
    'fa': 'fa-IR',
    'en': 'de-DE',
    'de': 'de-DE',
  };

  // ── Public API ──────────────────────────────────────────────────────────────
  bool get isPlaying        => _isPlaying;
  bool get soundEnabled     => _soundEnabled;
  bool get hintPulseActive  => _hintPulseActive;

  void addListener(void Function() listener)    => _listeners.add(listener);
  void removeListener(void Function() listener) => _listeners.remove(listener);

  void _notifyListeners() {
    for (final l in List.of(_listeners)) l();
  }

  void _setPlaying(bool value) {
    _isPlaying = value;
    _notifyListeners();
  }

  Future<void> _loadSoundPref() async {
    final prefs = await SharedPreferences.getInstance();
    _soundEnabled = prefs.getBool('sound_enabled') ?? true;
    _notifyListeners();
  }

  void toggleSound() {
    _soundEnabled = !_soundEnabled;
    if (!_soundEnabled) stop();
    _notifyListeners();
    SharedPreferences.getInstance()
        .then((p) => p.setBool('sound_enabled', _soundEnabled));
  }

  void setSoundEnabled(bool value) {
    _soundEnabled = value;
    if (!value) stop();
    _notifyListeners();
    SharedPreferences.getInstance()
        .then((p) => p.setBool('sound_enabled', _soundEnabled));
  }

  // Transient "please look here" pulse for the mute button, fired whenever
  // a tap-to-speak attempt is swallowed because sound is off — it doesn't
  // change soundEnabled, so it's broadcast through the same listener
  // mechanism rather than piggybacking on a real state change.
  void triggerMuteHint() {
    _hintPulseActive = true;
    _notifyListeners();
    Future.delayed(const Duration(milliseconds: 900), () {
      _hintPulseActive = false;
      _notifyListeners();
    });
  }

  Future<void> speak(String text, String language) async {
    if (!_soundEnabled) {
      triggerMuteHint();
      return;
    }
    await stop();
    final myRequestId = _requestId;
    try {
      final voiceName = _voices[language] ?? _voices['en']!;
      final langCode  = _langCodes[language] ?? 'de-DE';

      final ssml = "<speak version='1.0' xml:lang='$langCode'>"
          "<voice xml:lang='$langCode' name='$voiceName'>"
          "<prosody rate='0.80'>$text</prosody>"
          "</voice>"
          "</speak>";

      final response = await http.post(
        Uri.parse(
            'https://$_region.tts.speech.microsoft.com/cognitiveservices/v1'),
        headers: {
          'Ocp-Apim-Subscription-Key': _apiKey,
          'Content-Type': 'application/ssml+xml',
          'X-Microsoft-OutputFormat': 'audio-16khz-128kbitrate-mono-mp3',
          'User-Agent': 'KarYabApp',
        },
        body: ssml,
      );

      // A stop() (e.g. from a screen's dispose()) landed while we were
      // waiting on the network — the request that started this call is no
      // longer current, so don't start playback.
      if (myRequestId != _requestId) return;

      if (response.statusCode == 200) {
        final audioBytes = response.bodyBytes;
        if (myRequestId != _requestId) return;
        _setPlaying(true);
        await _player.play(BytesSource(audioBytes));
        print('TTS success: ${audioBytes.length} bytes');
      } else {
        print('TTS error ${response.statusCode}: ${response.body}');
        _setPlaying(false);
      }
    } catch (e) {
      print('TTS exception: $e');
      _setPlaying(false);
    }
  }

  Future<void> stop() async {
    _requestId++;
    _setPlaying(false);
    await _player.stop();
  }
}
