import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../services/firebase_service.dart';
import 'image_url_field.dart';
import 'location_input.dart';
import 'price_range.dart';

/// Adds a restaurant, or edits one when [restaurant] is given.
class AdminAddRestaurantScreen extends StatefulWidget {
  final Restaurant? restaurant;
  const AdminAddRestaurantScreen({super.key, this.restaurant});

  @override
  State<AdminAddRestaurantScreen> createState() => _AdminAddRestaurantScreenState();
}

class _AdminAddRestaurantScreenState extends State<AdminAddRestaurantScreen> {
  // Keys used to remember the last price range between new restaurants.
  static const _kLastMinPrice = 'lastMinPrice';
  static const _kLastMaxPrice = 'lastMaxPrice';
  static const _kLastOpenEnded = 'lastOpenEnded';

  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _tagsCtrl = TextEditingController();
  final _ratingCtrl = TextEditingController(text: '4.5');
  final _imageCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _minPriceCtrl = TextEditingController();
  final _maxPriceCtrl = TextEditingController();

  String _type = 'Restaurant';
  String _cuisine = 'Filipino';
  bool _openEnded = false;
  String? _oldPriceText; // shown when the saved price was not a range (e.g. "₱₱")
  bool _saving = false;

  /// Establishment types used by the app. Keep these identical to the chips
  /// in the onboarding screen, because matching compares the exact text.
  static const _baseTypes = [
    'Café',
    'Restaurant',
    'Karinderyá',
    'Fast food',
    'Eatery',
    'Bakeshop',
    'Street food',
  ];

  /// Cuisines used by the app. Keep these identical to the cuisine chips in
  /// the onboarding screen (Step1FoodPreferences), because matching compares
  /// the exact text.
  static const _baseCuisines = [
    'Filipino',
    'Asian fusion',
    'Comfort food',
    'Seafood',
    'Silog meals',
    'Bakery',
    'Western',
  ];

  bool get _isEdit => widget.restaurant != null;

  List<String> get _types =>
      _baseTypes.contains(_type) ? _baseTypes : [..._baseTypes, _type];

  /// If an older restaurant has a cuisine that is not in the list (for example
  /// "Coffee"), keep it selectable so the form still opens; the admin can then
  /// change it to one of the standard cuisines.
  List<String> get _cuisines =>
      _baseCuisines.contains(_cuisine) ? _baseCuisines : [..._baseCuisines, _cuisine];

  /// Older imported data wrote "Cafe", "Karinderya" and "Fastfood". Map them to
  /// the names used in the app so the dropdown and the matching agree.
  static String _canonicalType(String raw) {
    final key = raw.trim().toLowerCase().replaceAll('é', 'e').replaceAll('á', 'a').replaceAll(' ', '');
    switch (key) {
      case 'cafe':
        return 'Café';
      case 'karinderya':
        return 'Karinderyá';
      case 'fastfood':
        return 'Fast food';
      case 'bakery':
      case 'bakeshop':
        return 'Bakeshop';
      case 'streetfood':
        return 'Street food';
      default:
        return raw.trim();
    }
  }

  /// Maps a saved cuisine to the exact name used in the app when it differs
  /// only by capitalization or spacing (for example "filipino" or "Silog Meals").
  static String _canonicalCuisine(String raw) {
    final key = raw.trim().toLowerCase().replaceAll(' ', '');
    for (final c in _baseCuisines) {
      if (c.toLowerCase().replaceAll(' ', '') == key) return c;
    }
    return raw.trim();
  }

  @override
  void initState() {
    super.initState();
    final r = widget.restaurant;
    if (r != null) {
      _nameCtrl.text = r.name;
      if (r.cuisine.trim().isNotEmpty) _cuisine = _canonicalCuisine(r.cuisine);
      _addressCtrl.text = r.address;
      _descriptionCtrl.text = r.description;
      _tagsCtrl.text = r.tags.join(', ');
      _ratingCtrl.text = r.rating.toString();
      _imageCtrl.text = r.imageUrl ?? '';
      _locationCtrl.text = '${r.latitude},${r.longitude}';
      if (r.type.isNotEmpty) _type = _canonicalType(r.type);
      final range = parsePriceRange(r.priceRange);
      if (r.priceMin != null && r.priceMax != null) {
        // The saved numbers win: the tier text ("₱₱") has no range in it.
        _minPriceCtrl.text = r.priceMin!.round().toString();
        _maxPriceCtrl.text = r.priceMax!.round().toString();
        _openEnded = range?.openEnded ?? false;
      } else if (range != null) {
        _minPriceCtrl.text = range.min.toString();
        _maxPriceCtrl.text = range.max.toString();
        _openEnded = range.openEnded;
      } else if (r.priceRange.isNotEmpty) {
        _oldPriceText = r.priceRange;
      }
    } else {
      // New restaurant: reuse the last price range the admin entered.
      _loadSavedPrice();
    }
  }

