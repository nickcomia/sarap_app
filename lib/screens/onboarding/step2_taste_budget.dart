import 'package:flutter/material.dart';
import '../../theme.dart';
import '../../app_state.dart';
import '../../widgets/common.dart';

class Step2TasteBudget extends StatefulWidget {
  const Step2TasteBudget({super.key});

  @override
  State<Step2TasteBudget> createState() => _Step2TasteBudgetState();
}

class _Step2TasteBudgetState extends State<Step2TasteBudget> {
  final profile = AppState.instance.profile;

  static const spicinessLabels = ['None', 'Mild', 'Medium', 'Hot', 'Very Spicy'];
  static const sweetnessLabels = ['None', 'Light', 'Medium', 'Sweet', 'Very Sweet'];

  /// Always shown, even before any menu has loaded or when offline.
  static const dietaryRestrictions = [
    'Vegetarian',
    'No pork',
    'Halal',
    'Gluten-free',
    'Dairy-free',
  ];

  /// Other restriction names a diner may pick. A dish tag is only offered
  /// here when it is one of these. Tags such as "Contains pork" or
  /// "Non-Vegetarian" describe a dish, not something a diner needs, so they
  /// are not listed. The names match the suggestions in the admin tag dialog.
  static const _restrictionNames = [
    'Vegan',
    'Pescatarian',
    'Low sugar',
    'Sugar-free',
    'Low sodium',
    'Low fat',
    'Low carb',
    'High protein',
    'Keto',
    'Nut-free',
    'Egg-free',
    'Soy-free',
    'Shellfish-free',
    'Lactose-free',
    'Diabetic-friendly',
  ];

  /// Same names with capitals, spaces and dashes ignored, so "High-Protein"
  /// and "High protein" both count as a match.
  static final Set<String> _allowedKeys =
      _restrictionNames.map(_plain).toSet();

  static String _plain(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// Whether a dish tag should be offered to diners as a restriction.
  /// The known names always pass. A tag the admin typed themselves also
  /// passes when it reads like something a diner needs: short, only letters,
  /// spaces and dashes, and not a description of the dish ("Contains pork",
  /// "Non-Vegetarian", "not suitable for vegetarian"). That way a new tag
  /// such as "Low purine" appears on its own, while stray text does not.
  static bool _isOfferable(String tag) {
    final t = tag.trim();
    if (_allowedKeys.contains(_plain(t))) return true;
    if (t.length < 3 || t.length > 24) return false;
    if (!RegExp(r'^[A-Za-z][A-Za-z \-]*$').hasMatch(t)) return false;
    final k = t.toLowerCase();
    const dishStarts = [
      'contains', 'non-', 'non ', 'not ', 'may ', 'with ', 'or ', 'and ',
      'high in', 'suitable',
    ];
    if (dishStarts.any(k.startsWith)) return false;
    if (t.split(RegExp(r'[ \-]+')).length > 3) return false;
    return true;
  }

  /// Tags the admin added to dishes (filtered by _isOfferable).
  List<String> _menuTags = [];

  @override
  void initState() {
    super.initState();
    _loadMenuTags();
  }

  Future<void> _loadMenuTags() async {
    final tags = await AppState.instance.loadDietaryTagOptions();
    if (!mounted) return;
    setState(() => _menuTags = tags);
  }

  static String _k(String s) => s.trim().toLowerCase();

  /// Fixed list first, then recognised tags found on dishes, then anything
  /// the diner already picked that is in neither (so it can still be
  /// switched off). Names that differ only by capital letters are shown once.
  List<String> get _options {
    final seen = <String>{};
    final out = <String>[];
    void add(String t) {
      final k = _k(t);
      if (k.isEmpty || !seen.add(k)) return;
      out.add(t.trim());
    }

    dietaryRestrictions.forEach(add);
    for (final t in _menuTags) {
      if (_isOfferable(t)) add(t);
    }
    profile.dietaryRestrictions.forEach(add);
    return out;
  }

  bool _isSelected(String o) =>
      profile.dietaryRestrictions.any((d) => _k(d) == _k(o));

  void _toggle(String o) {
    setState(() {
      if (_isSelected(o)) {
        profile.dietaryRestrictions.removeWhere((d) => _k(d) == _k(o));
      } else {
        profile.dietaryRestrictions.add(o);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sliderBlock(
            title: 'Spiciness',
            valueLabel: spicinessLabels[profile.spiciness.round()],
            value: profile.spiciness,
            onChanged: (v) => setState(() => profile.spiciness = v),
          ),
          const SizedBox(height: 20),
          _sliderBlock(
            title: 'Sweetness',
            valueLabel: sweetnessLabels[profile.sweetness.round()],
            value: profile.sweetness,
            onChanged: (v) => setState(() => profile.sweetness = v),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              const Expanded(
                child: Text('Max budget per meal',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
              ),
              Text(
                profile.maxBudget >= 500
                    ? '₱500+'
                    : '₱${profile.maxBudget.round()}',
                style: const TextStyle(
                    fontWeight: FontWeight.w800, color: AppColors.primaryDark),
              ),
            ],
          ),
          Slider(
            min: 30,
            max: 500,
            divisions: 47,
            value: profile.maxBudget.clamp(30, 500).toDouble(),
            onChanged: (v) => setState(() => profile.maxBudget = v),
          ),
          const SizedBox(height: 12),
          const Text('Dietary Restrictions',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _options.map((o) {
              return SarapChip(
                label: o,
                selected: _isSelected(o),
                onTap: () => _toggle(o),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sliderBlock({
    required String title,
    required String valueLabel,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(title,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
            ),
            Text(valueLabel,
                style: const TextStyle(
                    fontWeight: FontWeight.w800, color: AppColors.primaryDark)),
          ],
        ),
        Slider(
          min: 0,
          max: 4,
          divisions: 4,
          value: value,
          onChanged: onChanged,
        ),
      ],
    );
  }
}