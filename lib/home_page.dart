import 'package:flutter/material.dart';
import 'screens/dashboard_screen.dart';
import 'screens/nutrition_screen.dart';
import 'screens/exercise_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/settings_screen.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const double _barHeight = 62;
  static const double _fabSize = 80;

  int _index = 0;

  final _pages = const [
    DashboardScreen(),
    NutritionScreen(),
    ChatScreen(),
    ExerciseScreen(),
    SettingsScreen(), 
  ];

  void _go(int i) => setState(() => _index = i);

  bool get _isChat => _index == 2;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: _pages[_index],
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: Transform.translate(
        offset: const Offset(0, 40),
        child: SizedBox(
          width: _fabSize,
          height: _fabSize,
          child: FloatingActionButton(
            heroTag: 'chat-fab',
            onPressed: () => _go(2),
            elevation: _isChat ? 8 : 4,
            shape: const CircleBorder(), 
            child: const Icon(Icons.chat_bubble_outline, size: 34),
          ),
        ),
      ),
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 12,
        color: cs.surface,
        elevation: 8,
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: _barHeight,
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _NavButton(
                        icon: Icons.dashboard_outlined,
                        label: 'Dashboard',
                        selected: _index == 0,
                        onTap: () => _go(0),
                      ),
                      _NavButton(
                        icon: Icons.restaurant_menu,
                        label: 'Nutrition',
                        selected: _index == 1,
                        onTap: () => _go(1),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: _fabSize + 24),

                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _NavButton(
                        icon: Icons.fitness_center,
                        label: 'Exercise',
                        selected: _index == 3,
                        onTap: () => _go(3),
                      ),
                      _NavButton(
                        icon: Icons.tune,
                        label: 'Preferences',
                        selected: _index == 4,
                        onTap: () => _go(4),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final Color iconColor = selected ? cs.primary : cs.onSurfaceVariant;
    final TextStyle textStyle = TextStyle(
      fontSize: 11,
      color: iconColor,
      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
    );

    return InkResponse(
      onTap: onTap,
      radius: 28,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: selected ? 26 : 24, color: iconColor),
            const SizedBox(height: 4),
            Text(label, style: textStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}
