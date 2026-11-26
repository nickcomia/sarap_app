import 'package:flutter/material.dart';
import '../../services/admin_service.dart';
import '../../services/firebase_service.dart';
import '../../theme.dart';
import 'admin_add_restaurant_screen.dart';
import 'admin_appeals_screen.dart';
import 'admin_dashboard_screen.dart';
import 'admin_restaurants_screen.dart';
import 'admin_reviews_screen.dart';
import 'admin_users_screen.dart';
import 'analytics_charts.dart';

/// Admin dashboard shell: a dark sidebar on wide screens (a slide-out menu
/// on narrow ones) with the selected page shown on the right.
///
/// The pages themselves are the existing admin screens, unchanged. "Add a
/// restaurant" opens on top as its own page, because it closes itself after
/// saving.
class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _NavItem {
  final String label;
  final IconData icon;
  final String section; // sidebar group heading
  final Widget Function()? page; // null => opens as a separate page
  const _NavItem(this.label, this.icon, this.section, this.page);
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  static const _wideBreakpoint = 900.0;
  int _selected = 0;
  final Set<int> _visited = {0}; // pages are built the first time they open

  late final List<_NavItem> _items = [
    _NavItem('Overview', Icons.space_dashboard_outlined, 'MAIN',
        () => _OverviewPage(onNavigate: _goTo, onAddRestaurant: _openAddRestaurant)),
    _NavItem('Restaurants & menus', Icons.storefront_outlined, 'MANAGE',
        () => const AdminRestaurantsScreen()),
    const _NavItem('Add a restaurant', Icons.add_business_outlined, 'MANAGE', null),
    _NavItem('Dashboard & reports', Icons.insights_outlined, 'INSIGHTS',
        () => const AdminDashboardScreen()),
    _NavItem('Users & moderation', Icons.people_outline, 'INSIGHTS',
        () => const AdminUsersScreen()),
    _NavItem('Review queue', Icons.rate_review_outlined, 'MODERATION',
        () => const AdminReviewsScreen()),
    _NavItem('Appeals', Icons.forum_outlined, 'MODERATION',
        () => const AdminAppealsScreen()),
  ];

  void _openAddRestaurant() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AdminAddRestaurantScreen()),
    );
  }

  void _goTo(int index) {
    final item = _items[index];
    if (item.page == null) {
      _openAddRestaurant();
      return;
    }
    setState(() {
      _selected = index;
      _visited.add(index);
    });
  }

  Widget _content() {
    return IndexedStack(
      index: _selected,
      children: [
        for (var i = 0; i < _items.length; i++)
          (_visited.contains(i) && _items[i].page != null)
              ? _items[i].page!()
              : const SizedBox.shrink(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= _wideBreakpoint;

      if (wide) {
        return Scaffold(
          backgroundColor: AppColors.background,
          body: Row(
            children: [
              SizedBox(
                width: 262,
                child: _Sidebar(
                  items: _items,
                  selected: _selected,
                  onSelect: _goTo,
                ),
              ),
              Expanded(child: _content()),
            ],
          ),
        );
      }

      // Narrow screens: slide-out menu plus a slim top strip.
      return Scaffold(
        backgroundColor: AppColors.background,
        drawer: Drawer(
          width: 280,
          backgroundColor: AppColors.navy,
          child: _Sidebar(
            items: _items,
            selected: _selected,
            onSelect: _goTo,
            closeDrawerOnSelect: true,
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Builder(
                builder: (ctx) => Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  color: AppColors.navy,
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Menu',
                        icon: const Icon(Icons.menu, color: Colors.white),
                        onPressed: () => Scaffold.of(ctx).openDrawer(),
                      ),
                      const Text('SARAP Admin',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 16)),
                    ],
                  ),
                ),
              ),
              Expanded(child: _content()),
            ],
          ),
        ),
      );
    });
  }
}

// ---------------------------------------------------------------------------
// Sidebar
// ---------------------------------------------------------------------------

class _Sidebar extends StatelessWidget {
  final List<_NavItem> items;
  final int selected;
  final ValueChanged<int> onSelect;
  final bool closeDrawerOnSelect;
  const _Sidebar({
    required this.items,
    required this.selected,
    required this.onSelect,
    this.closeDrawerOnSelect = false,
  });

