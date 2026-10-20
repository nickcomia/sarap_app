import 'package:flutter/material.dart';
import '../../theme.dart';
import '../../models.dart';
import '../../services/firebase_service.dart';
import '../../widgets/common.dart';
import 'admin_add_menu_item_screen.dart';

/// Menu items of one restaurant. Tap an item to edit or delete it; use the
/// switch to hide it from / show it in the customer app.
class AdminMenuItemsScreen extends StatefulWidget {
  final Restaurant restaurant;
  const AdminMenuItemsScreen({super.key, required this.restaurant});

  @override
  State<AdminMenuItemsScreen> createState() => _AdminMenuItemsScreenState();
}

class _AdminMenuItemsScreenState extends State<AdminMenuItemsScreen> {
  List<MenuItem>? _items;
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
        FirebaseService.fetchMenuItems(widget.restaurant.id, includeUnavailable: true),
        FirebaseService.fetchMenuItemAvailability(widget.restaurant.id),
      ]);
      if (mounted) {
        setState(() {
          _items = results[0] as List<MenuItem>;
          _available = results[1] as Map<String, bool>;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  void _reload() {
    setState(() => _items = null);
    _load();
  }

  Future<void> _toggle(MenuItem item, bool value) async {
    setState(() => _available[item.id] = value);
    try {
      await FirebaseService.setMenuItemAvailable(widget.restaurant.id, item.id, value);
    } catch (e) {
      if (!mounted) return;
      setState(() => _available[item.id] = !value);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update: $e')),
      );
    }
  }

  Future<void> _edit(MenuItem item) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AdminAddMenuItemScreen(
          restaurantId: widget.restaurant.id,
          item: item,
        ),
      ),
    );
    if (changed == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.restaurant.name),
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
                child: Text('Could not load menu items: $_error',
                    textAlign: TextAlign.center),
              ),
            )
          : items == null
              ? const Center(child: CircularProgressIndicator())
              : items.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.restaurant_menu,
                                size: 48, color: AppColors.muted),
                            SizedBox(height: 12),
                            Text('No menu items yet',
                                style: TextStyle(fontWeight: FontWeight.w700)),
                            SizedBox(height: 6),
                            Text('Tap the button below to add the first dish.',
                                style: TextStyle(
                                    color: AppColors.muted, fontSize: 13)),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(20),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final item = items[i];
                        final visible = _available[item.id] ?? true;
                        return Opacity(
                          opacity: visible ? 1 : 0.55,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => _edit(item),
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
                                      source: item.imageUrl,
                                      width: 54,
                                      height: 54,
                                      fallback: Container(
                                        width: 54,
                                        height: 54,
                                        color: AppColors.chipBg,
                                        child: const Icon(Icons.restaurant,
                                            color: AppColors.muted),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(item.name,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 14)),
                                        const SizedBox(height: 3),
                                        Text(
                                          '₱${item.price.toStringAsFixed(0)} • ${item.calories} kcal'
                                          '${visible ? '' : ' • Hidden from the app'}',
                                          style: const TextStyle(
                                              color: AppColors.muted, fontSize: 12.5),
                                        ),
                                        if (item.mealTypes.isNotEmpty)
                                          Text(item.mealTypes.join(', '),
                                              style: const TextStyle(
                                                  color: AppColors.muted,
                                                  fontSize: 11.5)),
                                      ],
                                    ),
                                  ),
                                  Tooltip(
                                    message: visible
                                        ? 'Visible in the app'
                                        : 'Hidden from the app',
                                    child: Switch(
                                      value: visible,
                                      onChanged: (v) => _toggle(item, v),
                                    ),
                                  ),
                                  const Icon(Icons.edit_outlined,
                                      color: AppColors.muted),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final added = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) =>
                  AdminAddMenuItemScreen(restaurantId: widget.restaurant.id),
            ),
          );
          if (added == true) _reload();
        },
        icon: const Icon(Icons.add),
        label: const Text('Add item'),
      ),
    );
  }
}