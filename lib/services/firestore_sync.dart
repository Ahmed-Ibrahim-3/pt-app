import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../providers/settings_provider.dart';
import '../providers/exercise_provider.dart';

import '../models/user_settings.dart';
import '../models/meal_model.dart';
import '../models/saved_meal.dart';
import '../models/workout_plan.dart';
import '../models/workout_plan_assignment.dart';
import '../models/workout_session.dart';

import '../services/saved_meals_service.dart';

String _enumName(Object e) => e.toString().split('.').last;
T _enumFromString<T>(List<T> values, String? name, T fallback) {
  if (name == null) return fallback;
  for (final v in values) {
    if (_enumName(v as Object) == name) return v;
  }
  return fallback;
}

class FirestoreSync {
  FirestoreSync(this.ref)
      : _db = FirebaseFirestore.instance,
        _auth = FirebaseAuth.instance;

  final Ref ref;
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  bool _inRefresh = false;

  StreamSubscription? _plansSub;
  StreamSubscription? _assignSub;
  StreamSubscription? _mealsSub;
  StreamSubscription? _sessionsSub;

  StreamSubscription<List<SavedMeal>>? _savedMealsLocalSub;
  StreamSubscription? _savedMealsRemoteSub;

  String? get _uid => _auth.currentUser?.uid;

  DocumentReference<Map<String, dynamic>> get _userDoc =>
      _db.collection('users').doc(_uid);
  CollectionReference<Map<String, dynamic>> get _plansCol =>
      _userDoc.collection('plans');
  CollectionReference<Map<String, dynamic>> get _assignCol =>
      _userDoc.collection('assignments');
  CollectionReference<Map<String, dynamic>> get _mealsCol =>
      _userDoc.collection('meals');
  CollectionReference<Map<String, dynamic>> get _savedMealsCol =>
      _userDoc.collection('savedMeals');
  CollectionReference<Map<String, dynamic>> get _sessionsCol =>
    _userDoc.collection('sessions');

  String get _plansBoxName => ExerciseHive.plansBoxFor(_uid);
  String get _assignBoxName => ExerciseHive.assignmentsBoxFor(_uid); 
  String get _sessionsBoxName => ExerciseHive.sessionsBoxFor(_uid); 
  String get _mealsBoxName => 'meals_box_${_uid ?? 'anon'}';
  final _savedMealsDb = SavedMealsDatabaseService();

  Future<Box<T>> _ensureOpen<T>(String name) async {
    if (Hive.isBoxOpen(name)) return Hive.box<T>(name);
    return Hive.openBox<T>(name);
  }

  Future<void> onAuthChange({String? previousUid, String? currentUid}) async {
    await _cancelMirrors();

    await _savedMealsDb.init();
  }

  Future<void> startMirrors() async {
    if (_uid == null) return;

    await _savedMealsDb.init();

    final plansBox = await _ensureOpen<ExercisePlan>(_plansBoxName);
    final assignBox = await _ensureOpen<PlanAssignment>(_assignBoxName);
    final mealsBox = await _ensureOpen<Meal>(_mealsBoxName);
    Box<WorkoutSession>? sessionsBox;
    try {
      sessionsBox = await _ensureOpen<WorkoutSession>(_sessionsBoxName);
    } catch (_) {
      sessionsBox = null;
    }

    await _cancelMirrors();

    _plansSub = plansBox.watch().listen((_) => pushPlansNow());
    _assignSub = assignBox.watch().listen((_) => pushAssignmentsNow());
    _mealsSub = mealsBox.watch().listen((_) => pushMealsNow());
    if (sessionsBox != null) {
      _sessionsSub = sessionsBox.watch().listen((_) => pushSessionsNow());
    }

    _savedMealsLocalSub = _savedMealsDb.watchAll().listen((list) async {
      if (_inRefresh) return;
      final batch = _db.batch();
      final remote = await _savedMealsCol.get();
      final remoteIds = remote.docs.map((d) => d.id).toSet();
      final localIds = list.map((e) => e.id).toSet();

      for (final s in list) {
        batch.set(_savedMealsCol.doc(s.id), s.toMap(), SetOptions(merge: true));
      }
      for (final rid in remoteIds.difference(localIds)) {
        batch.delete(_savedMealsCol.doc(rid));
      }
      await batch.commit();
    });

    _savedMealsRemoteSub = _savedMealsCol.snapshots().listen((snap) async {
      if (_inRefresh) return;
      for (final doc in snap.docs) {
        final data = doc.data();
        final s = SavedMeal.fromMap({...data, 'id': doc.id});
        await _savedMealsDb.upsert(s);
      }
    });

    await pushAllNow();
  }

  Future<void> _cancelMirrors() async {
    await _plansSub?.cancel();
    await _assignSub?.cancel();
    await _mealsSub?.cancel();
    await _sessionsSub?.cancel();
    await _savedMealsLocalSub?.cancel();
    await _savedMealsRemoteSub?.cancel();

    _plansSub = null;
    _assignSub = null;
    _mealsSub = null;
    _sessionsSub = null;
    _savedMealsLocalSub = null;
    _savedMealsRemoteSub = null;
  }

