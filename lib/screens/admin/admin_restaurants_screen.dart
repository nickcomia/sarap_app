import 'package:flutter/material.dart';
import '../../theme.dart';
import '../../models.dart';
import '../../services/firebase_service.dart';
import '../../widgets/common.dart';
import 'admin_add_restaurant_screen.dart';
import 'admin_menu_items_screen.dart';

/// Lists every restaurant straight from Firestore. Each row can be opened
/// (menu items), edited, or hidden from / shown in the customer app.
class AdminRestaurantsScreen extends StatefulWidget {
  const AdminRestaurantsScreen({super.key});

  @override
  State<AdminRestaurantsScreen> createState() => _AdminRestaurantsScreenState();
}

class _AdminRestaurantsScreenState extends State<AdminRestaurantsScreen> {
  List<Restaurant>? _restaurants;
  Map<String, bool> _available = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        FirebaseService.fetchRestaurants(forceServer: true, includeUnavailable: true),
        FirebaseService.fetchRestaurantAvailability(),
      ]);
      if (mounted) {
        setState(() {
          _restaurants = results[0] as List<Restaurant>;
          _available = results[1] as Map<String, bool>;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  void _reload() {
    setState(() => _restaurants = null);
    _load();
  }

  Future<void> _toggle(Restaurant r, bool value) async {
    setState(() => _available[r.id] = value);
    try {
      await FirebaseService.setRestaurantAvailable(r.id, value);
    } catch (e) {
      if (!mounted) return;
      setState(() => _available[r.id] = !value);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update: $e')),
      );
    }
  }

  Future<void> _edit(Restaurant r) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AdminAddRestaurantScreen(restaurant: r)),
    );
    if (changed == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final restaurants = _restaurants;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage restaurants'),
        actions: [
          IconButton(
            tooltip: 'Reload',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Could not load restaurants: $_error',
                    textAlign: TextAlign.center),
              ),
            )
          : restaurants == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(20),
                    itemCount: restaurants.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final r = restaurants[i];
                      final visible = _available[r.id] ?? true;
                      return Opacity(
                        opacity: visible ? 1 : 0.55,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => AdminMenuItemsScreen(restaurant: r)),
                          ),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.card,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: SmartImage(
                                    source: r.imageUrl,
                                    width: 54,
                                    height: 54,
                                    fallback: Container(
                                      width: 54,
                                      height: 54,
                                      color: Color(r.accentColorValue),
                                      child: const Icon(Icons.storefront,
                                          color: Colors.white),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(r.name,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 14.5)),
                                      const SizedBox(height: 3),
                                      Text(
                                        visible
                                            ? '${r.type} • Tap to manage menu items'
                                            : '${r.type} • Hidden from the app',
                                        style: const TextStyle(
                                            color: AppColors.muted, fontSize: 12.5),
                                      ),
                                    ],
                                  ),
                                ),
                                Tooltip(
                                  message: visible
                                      ? 'Visible in the app'
                                      : 'Hidden from the app',
                                  child: Switch(
                                    value: visible,
                                    onChanged: (v) => _toggle(r, v),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Edit restaurant',
                                  onPressed: () => _edit(r),
                                  icon: const Icon(Icons.edit_outlined,
                                      color: AppColors.muted),
                                ),
                                const Icon(Icons.chevron_right,
                                    color: AppColors.muted),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final added = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => const AdminAddRestaurantScreen()),
          );
          if (added == true) _reload();
        },
        icon: const Icon(Icons.add),
        label: const Text('Add restaurant'),
      ),
    );
  }
}