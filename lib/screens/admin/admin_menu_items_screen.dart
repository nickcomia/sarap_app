import 'package:flutter/material.dart';
import '../../theme.dart';
import '../../models.dart';
import '../../services/firebase_service.dart';
import 'admin_add_menu_item_screen.dart';

class AdminMenuItemsScreen extends StatefulWidget {
  final Restaurant restaurant;
  const AdminMenuItemsScreen({super.key, required this.restaurant});

  @override
  State<AdminMenuItemsScreen> createState() => _AdminMenuItemsScreenState();
}

class _AdminMenuItemsScreenState extends State<AdminMenuItemsScreen> {
  List<MenuItem>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await FirebaseService.fetchMenuItems(widget.restaurant.id);
    if (mounted) setState(() => _items = items);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.restaurant.name)),
      body: _items == null
          ? const Center(child: CircularProgressIndicator())
          : _items!.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.restaurant_menu, size: 48, color: AppColors.muted),
                        SizedBox(height: 12),
                        Text('No menu items yet',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                        SizedBox(height: 6),
                        Text('Tap the button below to add the first dish.',
                            style: TextStyle(color: AppColors.muted, fontSize: 13)),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemCount: _items!.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final item = _items![i];
                    return Container(
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
                            child: item.imageUrl != null
                                ? Image.network(item.imageUrl!,
                                    width: 54, height: 54, fit: BoxFit.cover)
                                : Container(
                                    width: 54,
                                    height: 54,
                                    color: AppColors.chipBg,
                                    child: const Icon(Icons.restaurant, color: AppColors.muted),
                                  ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.name,
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                                const SizedBox(height: 3),
                                Text(
                                  '₱${item.price.toStringAsFixed(0)} • ${item.calories} kcal',
                                  style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                                ),
                                if (item.mealTypes.isNotEmpty)
                                  Text(item.mealTypes.join(', '),
                                      style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final added = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => AdminAddMenuItemScreen(restaurantId: widget.restaurant.id),
            ),
          );
          if (added == true) _load();
        },
        icon: const Icon(Icons.add),
        label: const Text('Add item'),
      ),
    );
  }
}
