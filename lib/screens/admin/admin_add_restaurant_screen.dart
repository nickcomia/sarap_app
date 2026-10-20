import 'package:flutter/material.dart';
import '../../models.dart';
import '../../services/firebase_service.dart';
import 'image_url_field.dart';
import 'location_input.dart';

/// Adds a restaurant, or edits one when [restaurant] is given.
class AdminAddRestaurantScreen extends StatefulWidget {
  final Restaurant? restaurant;
  const AdminAddRestaurantScreen({super.key, this.restaurant});

  @override
  State<AdminAddRestaurantScreen> createState() => _AdminAddRestaurantScreenState();
}

class _AdminAddRestaurantScreenState extends State<AdminAddRestaurantScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _cuisineCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _tagsCtrl = TextEditingController();
  final _ratingCtrl = TextEditingController(text: '4.5');
  final _imageCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();

  String _type = 'Restaurant';
  String _priceRange = '₱';
  bool _saving = false;

  static const _baseTypes = ['Café', 'Restaurant', 'Karinderyá', 'Street food'];
  static const _basePrices = ['₱', '₱₱', '₱₱₱'];

  bool get _isEdit => widget.restaurant != null;

  List<String> get _types =>
      _baseTypes.contains(_type) ? _baseTypes : [..._baseTypes, _type];
  List<String> get _prices =>
      _basePrices.contains(_priceRange) ? _basePrices : [..._basePrices, _priceRange];

  @override
  void initState() {
    super.initState();
    final r = widget.restaurant;
    if (r != null) {
      _nameCtrl.text = r.name;
      _cuisineCtrl.text = r.cuisine;
      _addressCtrl.text = r.address;
      _descriptionCtrl.text = r.description;
      _tagsCtrl.text = r.tags.join(', ');
      _ratingCtrl.text = r.rating.toString();
      _imageCtrl.text = r.imageUrl ?? '';
      _locationCtrl.text = '${r.latitude},${r.longitude}';
      if (r.type.isNotEmpty) _type = r.type;
      if (r.priceRange.isNotEmpty) _priceRange = r.priceRange;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _cuisineCtrl.dispose();
    _addressCtrl.dispose();
    _descriptionCtrl.dispose();
    _tagsCtrl.dispose();
    _ratingCtrl.dispose();
    _imageCtrl.dispose();
    _locationCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final loc = parseLatLng(_locationCtrl.text);
    if (loc == null) return;

    final image = _imageCtrl.text.trim();
    final tags = _tagsCtrl.text
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    final rating = double.tryParse(_ratingCtrl.text.trim()) ?? 4.5;

    setState(() => _saving = true);
    try {
      if (_isEdit) {
        await FirebaseService.updateRestaurant(
          id: widget.restaurant!.id,
          name: _nameCtrl.text.trim(),
          type: _type,
          cuisine: _cuisineCtrl.text.trim(),
          priceRange: _priceRange,
          rating: rating,
          address: _addressCtrl.text.trim(),
          description: _descriptionCtrl.text.trim(),
          tags: tags,
          latitude: loc.lat,
          longitude: loc.lng,
          imageUrl: image.isEmpty ? null : image,
        );
      } else {
        await FirebaseService.addRestaurant(
          name: _nameCtrl.text.trim(),
          type: _type,
          cuisine: _cuisineCtrl.text.trim(),
          priceRange: _priceRange,
          rating: rating,
          address: _addressCtrl.text.trim(),
          description: _descriptionCtrl.text.trim(),
          tags: tags,
          latitude: loc.lat,
          longitude: loc.lng,
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
        title: const Text('Delete restaurant?'),
        content: Text(
            '"${widget.restaurant!.name}" and all of its menu items will be permanently deleted.'),
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
      await FirebaseService.deleteRestaurant(widget.restaurant!.id);
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
        title: Text(_isEdit ? 'Edit restaurant' : 'Add restaurant'),
        actions: [
          if (_isEdit)
            IconButton(
              tooltip: 'Delete restaurant',
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
                  decoration: const InputDecoration(labelText: 'Restaurant name'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _type,
                  decoration: const InputDecoration(labelText: 'Establishment type'),
                  items: _types
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (v) => setState(() => _type = v!),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _cuisineCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Cuisine (e.g. Filipino, Bakery)'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _priceRange,
                        decoration: const InputDecoration(labelText: 'Price range'),
                        items: _prices
                            .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                            .toList(),
                        onChanged: (v) => setState(() => _priceRange = v!),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _ratingCtrl,
                        decoration: const InputDecoration(labelText: 'Rating (1-5)'),
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _addressCtrl,
                  decoration: const InputDecoration(labelText: 'Address'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _descriptionCtrl,
                  decoration: const InputDecoration(labelText: 'Short description'),
                  maxLines: 2,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _tagsCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Tags (comma-separated)',
                    hintText: 'Budget-friendly, Halal, Breakfast',
                  ),
                ),
                const SizedBox(height: 14),
                LocationField(controller: _locationCtrl),
                const SizedBox(height: 28),
                ElevatedButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.4, color: Colors.white))
                      : Text(_isEdit ? 'Save changes' : 'Save restaurant'),
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