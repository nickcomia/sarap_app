import 'package:flutter/material.dart';
import '../services/firebase_service.dart';
import '../theme.dart';

/// The diner's own meal history: what they ate (newest first) and the meal
/// plans they replaced. Only the signed-in diner's data is read.
class MealHistoryScreen extends StatefulWidget {
  const MealHistoryScreen({super.key});

  @override
  State<MealHistoryScreen> createState() => _MealHistoryScreenState();
}

class _MealHistoryScreenState extends State<MealHistoryScreen> {
  List<Map<String, dynamic>> _meals = [];
  List<Map<String, dynamic>> _plans = [];
  bool _loading = true;
  String? _error;

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  static const _slotOrder = ['breakfast', 'lunch', 'merienda', 'dinner'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final meals = await FirebaseService.fetchMealHistoryRaw();
      List<Map<String, dynamic>> plans = [];
      try {
        plans = await FirebaseService.fetchPlanHistory();
      } catch (_) {
        // Past plans are optional; the meals can still be shown.
      }
      if (!mounted) return;
      setState(() {
        _meals = _oneRecordPerMeal(meals);
        _plans = plans;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load your history. Check your connection and try again.';
        _loading = false;
      });
    }
  }

  /// Picking a meal and marking it eaten leaves two records. Show the meal
  /// once, preferring the "eaten" one.
  List<Map<String, dynamic>> _oneRecordPerMeal(List<Map<String, dynamic>> logs) {
    final best = <String, Map<String, dynamic>>{};
    for (final m in logs) {
      final name = (m['dishName'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      final at = _dateOf(m);
      final day = at == null ? '' : '${at.year}-${at.month}-${at.day}';
      final key = '$day|${m['dayLabel']}|${m['slot']}|${name.toLowerCase()}';
      final old = best[key];
      if (old == null || (m['source'] == 'eaten' && old['source'] != 'eaten')) {
        best[key] = m;
      }
    }
    final list = best.values.toList();
    list.sort((a, b) {
      final x = (a['createdAt'] as DateTime?) ?? DateTime.now();
      final y = (b['createdAt'] as DateTime?) ?? DateTime.now();
      return y.compareTo(x);
    });
    return list;
  }

  /// The day a meal belongs to: its plan date when saved, otherwise the
  /// moment it was saved (older records).
  DateTime? _dateOf(Map<String, dynamic> m) {
    final p = DateTime.tryParse((m['date'] ?? '').toString());
    if (p != null) return DateTime(p.year, p.month, p.day);
    final c = m['createdAt'] as DateTime?;
    return c == null ? null : DateTime(c.year, c.month, c.day);
  }

  int _kcal(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

  String _cap(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  String _dateLabel(DateTime d) {
    final wd = _weekdays[d.weekday - 1];
    return '$wd, ${_months[d.month - 1]} ${d.day}, ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Meal history'),
          actions: [
            IconButton(
              tooltip: 'Reload',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
          bottom: const TabBar(
            tabs: [Tab(text: 'My meals'), Tab(text: 'Past plans')],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_error!, textAlign: TextAlign.center),
                    ),
                  )
                : TabBarView(children: [_mealsTab(), _plansTab()]),
      ),
    );
  }

  // ---------------------------------------------------------------
  // My meals
  // ---------------------------------------------------------------

  String _dayTitle(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(DateTime(d.year, d.month, d.day)).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return '${_weekdays[d.weekday - 1]}, ${_months[d.month - 1]} ${d.day}';
  }

  Widget _mealsTab() {
    final colors = context.colors;
    if (_meals.isEmpty) {
      return const _Empty(
          'No meals yet. Meals you log or choose in your meal plan appear here.');
    }

    final byDay = <String, List<Map<String, dynamic>>>{};
    final dayDate = <String, DateTime>{};
    final dishCounts = <String, int>{};
    final dishLabels = <String, String>{};
    var kcalTotal = 0;
    for (final m in _meals) {
      final at = _dateOf(m) ?? DateTime.now();
      final key = '${at.year}-${at.month}-${at.day}';
      byDay.putIfAbsent(key, () => []).add(m);
      dayDate[key] = at;
      kcalTotal += _kcal(m['calories']);
      final name = (m['dishName'] ?? '').toString().trim();
      final k = name.toLowerCase();
      dishCounts[k] = (dishCounts[k] ?? 0) + 1;
      dishLabels.putIfAbsent(k, () => name);
    }
    for (final list in byDay.values) {
      list.sort((a, b) => _slotOrder
          .indexOf('${a['slot']}')
          .compareTo(_slotOrder.indexOf('${b['slot']}')));
    }
    final top = dishCounts.entries.reduce((a, b) => a.value >= b.value ? a : b);
    final avgPerDay = (kcalTotal / byDay.length).round();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _Stat('Meals', '${_meals.length}')),
              const SizedBox(width: 10),
              Expanded(child: _Stat('Days', '${byDay.length}')),
              const SizedBox(width: 10),
              Expanded(child: _Stat('Avg per day', '$avgPerDay kcal')),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Most eaten: ${dishLabels[top.key]} (${top.value}x)',
          style: TextStyle(color: colors.muted, fontSize: 12.5),
        ),
        for (final key in (byDay.keys.toList()
              ..sort((a, b) => dayDate[b]!.compareTo(dayDate[a]!)))) ...[
          const SizedBox(height: 16),
          _dayCard(byDay[key]!, dayDate[key]!),
        ],
      ],
    );
  }

  Widget _dayCard(List<Map<String, dynamic>> meals, DateTime date) {
    final colors = context.colors;
    final kcal = meals.fold<int>(0, (a, m) => a + _kcal(m['calories']));
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(_dayTitle(date),
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: colors.navy)),
              const SizedBox(width: 8),
              Expanded(
                child: Text('${meals.length} meals',
                    style: TextStyle(color: colors.muted, fontSize: 12.5)),
              ),
              Text('$kcal kcal',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: colors.primaryDark)),
            ],
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < meals.length; i++) ...[
            if (i > 0) Divider(height: 1, color: colors.border),
            _mealRow(meals[i]),
          ],
        ],
      ),
    );
  }

  Widget _mealRow(Map<String, dynamic> m) {
    final colors = context.colors;
    final eaten = m['source'] == 'eaten';
    final place = (m['restaurantName'] ?? '').toString();
    final detail = [
      if (place.isNotEmpty) place,
      '${_kcal(m['calories'])} kcal',
    ].join(' • ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 66,
            child: Text(_cap('${m['slot']}'),
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: colors.primaryDark)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text((m['dishName'] ?? '').toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: colors.navy)),
                const SizedBox(height: 1),
                Text(detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.muted, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(eaten ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 20,
              color: eaten ? Colors.green.shade600 : colors.muted),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------
  // Past plans
  // ---------------------------------------------------------------

  Widget _plansTab() {
    // Only records that hold the meals actually eaten (older records that
    // kept every planned meal are not shown).
    final plans = [for (final p in _plans) if (p['eatenOnly'] == true) p];
    if (plans.isEmpty) {
      return const _Empty(
          'Nothing here yet. When you generate a new plan, the meals you '
          'marked as eaten in the old plan are kept here.');
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [for (final p in plans) _planCard(p)],
    );
  }

  Widget _planCard(Map<String, dynamic> p) {
    final colors = context.colors;
    final at = p['archivedAt'] as DateTime?;
    final meals = [
      for (final m in ((p['meals'] as List?) ?? const []))
        Map<String, dynamic>.from(m as Map)
    ];
    String dayKey(Map<String, dynamic> m) {
      final d = (m['date'] ?? '').toString();
      return d.isNotEmpty ? d : '0${_weekdays.indexOf('${m['dayLabel']}')}';
    }

    meals.sort((a, b) {
      final d = dayKey(a).compareTo(dayKey(b));
      if (d != 0) return d;
      return _slotOrder
          .indexOf('${a['slot']}')
          .compareTo(_slotOrder.indexOf('${b['slot']}'));
    });
    final byDay = <String, List<Map<String, dynamic>>>{};
    for (final m in meals) {
      byDay.putIfAbsent(dayKey(m), () => []).add(m);
    }
    String heading(String key, Map<String, dynamic> first) {
      final d = DateTime.tryParse(key);
      return d == null ? '${first['dayLabel']}' : _dayTitle(d);
    }
    final total = _kcal(p['totalCalories']);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppShadows.soft,
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: Text(at == null ? 'Earlier plan' : 'Plan replaced ${_dateLabel(at)}',
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14.5,
                  color: colors.navy)),
          subtitle: Text('${meals.length} meals eaten • $total kcal',
              style: TextStyle(color: colors.muted, fontSize: 12.5)),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final e in byDay.entries) ...[
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 6),
                child: Text(heading(e.key, e.value.first),
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: colors.primaryDark)),
              ),
              for (final m in e.value)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.check_circle,
                          size: 18, color: Colors.green.shade600),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${m['dishName']}',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13.5,
                                    color: colors.navy)),
                            Text(
                              [
                                _cap('${m['slot']}'),
                                if ((m['restaurantName'] ?? '').toString().isNotEmpty)
                                  '${m['restaurantName']}',
                                '${_kcal(m['calories'])} kcal',
                              ].join(' • '),
                              style: TextStyle(color: colors.muted, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.chipSelectedBg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: colors.navy)),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(color: colors.muted, fontSize: 12)),
          ],
        ),
      );
  }
}

class _Empty extends StatelessWidget {
  final String text;
  const _Empty(this.text);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.muted, height: 1.4)),
        ),
      );
  }
}