  @override
  Widget build(BuildContext context) {
    final email = AdminService.currentUser?.email ?? '';
    final initial = email.isNotEmpty ? email[0].toUpperCase() : 'A';

    final children = <Widget>[];
    String? lastSection;
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (item.section != lastSection) {
        lastSection = item.section;
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(14, 18, 14, 6),
          child: Text(item.section,
              style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2)),
        ));
      }
      children.add(_SidebarTile(
        item: item,
        active: i == selected && item.page != null,
        onTap: () {
          if (closeDrawerOnSelect) Navigator.of(context).pop();
          onSelect(i);
        },
      ));
    }

    return Container(
      color: AppColors.navy,
      child: SafeArea(
        child: Column(
          children: [
            // Brand: a compact SARAP logo with "Admin console" beside it.
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 6),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.asset(
                      'assets/icons/icon_logo.jpg',
                      width: 72,
                      height: 56,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox(
                        width: 72,
                        height: 56,
                        child: Icon(Icons.restaurant_menu,
                            color: Colors.white, size: 28),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('SARAPAdmin Console',
                        style: TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: children,
              ),
            ),
            // Signed-in admin + sign out
            Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 17,
                    backgroundColor: AppColors.primary,
                    child: Text(initial,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Administrator',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5)),
                        Text(email,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 11.5)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Sign out',
                    onPressed: () => AdminService.signOut(),
                    icon: const Icon(Icons.logout, color: Colors.white70, size: 20),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarTile extends StatelessWidget {
  final _NavItem item;
  final bool active;
  final VoidCallback onTap;
  const _SidebarTile(
      {required this.item, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: active ? AppColors.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          hoverColor: Colors.white.withValues(alpha: 0.06),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(item.icon,
                    size: 20, color: active ? Colors.white : Colors.white70),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(item.label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: active ? Colors.white : Colors.white70,
                          fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                          fontSize: 13.5)),
                ),
                if (item.page == null)
                  const Icon(Icons.open_in_new, size: 14, color: Colors.white38),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Overview page
// ---------------------------------------------------------------------------

class _OverviewPage extends StatefulWidget {
  final ValueChanged<int> onNavigate;
  final VoidCallback onAddRestaurant;
  const _OverviewPage({required this.onNavigate, required this.onAddRestaurant});

  @override
  State<_OverviewPage> createState() => _OverviewPageState();
}

class _OverviewPageState extends State<_OverviewPage> {
  Map<String, dynamic>? _stats;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool force = false}) async {
    setState(() {
      _stats = null;
      _error = null;
    });
    try {
      final s = await FirebaseService.fetchDashboardStats(forceRefresh: force);
      if (mounted) setState(() => _stats = s);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  String _today() {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June', 'July',
      'August', 'September', 'October', 'November', 'December'
    ];
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday',
      'Saturday', 'Sunday'];
    final d = DateTime.now();
    return '${days[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  int _n(Map<String, dynamic> s, String k) => (s[k] as num?)?.toInt() ?? 0;

  List<ChartRow> _rows(dynamic v) {
    return ((v as List?) ?? const []).map((e) {
      final m = e as Map;
      final c = (m['count'] as num).toInt();
      return ChartRow(m['name'].toString(), c, '$c');
    }).toList();
  }

  /// Summary of the analytics: extra numbers, four charts and a short list
  /// of things that need attention. The full version is on "Dashboard &
  /// reports".
  List<Widget> _summary(Map<String, dynamic> s) {
    final profileCount = _n(s, 'profileCount');
    final onboarded = _n(s, 'onboardedCount');
    final rate = profileCount == 0 ? 0 : (onboarded * 100 / profileCount).round();
    String dash(String flag, String v) => s[flag] == true ? v : '—';
    final avgReview = (s['avgReviewRating'] as num?)?.toDouble();

    final kpis = <(IconData, String, String)>[
      (Icons.task_alt_outlined, 'Finished onboarding', dash('profilesOk', '$rate%')),
      (Icons.calendar_month_outlined, 'Diners with a meal plan',
          dash('plansOk', '${s['usersWithPlan']}')),
      (Icons.rate_review_outlined, 'Reviews waiting',
          dash('reviewsOk', '${s['reviewsPending']}')),
      (Icons.grade_outlined, 'Average review rating',
          avgReview == null ? '—' : avgReview.toStringAsFixed(1)),
      (Icons.forum_outlined, 'Appeals waiting',
          dash('appealsOk', '${s['appealsPending']}')),
      (Icons.menu_book_outlined, 'Restaurants with no menu', '${s['noMenuCount']}'),
      (Icons.warning_amber_outlined, 'Users with strikes', '${s['usersWithStrikes']}'),
      (Icons.timer_off_outlined, 'Banned right now', '${s['bannedNow']}'),
    ];

    final charts = <Widget>[
      ChartCard(
        title: 'New users per week (last 8 weeks)',
        kind: ChartKind.line,
        empty: 'No sign-ups yet.',
        rows: _rows(s['signups']),
      ),
      ChartCard(
        title: 'Restaurants by type',
        kind: ChartKind.donut,
        empty: 'No restaurants yet.',
        rows: _rows(s['byType']),
      ),
      ChartCard(
        title: 'Rating distribution',
        kind: ChartKind.columns,
        empty: 'No ratings yet.',
        rows: _rows(s['ratingBuckets']),
      ),
      ChartCard(
        title: 'Health goals of diners',
        kind: ChartKind.donut,
        empty: 'No diner has finished onboarding yet.',
        rows: _rows(s['goalMix']),
      ),
    ];

    final attention = <String>[
      if (s['reviewsOk'] == true && _n(s, 'reviewsPending') > 0)
        '${_n(s, 'reviewsPending')} reviews are waiting in the Review queue.',
      if (s['appealsOk'] == true && _n(s, 'appealsPending') > 0)
        '${_n(s, 'appealsPending')} appeals are waiting for a decision.',
      if (_n(s, 'noMenuCount') > 0)
        '${_n(s, 'noMenuCount')} restaurants have no menu items yet.',
      if (_n(s, 'users') > 0 && _n(s, 'newUsers') == 0)
        'No new users signed up in the last 7 days.',
    ];

    return [
      const SizedBox(height: 26),
      Row(children: [
        Expanded(
            child: Text('Analytics summary',
                style: Theme.of(context).textTheme.titleLarge)),
        TextButton.icon(
          onPressed: () => widget.onNavigate(3),
          icon: const Icon(Icons.arrow_forward_rounded, size: 18),
          label: const Text('Full dashboard'),
        ),
      ]),
      const SizedBox(height: 12),
      LayoutBuilder(builder: (context, c) {
        final cols = c.maxWidth >= 860 ? 4 : 2;
        const gap = 10.0;
        final w = (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(spacing: gap, runSpacing: gap, children: [
          for (final k in kpis)
            SizedBox(
                width: w,
                child: _KpiCard(icon: k.$1, label: k.$2, value: k.$3)),
        ]);
      }),
      const SizedBox(height: 14),
      LayoutBuilder(builder: (context, c) {
        final twoCols = c.maxWidth >= 780;
        const gap = 12.0;
        final half = (c.maxWidth - gap) / 2;
        // Two per row, in a 2 x 2 grid. Cards of similar height share a row
        // (trend + ratings, then the two donuts), so there are no big gaps.
        final ordered = [charts[0], charts[2], charts[1], charts[3]];
        return Wrap(spacing: gap, runSpacing: gap, children: [
          for (final chart in ordered)
            SizedBox(
              width: twoCols ? half : c.maxWidth,
              child: chart,
            ),
        ]);
      }),
      const SizedBox(height: 14),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.chipSelectedBg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [
              Icon(Icons.lightbulb_outline, color: AppColors.primaryDark),
              SizedBox(width: 8),
              Text('Needs attention',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: AppColors.navy)),
            ]),
            const SizedBox(height: 10),
            if (attention.isEmpty)
              const Text('Nothing needs attention right now.',
                  style: TextStyle(color: AppColors.navy, fontSize: 13.5))
            else
              for (final i in attention)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('• $i',
                      style: const TextStyle(
                          color: AppColors.navy, fontSize: 13.5, height: 1.4)),
                ),
            const SizedBox(height: 4),
            const Text('More suggestions are on the Insights tab of the dashboard.',
                style: TextStyle(color: AppColors.muted, fontSize: 12)),
          ],
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final s = _stats;
    final phone = MediaQuery.of(context).size.width < 600;
    final pad = phone ? 16.0 : 28.0;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: ListView(
          padding: EdgeInsets.fromLTRB(pad, pad, pad, 40),
          children: [
            // Header
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Welcome back',
                          style: phone
                              ? Theme.of(context).textTheme.headlineSmall
                              : Theme.of(context).textTheme.headlineMedium),
                      const SizedBox(height: 4),
                      Text(_today(),
                          style: const TextStyle(
                              color: AppColors.muted, fontSize: 13.5)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: () => _load(force: true),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Key numbers
            if (_error != null)
              _InfoBox(
                icon: Icons.error_outline,
                text: 'Could not load the overview numbers. $_error',
                actionLabel: 'Try again',
                onAction: () => _load(force: true),
              )
            else if (s == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              LayoutBuilder(builder: (context, c) {
                final cols = c.maxWidth >= 860 ? 4 : (c.maxWidth >= 520 ? 2 : 1);
                const gap = 10.0;
                final w = (c.maxWidth - gap * (cols - 1)) / cols;
                Widget card(IconData i, String label, String value, {String? note}) =>
                    SizedBox(
                      width: w,
                      child: _KpiCard(icon: i, label: label, value: value, note: note),
                    );
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    card(Icons.people_outline, 'Registered users', '${s['users']}',
                        note: '+${s['newUsers']} in the last 7 days'),
                    card(Icons.storefront_outlined, 'Restaurants',
                        '${s['restaurants']}',
                        note: '${s['hiddenRestaurants']} hidden'),
                    card(Icons.restaurant_menu, 'Menu items', '${s['menuItems']}',
                        note: 'Across all restaurants'),
                    card(Icons.favorite_border, 'Saved places', '${s['totalSaves']}',
                        note:
                            'Avg rating ${(s['avgRating'] as num).toDouble().toStringAsFixed(1)}'),
                  ],
                );
              }),

            // Analytics summary (numbers, charts, suggested actions)
            if (s != null) ..._summary(s),

            const SizedBox(height: 30),
            Text('Quick actions', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 14),
            LayoutBuilder(builder: (context, c) {
              final cols = c.maxWidth >= 860 ? 3 : (c.maxWidth >= 560 ? 2 : 1);
              const gap = 14.0;
              final w = (c.maxWidth - gap * (cols - 1)) / cols;
              Widget action(IconData i, String title, String sub, VoidCallback f) =>
                  SizedBox(
                    width: w,
                    child: _ActionCard(icon: i, title: title, subtitle: sub, onTap: f),
                  );
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  action(Icons.storefront_outlined, 'Manage restaurants',
                      'View, edit, hide and manage menu items',
                      () => widget.onNavigate(1)),
                  action(Icons.add_business_outlined, 'Add a restaurant',
                      'Create a new restaurant profile', widget.onAddRestaurant),
                  action(Icons.insights_outlined, 'Reports',
                      'Engagement charts and a downloadable PDF',
                      () => widget.onNavigate(3)),
                  action(Icons.people_outline, 'Users & moderation',
                      'Ban, disable or re-enable accounts',
                      () => widget.onNavigate(4)),
                  action(Icons.rate_review_outlined, 'Review queue',
                      'Approve or reject pending reviews',
                      () => widget.onNavigate(5)),
                  action(Icons.forum_outlined, 'Appeals',
                      'Review appeals from disabled accounts',
                      () => widget.onNavigate(6)),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }
}

/// A compact number card. Smaller than before: less padding, a smaller icon
/// box and a smaller value, so more fits on screen.
class _KpiCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? note;
  const _KpiCard(
      {required this.icon, required this.label, required this.value, this.note});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppColors.chipSelectedBg,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, color: AppColors.primaryDark, size: 17),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(value,
              style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navy,
                  height: 1)),
          if (note != null) ...[
            const SizedBox(height: 5),
            Text(note!,
                style: const TextStyle(color: AppColors.muted, fontSize: 11)),
          ],
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: AppGradients.primary,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14.5,
                            color: AppColors.navy)),
                    const SizedBox(height: 3),
                    Text(subtitle,
                        style: const TextStyle(
                            color: AppColors.muted, fontSize: 12.5, height: 1.3)),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_rounded,
                  color: AppColors.muted, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  final IconData icon;
  final String text;
  final String actionLabel;
  final VoidCallback onAction;
  const _InfoBox({
    required this.icon,
    required this.text,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.chipSelectedBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primaryDark),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text,
                style: const TextStyle(color: AppColors.navy, fontSize: 13)),
          ),
          TextButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }
}