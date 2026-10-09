import 'package:flutter/material.dart';
import '../theme.dart';
import '../app_state.dart';
import '../widgets/common.dart';
import 'restaurant_detail_screen.dart';

/// The "Saved" tab of the bottom navigation bar — lists every restaurant
/// the user bookmarked via the heart/save button (Figure 14, item 2).
class SavedScreen extends StatelessWidget {
  const SavedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppState.instance;
    final saved = state.savedRestaurants;
    final colors = context.colors;

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          sliver: SliverToBoxAdapter(
            child: Text('Saved places', style: Theme.of(context).textTheme.headlineSmall),
          ),
        ),
        if (saved.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.favorite_border, size: 54, color: colors.muted),
                    const SizedBox(height: 14),
                    Text('No saved places yet',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Text(
                      'Tap the heart icon on any restaurant to save it here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            sliver: SliverList.separated(
              itemCount: saved.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final r = saved[i];
                return RestaurantCard(
                  restaurant: r,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => RestaurantDetailScreen(restaurant: r)),
                  ),
                  onSaveTap: () => state.toggleSaved(r.id),
                );
              },
            ),
          ),
      ],
    );
  }
}