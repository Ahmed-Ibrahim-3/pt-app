// lib/auth_gate.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import 'providers/auth_provider.dart';

import 'providers/settings_provider.dart';
import 'providers/profile_provider.dart';
import 'providers/nutrition_provider.dart';
import 'providers/exercise_provider.dart';
import 'providers/workout_provider.dart';

import 'services/firestore_sync.dart';

import 'home_page.dart';
import 'screens/sign_in_screen.dart';
class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});
  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  String? _lastUid;
  bool _wired = false;

  Future<void> _onAuthChanged(String? previousUid, String? currentUid) async {
    try { ref.invalidate(settingsProvider); ref.invalidate(userSettingsProvider); } catch (_) {}
    try {
      ref.invalidate(initMealsProvider);
      ref.invalidate(readyMealDbProvider);
      ref.invalidate(mealControllerProvider);
      ref.invalidate(mealsForTodayProvider);
    } catch (_) {}
    try {
      ref.invalidate(planRepoProvider);
      ref.invalidate(plansStreamProvider);
      ref.invalidate(assignmentRepoProvider);
      ref.invalidate(weekAssignmentsProvider);
      ref.invalidate(workoutSessionRepoProvider);
      ref.invalidate(workoutSessionForDayProvider);
    } catch (_) {}
    try { ref.invalidate(firestoreSyncProvider); } catch (_) {}

    ref.listen(authStateProvider, (prev, curr) {
      final prevUid = prev?.value?.uid;
      final curUid  = curr.value?.uid;
      if (prevUid != curUid) {
        ref.invalidate(settingsProvider);
        ref.invalidate(userSettingsProvider);

        unawaited(ref.read(firestoreSyncProvider).onAuthChange(
          previousUid: prevUid,
          currentUid: curUid,
        ));
        if (curUid != null) {
          unawaited(ref.read(firestoreSyncProvider).refreshFromCloud());
        }
      }
    });

    try {
      await ref.read(firestoreSyncProvider).onAuthChange(
        previousUid: previousUid,
        currentUid: currentUid,
      );
      if (currentUid != null) {
        await ref.read(firestoreSyncProvider).refreshFromCloud();
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
  if (!_wired) {
    _wired = true;
    ref.listen(authStateProvider, (prev, curr) {
      final prevUid = prev?.value?.uid;
      final curUid  = curr.value?.uid;
      if (prevUid != curUid) {
        final sync = ref.read(firestoreSyncProvider);

        sync.onAuthChange(previousUid: prevUid, currentUid: curUid);

        ref.invalidate(settingsProvider);

        unawaited(() async {
          await sync.refreshFromCloud();
          await sync.startMirrors(); 
        }());
  }
});

  }

    final authAsync = ref.watch(authStateProvider);
    return authAsync.when(
      data: (user) => user == null ? const SignInPage() : const HomePage(),
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Auth error: $e'))),
    );
  }
}