  Future<void> pushSettingsNow() async {
    if (_uid == null || _inRefresh) return;
    final s = ref.read(settingsProvider).value ?? UserSettings.initial();
    await _userDoc.set({
      'settings': {
        'name': s.name,
        'gender': _enumName(s.gender),
        'ageYears': s.ageYears,
        'heightCm': s.heightCm,
        'weightKg': s.weightKg,
        'goal': _enumName(s.goal),
        'units': _enumName(s.units),
        'activity': _enumName(s.activity),
        'defaultGym': s.defaultGym,
      },
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> pushPlansNow() async {
    if (_uid == null || _inRefresh) return;
    final box = await _ensureOpen<ExercisePlan>(_plansBoxName);

    final remote = await _plansCol.get();
    final remoteIds = remote.docs.map((d) => d.id).toSet();
    final localIds = <String>{};

    final batch = _db.batch();
    for (final key in box.keys) {
      final id = key.toString();
      localIds.add(id);
      final p = box.get(key)!;
      batch.set(_plansCol.doc(id), {
        'planKey': key,
        'name': p.name,
        'exerciseIds': p.exerciseIds,
        'createdAt': Timestamp.fromDate(p.createdAt),
        'updatedAt': p.updatedAt == null ? null : Timestamp.fromDate(p.updatedAt!),
      }, SetOptions(merge: true));
    }
    for (final rid in remoteIds.difference(localIds)) {
      batch.delete(_plansCol.doc(rid));
    }
    await batch.commit();
  }

  Future<void> pushAssignmentsNow() async {
    if (_uid == null || _inRefresh) return;
    final box = await _ensureOpen<PlanAssignment>(_assignBoxName);

    final remote = await _assignCol.get();
    final remoteIds = remote.docs.map((d) => d.id).toSet();
    final localIds = <String>{};

    final batch = _db.batch();
    for (final key in box.keys) {
      final id = key.toString();
      localIds.add(id);
      final a = box.get(key)!;
      batch.set(_assignCol.doc(id), {
        'date': Timestamp.fromDate(a.date),
        'planKey': a.planKey,
        'completed': a.completed,
        'location': a.location,
      }, SetOptions(merge: true));
    }
    for (final rid in remoteIds.difference(localIds)) {
      batch.delete(_assignCol.doc(rid));
    }
    await batch.commit();
  }

  Future<void> pushMealsNow() async {
    if (_uid == null || _inRefresh) return;
    final box = await _ensureOpen<Meal>(_mealsBoxName);

    final remote = await _mealsCol.get();
    final remoteIds = remote.docs.map((d) => d.id).toSet();
    final localIds = <String>{};

    final batch = _db.batch();
    for (final key in box.keys) {
      final id = key.toString();
      localIds.add(id);
      final m = box.get(key)!;
      batch.set(_mealsCol.doc(id), {
        'id': m.id,
        'name': m.name,
        'calories': m.calories,
        'protein': m.protein,
        'carbs': m.carbs,
        'fat': m.fat,
        'loggedAt': Timestamp.fromDate(m.loggedAt),
        'notes': m.notes,
      }, SetOptions(merge: true));
    }
    for (final rid in remoteIds.difference(localIds)) {
      batch.delete(_mealsCol.doc(rid));
    }
    await batch.commit();
  }

  Future<void> pushSessionsNow() async {
    if (_uid == null || _inRefresh) return;
    final box = await _ensureOpen<WorkoutSession>(_sessionsBoxName);

    final remote = await _sessionsCol.get();
    final remoteIds = remote.docs.map((d) => d.id).toSet();
    final localIds = <String>{};

    final batch = _db.batch();

    for (final key in box.keys) {
      final id = key.toString();
      final s = box.get(key);
      if (s == null) continue;
      localIds.add(id);

      final entries = [
        for (final e in s.entries)
          {
            'exerciseId': e.exerciseStableId,
            'sets': [
              for (final set in e.sets)
                {
                  'reps': set.reps,
                  'weight': set.weight,
                  'done': set.done,
                }
            ],
          }
      ];

      batch.set(_sessionsCol.doc(id), {
        'date': Timestamp.fromDate(s.date),
        'planKey': s.planKey,
        'entries': entries,
        'startedAt': Timestamp.fromDate(s.startedAt),
        'finishedAt': s.finishedAt != null ? Timestamp.fromDate(s.finishedAt!) : null,
        'completed': s.completed,
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    for (final rid in remoteIds.difference(localIds)) {
      batch.delete(_sessionsCol.doc(rid));
    }

    await batch.commit();
  }


  Future<void> pushAllNow() async {
    if (_uid == null) return;

    await pushSettingsNow();

    for (final s in _savedMealsDb.getAll()) {
      await _savedMealsCol.doc(s.id).set(s.toMap(), SetOptions(merge: true));
    }

    await Future.wait([
      pushPlansNow(),
      pushAssignmentsNow(),
      pushMealsNow(),
      pushSessionsNow()
    ]);
  }

  Future<void> refreshFromCloud() async {
    if (_uid == null) return;

    _inRefresh = true;
    try {
      final snap = await _userDoc.get();
      if (snap.exists) {
        final s = (snap.data()?['settings'] as Map<String, dynamic>?) ?? {};
        final settings = UserSettings(
          name: s['name'] as String? ?? '',
          gender: _enumFromString(Gender.values, s['gender'] as String?, Gender.male),
          ageYears: (s['ageYears'] as num?)?.toInt() ?? 30,
          heightCm: (s['heightCm'] as num?)?.toDouble() ?? 175.0,
          weightKg: (s['weightKg'] as num?)?.toDouble() ?? 75.0,
          goal: _enumFromString(Goal.values, s['goal'] as String?, Goal.maintain),
          units: _enumFromString(Units.values, s['units'] as String?, Units.metric),
          activity: _enumFromString(ActivityLevel.values, s['activity'] as String?, ActivityLevel.moderate),
          experience: _enumFromString(ExperienceLevel.values, s['experience'] as String?,ExperienceLevel.beginner),
          defaultGym: s['defaultGym'] as String? ?? '',
        );
        await ref.read(settingsProvider.notifier).save(settings);
      } else {
        await pushSettingsNow();
      }

      final plansBox = await _ensureOpen<ExercisePlan>(_plansBoxName);
      final assignBox = await _ensureOpen<PlanAssignment>(_assignBoxName);
      final mealsBox = await _ensureOpen<Meal>(_mealsBoxName);

      await plansBox.clear();
      final plans = await _plansCol.get();
      for (final d in plans.docs) {
        final data = d.data();
        final plan = ExercisePlan(
          name: data['name'] as String? ?? '',
          exerciseIds: (data['exerciseIds'] as List?)?.cast<String>() ?? <String>[],
          createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
          updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
        );
        final keyStr = d.id;
        final key = int.tryParse(keyStr);
        if (key != null) {
          await plansBox.put(key, plan);
        } else {
          await plansBox.put(keyStr, plan);
        }
      }

      await assignBox.clear();
      final assigns = await _assignCol.get();
      for (final d in assigns.docs) {
        final data = d.data();
        final a = PlanAssignment(
          date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
          planKey: (data['planKey'] as num?)?.toInt() ?? 0,
          completed: data['completed'] as bool? ?? false,
          location: data['location'] as String?,
        );
        await assignBox.put(d.id, a);
      }

      await mealsBox.clear();
      final meals = await _mealsCol.get();
      for (final d in meals.docs) {
        final data = d.data();
        final m = Meal(
          id: data['id'] as String,
          name: data['name'] as String? ?? '',
          calories: (data['calories'] as num?)?.toDouble() ?? 0,
          protein: (data['protein'] as num?)?.toDouble() ?? 0,
          carbs: (data['carbs'] as num?)?.toDouble() ?? 0,
          fat: (data['fat'] as num?)?.toDouble() ?? 0,
          loggedAt: (data['loggedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
          notes: data['notes'] as String?,
        );
        await mealsBox.put(m.id, m);
      }

      await _savedMealsDb.init();
      final savedSnap = await _savedMealsCol.get();
      for (final d in savedSnap.docs) {
        final s = SavedMeal.fromMap({...d.data(), 'id': d.id});
        await _savedMealsDb.upsert(s);
      }
    } finally {
      _inRefresh = false;
      await startMirrors();
    }

    final sessionsBox = await _ensureOpen<WorkoutSession>(_sessionsBoxName);
    await sessionsBox.clear();
    final sessions = await _sessionsCol.get();
    for (final d in sessions.docs) {
      final data = d.data();

      final entries = <WorkoutEntry>[];
      final rawEntries = (data['entries'] as List?) ?? const [];
      for (final e in rawEntries) {
        final sets = <SetEntry>[];
        final rawSets = (e['sets'] as List?) ?? const [];
        for (final s in rawSets) {
          sets.add(SetEntry(
            reps: (s['reps'] as num?)?.toInt() ?? 0,
            weight: (s['weight'] as num?)?.toDouble() ?? 0.0,
            done: (s['done'] as bool?) ?? false,
          ));
        }
        entries.add(WorkoutEntry(
          exerciseStableId: (e['exerciseId'] as String?) ?? '',
          sets: sets,
        ));
      }

      final session = WorkoutSession(
        date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
        planKey: (data['planKey'] as num?)?.toInt() ?? 0,
        entries: entries,
        startedAt: (data['startedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        finishedAt: (data['finishedAt'] as Timestamp?)?.toDate(),
        completed: (data['completed'] as bool?) ?? false,
      );

      await sessionsBox.put(d.id, session);
    }
  }
}

final firestoreSyncProvider = Provider<FirestoreSync>((ref) => FirestoreSync(ref));
