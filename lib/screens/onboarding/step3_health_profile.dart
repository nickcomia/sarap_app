import 'package:flutter/material.dart';
import '../../theme.dart';
import '../../app_state.dart';
import '../../models.dart';

class Step3HealthProfile extends StatefulWidget {
  const Step3HealthProfile({super.key});

  @override
  State<Step3HealthProfile> createState() => _Step3HealthProfileState();
}

class _Step3HealthProfileState extends State<Step3HealthProfile> {
  final profile = AppState.instance.profile;
  late final ageController =
      TextEditingController(text: profile.age.toString());
  late final heightController =
      TextEditingController(text: profile.heightCm.round().toString());
  late final weightController =
      TextEditingController(text: profile.weightKg.round().toString());
        late final goalWeightController = TextEditingController(
    text: profile.goalWeightKg?.round().toString() ?? '',
  );

  @override
  void dispose() {
    ageController.dispose();
    heightController.dispose();
    weightController.dispose();
    goalWeightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _numberField(
                  label: 'Age',
                  suffix: 'yrs',
                  controller: ageController,
                  onChanged: (v) => profile.age = int.tryParse(v) ?? profile.age,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _numberField(
                  label: 'Height',
                  suffix: 'cm',
                  controller: heightController,
                  onChanged: (v) =>
                      profile.heightCm = double.tryParse(v) ?? profile.heightCm,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _numberField(
            label: 'Weight',
            suffix: 'kg',
            controller: weightController,
            onChanged: (v) => profile.weightKg = double.tryParse(v) ?? profile.weightKg,
          ),
          const SizedBox(height: 22),
          const Text('Biological Sex',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
          const SizedBox(height: 10),
          _segmented<BiologicalSex>(
            options: BiologicalSex.values,
            labels: (v) => v.label,
            selected: profile.sex,
            onSelect: (v) => setState(() => profile.sex = v),
          ),
          const SizedBox(height: 22),
          const Text('Activity Level',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
          const SizedBox(height: 10),
          _segmented<ActivityLevel>(
            options: ActivityLevel.values,
            labels: (v) => v.label,
            selected: profile.activityLevel,
            onSelect: (v) => setState(() => profile.activityLevel = v),
          ),
          const SizedBox(height: 22),
          const Text('Health Goal',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
          const SizedBox(height: 10),
          Column(
            children: HealthGoal.values.map((g) {
              final selected = profile.healthGoal == g;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => setState(() {
                    profile.healthGoal = g;
                    // Reset to a sensible default whenever the goal changes,
                    // so an old goal weight doesn't linger from a prior choice.
                    if (g == HealthGoal.maintain) {
                      profile.goalWeightKg = null;
                      goalWeightController.text = '';
                    } else if (profile.goalWeightKg == null) {
                      final suggested = g == HealthGoal.lose
                          ? profile.weightKg - 5
                          : profile.weightKg + 5;
                      profile.goalWeightKg = suggested;
                      goalWeightController.text = suggested.round().toString();
                    }
                  }),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                    decoration: BoxDecoration(
                      color: selected ? AppColors.chipSelectedBg : AppColors.chipBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: selected ? AppColors.primary : Colors.transparent,
                        width: 1.4,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          selected ? Icons.radio_button_checked : Icons.radio_button_off,
                          color: selected ? AppColors.primaryDark : AppColors.muted,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Text(g.label,
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: selected ? AppColors.primaryDark : AppColors.navy)),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          if (profile.healthGoal != HealthGoal.maintain) ...[
            const SizedBox(height: 16),
            _numberField(
              label: profile.healthGoal == HealthGoal.lose
                  ? 'Goal weight (how much you want to weigh)'
                  : 'Goal weight (how much you want to weigh)',
              suffix: 'kg',
              controller: goalWeightController,
              onChanged: (v) => setState(() {
                profile.goalWeightKg = double.tryParse(v) ?? profile.goalWeightKg;
              }),
            ),
            const SizedBox(height: 10),
            Builder(builder: (context) {
              final weeks = profile.estimatedWeeksToGoal;
              final kcal = profile.dailyCalorieTarget;
              if (weeks == null) return const SizedBox.shrink();
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.chipBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  weeks == 0
                      ? 'You\'re already at your goal weight.'
                      : 'At a safe pace, this is about $weeks ${weeks == 1 ? "week" : "weeks"} away — targeting $kcal kcal/day.',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12.5, height: 1.4),
                ),
              );
            }),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _numberField({
    required String label,
    required String suffix,
    required TextEditingController controller,
    required ValueChanged<String> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          onChanged: onChanged,
          decoration: InputDecoration(suffixText: suffix),
        ),
      ],
    );
  }

  Widget _segmented<T>({
    required List<T> options,
    required String Function(T) labels,
    required T selected,
    required ValueChanged<T> onSelect,
  }) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: options.map((o) {
        final isSelected = o == selected;
        return InkWell(
          onTap: () => onSelect(o),
          borderRadius: BorderRadius.circular(30),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.primary : AppColors.chipBg,
              borderRadius: BorderRadius.circular(30),
            ),
            child: Text(
              labels(o),
              style: TextStyle(
                color: isSelected ? Colors.white : AppColors.navy,
                fontWeight: FontWeight.w600,
                fontSize: 13.5,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
