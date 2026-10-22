import 'package:shared_preferences/shared_preferences.dart';

import '../domain/voice_gateway.dart';

class StoredVoicePreferences implements VoicePreferences {
  final _preferences = SharedPreferencesAsync();
  static const _key = 'navi.handsFree.enabled.v1';

  @override
  Future<bool> readEnabled() async => await _preferences.getBool(_key) ?? false;

  @override
  Future<void> writeEnabled(bool enabled) => _preferences.setBool(_key, enabled);
}
