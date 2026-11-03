import 'package:flutter/material.dart';
import '../theme.dart';
import '../app_state.dart';
import '../models.dart';
import '../services/notification_service.dart';
import 'onboarding/onboarding_flow.dart';

/// Figure 15: 7-Day Meal Plan Screen.
/// (1) Day selector tabs, (2) meal edit / swap icons, (3) "Tap to pick a
/// dinner option" prompt for empty slots.
///
/// Merienda is optional: an empty merienda slot is normal, so it is not
/// counted as a missing meal in the summary or in the reminder.
class MealPlanScreen extends StatefulWidget {
  const MealPlanScreen({super.key});

  @override
  State<MealPlanScreen> createState() => _MealPlanScreenState();
}

class _MealPlanScreenState extends State<MealPlanScreen> {
  int _dayIndex = 0;
  bool _regenerating = false;

  static const _fullDayNames = {
    'Mon': 'Monday',
    'Tue': 'Tuesday',
    'Wed': 'Wednesday',
    'Thu': 'Thursday',
    'Fri': 'Friday',
    'Sat': 'Saturday',
    'Sun': 'Sunday',
  };

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

  /// Asks for a fresh plan. If nothing can be planned (no matching meals,
  /// incomplete profile) the existing plan is kept and a message is shown.
  /// AppState ignores repeated requests while one is running.
  Future<void> _regenerate() async {
    if (_regenerating) return;
    setState(() => _regenerating = true);
    await AppState.instance.generateMealPlan();
    if (!mounted) return;
    setState(() => _regenerating = false);
  }

