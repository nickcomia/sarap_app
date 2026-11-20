import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme.dart';
import '../app_state.dart';
import '../models.dart';
import '../services/firebase_service.dart';
import '../widgets/common.dart';
import '../widgets/review_sheet.dart';

/// Figure 14: Restaurant / Establishment Detail Screen.
/// (1) Back arrow, (2) heart/save button, (3) "Get directions" button.
/// Each menu item also has an "Add to meal plan" button, and users can
/// read approved reviews and write their own (checked before posting).
class RestaurantDetailScreen extends StatefulWidget {
  final Restaurant restaurant;
  const RestaurantDetailScreen({super.key, required this.restaurant});

  @override
  State<RestaurantDetailScreen> createState() => _RestaurantDetailScreenState();
}

class _RestaurantDetailScreenState extends State<RestaurantDetailScreen> {
  List<MenuItem>? _menuItems;
  bool _adding = false;

  List<Review>? _reviews; // approved reviews, visible to everyone
  List<Review> _myReviews = []; // the signed-in user's own reviews

  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  @override
  void initState() {
    super.initState();
    _loadMenu();
    _loadReviews();
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

  String _date(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';

  Future<void> _loadReviews() async {
    try {
      final results = await Future.wait<List<Review>>([
        FirebaseService.fetchApprovedReviews(widget.restaurant.id),
        FirebaseService.fetchMyReviews(widget.restaurant.id),
      ]);
      if (!mounted) return;
      setState(() {
        _reviews = results[0];
        _myReviews = results[1];
      });
    } catch (e) {
      debugPrint('fetchReviews FAILED for "${widget.restaurant.name}": $e');
      if (mounted) setState(() => _reviews = []);
    }
  }

  Future<void> _writeReview() async {
    final app = AppState.instance;
    if (!app.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sign in to write a review')));
      return;
    }
    if (app.isBanned) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'You can post reviews again on ${_date(app.bannedUntil!)}.')));
      return;
    }
    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ReviewSheet(restaurant: widget.restaurant),
    );
    if (!mounted) return;
    setState(() {}); // a violation may have started a ban
    if (submitted == true) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Thanks! Your review will appear once it is approved.')));
      _loadReviews();
    }
  }

  /// Lets the user choose a day and meal slot for [item], then adds it to
  /// the meal plan if it passes the planner's rules (local, valid
  /// price/calories, budget, dietary restrictions, remaining calories).
  Future<void> _addToPlan(MenuItem item) async {
    if (_adding) return;

    var dayIndex = 0;
    var slot = MealSlot.values.firstWhere(
      (s) => item.mealTypes
          .map((m) => m.toLowerCase().trim())
          .contains(s.label.toLowerCase()),
      orElse: () => MealSlot.lunch,
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Add to meal plan'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${item.name} • ${item.calories} kcal',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 14),
                DropdownButtonFormField<int>(
                  initialValue: dayIndex,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'Day', border: OutlineInputBorder()),
                  items: [
                    for (var i = 0; i < _days.length; i++)
                      DropdownMenuItem(value: i, child: Text(_days[i])),
                  ],
                  onChanged: (v) => setLocal(() => dayIndex = v ?? 0),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<MealSlot>(
                  initialValue: slot,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'Meal', border: OutlineInputBorder()),
                  items: [
                    for (final s in MealSlot.values)
                      DropdownMenuItem(value: s, child: Text(s.label)),
                  ],
                  onChanged: (v) => setLocal(() => slot = v ?? slot),
                ),
                const SizedBox(height: 10),
                const Text(
                  'If that meal already has a dish, it will be replaced.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _adding = true);
    final problem = await AppState.instance
        .addMenuItemToPlan(item, widget.restaurant, dayIndex, slot);
    if (!mounted) return;
    setState(() => _adding = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(problem ??
          'Added ${item.name} to ${_days[dayIndex]} ${slot.label.toLowerCase()}'),
    ));
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
                      Text(r.priceLabel,
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
                  Text('Reviews', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 10),
                  _buildReviewsSection(context),
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
                    Text(
                        item.calories > 0
                            ? '${item.calories} kcal'
                            : 'Calories not available',
                        style: TextStyle(color: colors.muted, fontSize: 12)),
                  ],
                ),
              ),
              Text('₱${item.price.toStringAsFixed(0)}',
                  style: TextStyle(fontWeight: FontWeight.w800, color: colors.navy)),
              IconButton(
                tooltip: 'Add to meal plan',
                onPressed: _adding ? null : () => _addToPlan(item),
                icon: Icon(Icons.add_circle_outline, color: colors.primaryDark),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _stars(int rating, {double size = 15}) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 5; i++)
            Icon(i < rating ? Icons.star : Icons.star_border,
                size: size, color: Colors.amber.shade600),
        ],
      );

  Widget _buildReviewsSection(BuildContext context) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final app = AppState.instance;

    if (_reviews == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
      );
    }

    final reviews = _reviews!;
    final avg = reviews.isEmpty
        ? null
        : reviews.fold<int>(0, (s, r) => s + r.rating) / reviews.length;
    final hasPending = _myReviews.any((r) => r.status == ReviewStatus.pending);
    final hasApproved = _myReviews.any((r) => r.status == ReviewStatus.approved);

    Widget note(String s) =>
        Text(s, style: TextStyle(color: colors.muted, fontSize: 12.5));

    final Widget action;
    if (hasPending) {
      action = note('Your review is waiting for approval.');
    } else if (hasApproved) {
      action = note('Thanks for reviewing this place.');
    } else if (app.isBanned) {
      action = note('You can post reviews again on ${_date(app.bannedUntil!)}.');
    } else {
      action = OutlinedButton.icon(
        onPressed: _writeReview,
        icon: const Icon(Icons.rate_review_outlined),
        label: const Text('Write a review'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (avg != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                _stars(avg.round(), size: 18),
                const SizedBox(width: 8),
                Text(
                    '${avg.toStringAsFixed(1)} • ${reviews.length} review'
                    '${reviews.length == 1 ? '' : 's'}',
                    style: TextStyle(color: colors.muted, fontSize: 13)),
              ],
            ),
          ),
        action,
        const SizedBox(height: 10),
        if (reviews.isEmpty)
          note('No reviews yet. Be the first to share your experience.')
        else
          for (final r in reviews.take(20))
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.card,
                borderRadius: BorderRadius.circular(14),
                boxShadow: isDark ? null : AppShadows.soft,
                border: Border.all(color: colors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(r.userName,
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                                color: colors.navy)),
                      ),
                      if (r.createdAt != null)
                        Text(_date(r.createdAt!),
                            style: TextStyle(color: colors.muted, fontSize: 11.5)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  _stars(r.rating),
                  if (r.dish != null) ...[
                    const SizedBox(height: 4),
                    Text('Ate: ${r.dish}',
                        style: TextStyle(color: colors.muted, fontSize: 12)),
                  ],
                  const SizedBox(height: 6),
                  Text(r.text,
                      style: TextStyle(color: colors.navy, fontSize: 13.5, height: 1.4)),
                ],
              ),
            ),
      ],
    );
  }
}