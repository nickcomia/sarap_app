import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../theme.dart';
import '../../services/firebase_service.dart';
import '../../data/food_composition_reference.dart';
import '../../widgets/common.dart';

class AdminAddMenuItemScreen extends StatefulWidget {
  final String restaurantId;
  const AdminAddMenuItemScreen({super.key, required this.restaurantId});

  @override
  State<AdminAddMenuItemScreen> createState() => _AdminAddMenuItemScreenState();
}

class _AdminAddMenuItemScreenState extends State<AdminAddMenuItemScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _caloriesCtrl = TextEditingController();

  final Set<String> _mealTypes = {};
  final Set<String> _dietaryTags = {};
  File? _photo;
  bool _saving = false;
  int? _suggestedCalories;

  static const _mealTypeOptions = ['Breakfast', 'Lunch', 'Dinner', 'Merienda', 'Late night'];
  static const _dietaryOptions = ['Vegetarian', 'No pork', 'Halal', 'Gluten-free', 'Dairy-free'];

  @override
  void initState() {
    super.initState();
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
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final picked = await ImagePicker().pickImage(source: source, imageQuality: 80);
    if (picked != null) setState(() => _photo = File(picked.path));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      String? imageUrl;
      if (_photo != null) {
        imageUrl = await FirebaseService.uploadImage(
          _photo!,
          'menu_items/${widget.restaurantId}',
        );
      }
      await FirebaseService.addMenuItem(
        restaurantId: widget.restaurantId,
        name: _nameCtrl.text.trim(),
        price: double.tryParse(_priceCtrl.text.trim()) ?? 0,
        calories: int.tryParse(_caloriesCtrl.text.trim()) ?? 0,
        mealTypes: _mealTypes.toList(),
        dietaryTags: _dietaryTags.toList(),
        imageUrl: imageUrl,
      );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add menu item')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            GestureDetector(
              onTap: _pickPhoto,
              child: Container(
                height: 160,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppColors.chipBg,
                  borderRadius: BorderRadius.circular(16),
                  image: _photo != null
                      ? DecorationImage(image: FileImage(_photo!), fit: BoxFit.cover)
                      : null,
                ),
                child: _photo == null
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add_a_photo_outlined, color: AppColors.muted, size: 32),
                            SizedBox(height: 8),
                            Text('Add a photo of the dish', style: TextStyle(color: AppColors.muted)),
                          ],
                        ),
                      )
                    : null,
              ),
            ),
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
                    keyboardType: TextInputType.number,
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _caloriesCtrl,
                    decoration: const InputDecoration(labelText: 'Calories (approx.)'),
                    keyboardType: TextInputType.number,
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                ),
              ],
            ),
            if (_suggestedCalories != null) ...[
              const SizedBox(height: 8),
              InkWell(
                onTap: () => setState(() => _caloriesCtrl.text = _suggestedCalories.toString()),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppColors.chipSelectedBg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.auto_awesome, size: 14, color: AppColors.primaryDark),
                      const SizedBox(width: 6),
                      Text(
                        'Suggested: ~$_suggestedCalories kcal (FNRI reference) — tap to use',
                        style: const TextStyle(
                            fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.primaryDark),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            const Text('Meal type', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
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
            const Text('Dietary tags', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _dietaryOptions.map((d) {
                final selected = _dietaryTags.contains(d);
                return SarapChip(
                  label: d,
                  selected: selected,
                  onTap: () => setState(() {
                    selected ? _dietaryTags.remove(d) : _dietaryTags.add(d);
                  }),
                );
              }).toList(),
            ),
            const SizedBox(height: 28),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                  : const Text('Save menu item'),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
