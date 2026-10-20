import 'package:flutter/material.dart';
import '../../services/admin_service.dart';
import '../../theme.dart';
import 'admin_add_restaurant_screen.dart';
import 'admin_restaurants_screen.dart';

/// Landing page of the admin dashboard. Live tiles open screens that
/// already exist; the rest map to the remaining items of the
/// Administrator Module (1.1.1 to 1.1.4) and are filled in as they are built.
class AdminHomeScreen extends StatelessWidget {
  const AdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final email = AdminService.currentUser?.email ?? '';
    return Scaffold(
      appBar: AppBar(
        title: const Text('SARAP Admin'),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(email,
                  style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
            ),
          ),
          const IconButton(
            tooltip: 'Sign out',
            onPressed: AdminService.signOut,
            icon: Icon(Icons.logout),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text('Restaurants & menus (1.1.1)',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              _tile(
                context,
                icon: Icons.storefront_outlined,
                title: 'Restaurants and menu items',
                subtitle: 'View, edit, and manage listings',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AdminRestaurantsScreen()),
                ),
              ),
              _tile(
                context,
                icon: Icons.add_business_outlined,
                title: 'Add a restaurant',
                subtitle: 'Create a new restaurant profile',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AdminAddRestaurantScreen()),
                ),
              ),
              const SizedBox(height: 22),
              Text('Coming next', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              _tile(context,
                  icon: Icons.category_outlined,
                  title: 'Food categories, nutrition, promotions',
                  subtitle: '1.1.1'),
              _tile(context,
                  icon: Icons.rate_review_outlined,
                  title: 'Users, reviews, feedback, moderation',
                  subtitle: '1.1.3'),
              _tile(context,
                  icon: Icons.insights_outlined,
                  title: 'Engagement, dashboards, reports',
                  subtitle: '1.1.2 and 1.1.4'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppShadows.soft,
        ),
        child: Material(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            enabled: enabled,
            onTap: onTap,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            leading: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.chipSelectedBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppColors.primaryDark),
            ),
            title: Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 14.5)),
            subtitle: Text(subtitle),
            trailing:
                enabled ? const Icon(Icons.chevron_right_rounded) : null,
          ),
        ),
      ),
    );
  }
}