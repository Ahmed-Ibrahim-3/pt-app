import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final sleepLogProvider = AsyncNotifierProvider<SleepLogNotifier, Map<String, double>>(SleepLogNotifier.new);

class SleepLogNotifier extends AsyncNotifier<Map<String, double>> {
  static const _key = 'sleep_log_v1'; 
  @override
  Future<Map<String, double>> build() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_key);
    if (raw == null) return {};
    try {
      final Map<String, dynamic> m = jsonDecode(raw);
      return m.map((k, v) => MapEntry(k, (v as num).toDouble()));
    } catch (_) {
      return {};
    }
  }

  Future<void> setHours(DateTime day, double hours) async {
    final d = DateTime(day.year, day.month, day.day);
    final ymd = '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final next = {...(state.value ?? {}), ymd: hours};
    state = AsyncData(next);
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_key, jsonEncode(next));
  }
}

final sleepHoursForDateProvider = Provider.family<double?, DateTime>((ref, date) {
  final m = ref.watch(sleepLogProvider).value ?? const <String, double>{};
  final d = DateTime(date.year, date.month, date.day);
  final ymd = '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  return m[ymd];
});
