import 'package:flutter/material.dart';
import '../../app_state.dart';
import '../../widgets/common.dart';

class Step1FoodPreferences extends StatefulWidget {
  const Step1FoodPreferences({super.key});

  @override
  State<Step1FoodPreferences> createState() => _Step1FoodPreferencesState();
}

class _Step1FoodPreferencesState extends State<Step1FoodPreferences> {
  final profile = AppState.instance.profile;

  static const establishmentTypes = ['Café', 'Restaurant', 'Karinderyá', 'Street food'];
  static const cuisines = [
    'Filipino',
    'Asian fusion',
    'Comfort food',
    'Seafood',
    'Silog meals',
    'Bakery',
    'Western',
  ];
  static const mealTypes = ['Breakfast', 'Lunch', 'Dinner', 'Merienda', 'Late night'];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('Establishment Type'),
          _chipWrap(establishmentTypes, profile.establishmentTypes),
          const SizedBox(height: 22),
          _sectionLabel('Cuisine Preference'),
          _chipWrap(cuisines, profile.cuisines),
          const SizedBox(height: 22),
          _sectionLabel('Meal Type'),
          _chipWrap(mealTypes, profile.mealTypes),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
      );

  Widget _chipWrap(List<String> options, Set<String> selectedSet) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: options.map((o) {
        return SarapChip(
          label: o,
          selected: selectedSet.contains(o),
          onTap: () => setState(() {
            selectedSet.contains(o) ? selectedSet.remove(o) : selectedSet.add(o);
          }),
        );
      }).toList(),
    );
  }
}
