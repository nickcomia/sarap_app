import 'package:flutter/material.dart';
import '../../theme.dart';
import '../../models.dart';
import '../../services/firebase_service.dart';

/// Promotions, food categories and nutrition information.
class AdminContentScreen extends StatelessWidget {
  const AdminContentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Categories, nutrition & promotions'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Promotions'),
              Tab(text: 'Food categories'),
              Tab(text: 'Nutrition'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _CrudTab(
              collection: 'promotions',
              singular: 'promotion',
              icon: Icons.local_offer_outlined,
              titleKey: 'title',
              subtitleKey: 'discount',
              hasActive: true,
              fields: [
                _FieldSpec('title', 'Title', required: true),
                _FieldSpec('description', 'Description', multiline: true),
                _FieldSpec('discount', 'Offer (e.g. 20% off, Buy 1 Get 1)'),
                _FieldSpec('restaurant', 'Restaurant name (optional)'),
                _FieldSpec('imageUrl', 'Image URL (optional)'),
              ],
            ),
            _CrudTab(
              collection: 'foodCategories',
              singular: 'category',
              icon: Icons.category_outlined,
              titleKey: 'name',
              subtitleKey: 'description',
              hasActive: false,
              fields: [
                _FieldSpec('name', 'Category name', required: true),
                _FieldSpec('description', 'Description', multiline: true),
              ],
            ),
            _NutritionTab(),
          ],
        ),
      ),
    );
  }
}

class _FieldSpec {
  final String key;
  final String label;
  final bool multiline;
  final bool required;
  const _FieldSpec(this.key, this.label, {this.multiline = false, this.required = false});
}

/// Generic list + add/edit/delete for a simple Firestore collection.
class _CrudTab extends StatefulWidget {
  final String collection;
  final String singular;
  final IconData icon;
  final String titleKey;
  final String? subtitleKey;
  final bool hasActive;
  final List<_FieldSpec> fields;

  const _CrudTab({
    required this.collection,
    required this.singular,
    required this.icon,
    required this.titleKey,
    required this.fields,
    this.subtitleKey,
    this.hasActive = false,
  });

  @override
  State<_CrudTab> createState() => _CrudTabState();
}

class _CrudTabState extends State<_CrudTab> {
  List<Map<String, dynamic>>? _rows;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await FirebaseService.adminListDocs(widget.collection);
      if (mounted) {
        setState(() {
          _rows = list;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _edit([Map<String, dynamic>? row]) async {
    final ctrls = <String, TextEditingController>{
      for (final f in widget.fields)
        f.key: TextEditingController(text: '${row?[f.key] ?? ''}'),
    };
    final formKey = GlobalKey<FormState>();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(row == null ? 'Add ${widget.singular}' : 'Edit ${widget.singular}'),
        content: SizedBox(
          width: 420,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final f in widget.fields)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextFormField(
                        controller: ctrls[f.key],
                        decoration: InputDecoration(labelText: f.label),
                        maxLines: f.multiline ? 3 : 1,
                        validator: f.required
                            ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
                            : null,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.of(ctx).pop(true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (ok != true) return;
    final data = <String, dynamic>{
      for (final f in widget.fields) f.key: ctrls[f.key]!.text.trim(),
    };
    if (row == null && widget.hasActive) data['active'] = true;
    try {
      await FirebaseService.adminSaveDoc(widget.collection, row?['id'] as String?, data);
      _load();
    } catch (e) {
      _snack('Could not save: $e');
    }
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${widget.singular}?'),
        content: Text('"${row[widget.titleKey]}" will be permanently deleted.'),
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
    try {
      await FirebaseService.adminDeleteDoc(widget.collection, row['id'] as String);
      _load();
    } catch (e) {
      _snack('Could not delete: $e');
    }
  }

  Future<void> _toggle(Map<String, dynamic> row, bool value) async {
    setState(() => row['active'] = value);
    try {
      await FirebaseService.adminSaveDoc(
          widget.collection, row['id'] as String, {'active': value});
    } catch (e) {
      if (mounted) setState(() => row['active'] = !value);
      _snack('Could not update: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Could not load: $_error', textAlign: TextAlign.center),
              ),
            )
          : rows == null
              ? const Center(child: CircularProgressIndicator())
              : rows.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text('No ${widget.singular}s yet. Tap Add to create one.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppColors.muted)),
                      ),
                    )
                  : Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 800),
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 90),
                          itemCount: rows.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, i) {
                            final r = rows[i];
                            final active = r['active'] != false;
                            final sub = widget.subtitleKey == null
                                ? ''
                                : (r[widget.subtitleKey] ?? '').toString();
                            return Opacity(
                              opacity: widget.hasActive && !active ? 0.55 : 1,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: AppColors.card,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: AppColors.border),
                                ),
                                child: ListTile(
                                  onTap: () => _edit(r),
                                  leading: Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color: AppColors.chipSelectedBg,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(widget.icon, color: AppColors.primaryDark),
                                  ),
                                  title: Text((r[widget.titleKey] ?? '').toString(),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700, fontSize: 14)),
                                  subtitle: sub.isEmpty ? null : Text(sub),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (widget.hasActive)
                                        Switch(
                                          value: active,
                                          onChanged: (v) => _toggle(r, v),
                                        ),
                                      IconButton(
                                        tooltip: 'Delete',
                                        onPressed: () => _delete(r),
                                        icon: const Icon(Icons.delete_outline,
                                            color: AppColors.muted),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add_${widget.collection}',
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: Text('Add ${widget.singular}'),
      ),
    );
  }
}

