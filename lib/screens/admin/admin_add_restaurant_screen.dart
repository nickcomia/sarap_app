import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../theme.dart';
import '../../services/firebase_service.dart';
import '../../services/location_service.dart';

class AdminAddRestaurantScreen extends StatefulWidget {
  const AdminAddRestaurantScreen({super.key});

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

  String _type = 'Restaurant';
  String _priceRange = '₱';
  File? _photo;
  double? _lat;
  double? _lng;
  bool _capturingLocation = false;
  bool _saving = false;

  static const _types = ['Café', 'Restaurant', 'Karinderyá', 'Street food'];
  static const _prices = ['₱', '₱₱', '₱₱₱'];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _cuisineCtrl.dispose();
    _addressCtrl.dispose();
    _descriptionCtrl.dispose();
    _tagsCtrl.dispose();
    _ratingCtrl.dispose();
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

  Future<void> _captureLocation() async {
    setState(() => _capturingLocation = true);
    final pos = await LocationService.getCurrentLocation();
    if (!mounted) return;
    setState(() {
      _capturingLocation = false;
      if (pos != null) {
        _lat = pos.latitude;
        _lng = pos.longitude;
      }
    });
    if (pos == null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not get your location — check location permission')),
      );
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_lat == null || _lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tap "Capture current location" first')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      String? imageUrl;
      if (_photo != null) {
        imageUrl = await FirebaseService.uploadImage(_photo!, 'restaurants');
      }
      await FirebaseService.addRestaurant(
        name: _nameCtrl.text.trim(),
        type: _type,
        cuisine: _cuisineCtrl.text.trim(),
        priceRange: _priceRange,
        rating: double.tryParse(_ratingCtrl.text.trim()) ?? 4.5,
        address: _addressCtrl.text.trim(),
        description: _descriptionCtrl.text.trim(),
        tags: _tagsCtrl.text
            .split(',')
            .map((t) => t.trim())
            .where((t) => t.isNotEmpty)
            .toList(),
        latitude: _lat!,
        longitude: _lng!,
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
      appBar: AppBar(title: const Text('Add restaurant')),
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
                            Text('Add a cover photo', style: TextStyle(color: AppColors.muted)),
                          ],
                        ),
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Restaurant name'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              value: _type,
              decoration: const InputDecoration(labelText: 'Establishment type'),
              items: _types.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
              onChanged: (v) => setState(() => _type = v!),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _cuisineCtrl,
              decoration: const InputDecoration(labelText: 'Cuisine (e.g. Filipino, Bakery)'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _priceRange,
                    decoration: const InputDecoration(labelText: 'Price range'),
                    items: _prices.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                    onChanged: (v) => setState(() => _priceRange = v!),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _ratingCtrl,
                    decoration: const InputDecoration(labelText: 'Rating (1-5)'),
                    keyboardType: TextInputType.number,
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
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _capturingLocation ? null : _captureLocation,
              icon: _capturingLocation
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.my_location),
              label: Text(
                _lat != null
                    ? 'Location captured (${_lat!.toStringAsFixed(4)}, ${_lng!.toStringAsFixed(4)})'
                    : 'Capture current location',
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Stand at (or near) the restaurant, then tap the button above — '
              'this records its real map position.',
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
            const SizedBox(height: 28),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                  : const Text('Save restaurant'),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
