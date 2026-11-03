import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../services/firebase_service.dart';
import '../../theme.dart';

/// Imports menu items for ONE restaurant from a .csv file (in Excel:
/// File > Save As > "CSV UTF-8").
///
/// Columns (first row is the header, order does not matter):
///   name | price | calories | mealTypes | dietaryTags | imageUrl
/// mealTypes and dietaryTags can hold several values separated by commas.
///
/// Nothing is saved until the admin has seen the preview and taps Import.
/// Rows with problems are listed with the reason and are NOT imported.
/// Dishes whose name already exists on this restaurant are skipped, so
/// importing the same file twice never creates duplicates.
class AdminImportMenuScreen extends StatefulWidget {
  final String restaurantId;
  final String restaurantName;
  const AdminImportMenuScreen({
    super.key,
    required this.restaurantId,
    required this.restaurantName,
  });

  @override
  State<AdminImportMenuScreen> createState() => _AdminImportMenuScreenState();
}

/// One parsed spreadsheet row.
class _ImportRow {
  final int rowNumber; // the row number as shown in Excel
  final String name;
  final double price;
  final int calories;
  final List<String> mealTypes;
  final List<String> dietaryTags;
  final String? imageUrl;
  final List<String> errors;
  final List<String> warnings;
  String? skipReason; // set when the dish already exists

  _ImportRow({
    required this.rowNumber,
    required this.name,
    required this.price,
    required this.calories,
    required this.mealTypes,
    required this.dietaryTags,
    required this.imageUrl,
    required this.errors,
    required this.warnings,
  });

  bool get hasErrors => errors.isNotEmpty;
  bool get isSkipped => skipReason != null;
  bool get isReady => !hasErrors && !isSkipped;
}

class _AdminImportMenuScreenState extends State<AdminImportMenuScreen> {
  // Same names the add-menu-item form and the meal plan use.
  static const _mealTypeNames = [
    'Breakfast',
    'Lunch',
    'Dinner',
    'Merienda',
    'Dessert',
    'Late night',
  ];
  static const _dietaryNames = [
    'Vegetarian',
    'No pork',
    'Halal',
    'Gluten-free',
    'Dairy-free',
  ];

  String? _fileName;
  List<_ImportRow>? _rows;
  String? _error;
  bool _reading = false;
  bool _importing = false;
  int _done = 0;

  // ------------------------------------------------------------------
  // Reading the file
  // ------------------------------------------------------------------

  Future<void> _pickFile() async {
    setState(() {
      _error = null;
      _reading = true;
    });
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv'],
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) {
        if (mounted) setState(() => _reading = false);
        return;
      }
      final file = picked.files.first;
      final fileName = file.name;
      final bytes = file.bytes;
      if (bytes == null) {
        throw const FormatException('Could not read that file. Please try again.');
      }

      final table = _readTable(fileName, bytes);
      final rows = _buildRows(table);

      // Skip dishes that already exist on this restaurant (or repeat in the file).
      final existing = await FirebaseService.fetchMenuItems(
        widget.restaurantId,
        includeUnavailable: true,
      );
      final seen = existing.map((m) => m.name.trim().toLowerCase()).toSet();
      for (final r in rows) {
        if (r.hasErrors) continue;
        final key = r.name.toLowerCase();
        if (seen.contains(key)) {
          r.skipReason = 'Already on this menu';
        } else {
          seen.add(key);
        }
      }

