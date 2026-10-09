import 'package:flutter/material.dart';
import '../app_state.dart';
import '../theme.dart';
import 'discovery_feed.dart';
import 'meal_plan_screen.dart';
import 'saved_screen.dart';
import 'profile_screen.dart';

/// Wraps the four main sections of the app behind a persistent bottom
/// navigation bar, as described for Figure 13: "For You, Meal Plan, Saved,
/// and Profile".
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final state = AppState.instance;

  final _pages = const [
    DiscoveryFeed(),
    MealPlanScreen(),
    SavedScreen(),
    ProfileScreen(),
  ];

  final _items = const [
    (icon: Icons.explore_outlined, activeIcon: Icons.explore, label: 'For You'),
    (icon: Icons.calendar_month_outlined, activeIcon: Icons.calendar_month, label: 'Meal Plan'),
    (icon: Icons.favorite_border, activeIcon: Icons.favorite, label: 'Saved'),
    (icon: Icons.person_outline, activeIcon: Icons.person, label: 'Profile'),
  ];

  @override
  void initState() {
    super.initState();
    state.addListener(_onStateChanged);
    _loadInitialData();
  }

  // Fetches fresh restaurant data, then re-applies which ones this
  // account has saved (loadRestaurantsFromServer() replaces the whole
  // list with brand-new objects that default to isSaved: false), and
  // fetches location in parallel since it doesn't depend on restaurants.
  // Finally kicks off the AI recommendations call (fire-and-forget —
  // it's a bonus layer on top of the already-visible rule-based list).
  Future<void> _loadInitialData() async {
    await state.loadRestaurantsFromServer();
    await Future.wait([
      if (state.isLoggedIn) state.loadSavedFromServer(),
      state.refreshLocation(),
    ]);
    state.loadAiRecommendations();
  }

  @override
  void dispose() {
    state.removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: state.homeTabIndex,
          children: _pages,
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: context.colors.card,
              borderRadius: BorderRadius.circular(26),
              boxShadow: Theme.of(context).brightness == Brightness.dark
                  ? null
                  : AppShadows.floating,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(_items.length, (i) {
                final item = _items[i];
                final active = state.homeTabIndex == i;
                return Expanded(
                  child: InkWell(
                    onTap: () => state.setHomeTab(i),
                    borderRadius: BorderRadius.circular(20),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        gradient: active ? AppGradients.primary : null,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            active ? item.activeIcon : item.icon,
                            color: active ? Colors.white : context.colors.muted,
                            size: 22,
                          ),
                          if (active) ...[
                            const SizedBox(height: 3),
                            Text(
                              item.label,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}