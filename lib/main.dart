import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pt/providers/exercise_provider.dart';
import 'home_page.dart'; 
import 'package:hive_flutter/hive_flutter.dart';
import 'models/meal_model.dart';
import 'models/workout_plan.dart';
import 'models/workout_plan_assignment.dart';
import 'models/workout_session.dart';

Future<void> _initHive() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  if (!Hive.isAdapterRegistered(1)){
    Hive.registerAdapter(MealAdapter());
  }
  Hive.registerAdapter(ExercisePlanAdapter());
  Hive.registerAdapter(PlanAssignmentAdapter());
  await Hive.openBox<ExercisePlan>(ExerciseHive.plansBox);
  await Hive.openBox<PlanAssignment>(ExerciseHive.assignmentsBox);
  Hive.registerAdapter(WorkoutSessionAdapter());
  Hive.registerAdapter(WorkoutEntryAdapter());
  Hive.registerAdapter(SetEntryAdapter());
  await Hive.openBox<WorkoutSession>(ExerciseHive.sessionsBox);
}

void main() async {
  await _initHive();
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
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}