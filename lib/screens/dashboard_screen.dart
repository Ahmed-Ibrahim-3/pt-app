import 'package:flutter/material.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _calorieGoal = 2400;

  late TextEditingController _calorieController;

  @override
  void initState() {
    super.initState();
    _calorieController = TextEditingController(text: _calorieGoal.toString());
  }

  @override
  void dispose() {
    _calorieController.dispose();
    super.dispose();
  }

  Future<void> _showEditCalorieGoalDialog() async {
    _calorieController.text = _calorieGoal.toString();
    return showDialog<void>(
      context: context,
      barrierDismissible: true, 
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Edit Calorie Goal'),
          content: TextField(
            controller: _calorieController,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Daily Calories (kcal)'),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text('Save'),
              onPressed: () {
                final int? newGoal = int.tryParse(_calorieController.text);
                if (newGoal != null && newGoal > 0) {
                  setState(() {
                    _calorieGoal = newGoal;
                  });
                }
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    
    final int proteinGoal = (_calorieGoal * 0.30 / 4).round();
    final int carbsGoal = (_calorieGoal * 0.40 / 4).round();
    final int fatGoal = (_calorieGoal * 0.30 / 9).round();

    final int proteinGrams = (proteinGoal / 2).round();
    final int carbsGrams = (carbsGoal / 2).round();
    final int fatGrams = (fatGoal / 2).round();

    final int caloriesConsumed = (proteinGrams * 4) + (carbsGrams * 4) + (fatGrams * 9);

    final double calorieProgress = _calorieGoal > 0 ? (caloriesConsumed / _calorieGoal) : 0;
    final double proteinProgress = proteinGoal > 0 ? (proteinGrams / proteinGoal) : 0;
    final double carbsProgress = carbsGoal > 0 ? (carbsGrams / carbsGoal) : 0;
    final double fatProgress = fatGoal > 0 ? (fatGrams / fatGoal) : 0;

    return Scaffold(
      appBar: AppBar(
        title: Text('Welcome Back, User!', style: Theme.of(context).textTheme.titleLarge),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _buildCalorieCard(context, caloriesConsumed, _calorieGoal, calorieProgress, onEditPressed: _showEditCalorieGoalDialog),
          const SizedBox(height: 24),
          Text('Macronutrients', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          _buildMacroRow(context, proteinProgress, proteinGrams, proteinGoal, 'Protein', Colors.red),
          const SizedBox(height: 12),
          _buildMacroRow(context, carbsProgress, carbsGrams, carbsGoal, 'Carbs', Colors.blue),
          const SizedBox(height: 12),
          _buildMacroRow(context, fatProgress, fatGrams, fatGoal, 'Fat', Colors.amber),
        ]),
      ),
    );
  }

  Widget _buildCalorieCard(BuildContext context, int consumed, int goal, double progress, {required VoidCallback onEditPressed}) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          SizedBox(
            width: 100, height: 100,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox(
                width: 100, height: 100,
                child: CircularProgressIndicator(
                  value: progress, strokeWidth: 8,
                  backgroundColor: Theme.of(context).progressIndicatorTheme.circularTrackColor,
                  valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).progressIndicatorTheme.color!),
                ),
              ),
              Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('$consumed', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 22)),
                Text('kcal', style: Theme.of(context).textTheme.bodyMedium),
              ]),
            ]),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Calories Remaining', style: Theme.of(context).textTheme.titleMedium),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 20.0, color: Colors.white70),
                    onPressed: onEditPressed,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text('${goal - consumed}', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 28, color: Colors.lightGreenAccent)),
              Text('Goal: $goal kcal', style: Theme.of(context).textTheme.bodyMedium),
            ]),
          )
        ]),
      ),
    );
  }

  Widget _buildMacroRow(BuildContext context, double progress, int value, int goal, String label, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(label, style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold, color: color)),
            Text('$value / ${goal}g', style: Theme.of(context).textTheme.bodyMedium),
          ]),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0), minHeight: 8,
            borderRadius: BorderRadius.circular(4),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ]),
      ),
    );
  }
}