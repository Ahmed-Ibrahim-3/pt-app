import 'package:hive/hive.dart';
import '../models/saved_meal.dart';

class SavedMealsDatabaseService {
  static const _boxName = 'saved_meals_box';
  Box<SavedMeal>? _box;

  Future<void> init() async {
    _box ??= await Hive.openBox<SavedMeal>(_boxName);
  }

  Box<SavedMeal> get _requireBox {
    final b = _box;
    if (b == null) {
      throw StateError('SavedMealsDatabaseService not initialized. Call init() first.');
    }
    return b;
  }

  Future<SavedMeal?> getById(String id) async => _requireBox.get(id);

  Future<void> upsert(SavedMeal m) async => _requireBox.put(m.id, m);

  Future<void> delete(String id) async => _requireBox.delete(id);

  List<SavedMeal> getAll() => _requireBox.values.toList(growable: false);

  Stream<List<SavedMeal>> watchAll() async* {
    final box = _requireBox;
    yield getAll();
    yield* box.watch().map((_) => getAll());
  }
}
