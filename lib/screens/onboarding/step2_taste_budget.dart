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
  static const dietaryRestrictions = [
    'Vegetarian',
    'No pork',
    'Halal',
    'Gluten-free',
    'Dairy-free',
  ];

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
            children: dietaryRestrictions.map((o) {
              final selected = profile.dietaryRestrictions.contains(o);
              return SarapChip(
                label: o,
                selected: selected,
                onTap: () => setState(() {
                  selected
                      ? profile.dietaryRestrictions.remove(o)
                      : profile.dietaryRestrictions.add(o);
                }),
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
