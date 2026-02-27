import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:pt/firebase_options.dart';

import 'auth_gate.dart';
import 'models/meal_model.dart';
import 'models/workout_plan.dart';
import 'models/workout_plan_assignment.dart';
import 'models/workout_session.dart';
import 'providers/exercise_provider.dart';

Future<void> _initHive() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();

  Hive.registerAdapter(MealAdapter());
  Hive.registerAdapter(ExercisePlanAdapter());
  Hive.registerAdapter(PlanAssignmentAdapter());
  Hive.registerAdapter(WorkoutSessionAdapter());
  Hive.registerAdapter(WorkoutEntryAdapter());
  Hive.registerAdapter(SetEntryAdapter());

  await Hive.openBox<Meal>('meals_box');
  await Hive.openBox<ExercisePlan>(ExerciseHive.plansBox);
  await Hive.openBox<PlanAssignment>(ExerciseHive.assignmentsBox);
  await Hive.openBox<WorkoutSession>(ExerciseHive.sessionsBox);
}

void main() async {
  await _initHive();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  unawaited(GoogleSignIn.instance.initialize().then(
      (_) => GoogleSignIn.instance.attemptLightweightAuthentication()));

  runApp(const ProviderScope(child: MyApp()));
}

class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  ScrollViewKeyboardDismissBehavior getKeyboardDismissBehavior(
    BuildContext context,
  ) {
    return ScrollViewKeyboardDismissBehavior.onDrag;
  }
}

class KeyboardDismissOnPointerDown extends StatelessWidget {
  final Widget child;
  const KeyboardDismissOnPointerDown({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
        if (keyboardOpen) {
          FocusManager.instance.primaryFocus?.unfocus();
        }
      },
      child: child,
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fitness & Nutrition Tracker',
      debugShowCheckedModeBanner: false,

      scrollBehavior: const AppScrollBehavior(),

      builder: (context, child) {
        return KeyboardDismissOnPointerDown(
          child: child ?? const SizedBox.shrink(),
        );
      },

      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: Colors.blueGrey,
        scaffoldBackgroundColor: const Color(0xFF121212),
        cardColor: const Color(0xFF1E1E1E),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Colors.white),
          bodyMedium: TextStyle(color: Colors.white70),
          titleLarge: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          titleMedium: TextStyle(color: Colors.white),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Color(0xFF1E1E1E),
          selectedItemColor: Colors.white,
          unselectedItemColor: Colors.grey,
          type: BottomNavigationBarType.fixed,
        ),
        progressIndicatorTheme: ProgressIndicatorThemeData(
          color: Colors.lightGreenAccent,
          linearTrackColor: Colors.grey,
          circularTrackColor: Colors.grey,
        ),
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}