/// Calories / protein / carbs / fat for every menu item.
class _NutritionTab extends StatefulWidget {
  const _NutritionTab();

  @override
  State<_NutritionTab> createState() => _NutritionTabState();
}

class _NutritionTabState extends State<_NutritionTab> {
  List<MenuItem>? _items;
  Map<String, String> _restaurantNames = {};
  Map<String, Map<String, dynamic>> _extras = {};
  String? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        FirebaseService.fetchAllMenuItems(includeUnavailable: true),
        FirebaseService.fetchRestaurants(includeUnavailable: true),
        FirebaseService.fetchNutritionExtras(),
      ]);
      final items = results[0] as List<MenuItem>;
      final restaurants = results[1] as List<Restaurant>;
      final extras = results[2] as Map<String, Map<String, dynamic>>;
      final names = {for (final r in restaurants) r.id: r.name};
      items.sort((a, b) {
        final c = (names[a.restaurantId] ?? '').compareTo(names[b.restaurantId] ?? '');
        return c != 0 ? c : a.name.compareTo(b.name);
      });
      if (mounted) {
        setState(() {
          _items = items;
          _restaurantNames = names;
          _extras = extras;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  String _num(dynamic v) => v is num ? v.toString() : '';

  Future<void> _edit(MenuItem item) async {
    final extra = _extras['${item.restaurantId}/${item.id}'] ?? {};
    final kcal = TextEditingController(text: item.calories.toString());
    final protein = TextEditingController(text: _num(extra['proteinG']));
    final carbs = TextEditingController(text: _num(extra['carbsG']));
    final fat = TextEditingController(text: _num(extra['fatG']));
    final formKey = GlobalKey<FormState>();

    Widget field(TextEditingController c, String label, {bool required = false}) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: label),
          validator: (v) {
            final s = v?.trim() ?? '';
            if (s.isEmpty) return required ? 'Required' : null;
            return double.tryParse(s) == null ? 'Enter a number' : null;
          },
        ),
      );
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(item.name),
        content: SizedBox(
          width: 360,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  field(kcal, 'Calories (kcal)', required: true),
                  field(protein, 'Protein (g)'),
                  field(carbs, 'Carbohydrates (g)'),
                  field(fat, 'Fat (g)'),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.of(ctx).pop(true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    double? parse(TextEditingController c) => double.tryParse(c.text.trim());
    try {
      await FirebaseService.updateMenuItemNutrition(
        restaurantId: item.restaurantId,
        itemId: item.id,
        calories: (parse(kcal) ?? 0).round(),
        proteinG: parse(protein),
        carbsG: parse(carbs),
        fatG: parse(fat),
      );
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Could not load: $_error', textAlign: TextAlign.center),
        ),
      );
    }
    final items = _items;
    if (items == null) return const Center(child: CircularProgressIndicator());

    final q = _query.toLowerCase();
    final shown = items
        .where((i) =>
            '${i.name} ${_restaurantNames[i.restaurantId] ?? ''}'.toLowerCase().contains(q))
        .toList();

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: const InputDecoration(
                  hintText: 'Search dish or restaurant',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                itemCount: shown.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final item = shown[i];
                  final extra = _extras['${item.restaurantId}/${item.id}'] ?? {};
                  final macros = <String>[
                    if (extra['proteinG'] is num) 'P ${extra['proteinG']}g',
                    if (extra['carbsG'] is num) 'C ${extra['carbsG']}g',
                    if (extra['fatG'] is num) 'F ${extra['fatG']}g',
                  ].join('  ');
                  return Container(
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: ListTile(
                      onTap: () => _edit(item),
                      title: Text(item.name,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      subtitle: Text(
                        '${_restaurantNames[item.restaurantId] ?? 'Unknown restaurant'}'
                        ' • ${item.calories} kcal'
                        '${macros.isEmpty ? '' : '  •  $macros'}',
                      ),
                      trailing: const Icon(Icons.edit_outlined, color: AppColors.muted),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}