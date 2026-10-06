import 'package:flutter/material.dart';
import '../theme.dart';
import '../app_state.dart';
import '../models.dart';
import '../services/notification_service.dart';

/// Figure 15: 7-Day Meal Plan Screen.
/// (1) Day selector tabs, (2) meal edit icon, (3) "Tap to pick a dinner
/// option" prompt for empty slots.
class MealPlanScreen extends StatefulWidget {
  const MealPlanScreen({super.key});

  @override
  State<MealPlanScreen> createState() => _MealPlanScreenState();
}

class _MealPlanScreenState extends State<MealPlanScreen> {
  int _dayIndex = 0;

@override
  void initState() {
    super.initState();
    final state = AppState.instance;
    if (state.mealPlan.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) state.ensureEmptyMealPlanIfNeeded();
      });
    }
  }

  Future<void> _sendTodayReminder(DayPlan day, int remainingKcal) async {
    final unfilled = day.meals.where((m) => !m.isFilled).map((m) => m.slot.label).toList();
    final filled = day.meals.where((m) => m.isFilled).map((m) => m.dishName).join(', ');
    final body = unfilled.isEmpty
        ? 'Today (${day.dayLabel}): $filled. $remainingKcal kcal remaining.'
        : 'Today (${day.dayLabel}): don\'t forget to pick your ${unfilled.join(", ")}. '
            '$remainingKcal kcal remaining today.';

    await NotificationService.showLocal(title: 'SARAP meal reminder', body: body);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reminder sent — check your notifications')),
      );
    }
  }

  Future<void> _openEditSheet(MealEntry meal) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditMealSheet(dayIndex: _dayIndex, meal: meal),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppState.instance;
    final plan = state.mealPlan;
    if (plan.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final day = plan[_dayIndex];
    final profile = state.profile;
    final remaining = (profile.dailyCalorieTarget - day.totalCalories)
        .clamp(0, profile.dailyCalorieTarget);

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('7-day meal plan', style: Theme.of(context).textTheme.headlineSmall),
                    ),
                    IconButton(
                      tooltip: 'Remind me about today\'s meals',
                      onPressed: () => _sendTodayReminder(day, remaining.toInt()),
                      icon: const Icon(Icons.notifications_outlined, color: AppColors.navy),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text('Log what you actually ate — from restaurants or home-cooked',
                    style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.navy,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      _headerStat('Daily target', '${profile.dailyCalorieTarget} kcal'),
                      _headerDivider(),
                      _headerStat('Today so far', '${day.totalCalories} kcal'),
                      _headerDivider(),
                      _headerStat('Remaining', '$remaining kcal'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // (1) Day selector tabs
                SizedBox(
                  height: 42,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: plan.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      final selected = i == _dayIndex;
                      return InkWell(
                        onTap: () => setState(() => _dayIndex = i),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: selected ? AppColors.primary : AppColors.chipBg,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            plan[i].dayLabel,
                            style: TextStyle(
                              color: selected ? Colors.white : AppColors.navy,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 18),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          sliver: SliverList.separated(
            itemCount: day.meals.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final meal = day.meals[i];
              return meal.isFilled
                  ? _mealCard(context, meal)
                  : _emptySlotCard(context, meal);
            },
          ),
        ),
      ],
    );
  }

  Widget _headerStat(String label, String value) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.white60, fontSize: 10.5)),
            const SizedBox(height: 3),
            Text(value,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14.5)),
          ],
        ),
      );

  Widget _headerDivider() => Container(
        width: 1,
        height: 32,
        color: Colors.white24,
        margin: const EdgeInsets.symmetric(horizontal: 8),
      );

  Widget _mealCard(BuildContext context, MealEntry meal) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.chipSelectedBg,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(_iconForSlot(meal.slot), color: AppColors.primaryDark, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(meal.slot.label.toUpperCase(),
                    style: const TextStyle(
                        fontSize: 10.5, color: AppColors.muted, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(meal.dishName ?? '',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 2),
                Text('${meal.restaurantName} • ${meal.calories} kcal',
                    style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              ],
            ),
          ),
          // (2) Meal edit icon — now opens the log sheet
          InkWell(
            onTap: () => _openEditSheet(meal),
            borderRadius: BorderRadius.circular(10),
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.edit_outlined, size: 19, color: AppColors.muted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptySlotCard(BuildContext context, MealEntry meal) {
    return InkWell(
      onTap: () => _openEditSheet(meal),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.chipBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: AppColors.primary.withOpacity(0.4),
              style: BorderStyle.solid,
              width: 1.4),
        ),
        child: Row(
          children: [
            Icon(Icons.add_circle_outline, color: AppColors.primaryDark),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                // (3) "Tap to pick a dinner option" prompt (or breakfast/lunch/merienda as applicable)
                'Tap to log your ${meal.slot.label.toLowerCase()}',
                style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.primaryDark),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconForSlot(MealSlot slot) {
    switch (slot) {
      case MealSlot.breakfast:
        return Icons.free_breakfast_outlined;
      case MealSlot.lunch:
        return Icons.lunch_dining_outlined;
      case MealSlot.merienda:
        return Icons.icecream_outlined;
      case MealSlot.dinner:
        return Icons.dinner_dining_outlined;
    }
  }
}

/// Bottom sheet for logging what was actually eaten — either a dish from
/// a real restaurant (Firestore data) or something cooked at home.
///
/// NOTE: wrapped in an explicit SizedBox(width: screen width) and avoids
/// Spacer()/Expanded() directly under the modal route — showModalBottomSheet
/// briefly reports an unbounded width while it animates open, which crashes
/// any Row that relies on flexible children to resolve its layout.
class _EditMealSheet extends StatefulWidget {
  final int dayIndex;
  final MealEntry meal;
  const _EditMealSheet({required this.dayIndex, required this.meal});

  @override
  State<_EditMealSheet> createState() => _EditMealSheetState();
}

class _EditMealSheetState extends State<_EditMealSheet> {
  bool _fromRestaurant = true;
  String? _selectedRestaurantId;
  late final TextEditingController _dishController;
  late final TextEditingController _calorieController;

  @override
  void initState() {
    super.initState();
    _dishController = TextEditingController(text: widget.meal.dishName ?? '');
    _calorieController =
        TextEditingController(text: widget.meal.calories?.toString() ?? '');

    final currentRName = widget.meal.restaurantName;
    if (currentRName != null && currentRName != 'Home-cooked') {
      final matches =
          AppState.instance.restaurants.where((r) => r.name == currentRName);
      if (matches.isNotEmpty) {
        _selectedRestaurantId = matches.first.id;
        _fromRestaurant = true;
      } else {
        _fromRestaurant = false;
      }
    } else if (currentRName == 'Home-cooked') {
      _fromRestaurant = false;
    }
  }

  @override
  void dispose() {
    _dishController.dispose();
    _calorieController.dispose();
    super.dispose();
  }

  void _save() {
    final dish = _dishController.text.trim();
    final calories = int.tryParse(_calorieController.text.trim());

    if (dish.isEmpty || calories == null || calories <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a dish name and a valid calorie amount')),
      );
      return;
    }

    String restaurantName;
    if (_fromRestaurant) {
      if (_selectedRestaurantId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pick a restaurant')),
        );
        return;
      }
      final r = AppState.instance.restaurants
          .firstWhere((r) => r.id == _selectedRestaurantId);
      restaurantName = r.name;
    } else {
      restaurantName = 'Home-cooked';
    }

    AppState.instance.setMeal(
      widget.dayIndex,
      widget.meal.slot,
      dishName: dish,
      restaurantName: restaurantName,
      calories: calories,
    );
    Navigator.of(context).pop();
  }

  void _remove() {
    AppState.instance.clearMeal(widget.dayIndex, widget.meal.slot);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final restaurants = AppState.instance.restaurants;
    final screenWidth = MediaQuery.of(context).size.width;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      // Explicit bounded width — avoids the transient "unbounded width"
      // constraint showModalBottomSheet sends during its opening animation.
      child: SizedBox(
        width: screenWidth,
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              Text('Log ${widget.meal.slot.label}',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _toggleChip(
                      label: 'From a restaurant',
                      selected: _fromRestaurant,
                      onTap: () => setState(() => _fromRestaurant = true),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _toggleChip(
                      label: 'Home-cooked',
                      selected: !_fromRestaurant,
                      onTap: () => setState(() => _fromRestaurant = false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_fromRestaurant) ...[
                SizedBox(
                  width: double.infinity,
                  child: DropdownButtonFormField<String>(
                    value: _selectedRestaurantId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Restaurant',
                      border: OutlineInputBorder(),
                    ),
                    items: restaurants
                        .map((r) => DropdownMenuItem(value: r.id, child: Text(r.name)))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedRestaurantId = v),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              SizedBox(
                width: double.infinity,
                child: TextField(
                  controller: _dishController,
                  decoration: InputDecoration(
                    labelText: _fromRestaurant ? 'Dish name' : 'What did you cook?',
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: TextField(
                  controller: _calorieController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Calories (kcal)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Both buttons wrapped in Flexible: this steers the Row onto
              // the flex layout path instead of the intrinsic-width path.
              // showModalBottomSheet's opening animation can briefly hand
              // this Row an unbounded width, and the intrinsic-width path
              // crashes on that; the flex path handles it safely.
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  widget.meal.isFilled
                      ? Flexible(
                          child: TextButton(
                            onPressed: _remove,
                            child: const Text('Remove', style: TextStyle(color: Colors.red)),
                          ),
                        )
                      : const SizedBox.shrink(),
                  Flexible(
                    child: ElevatedButton(
                      onPressed: _save,
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toggleChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.chipBg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.navy,
            fontWeight: FontWeight.w700,
            fontSize: 12.5,
          ),
        ),
      ),
    );
  }
}