import 'package:flutter/material.dart';
import '../../theme.dart';
import '../../app_state.dart';
import 'admin_add_restaurant_screen.dart';
import 'admin_menu_items_screen.dart';

/// Simple in-app data-entry tool: lets you add real restaurants (with a
/// cover photo) and, per restaurant, real menu items (each with its own
/// photo) — meant to be used on your phone while actually visiting each
/// place. This is a developer/data-entry screen, not part of the normal
/// end-user flow.
class AdminRestaurantsScreen extends StatefulWidget {
  const AdminRestaurantsScreen({super.key});

  @override
  State<AdminRestaurantsScreen> createState() => _AdminRestaurantsScreenState();
}

class _AdminRestaurantsScreenState extends State<AdminRestaurantsScreen> {
  bool _refreshing = false;

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    await AppState.instance.loadRestaurantsFromServer();
    if (mounted) setState(() => _refreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    final restaurants = AppState.instance.restaurants;

    return Scaffold(
      appBar: AppBar(title: const Text('Manage restaurants')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _refreshing
            ? const Center(child: CircularProgressIndicator())
            : ListView.separated(
                padding: const EdgeInsets.all(20),
                itemCount: restaurants.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final r = restaurants[i];
                  return InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => AdminMenuItemsScreen(restaurant: r)),
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
                            child: r.imageUrl != null
                                ? Image.network(r.imageUrl!,
                                    width: 54, height: 54, fit: BoxFit.cover)
                                : Container(
                                    width: 54,
                                    height: 54,
                                    color: Color(r.accentColorValue),
                                    child: const Icon(Icons.storefront, color: Colors.white),
                                  ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(r.name,
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                                const SizedBox(height: 3),
                                Text('${r.type} • Tap to manage menu items',
                                    style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right, color: AppColors.muted),
                        ],
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
          if (added == true) _refresh();
        },
        icon: const Icon(Icons.add),
        label: const Text('Add restaurant'),
      ),
    );
  }
}
