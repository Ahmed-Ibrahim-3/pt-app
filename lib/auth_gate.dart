// lib/auth_gate.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  bool _wired = false;

  @override
  Widget build(BuildContext context) {
    if (!_wired) {
      _wired = true;

      ref.listen(authStateProvider, (prev, curr) async {
        final prevUid = prev?.value?.uid;
        final curUid  = curr.value?.uid;

        try { ref.invalidate(settingsProvider); ref.invalidate(userSettingsProvider); } catch (_) {}
        try {
          ref.invalidate(initMealsProvider);
          ref.invalidate(readyMealDbProvider);
          ref.invalidate(mealControllerProvider);
          ref.invalidate(mealsForTodayProvider);
          ref.invalidate(initSavedMealsProvider);
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

        final sync = ref.read(firestoreSyncProvider);

        await sync.onAuthChange(previousUid: prevUid, currentUid: curUid);

        if (curUid != null) {
          try { await ref.read(initSavedMealsProvider.future); } catch (_) {}

          await sync.refreshFromCloud();
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