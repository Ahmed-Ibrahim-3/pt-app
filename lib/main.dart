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

  // Register all adapters you use
  Hive.registerAdapter(MealAdapter());                 // typeId: 1 (per your project)
  Hive.registerAdapter(ExercisePlanAdapter());         // typeId: 2
  Hive.registerAdapter(PlanAssignmentAdapter());       // typeId: 3
  Hive.registerAdapter(WorkoutSessionAdapter());       // typeId: 4
  Hive.registerAdapter(WorkoutEntryAdapter());         // typeId: 5
  Hive.registerAdapter(SetEntryAdapter());             // typeId: 6

  // Open boxes (names must match)
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

    unawaited(GoogleSignIn.instance.initialize()
        .then((_) => GoogleSignIn.instance.attemptLightweightAuthentication()));
    runApp(ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fitness & Nutrition Tracker',
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
          color: Colors.lightGreenAccent.shade400,
          linearTrackColor: Colors.grey.shade800,
          circularTrackColor: Colors.grey.shade800,
        ),
        useMaterial3: true,
      ),
      home: const AuthGate(),
      debugShowCheckedModeBanner: false,
    );
  }
}

