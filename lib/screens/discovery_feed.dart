import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../theme.dart';
import '../app_state.dart';
import '../models.dart';
import '../widgets/common.dart';
import 'restaurant_detail_screen.dart';

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

  void _openFullMap() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FullMapSheet(restaurants: AppState.instance.sortedByMatch),
    );
  }

  static const _tanauanCenter = LatLng(14.0863, 121.1497);

  Set<Marker> _buildMarkers(List<Restaurant> restaurants) {
    return restaurants.map((r) {
      return Marker(
        markerId: MarkerId(r.id),
        position: LatLng(r.latitude, r.longitude),
        infoWindow: InfoWindow(
          title: r.name,
          snippet: '${r.matchPercent}% match • ${r.distanceKm.toStringAsFixed(1)} km',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => RestaurantDetailScreen(restaurant: r)),
          ),
        ),
      );
    }).toSet();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppState.instance;
    final results = state.sortedByMatch.where((r) {
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return r.name.toLowerCase().contains(q) ||
          r.cuisine.toLowerCase().contains(q) ||
          r.type.toLowerCase().contains(q);
    }).toList();

    final cameraTarget = (state.userLat != null && state.userLng != null)
        ? LatLng(state.userLat!, state.userLng!)
        : _tanauanCenter;

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
                        style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 13),
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
                          boxShadow: AppShadows.soft,
                        ),
                        child: TextField(
                          controller: _searchController,
                          onChanged: (v) => setState(() => _query = v),
                          decoration: const InputDecoration(
                            hintText: 'Search restaurants, cafés, cuisines…',
                            prefixIcon: Icon(Icons.search, color: AppColors.muted),
                            filled: true,
                            fillColor: Colors.white,
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
                              color: AppColors.primary.withOpacity(0.35),
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

                // A real, live Google Map preview — tap to expand full screen.
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: AppShadows.card,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: SizedBox(
                      height: 130,
                      child: Stack(
                        children: [
                          AbsorbPointer(
                            child: GoogleMap(
                              initialCameraPosition: CameraPosition(target: cameraTarget, zoom: 14),
                              markers: _buildMarkers(results),
                              myLocationEnabled: state.userLat != null,
                              myLocationButtonEnabled: false,
                              zoomControlsEnabled: false,
                              liteModeEnabled: true,
                            ),
                          ),
                          Positioned.fill(
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(onTap: _openFullMap),
                            ),
                          ),
                          Positioned(
                            right: 10,
                            bottom: 10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: AppShadows.soft,
                              ),
                              child: const Text('Tap to expand map',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                            ),
                          ),
                          if (state.locationDenied)
                            Positioned(
                              left: 10,
                              top: 10,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: AppShadows.soft,
                                ),
                                child: const Text('Location off — showing est. distances',
                                    style: TextStyle(fontSize: 10.5, color: AppColors.muted)),
                              ),
                            ),
                        ],
                      ),
                    ),
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
                                        color: Colors.white.withOpacity(0.9),
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

class _FullMapSheet extends StatefulWidget {
  final List<Restaurant> restaurants;
  const _FullMapSheet({required this.restaurants});

  @override
  State<_FullMapSheet> createState() => _FullMapSheetState();
}

class _FullMapSheetState extends State<_FullMapSheet> {
  static const _tanauanCenter = LatLng(14.0863, 121.1497);
  final _sheetController = DraggableScrollableController();

  Set<Marker> _buildMarkers(BuildContext context) {
    return widget.restaurants.map((r) {
      return Marker(
        markerId: MarkerId(r.id),
        position: LatLng(r.latitude, r.longitude),
        infoWindow: InfoWindow(
          title: r.name,
          snippet: '${r.matchPercent}% match • ${r.distanceKm.toStringAsFixed(1)} km away',
          onTap: () {
            Navigator.of(context).pop();
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => RestaurantDetailScreen(restaurant: r)),
            );
          },
        ),
      );
    }).toSet();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppState.instance;
    final cameraTarget = (state.userLat != null && state.userLng != null)
        ? LatLng(state.userLat!, state.userLng!)
        : _tanauanCenter;

    return DraggableScrollableSheet(
      controller: _sheetController,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Drag handle — this is the only reliable drag target since
              // GoogleMap below intercepts pan gestures for itself.
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragUpdate: (details) {
                  final newSize = _sheetController.size -
                      details.primaryDelta! / MediaQuery.of(context).size.height;
                  _sheetController.jumpTo(newSize.clamp(0.5, 0.95));
                },
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text('Nearby food spots',
                                style: Theme.of(context).textTheme.titleLarge),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                    child: GoogleMap(
                      initialCameraPosition: CameraPosition(target: cameraTarget, zoom: 14),
                      markers: _buildMarkers(context),
                      myLocationEnabled: state.userLat != null,
                      myLocationButtonEnabled: true,
                      zoomControlsEnabled: true,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}