      if (!mounted) return;
      setState(() {
        _fileName = fileName;
        _rows = rows;
        _reading = false;
      });
    } on FormatException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _rows = null;
          _reading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not read the file: $e';
          _rows = null;
          _reading = false;
        });
      }
    }
  }

  List<List<String>> _readTable(String fileName, Uint8List bytes) {
    if (!fileName.toLowerCase().endsWith('.csv')) {
      throw const FormatException(
          'Please choose a .csv file. In Excel: File > Save As > "CSV UTF-8 (Comma delimited)".');
    }
    return _parseCsv(utf8.decode(bytes, allowMalformed: true));
  }

  /// Small CSV reader that understands quoted values, so a cell like
  /// "Vegetarian, Gluten-free" stays in one column.
  List<List<String>> _parseCsv(String input) {
    final text = input.startsWith('\uFEFF') ? input.substring(1) : input;
    final rows = <List<String>>[];
    var row = <String>[];
    final cell = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      if (inQuotes) {
        if (c == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            cell.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          cell.write(c);
        }
      } else if (c == '"') {
        inQuotes = true;
      } else if (c == ',') {
        row.add(cell.toString());
        cell.clear();
      } else if (c == '\n' || c == '\r') {
        if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
        row.add(cell.toString());
        cell.clear();
        rows.add(row);
        row = <String>[];
      } else {
        cell.write(c);
      }
    }
    if (cell.isNotEmpty || row.isNotEmpty) {
      row.add(cell.toString());
      rows.add(row);
    }
    return rows;
  }

  // ------------------------------------------------------------------
  // Turning rows into menu items (with checks)
  // ------------------------------------------------------------------

  static String _letters(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');

  List<_ImportRow> _buildRows(List<List<String>> table) {
    if (table.isEmpty) throw const FormatException('The file is empty.');

    final header = table.first.map(_letters).toList();
    int col(List<String> names) {
      for (final n in names) {
        final i = header.indexOf(n);
        if (i >= 0) return i;
      }
      return -1;
    }

    final cName = col(['name', 'dish', 'dishname', 'product', 'productname']);
    final cPrice = col(['price', 'php', 'amount']);
    final cCal = col(['calories', 'calorie', 'kcal']);
    final cMeal = col(['mealtypes', 'mealtype', 'meal']);
    final cDiet = col(['dietarytags', 'dietarytag', 'dietary', 'diet']);
    final cImage = col(['imageurl', 'image', 'photo', 'photourl']);

    final missing = <String>[
      if (cName < 0) 'name',
      if (cPrice < 0) 'price',
      if (cCal < 0) 'calories',
    ];
    if (missing.isNotEmpty) {
      throw FormatException(
          'The first row must be a header with these columns. Missing: ${missing.join(', ')}.');
    }

    String cellAt(List<String> r, int c) =>
        (c >= 0 && c < r.length) ? r[c].trim() : '';

    final rows = <_ImportRow>[];
    for (var i = 1; i < table.length; i++) {
      final r = table[i];
      if (r.every((c) => c.trim().isEmpty)) continue; // blank line

      final errors = <String>[];
      final warnings = <String>[];

      final name = cellAt(r, cName);
      if (name.isEmpty) errors.add('Name is empty');

      final price = _parseNumber(cellAt(r, cPrice));
      if (price == null || !price.isFinite || price <= 0) {
        errors.add('Price must be a number above 0');
      }

      final calNum = _parseNumber(cellAt(r, cCal));
      final calories = calNum?.round();
      if (calories == null || calories <= 0 || calories > 10000) {
        errors.add('Calories must be between 1 and 10000');
      }

      final meals = <String>[];
      for (final raw in _splitList(cellAt(r, cMeal))) {
        final match = _mealTypeNames
            .where((m) => _letters(m) == _letters(raw))
            .toList();
        if (match.isEmpty) {
          errors.add('Unknown meal type "$raw" (use ${_mealTypeNames.join(', ')})');
        } else if (!meals.contains(match.first)) {
          meals.add(match.first);
        }
      }
      if (meals.isEmpty && !errors.any((e) => e.startsWith('Unknown meal'))) {
        warnings.add('No meal type, so it will not be used in meal plans');
      }

      final diet = <String>[];
      for (final raw in _splitList(cellAt(r, cDiet))) {
        final match = _dietaryNames
            .where((d) => _letters(d) == _letters(raw))
            .toList();
        final tag = match.isEmpty ? raw : match.first; // keep custom tags as typed
        if (!diet.contains(tag)) diet.add(tag);
      }

      final image = cellAt(r, cImage);

      rows.add(_ImportRow(
        rowNumber: i + 1,
        name: name,
        price: price ?? 0,
        calories: calories ?? 0,
        mealTypes: meals,
        dietaryTags: diet,
        imageUrl: image.isEmpty ? null : image,
        errors: errors,
        warnings: warnings,
      ));
    }

    if (rows.isEmpty) {
      throw const FormatException('No menu items were found under the header row.');
    }
    return rows;
  }

  /// "₱1,200.50" -> 1200.5
  double? _parseNumber(String s) {
    final cleaned = s.replaceAll(',', '').replaceAll(RegExp(r'[^0-9.]'), '');
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }

  List<String> _splitList(String s) =>
      s.split(RegExp(r'[,;]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  // ------------------------------------------------------------------
  // Saving
  // ------------------------------------------------------------------

  Future<void> _import() async {
    final ready = (_rows ?? []).where((r) => r.isReady).toList();
    if (ready.isEmpty || _importing) return;

    setState(() {
      _importing = true;
      _done = 0;
    });

    var saved = 0;
    final failed = <String>[];
    for (final r in ready) {
      try {
        await FirebaseService.addMenuItem(
          restaurantId: widget.restaurantId,
          name: r.name,
          price: r.price,
          calories: r.calories,
          mealTypes: r.mealTypes,
          dietaryTags: r.dietaryTags,
          imageUrl: r.imageUrl,
        );
        saved++;
      } catch (e) {
        failed.add('Row ${r.rowNumber} (${r.name}): $e');
      }
      if (!mounted) return;
      setState(() => _done = saved + failed.length);
    }

    if (!mounted) return;
    setState(() => _importing = false);

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import finished'),
        content: Text(
          '$saved item${saved == 1 ? '' : 's'} added to ${widget.restaurantName}.'
          '${failed.isEmpty ? '' : '\n\n${failed.length} failed:\n${failed.join('\n')}'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (mounted && saved > 0) Navigator.of(context).pop(true);
  }

  // ------------------------------------------------------------------
  // UI
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final ready = rows?.where((r) => r.isReady).length ?? 0;
    final skipped = rows?.where((r) => r.isSkipped).length ?? 0;
    final problems = rows?.where((r) => r.hasErrors).length ?? 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Import menu items')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text('Importing into: ${widget.restaurantName}',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Text(
                  'Use a .csv file (in Excel: File > Save As > CSV UTF-8). The first row must be the header:\n\n'
                  'name | price | calories | mealTypes | dietaryTags | imageUrl\n\n'
                  '• mealTypes: Breakfast, Lunch, Dinner, Merienda, Dessert, Late night\n'
                  '• dietaryTags: Vegetarian, No pork, Halal, Gluten-free, Dairy-free\n'
                  '• Put several values in one cell separated by commas\n'
                  '• imageUrl can be left empty\n'
                  '• Dishes that already exist on this menu are skipped',
                  style: TextStyle(fontSize: 12.5, height: 1.45, color: AppColors.muted),
                ),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: (_reading || _importing) ? null : _pickFile,
                icon: _reading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.upload_file),
                label: Text(_fileName == null
                    ? 'Choose .csv file'
                    : 'Choose a different file ($_fileName)'),
                style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14)),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    style: TextStyle(color: Colors.red.shade700, fontSize: 13)),
              ],
              if (rows != null) ...[
                const SizedBox(height: 18),
                Wrap(
                  spacing: 14,
                  runSpacing: 6,
                  children: [
                    Text('$ready ready',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.green.shade700)),
                    Text('$skipped skipped (already exist)',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, color: AppColors.muted)),
                    Text('$problems with problems',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: problems > 0
                                ? Colors.red.shade700
                                : AppColors.muted)),
                  ],
                ),
                const SizedBox(height: 10),
                for (final r in rows) _rowTile(r),
                const SizedBox(height: 16),
                if (_importing) ...[
                  LinearProgressIndicator(
                      value: ready == 0 ? null : _done / ready),
                  const SizedBox(height: 8),
                  Text('Saving $_done of $ready...',
                      style: const TextStyle(fontSize: 12.5)),
                  const SizedBox(height: 8),
                ],
                ElevatedButton(
                  onPressed: (ready == 0 || _importing) ? null : _import,
                  child: Text(ready == 0
                      ? 'Nothing to import'
                      : 'Import $ready item${ready == 1 ? '' : 's'}'),
                ),
                if (problems > 0)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Rows with problems are not imported. Fix them in the file and import again; '
                      'items already added will be skipped.',
                      style: TextStyle(fontSize: 12, color: AppColors.muted),
                    ),
                  ),
                const SizedBox(height: 20),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _rowTile(_ImportRow r) {
    IconData icon;
    Color color;
    if (r.hasErrors) {
      icon = Icons.error_outline;
      color = Colors.red.shade700;
    } else if (r.isSkipped) {
      icon = Icons.skip_next_outlined;
      color = AppColors.muted;
    } else if (r.warnings.isNotEmpty) {
      icon = Icons.warning_amber_rounded;
      color = Colors.orange.shade800;
    } else {
      icon = Icons.check_circle_outline;
      color = Colors.green.shade700;
    }

    final title = r.name.isEmpty ? '(no name)' : r.name;
    final details = <String>[
      if (!r.hasErrors) '₱${r.price.toStringAsFixed(r.price % 1 == 0 ? 0 : 2)}',
      if (!r.hasErrors) '${r.calories} kcal',
      if (r.mealTypes.isNotEmpty) r.mealTypes.join(', '),
      if (r.dietaryTags.isNotEmpty) r.dietaryTags.join(', '),
    ];
    final notes = <String>[
      ...r.errors,
      if (r.skipReason != null) r.skipReason!,
      ...r.warnings,
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Row ${r.rowNumber} · $title',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13.5)),
                if (details.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(details.join(' • '),
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.muted)),
                  ),
                for (final n in notes)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(n, style: TextStyle(fontSize: 12, color: color)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}