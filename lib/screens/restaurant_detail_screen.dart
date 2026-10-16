import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme.dart';
import '../app_state.dart';
import '../models.dart';
import '../services/firebase_service.dart';
import '../widgets/common.dart';

/// Figure 14: Restaurant / Establishment Detail Screen.
/// (1) Back arrow, (2) heart/save button, (3) "Get directions" button.
class RestaurantDetailScreen extends StatefulWidget {
  final Restaurant restaurant;
  const RestaurantDetailScreen({super.key, required this.restaurant});

  @override
  State<RestaurantDetailScreen> createState() => _RestaurantDetailScreenState();
}

class _RestaurantDetailScreenState extends State<RestaurantDetailScreen> {
  List<MenuItem>? _menuItems;

  @override
  void initState() {
    super.initState();
    _loadMenu();
  }

  Future<void> _loadMenu() async {
    try {
      final items = await FirebaseService.fetchMenuItems(widget.restaurant.id);
      debugPrint('Loaded ${items.length} menu items for "${widget.restaurant.name}" (id: ${widget.restaurant.id})');
      if (mounted) setState(() => _menuItems = items);
    } catch (e, st) {
      debugPrint('fetchMenuItems FAILED for "${widget.restaurant.name}" (id: ${widget.restaurant.id}): $e');
      debugPrint('$st');
      if (mounted) setState(() => _menuItems = []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final r = widget.restaurant;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            backgroundColor: Color(r.accentColorValue),
            // (1) Back arrow button
            leading: Padding(
              padding: const EdgeInsets.all(8),
              child: CircleAvatar(
                backgroundColor: Colors.white,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: AppColors.navy, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
            actions: [
              // (2) Heart / save button
              Padding(
                padding: const EdgeInsets.all(8),
                child: CircleAvatar(
                  backgroundColor: Colors.white,
                  child: IconButton(
                    icon: Icon(
                      r.isSaved ? Icons.favorite : Icons.favorite_border,
                      color: r.isSaved ? AppColors.primary : AppColors.navy,
                      size: 20,
                    ),
                    onPressed: () {
                      AppState.instance.toggleSaved(r.id);
                      setState(() {});
                    },
                  ),
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: SmartImage(
                source: r.imageUrl,
                fallback: Container(
                  color: Color(r.accentColorValue),
                  child: const Center(
                    child: Icon(Icons.restaurant, color: Colors.white, size: 64),
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(r.name, style: Theme.of(context).textTheme.headlineSmall),
                      ),
                      MatchBadge(percent: r.matchPercent),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text('${r.type} • ${r.cuisine}',
                      style: TextStyle(color: colors.muted, fontSize: 13.5)),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Icon(Icons.star, size: 17, color: Colors.amber.shade600),
                      const SizedBox(width: 4),
                      Text('${r.rating}',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                              color: colors.navy)),
                      const SizedBox(width: 14),
                      Icon(Icons.location_on_outlined, size: 16, color: colors.muted),
                      const SizedBox(width: 2),
                      Text('${r.distanceKm} km away',
                          style: TextStyle(color: colors.muted, fontSize: 13)),
                      const SizedBox(width: 14),
                      Text(r.priceRange,
                          style: TextStyle(fontWeight: FontWeight.w800, color: colors.navy)),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text('About', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(r.description,
                      style: TextStyle(color: colors.navy, fontSize: 13.5, height: 1.5)),
                  const SizedBox(height: 18),
                  Text('Menu', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 10),
                  _buildMenuSection(context),
                  const SizedBox(height: 18),
                  Text('Highlights', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: r.tags
                        .map((t) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: colors.chipBg,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(t,
                                  style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: colors.navy)),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 18),
                  Text('Address', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.place_outlined, size: 18, color: colors.muted),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(r.address,
                            style: TextStyle(color: colors.navy, fontSize: 13.5)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      // (3) Get directions button
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          child: ElevatedButton.icon(
            onPressed: () async {
              final uri = Uri.parse(
                'https://www.google.com/maps/dir/?api=1&destination=${r.latitude},${r.longitude}',
              );
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              } else if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Could not open maps for ${r.name}')),
                );
              }
            },
            icon: const Icon(Icons.directions_outlined),
            label: const Text('Get directions'),
          ),
        ),
      ),
    );
  }

  Widget _buildMenuSection(BuildContext context) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_menuItems == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
      );
    }
    if (_menuItems!.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.chipBg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          'No menu items added yet.',
          style: TextStyle(color: colors.muted, fontSize: 13),
        ),
      );
    }
    return Column(
      children: _menuItems!.map((item) {
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(14),
            boxShadow: isDark ? null : AppShadows.soft,
            border: Border.all(color: colors.border),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SmartImage(
                  source: item.imageUrl,
                  width: 56,
                  height: 56,
                  fallback: Container(
                    width: 56,
                    height: 56,
                    color: colors.chipBg,
                    child: Icon(Icons.restaurant, color: colors.muted),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.name,
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                            color: colors.navy)),
                    const SizedBox(height: 2),
                    Text('${item.calories} kcal',
                        style: TextStyle(color: colors.muted, fontSize: 12)),
                  ],
                ),
              ),
              Text('₱${item.price.toStringAsFixed(0)}',
                  style: TextStyle(fontWeight: FontWeight.w800, color: colors.navy)),
            ],
          ),
        );
      }).toList(),
    );
  }
}