  /// Fills the price fields with the last saved range (new restaurants only).
  Future<void> _loadSavedPrice() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        if (_minPriceCtrl.text.isEmpty) {
          _minPriceCtrl.text = prefs.getString(_kLastMinPrice) ?? '';
        }
        if (_maxPriceCtrl.text.isEmpty) {
          _maxPriceCtrl.text = prefs.getString(_kLastMaxPrice) ?? '';
        }
        _openEnded = prefs.getBool(_kLastOpenEnded) ?? false;
      });
    } catch (_) {
      // Storage unavailable: just start with empty fields.
    }
  }

  /// Remembers the price range so the next new restaurant starts with it.
  Future<void> _rememberPrice() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kLastMinPrice, _minPriceCtrl.text.trim());
      await prefs.setString(_kLastMaxPrice, _maxPriceCtrl.text.trim());
      await prefs.setBool(_kLastOpenEnded, _openEnded);
    } catch (_) {
      // Not critical: the restaurant is already saved.
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _descriptionCtrl.dispose();
    _tagsCtrl.dispose();
    _ratingCtrl.dispose();
    _imageCtrl.dispose();
    _locationCtrl.dispose();
    _minPriceCtrl.dispose();
    _maxPriceCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final loc = parseLatLng(_locationCtrl.text);
    if (loc == null) return;

    final minPrice = int.parse(_minPriceCtrl.text.trim());
    final maxPrice = int.parse(_maxPriceCtrl.text.trim());
    final priceText = formatPriceRange(minPrice, maxPrice, openEnded: _openEnded);

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
          cuisine: _cuisine,
          priceRange: priceText,
          rating: rating,
          address: _addressCtrl.text.trim(),
          description: _descriptionCtrl.text.trim(),
          tags: tags,
          latitude: loc.lat,
          longitude: loc.lng,
          imageUrl: image.isEmpty ? null : image,
          priceMin: minPrice,
          priceMax: maxPrice,
        );
      } else {
        await FirebaseService.addRestaurant(
          name: _nameCtrl.text.trim(),
          type: _type,
          cuisine: _cuisine,
          priceRange: priceText,
          rating: rating,
          address: _addressCtrl.text.trim(),
          description: _descriptionCtrl.text.trim(),
          tags: tags,
          latitude: loc.lat,
          longitude: loc.lng,
          imageUrl: image.isEmpty ? null : image,
          priceMin: minPrice,
          priceMax: maxPrice,
        );
        // Keep this price range for the next new restaurant.
        await _rememberPrice();
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

  String? _priceValidator(String? v) {
    final s = v?.trim() ?? '';
    if (s.isEmpty) return 'Required';
    final n = int.tryParse(s);
    if (n == null || n < 0) return 'Enter a whole number';
    return null;
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
                DropdownButtonFormField<String>(
                  initialValue: _cuisine,
                  decoration: const InputDecoration(labelText: 'Cuisine'),
                  items: _cuisines
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) => setState(() => _cuisine = v!),
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _minPriceCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Lowest price (₱)', prefixText: '₱ '),
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        validator: _priceValidator,
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _maxPriceCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Highest price (₱)', prefixText: '₱ '),
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        validator: (v) {
                          final base = _priceValidator(v);
                          if (base != null) return base;
                          final lo = int.tryParse(_minPriceCtrl.text.trim());
                          final hi = int.parse(v!.trim());
                          if (lo != null && hi < lo) return 'Must be at least the lowest price';
                          return null;
                        },
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('No upper limit (show the highest price with +)'),
                  value: _openEnded,
                  onChanged: (v) => setState(() => _openEnded = v),
                ),
                Builder(builder: (context) {
                  final lo = int.tryParse(_minPriceCtrl.text.trim());
                  final hi = int.tryParse(_maxPriceCtrl.text.trim());
                  final preview = (lo != null && hi != null && hi >= lo)
                      ? 'Shown in the app as: ${formatPriceRange(lo, hi, openEnded: _openEnded)}'
                      : (_oldPriceText != null
                          ? 'Saved price was "$_oldPriceText". Enter the actual lowest and highest price.'
                          : 'Enter the cheapest and the most expensive item on the menu.');
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(preview,
                        style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                  );
                }),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _ratingCtrl,
                  decoration: const InputDecoration(labelText: 'Rating (1-5)'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
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