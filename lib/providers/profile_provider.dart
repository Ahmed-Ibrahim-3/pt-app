import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_settings.dart';
import 'settings_provider.dart';

final userSettingsProvider = Provider<UserSettings>((ref) {
  return ref.watch(settingsProvider).value ?? UserSettings.initial();
});