  void _completeProfile() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const OnboardingFlow(initialStep: 2)),
    );
  }

  Future<void> _sendTodayReminder(DayPlan day, int remainingKcal) async {
    // Merienda is optional, so it is never listed as "don't forget".
    final unfilled = day.meals
        .where((m) => !m.isFilled && m.slot != MealSlot.merienda)
        .map((m) => m.slot.label)
        .toList();
    final filled = day.meals.where((m) => m.isFilled).map((m) => m.dishName).join(', ');
    final left = remainingKcal >= 0
        ? '$remainingKcal kcal remaining'
        : '${-remainingKcal} kcal over target';
    final body = unfilled.isEmpty
        ? 'Today (${day.dayLabel}): $filled. $left.'
        : 'Today (${day.dayLabel}): don\'t forget to pick your ${unfilled.join(", ")}. '
            '$left today.';

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
    if (mounted) setState(() {});
  }

  /// Opens the picker for swapping a filled slot or filling an empty one.
  /// The picker can hand control to the manual log sheet.
  Future<void> _openPicker(MealEntry meal) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _OptionPickerSheet(dayIndex: _dayIndex, slot: meal.slot),
    );
    if (!mounted) return;
    setState(() {});
    if (result == 'manual') {
      await _openEditSheet(meal);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppState.instance;
    final plan = state.mealPlan;
    if (plan.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final day = plan[_dayIndex];
    final complete = state.hasRequiredHealthData;
    final target = state.dailyTarget;
    // Not clamped: a negative value means the user is over target.
    final remaining = state.remainingFor(day);
    final colors = context.colors;
    // Merienda only counts as a meal once it has a dish, so skipping it
    // never looks like a missing meal ("3 of 3", not "3 of 4").
    final countedMeals = day.meals
        .where((m) => m.slot != MealSlot.merienda || m.isFilled)
        .toList();
    final loggedMeals = countedMeals.where((m) => m.isFilled).length;
    final totalMeals = countedMeals.length;

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
                    _regenerating
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2.2),
                            ),
                          )
                        : IconButton(
                            tooltip: 'Generate a fresh plan',
                            onPressed: _regenerate,
                            icon: Icon(Icons.autorenew, color: colors.navy),
                          ),
                    IconButton(
                      tooltip: 'Remind me about today\'s meals',
                      onPressed: () {
                        if (!complete) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Complete your health profile first')),
                          );
                          return;
                        }
                        _sendTodayReminder(day, remaining);
                      },
                      icon: Icon(Icons.notifications_outlined, color: colors.navy),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text('Log what you actually ate — from restaurants or home-cooked',
                    style: TextStyle(color: colors.muted, fontSize: 12.5)),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: AppGradients.hero,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      _headerStat('Daily target', complete ? '$target kcal' : '—'),
                      _headerDivider(),
                      _headerStat('Day total', '${day.totalCalories} kcal'),
                      _headerDivider(),
                      _headerStat(
                        remaining >= 0 ? 'Remaining' : 'Over target',
                        complete
                            ? (remaining >= 0
                                ? '$remaining kcal'
                                : '+${-remaining} kcal')
                            : '—',
                      ),
                    ],
                  ),
                ),
                if (complete) ...[
                  const SizedBox(height: 10),
                  _summaryCard(
                      context, day, loggedMeals, totalMeals, target, remaining),
                ],
                if (state.planMessage != null) ...[
                  const SizedBox(height: 12),
                  _noticeBanner(context, state.planMessage!, showAction: !complete),
                ],
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
                        // Only changes which day is displayed — never
                        // touches the meals themselves.
                        onTap: () => setState(() => _dayIndex = i),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: selected ? colors.primary : colors.chipBg,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            plan[i].dayLabel,
                            style: TextStyle(
                              color: selected ? Colors.white : colors.navy,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  _fullDayNames[day.dayLabel] ?? day.dayLabel,
                  style: TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 16, color: colors.navy),
                ),
                const SizedBox(height: 12),
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

  /// Per-day nutrition summary. Only calories are tracked in the plan
  /// (protein/carbs/fat are not stored on plan entries), so only calories
  /// are shown — nothing is estimated or invented.
  Widget _summaryCard(BuildContext context, DayPlan day, int logged, int total,
      int target, int remaining) {
    final colors = context.colors;
    final pct = target <= 0 ? 0 : ((day.totalCalories / target) * 100).round();
    final over = remaining < 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.chipBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_fullDayNames[day.dayLabel] ?? day.dayLabel} summary',
            style: TextStyle(
                fontWeight: FontWeight.w800, fontSize: 12.5, color: colors.navy),
          ),
          const SizedBox(height: 4),
          Text(
            '$logged of $total meals • ${day.totalCalories} kcal '
            'of $target kcal ($pct%)'
            '${over ? ' • ${-remaining} kcal over target' : ' • $remaining kcal left'}',
            style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: over ? Colors.red.shade700 : colors.navy),
          ),
          const SizedBox(height: 2),
          Text('Only calories are tracked in the meal plan.',
              style: TextStyle(fontSize: 11, color: colors.muted)),
        ],
      ),
    );
  }

  Widget _noticeBanner(BuildContext context, String message, {required bool showAction}) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.chipSelectedBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.primary.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 18, color: colors.primaryDark),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                      fontSize: 12.5, height: 1.4, color: colors.navy),
                ),
              ),
            ],
          ),
          if (showAction) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _completeProfile,
                child: const Text('Complete profile'),
              ),
            ),
          ],
        ],
      ),
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
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.border),
        boxShadow: isDark ? null : AppShadows.soft,
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: colors.chipSelectedBg,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(_iconForSlot(meal.slot), color: colors.primaryDark, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(meal.slot.label.toUpperCase(),
                    style: TextStyle(
                        fontSize: 10.5, color: colors.muted, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(meal.dishName ?? '',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14, color: colors.navy)),
                const SizedBox(height: 2),
                Text('${meal.restaurantName} • ${meal.calories} kcal',
                    style: TextStyle(color: colors.muted, fontSize: 12)),
              ],
            ),
          ),
          // Swap this meal for another eligible dish
          InkWell(
            onTap: () => _openPicker(meal),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(Icons.swap_horiz, size: 21, color: colors.primaryDark),
            ),
          ),
          // (2) Meal edit icon — opens the manual log sheet
          InkWell(
            onTap: () => _openEditSheet(meal),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(Icons.edit_outlined, size: 19, color: colors.muted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptySlotCard(BuildContext context, MealEntry meal) {
    final colors = context.colors;
    return InkWell(
      onTap: () => _openPicker(meal),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.chipBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: colors.primary.withValues(alpha: 0.4),
              style: BorderStyle.solid,
              width: 1.4),
        ),
        child: Row(
          children: [
            Icon(Icons.add_circle_outline, color: colors.primaryDark),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                // (3) "Tap to pick a dinner option" prompt (or breakfast/lunch/merienda as applicable)
                'Tap to pick your ${meal.slot.label.toLowerCase()}',
                style: TextStyle(fontWeight: FontWeight.w600, color: colors.primaryDark),
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

/// Picker for swapping a filled slot or filling an empty one. Shows only
/// dishes that are eligible (local, available, budget/diet-compliant and —
/// for an empty slot — within the day's remaining calories). Opening it
/// changes nothing; only "Confirm" saves, and "Cancel" leaves the plan as is.
class _OptionPickerSheet extends StatefulWidget {
  final int dayIndex;
  final MealSlot slot;
  const _OptionPickerSheet({required this.dayIndex, required this.slot});

  @override
  State<_OptionPickerSheet> createState() => _OptionPickerSheetState();
}

class _OptionPickerSheetState extends State<_OptionPickerSheet> {
  OptionResult? _result;
  MealOption? _selected;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _selected = null;
    });
    final r = await AppState.instance.loadOptions(widget.dayIndex, widget.slot);
    if (!mounted) return;
    setState(() {
      _result = r;
      _loading = false;
    });
  }

  Future<void> _confirm() async {
    final choice = _selected;
    if (choice == null || _saving) return; // blocks double taps
    setState(() {
      _saving = true;
      _error = null;
    });
    final problem = await AppState.instance
        .chooseOption(widget.dayIndex, widget.slot, choice);
    if (!mounted) return;
    if (problem == null) {
      Navigator.of(context).pop('saved');
      return;
    }
    setState(() {
      _saving = false;
      _error = problem;
    });
    await _load(); // refresh the list so a stale choice disappears
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final media = MediaQuery.of(context);
    final day = AppState.instance.mealPlan[widget.dayIndex];
    final slotName = widget.slot.label.toLowerCase();
    final result = _result;
    final isSwap = result?.isSwap ??
        day.meals.firstWhere((m) => m.slot == widget.slot).isFilled;

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SizedBox(
        width: media.size.width,
        child: Container(
          constraints: BoxConstraints(maxHeight: media.size.height * 0.75),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
                    color: colors.border,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              Text(
                isSwap ? 'Swap your $slotName' : 'Pick your $slotName',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                result?.allowance != null
                    ? '${day.dayLabel} • ${result!.allowance} kcal remaining today'
                    : day.dayLabel,
                style: TextStyle(color: colors.muted, fontSize: 12.5),
              ),
              const SizedBox(height: 12),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(_error!,
                      style: TextStyle(color: Colors.red.shade700, fontSize: 12.5)),
                ),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
                )
              else if (result != null && result.options.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    result.message ?? 'No eligible dishes were found.',
                    style: TextStyle(color: colors.navy, fontSize: 13.5, height: 1.4),
                  ),
                )
              else if (result != null)
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: result.options.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final o = result.options[i];
                      final selected = _selected?.item.id == o.item.id;
                      return InkWell(
                        onTap: _saving ? null : () => setState(() => _selected = o),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: selected ? colors.chipSelectedBg : colors.chipBg,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: selected ? colors.primary : Colors.transparent,
                              width: 1.4,
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(o.item.name,
                                        style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13.5,
                                            color: colors.navy)),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${o.restaurantName} • ${o.item.calories} kcal',
                                      style: TextStyle(
                                          color: colors.muted, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              Text('₱${o.item.price.toStringAsFixed(0)}',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: colors.navy)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: TextButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop('cancel'),
                      child: const Text('Cancel'),
                    ),
                  ),
                  Flexible(
                    child: TextButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop('manual'),
                      child: const Text('Log manually'),
                    ),
                  ),
                  Flexible(
                    child: ElevatedButton(
                      onPressed: (_selected == null || _saving) ? null : _confirm,
                      child: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Confirm'),
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
  bool _saving = false;
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

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save() async {
    if (_saving) return; // a double tap must not save twice
    final dish = _dishController.text.trim();
    final calories = int.tryParse(_calorieController.text.trim());

    if (dish.isEmpty || calories == null || calories <= 0 || calories > 10000) {
      _toast('Enter a dish name and calories between 1 and 10000');
      return;
    }

    String restaurantName;
    if (_fromRestaurant) {
      if (_selectedRestaurantId == null) {
        _toast('Pick a restaurant');
        return;
      }
      final r = AppState.instance.restaurants
          .firstWhere((r) => r.id == _selectedRestaurantId);
      restaurantName = r.name;
    } else {
      restaurantName = 'Home-cooked';
    }

    setState(() => _saving = true);
    final ok = await AppState.instance.setMeal(
      widget.dayIndex,
      widget.meal.slot,
      dishName: dish,
      restaurantName: restaurantName,
      calories: calories,
    );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() => _saving = false);
      _toast(AppState.instance.planMessage ??
          'Could not save your change. Please try again.');
    }
  }

  Future<void> _remove() async {
    if (_saving) return;
    setState(() => _saving = true);
    final ok =
        await AppState.instance.clearMeal(widget.dayIndex, widget.meal.slot);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() => _saving = false);
      _toast(AppState.instance.planMessage ??
          'Could not remove the meal. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final restaurants = AppState.instance.restaurants;
    final screenWidth = MediaQuery.of(context).size.width;
    final colors = context.colors;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      // Explicit bounded width — avoids the transient "unbounded width"
      // constraint showModalBottomSheet sends during its opening animation.
      child: SizedBox(
        width: screenWidth,
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
                    color: colors.border,
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
                      context: context,
                      label: 'From a restaurant',
                      selected: _fromRestaurant,
                      onTap: () => setState(() => _fromRestaurant = true),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _toggleChip(
                      context: context,
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
                    initialValue: _selectedRestaurantId,
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
                            onPressed: _saving ? null : _remove,
                            child: const Text('Remove', style: TextStyle(color: Colors.red)),
                          ),
                        )
                      : const SizedBox.shrink(),
                  Flexible(
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save'),
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
    required BuildContext context,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? colors.primary : colors.chipBg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : colors.navy,
            fontWeight: FontWeight.w700,
            fontSize: 12.5,
          ),
        ),
      ),
    );
  }
}