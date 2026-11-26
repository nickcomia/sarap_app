import 'package:flutter/material.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../services/firebase_service.dart';
import '../../data/food_composition_reference.dart';
import '../../widgets/common.dart';
import 'image_url_field.dart';

/// Adds a menu item, or edits/deletes one when [item] is given.
class AdminAddMenuItemScreen extends StatefulWidget {
  final String restaurantId;
  final MenuItem? item;
  const AdminAddMenuItemScreen({super.key, required this.restaurantId, this.item});

  @override
  State<AdminAddMenuItemScreen> createState() => _AdminAddMenuItemScreenState();
}

class _AdminAddMenuItemScreenState extends State<AdminAddMenuItemScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _caloriesCtrl = TextEditingController();
  final _servingCtrl = TextEditingController();
  final _imageCtrl = TextEditingController();

  final Set<String> _mealTypes = {};
  final Set<String> _dietaryTags = {};

  /// Tags the administrator typed in on this screen. They stay visible as
  /// chips (even when switched off) until the screen is closed.
  final List<String> _extraDietary = [];
  bool _saving = false;
  int? _suggestedCalories;

  static const _baseMealTypes = [
    'Breakfast',
    'Lunch',
    'Dinner',
    'Merienda',
    'Dessert',
    'Late night',
  ];
  static const _baseDietary = [
    'Vegetarian',
    'No pork',
    'Halal',
    'Gluten-free',
    'Dairy-free',
  ];

  /// Ideas shown in the "Add tag" box so the admin does not have to think of
  /// one. Tags already on screen are left out automatically.
  static const _suggestedDietary = [
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

  bool get _isEdit => widget.item != null;

  // Show the usual options plus anything already saved on this item.
  List<String> get _mealTypeOptions =>
      [..._baseMealTypes, ..._mealTypes.where((m) => !_baseMealTypes.contains(m))];

  // The usual tags, then tags typed in on this screen, then any other tag
  // already saved on the item (for example one added earlier).
  List<String> get _dietaryOptions {
    final out = <String>[..._baseDietary];
    for (final t in [..._extraDietary, ..._dietaryTags]) {
      if (!out.any((o) => o.toLowerCase() == t.toLowerCase())) out.add(t);
    }
    return out;
  }

  @override
  void initState() {
    super.initState();
    final it = widget.item;
    if (it != null) {
      _nameCtrl.text = it.name;
      _priceCtrl.text = it.price.toStringAsFixed(it.price % 1 == 0 ? 0 : 2);
      _caloriesCtrl.text = it.calories.toString();
      _servingCtrl.text = it.servingSize ?? '';
      _imageCtrl.text = it.imageUrl ?? '';
      _mealTypes.addAll(it.mealTypes);
      _dietaryTags.addAll(it.dietaryTags);
    }
    _nameCtrl.addListener(_updateSuggestion);
  }

  void _updateSuggestion() {
    final suggestion = FoodCompositionReference.suggestCalories(_nameCtrl.text);
    if (suggestion != _suggestedCalories) {
      setState(() => _suggestedCalories = suggestion);
    }
  }

  @override
  void dispose() {
    _nameCtrl.removeListener(_updateSuggestion);
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _caloriesCtrl.dispose();
    _servingCtrl.dispose();
    _imageCtrl.dispose();
    super.dispose();
  }

  /// Opens the "Add tag" box (suggestions + typing) and turns every chosen
  /// tag on for this item.
  Future<void> _addDietaryTag() async {
    final picked = await showDialog<List<String>>(
      context: context,
      builder: (_) => _NewTagDialog(
        existing: _dietaryOptions,
        suggestions: _suggestedDietary,
      ),
    );
    if (picked == null || picked.isEmpty) return;

    setState(() {
      for (final raw in picked) {
        final tag = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
        if (tag.isEmpty) continue;

        // Same name as an existing chip (any capitalization): switch it on.
        String? match;
        for (final o in _dietaryOptions) {
          if (o.toLowerCase() == tag.toLowerCase()) {
            match = o;
            break;
          }
        }
        if (match != null) {
          _dietaryTags.add(match);
        } else {
          final nice = tag[0].toUpperCase() + tag.substring(1);
          _extraDietary.add(nice);
          _dietaryTags.add(nice);
        }
      }
    });
  }

  Widget _addTagChip() {
    return InkWell(
      onTap: _addDietaryTag,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.primary),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 16, color: AppColors.primaryDark),
            SizedBox(width: 4),
            Text('Add tag',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: AppColors.primaryDark)),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final image = _imageCtrl.text.trim();
    setState(() => _saving = true);
    try {
      if (_isEdit) {
        await FirebaseService.updateMenuItem(
          restaurantId: widget.restaurantId,
          itemId: widget.item!.id,
          name: _nameCtrl.text.trim(),
          price: double.tryParse(_priceCtrl.text.trim()) ?? 0,
          calories: int.tryParse(_caloriesCtrl.text.trim()) ?? 0,
          mealTypes: _mealTypes.toList(),
          dietaryTags: _dietaryTags.toList(),
          servingSize: _servingCtrl.text.trim(),
          imageUrl: image.isEmpty ? null : image,
        );
      } else {
        await FirebaseService.addMenuItem(
          restaurantId: widget.restaurantId,
          name: _nameCtrl.text.trim(),
          price: double.tryParse(_priceCtrl.text.trim()) ?? 0,
          calories: int.tryParse(_caloriesCtrl.text.trim()) ?? 0,
          mealTypes: _mealTypes.toList(),
          dietaryTags: _dietaryTags.toList(),
          servingSize: _servingCtrl.text.trim(),
          imageUrl: image.isEmpty ? null : image,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete menu item?'),
        content: Text('"${widget.item!.name}" will be permanently deleted.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _saving = true);
    try {
      await FirebaseService.deleteMenuItem(widget.restaurantId, widget.item!.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit menu item' : 'Add menu item'),
        actions: [
          if (_isEdit)
            IconButton(
              tooltip: 'Delete menu item',
              onPressed: _saving ? null : _delete,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                ImageUrlField(controller: _imageCtrl),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(labelText: 'Dish / product name'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _priceCtrl,
                        decoration: const InputDecoration(labelText: 'Price (₱)'),
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _caloriesCtrl,
                        decoration:
                            const InputDecoration(labelText: 'Calories (approx.)'),
                        keyboardType: TextInputType.number,
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _servingCtrl,
                  maxLength: 40,
                  decoration: const InputDecoration(
                    labelText: 'Serving size',
                    hintText: 'e.g. 1 slice, 16 oz cup, 1 plate (about 250 g)',
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                if (_suggestedCalories != null) ...[
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () => setState(
                        () => _caloriesCtrl.text = _suggestedCalories.toString()),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: AppColors.chipSelectedBg,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.auto_awesome,
                              size: 14, color: AppColors.primaryDark),
                          const SizedBox(width: 6),
                          Text(
                            'Suggested: ~$_suggestedCalories kcal (FNRI reference) — tap to use',
                            style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primaryDark),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                const Text('Meal type',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _mealTypeOptions.map((m) {
                    final selected = _mealTypes.contains(m);
                    return SarapChip(
                      label: m,
                      selected: selected,
                      onTap: () => setState(() {
                        selected ? _mealTypes.remove(m) : _mealTypes.add(m);
                      }),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                const Text('Dietary tags',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 4),
                const Text(
                    'Tap a tag to switch it on or off. Use "Add tag" for one that is not listed.',
                    style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ..._dietaryOptions.map((d) {
                      final selected = _dietaryTags.contains(d);
                      return SarapChip(
                        label: d,
                        selected: selected,
                        onTap: () => setState(() {
                          selected ? _dietaryTags.remove(d) : _dietaryTags.add(d);
                        }),
                      );
                    }),
                    _addTagChip(),
                  ],
                ),
                const SizedBox(height: 28),
                ElevatedButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.4, color: Colors.white))
                      : Text(_isEdit ? 'Save changes' : 'Save menu item'),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Dialog for adding dietary tags: tap one or more suggestions, and/or type
/// your own. Returns the chosen tag names, or null on cancel. It owns its
/// text field, so nothing needs cleaning up by the screen.
class _NewTagDialog extends StatefulWidget {
  final List<String> existing; // tags already shown on the screen
  final List<String> suggestions;
  const _NewTagDialog({required this.existing, required this.suggestions});

  @override
  State<_NewTagDialog> createState() => _NewTagDialogState();
}

class _NewTagDialogState extends State<_NewTagDialog> {
  final _ctrl = TextEditingController();
  final Set<String> _picked = {};
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  List<String> get _available => [
        for (final s in widget.suggestions)
          if (!widget.existing.any((e) => e.toLowerCase() == s.toLowerCase())) s
      ];

  int get _count => _picked.length + (_ctrl.text.trim().isEmpty ? 0 : 1);

  void _submit() {
    final typed = _ctrl.text.trim();
    if (RegExp(r'[,;|]').hasMatch(typed)) {
      setState(() => _error = 'Do not use commas, semicolons or "|"');
      return;
    }
    final result = [..._picked, if (typed.isNotEmpty) typed];
    if (result.isEmpty) {
      setState(() => _error = 'Pick a suggestion or type a tag name');
      return;
    }
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final available = _available;
    return AlertDialog(
      title: const Text('Add dietary tags'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (available.isNotEmpty) ...[
                const Text('Suggestions',
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(height: 4),
                const Text('Tap the ones that apply to this dish.',
                    style: TextStyle(color: AppColors.muted, fontSize: 12)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in available)
                      FilterChip(
                        label: Text(s),
                        selected: _picked.contains(s),
                        showCheckmark: false,
                        backgroundColor: AppColors.chipBg,
                        selectedColor: AppColors.primary,
                        side: BorderSide.none,
                        labelStyle: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: _picked.contains(s)
                              ? Colors.white
                              : AppColors.navy,
                        ),
                        onSelected: (v) => setState(() {
                          v ? _picked.add(s) : _picked.remove(s);
                          _error = null;
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
              ],
              const Text('Or type your own',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 8),
              TextField(
                controller: _ctrl,
                maxLength: 24,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'e.g. Low sugar',
                  errorText: _error,
                ),
                onChanged: (_) => setState(() => _error = null),
                onSubmitted: (_) => _submit(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        TextButton(
            onPressed: _submit,
            child: Text(_count > 1 ? 'Add ($_count)' : 'Add')),
      ],
    );
  }
}