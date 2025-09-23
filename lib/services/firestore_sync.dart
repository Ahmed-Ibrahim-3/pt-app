// lib/services/firestore_sync.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_settings.dart';
import '../models/meal_model.dart';
import '../models/workout_plan.dart';
import '../models/workout_plan_assignment.dart';
import '../models/workout_session.dart';
import '../services/database_service.dart';
import '../providers/exercise_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/nutrition_provider.dart';
import '../providers/settings_provider.dart';

final firestoreProvider = Provider<FirebaseFirestore>((_) => FirebaseFirestore.instance);

final firestoreSyncProvider = Provider<FirestoreSync>((ref) {
  return FirestoreSync(
    ref: ref,
    firestore: ref.watch(firestoreProvider),
    auth: ref.watch(firebaseAuthProvider),
    mealDb: ref.read(mealDbProvider),
  );
});

class FirestoreSync {
  FirestoreSync({
    required this.ref,
    required this.firestore,
    required this.auth,
    required this.mealDb,
  });

  final Ref ref;
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final MealDatabaseService mealDb;

  String? _uid;
  bool _importing = false;
  bool _uploadsEnabled = false;

  StreamSubscription? _mealsWatch;
  StreamSubscription? _plansWatch;
  StreamSubscription? _assignWatch;
  StreamSubscription? _sessionsWatch;

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      firestore.collection('users').doc(uid);
  CollectionReference<Map<String, dynamic>> _meals(String uid) => _userDoc(uid).collection('meals');
  CollectionReference<Map<String, dynamic>> _plans(String uid) => _userDoc(uid).collection('plans');
  CollectionReference<Map<String, dynamic>> _assign(String uid) => _userDoc(uid).collection('assignments');
  CollectionReference<Map<String, dynamic>> _sessions(String uid) => _userDoc(uid).collection('sessions');

  Future<void> refreshFromCloud() async {
    final u = auth.currentUser;
    if (u == null) return;

    _uploadsEnabled = false;
    await _stopWatchers();

    _importing = true;
    try {
      await _importCloudToLocal(u.uid);
      _uid = u.uid; 
    } finally {
      _importing = false;
    }

    _uploadsEnabled = true;
    await _startWatchers();

    ref.invalidate(settingsProvider);
    ref.invalidate(initMealsProvider);
  }

  Future<void> onLaunch() async {
    final u = auth.currentUser;
    if (u == null) return;
    await _switchToUid(u.uid);
  }

  Future<void> onAuthChange({String? previousUid, String? currentUid}) async {
    await _switchToUid(currentUid);
  }

  Future<void> pushSettingsNow() async {
    if (!_uploadsEnabled || _importing) return;
    final u = auth.currentUser;
    if (u == null || _uid != u.uid) return;

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('user_settings_v1');
    final settings = raw == null ? UserSettings.initial() : UserSettings.fromJsonString(raw);

    await _userDoc(_uid!).set({
      'settings': settings.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _switchToUid(String? uid) async {
    _uploadsEnabled = false;
    await _stopWatchers();

    _uid = uid;

    if (_uid == null) return;

    _importing = true;
    try {
      await _importCloudToLocal(_uid!);
    } finally {
      _importing = false;
    }

    _uploadsEnabled = true;
    await _startWatchers();

    ref.invalidate(settingsProvider);
    ref.invalidate(initMealsProvider);
  }

  Future<void> _importCloudToLocal(String uid) async {
    final ud = await _userDoc(uid).get();
    final m = ud.data();
    final settings = UserSettings.fromMap(m?['settings'] as Map<String, dynamic>?);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_settings_v1', settings.toJsonString());

    await mealDb.init();
    final mealsSnap = await _meals(uid).get();
    final meals = mealsSnap.docs.map((d) => d.data()).toList();
    await mealDb.replaceAll(meals);

    final plansBox = Hive.box<ExercisePlan>(ExerciseHive.plansBox);
    final assignBox = Hive.box<PlanAssignment>(ExerciseHive.assignmentsBox);
    final sessionsBox = Hive.box<WorkoutSession>(ExerciseHive.sessionsBox);

    await plansBox.clear();
    await assignBox.clear();
    await sessionsBox.clear();

    final plans = await _plans(uid).get();
    for (final d in plans.docs) {
      final key = int.tryParse(d.id) ?? (d.data()['key'] as int? ?? d.hashCode);
      await plansBox.put(key, ExercisePlan.fromMap(d.data()));
    }

    final assigns = await _assign(uid).get();
    for (final d in assigns.docs) {
      final key = int.tryParse(d.id) ?? (d.data()['key'] as int? ?? d.hashCode);
      await assignBox.put(key, PlanAssignment.fromMap(d.data()));
    }

    final sessions = await _sessions(uid).get();
    for (final d in sessions.docs) {
      final key = int.tryParse(d.id) ?? (d.data()['key'] as int? ?? d.hashCode);
      await sessionsBox.put(key, WorkoutSession.fromMap(d.data()));
    }
  }

  Future<void> _startWatchers() async {
    if (_uid == null) return;

    _mealsWatch = Hive.box<Meal>('meals_box').watch().listen((e) async {
      if (!_uploadsEnabled || _importing || _uid == null) return;
      final boxUid = _uid!;
      final id = e.key as String;
      if (e.deleted) {
        await _meals(boxUid).doc(id).delete();
      } else {
        final meal = e.value as Meal;
        await _meals(boxUid).doc(id).set({
          ...meal.toMap(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    });

    _plansWatch = Hive.box<ExercisePlan>(ExerciseHive.plansBox).watch().listen((e) async {
      if (!_uploadsEnabled || _importing || _uid == null) return;
      final boxUid = _uid!;
      final key = e.key.toString();
      if (e.deleted) {
        await _plans(boxUid).doc(key).delete();
      } else {
        final plan = e.value as ExercisePlan;
        await _plans(boxUid).doc(key).set({
          'key': e.key,
          ...plan.toMap(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    });

    _assignWatch = Hive.box<PlanAssignment>(ExerciseHive.assignmentsBox).watch().listen((e) async {
      if (!_uploadsEnabled || _importing || _uid == null) return;
      final boxUid = _uid!;
      final key = e.key.toString();
      if (e.deleted) {
        await _assign(boxUid).doc(key).delete();
      } else {
        final assign = e.value as PlanAssignment;
        await _assign(boxUid).doc(key).set({
          'key': e.key,
          ...assign.toMap(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    });

    _sessionsWatch = Hive.box<WorkoutSession>(ExerciseHive.sessionsBox).watch().listen((e) async {
      if (!_uploadsEnabled || _importing || _uid == null) return;
      final boxUid = _uid!;
      final key = e.key.toString();
      if (e.deleted) {
        await _sessions(boxUid).doc(key).delete();
      } else {
        final session = e.value as WorkoutSession;
        await _sessions(boxUid).doc(key).set({
          'key': e.key,
          ...session.toMap(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    });
  }

  Future<void> _stopWatchers() async {
    await _mealsWatch?.cancel(); _mealsWatch = null;
    await _plansWatch?.cancel(); _plansWatch = null;
    await _assignWatch?.cancel(); _assignWatch = null;
    await _sessionsWatch?.cancel(); _sessionsWatch = null;
  }
}
