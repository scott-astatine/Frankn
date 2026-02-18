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
  static const String _keyColorScheme = 'color_scheme';
  static const String _keySavedHosts = 'saved_hosts';

  // Default Values
  static const String _defaultSignalingUrl = 'ws://152.67.19.202:8037';
  static const String _defaultColorScheme = 'Cyberpunk';

  /// Initializes the underlying SharedPreferences instance.
  /// Should be called during app startup.
  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // ========== ACCESSORS ==========

  /// Returns the configured signaling server URL.
  String get signalingUrl => _prefs.getString(_keySignalingUrl) ?? _defaultSignalingUrl;
  
  /// Persists a new signaling server URL.
  Future<bool> setSignalingUrl(String value) async => await _prefs.setString(_keySignalingUrl, value);

  /// Returns the ID of the most recently connected host.
  String? get lastHostId => _prefs.getString(_keyLastHostId);
  
  /// Persists the ID of the currently connected host for future auto-reconnect.
  Future<bool> setLastHostId(String value) async => await _prefs.setString(_keyLastHostId, value);

  /// Returns the preferred font size for terminal-like views.
  double get terminalFontSize => _prefs.getDouble(_keyTerminalFontSize) ?? 13.0;
  
  /// Persists a new terminal font size preference.
  Future<bool> setTerminalFontSize(double value) async => await _prefs.setDouble(_keyTerminalFontSize, value);

  /// Returns the selected color scheme name.
  String get colorScheme => _prefs.getString(_keyColorScheme) ?? _defaultColorScheme;

  /// Persists a new color scheme preference.
  Future<bool> setColorScheme(String value) async => await _prefs.setString(_keyColorScheme, value);

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
