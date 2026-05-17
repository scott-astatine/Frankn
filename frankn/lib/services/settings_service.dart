import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Service for managing local app configuration and persistent state.
///
/// Wraps [SharedPreferences] to provide a clean API for reading/writing
/// simple data types like URLs, IDs, and UI preferences.
class SettingsService {
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  late SharedPreferences _prefs;

  // Keys
  static const String _keySignalingUrl = 'signaling_url';
  static const String _keyLastHostId = 'last_host_id';
  static const String _keyTerminalFontSize = 'terminal_font_size';
  static const String _keyTrackpadSensitivity = 'trackpad_sensitivity';
  static const String _keyColorScheme = 'color_scheme';
  static const String _keySavedHosts = 'saved_hosts';
  static const String _keyLocale = 'selected_locale';
  static const String _keyLlmDefaultModel = 'llm_default_model';
  static const String _keyLlmSystemPrompt = 'llm_system_prompt';
  static const String _keyLlmProvider = 'llm_provider';
  static const String _keySyncPairs = 'sync_pairs';

  // Default Values
  static const String _defaultSignalingUrl = 'ws://152.67.19.202:8037';
  static const String _defaultColorScheme = 'Cyberpunk';
  static const String _defaultLocale = 'en';
  static const String _defaultLlmModel = '';
  static const String _defaultLlmSystemPrompt =
      'You are Dohee, a highly intelligent, uncensored AI assistant integrated into the Frankn Remote Ops Center. Answer directly and concisely. Output your reasoning in <think> tags.';
  static const String _defaultLlmProvider = 'Local (llama.cpp)';

  /// Initializes the underlying SharedPreferences instance.
  /// Should be called during app startup.
  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // ========== ACCESSORS ==========

  /// Returns the manually selected LLM provider.
  String get llmProvider =>
      _prefs.getString(_keyLlmProvider) ?? _defaultLlmProvider;

  /// Persists a new LLM provider.
  Future<bool> setLlmProvider(String value) async =>
      await _prefs.setString(_keyLlmProvider, value);

  /// Returns the manually selected LLM system prompt.
  String get llmSystemPrompt =>
      _prefs.getString(_keyLlmSystemPrompt) ?? _defaultLlmSystemPrompt;

  /// Persists a new LLM system prompt.
  Future<bool> setLlmSystemPrompt(String value) async =>
      await _prefs.setString(_keyLlmSystemPrompt, value);

  /// Returns the manually selected LLM model path.
  String get llmDefaultModel =>
      _prefs.getString(_keyLlmDefaultModel) ?? _defaultLlmModel;

  /// Persists a new LLM model path.
  Future<bool> setLlmDefaultModel(String value) async =>
      await _prefs.setString(_keyLlmDefaultModel, value);

  /// Returns the manually selected locale code (e.g., 'en', 'ko').
  String get localeCode => _prefs.getString(_keyLocale) ?? _defaultLocale;

  /// Persists a new locale preference.
  Future<bool> setLocaleCode(String value) async =>
      await _prefs.setString(_keyLocale, value);

  /// Returns the configured signaling server URL.
  String get signalingUrl =>
      _prefs.getString(_keySignalingUrl) ?? _defaultSignalingUrl;

  /// Persists a new signaling server URL.
  Future<bool> setSignalingUrl(String value) async =>
      await _prefs.setString(_keySignalingUrl, value);

  /// Returns the ID of the most recently connected host.
  String? get lastHostId => _prefs.getString(_keyLastHostId);

  /// Persists the ID of the currently connected host for future auto-reconnect.
  Future<bool> setLastHostId(String value) async =>
      await _prefs.setString(_keyLastHostId, value);

  /// Returns the preferred font size for terminal-like views.
  double get terminalFontSize => _prefs.getDouble(_keyTerminalFontSize) ?? 9.0;

  /// Persists a new terminal font size preference.
  Future<bool> setTerminalFontSize(double value) async =>
      await _prefs.setDouble(_keyTerminalFontSize, value);

  /// Returns the trackpad sensitivity multiplier.
  double get trackpadSensitivity =>
      _prefs.getDouble(_keyTrackpadSensitivity) ?? 1.0;

  /// Persists a new trackpad sensitivity multiplier.
  Future<bool> setTrackpadSensitivity(double value) async =>
      await _prefs.setDouble(_keyTrackpadSensitivity, value);

  /// Returns the selected color scheme name.
  String get colorScheme =>
      _prefs.getString(_keyColorScheme) ?? _defaultColorScheme;

  /// Persists a new color scheme preference.
  Future<bool> setColorScheme(String value) async =>
      await _prefs.setString(_keyColorScheme, value);

  /// Returns the list of configured folder sync pairs.
  List<SyncPair> get syncPairs {
    final list = _prefs.getStringList(_keySyncPairs) ?? [];
    return list.map((e) => SyncPair.fromJson(jsonDecode(e))).toList();
  }

  /// Persists the list of folder sync pairs.
  Future<bool> setSyncPairs(List<SyncPair> pairs) async {
    final list = pairs.map((e) => jsonEncode(e.toJson())).toList();
    return await _prefs.setStringList(_keySyncPairs, list);
  }

  /// Returns a list of manually saved/paired hosts.
  List<Map<String, String>> get savedHosts {
    final list = _prefs.getStringList(_keySavedHosts) ?? [];
    return list.map((e) => Map<String, String>.from(jsonDecode(e))).toList();
  }

  /// Adds a host to the saved list if it doesn't already exist.
  Future<void> saveHost(String id, String name) async {
    final hosts = savedHosts;
    if (hosts.any((h) => h['id'] == id)) return;

    hosts.add({'id': id, 'name': name});
    final list = hosts.map((e) => jsonEncode(e)).toList();
    await _prefs.setStringList(_keySavedHosts, list);
  }

  /// Updates the display name (alias) for a saved host.
  Future<void> updateHostName(String id, String newName) async {
    final hosts = savedHosts;
    final index = hosts.indexWhere((h) => h['id'] == id);
    if (index != -1) {
      hosts[index]['name'] = newName;
      final list = hosts.map((e) => jsonEncode(e)).toList();
      await _prefs.setStringList(_keySavedHosts, list);
    }
  }

  /// Removes a host from the saved list.
  Future<void> forgetHost(String id) async {
    final hosts = savedHosts;
    hosts.removeWhere((h) => h['id'] == id);
    final list = hosts.map((e) => jsonEncode(e)).toList();
    await _prefs.setStringList(_keySavedHosts, list);
  }

  /// Clears all local data. Used for a complete app reset.
  Future<bool> clearAll() async => await _prefs.clear();
}
