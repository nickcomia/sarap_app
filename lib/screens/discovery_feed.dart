import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../theme.dart';
import '../app_state.dart';
import '../models.dart';
import '../widgets/common.dart';
import 'restaurant_detail_screen.dart';
import 'restaurant_map_screen.dart';

/// Figure 13: Home / Discovery Feed.
/// (1) Search bar, (2) map expand button, (3) restaurant match cards
/// ranked by match %, (4) bottom navigation bar (provided by HomeShell).
class DiscoveryFeed extends StatefulWidget {
  const DiscoveryFeed({super.key});

  @override
  State<DiscoveryFeed> createState() => _DiscoveryFeedState();
}

class _DiscoveryFeedState extends State<DiscoveryFeed> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Opens the full in-app Tanauan map (pins, nearby list, routes).
  void _openFullMap() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const RestaurantMapScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (context, _) => _buildFeed(context),
    );
  }

  Widget _buildFeed(BuildContext context) {
    final state = AppState.instance;
    final results = state.sortedByMatch.where((r) {
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return r.name.toLowerCase().contains(q) ||
          r.cuisine.toLowerCase().contains(q) ||
          r.type.toLowerCase().contains(q);
    }).toList();

    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Gradient greeting banner
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: AppGradients.hero,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: AppShadows.card,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Hi, ${state.profile.name.split(' ').first} 👋',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          )),
                      const SizedBox(height: 4),
                      Text(
                        "Here's what's trending near Tanauan City",
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // (1) Search bar + (2) map expand button
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: isDark ? null : AppShadows.soft,
                        ),
                        child: TextField(
                          controller: _searchController,
                          onChanged: (v) => setState(() => _query = v),
                          style: TextStyle(color: colors.navy),
                          decoration: InputDecoration(
                            hintText: 'Search restaurants, cafés, cuisines…',
                            hintStyle: TextStyle(color: colors.muted),
                            prefixIcon: Icon(Icons.search, color: colors.muted),
                            filled: true,
                            fillColor: colors.card,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    InkWell(
                      onTap: _openFullMap,
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          gradient: AppGradients.primary,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: colors.primary.withValues(alpha: 0.35),
                              blurRadius: 14,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.map_outlined, color: Colors.white),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // Small map preview of Tanauan (tap to open the full map).
                RepaintBoundary(
                  child: _MapPreview(
                    restaurants: state.restaurants,
                    userLat: state.userLat,
                    userLng: state.userLng,
                    locationDenied: state.locationDenied,
                    onExpand: _openFullMap,
                  ),
                ),
                const SizedBox(height: 22),

                // ✨ AI Picks — Gemini-reasoned recommendations layered on
                // top of the rule-based matching below. Hidden entirely if
                // loading or empty, so it never feels like broken UI.
                if (state.loadingAiPicks) ...[
                  Row(
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 10),
                      Text('Finding your AI picks…',
                          style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ),
                  const SizedBox(height: 16),
                ] else if (state.aiPicks.isNotEmpty) ...[
                  Row(
                    children: [
                      const Text('✨', style: TextStyle(fontSize: 16)),
                      const SizedBox(width: 6),
                      Text('AI Picks for you',
                          style: Theme.of(context).textTheme.titleMedium),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 132,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: state.aiPicks.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (context, i) {
                        final pick = state.aiPicks[i];
                        Restaurant? restaurant;
                        try {
                          restaurant = state.restaurants
                              .firstWhere((r) => r.id == pick.restaurantId);
                        } catch (_) {
                          restaurant = null;
                        }
                        if (restaurant == null) return const SizedBox.shrink();

                        return GestureDetector(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => RestaurantDetailScreen(restaurant: restaurant!),
                            ),
                          ),
                          child: Container(
                            width: 220,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              gradient: AppGradients.primary,
                              borderRadius: BorderRadius.circular(18),
                              boxShadow: AppShadows.card,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(restaurant.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14.5)),
                                const SizedBox(height: 6),
                                Expanded(
                                  child: Text(
                                    pick.reason,
                                    maxLines: 4,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.9),
                                        fontSize: 12,
                                        height: 1.3),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 22),
                ],

                Text('Matched for you (${results.length})',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),

        // (3) Restaurant match cards
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          sliver: SliverList.separated(
            itemCount: results.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final r = results[i];
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

/// The small, non-interactive map of Tanauan on the feed. Tapping it opens
/// the full [RestaurantMapScreen].
class _MapPreview extends StatelessWidget {
  final List<Restaurant> restaurants;
  final double? userLat;
  final double? userLng;
  final bool locationDenied;
  final VoidCallback onExpand;
  const _MapPreview({
    required this.restaurants,
    required this.userLat,
    required this.userLng,
    required this.locationDenied,
    required this.onExpand,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bounds = RestaurantMapScreen.cityBounds;

    // Centre on the user only when they are inside Tanauan.
    var target = RestaurantMapScreen.cityCenter;
    LatLng? me;
    if (userLat != null && userLng != null) {
      final p = LatLng(userLat!, userLng!);
      if (bounds.contains(p)) {
        target = p;
        me = p;
      }
    }

    final markers = <Marker>[
      for (final r in restaurants)
        if (bounds.contains(LatLng(r.latitude, r.longitude)))
          Marker(
            point: LatLng(r.latitude, r.longitude),
            width: 14,
            height: 14,
            child: Container(
              decoration: BoxDecoration(
                color: colors.primary,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
      if (me != null)
        Marker(
          point: me,
          width: 16,
          height: 16,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.blue,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
        ),
    ];

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: isDark ? null : AppShadows.card,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          height: 130,
          child: Stack(
            children: [
              IgnorePointer(
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: target,
                    initialZoom: 13,
                    cameraConstraint: CameraConstraint.contain(bounds: bounds),
                    interactionOptions:
                        const InteractionOptions(flags: InteractiveFlag.none),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.sarap_app',
                    ),
                    MarkerLayer(markers: markers),
                  ],
                ),
              ),
              Positioned.fill(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(onTap: onExpand),
                ),
              ),
              Positioned(
                left: 8,
                bottom: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  color: Colors.white70,
                  child: const Text('© OpenStreetMap contributors',
                      style: TextStyle(fontSize: 9, color: Colors.black87)),
                ),
              ),
              Positioned(
                right: 10,
                bottom: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: colors.card,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: isDark ? null : AppShadows.soft,
                  ),
                  child: Text('Tap to open map',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: colors.navy)),
                ),
              ),
              if (locationDenied)
                Positioned(
                  left: 10,
                  top: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: colors.card,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: isDark ? null : AppShadows.soft,
                    ),
                    child: Text('Location off — showing est. distances',
                        style: TextStyle(fontSize: 10.5, color: colors.muted)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}