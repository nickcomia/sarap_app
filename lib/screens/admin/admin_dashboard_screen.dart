import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../theme.dart';
import '../../services/firebase_service.dart';
import '../../services/pdf_actions.dart';

/// Engagement dashboard: headline numbers, simple bar charts, and a
/// copyable text report.
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  Map<String, dynamic>? _stats;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _stats = null;
      _error = null;
    });
    try {
      final s = await FirebaseService.fetchDashboardStats();
      if (mounted) setState(() => _stats = s);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  List<MapEntry<String, int>> _entries(dynamic v) {
    return (v as List).map((e) {
      final m = e as Map;
      return MapEntry(m['name'].toString(), m['count'] as int);
    }).toList();
  }

  String _reportText(Map<String, dynamic> s) {
    final b = StringBuffer();
    b.writeln('SARAP Admin Report');
    b.writeln('Generated: ${DateTime.now().toIso8601String()}');
    b.writeln();
    b.writeln('Registered users: ${s['users']}');
    b.writeln('New users (last 7 days): ${s['newUsers']}');
    b.writeln('Restaurants: ${s['restaurants']} (hidden: ${s['hiddenRestaurants']})');
    b.writeln('Menu items: ${s['menuItems']}');
    b.writeln('Average restaurant rating: ${(s['avgRating'] as double).toStringAsFixed(2)}');
    b.writeln('Total saved places: ${s['totalSaves']}');
    b.writeln();
    b.writeln('Most saved restaurants:');
    for (final e in _entries(s['mostSaved'])) {
      b.writeln('  ${e.key}: ${e.value}');
    }
    b.writeln();
    b.writeln('Restaurants by type:');
    for (final e in _entries(s['byType'])) {
      b.writeln('  ${e.key}: ${e.value}');
    }
    return b.toString();
  }

  // ---------------------------------------------------------------
  // PDF report (print dialog / "Save as PDF" / download)
  // ---------------------------------------------------------------

  String _pdfName() {
    final d = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return 'SARAP-report-${d.year}-${two(d.month)}-${two(d.day)}.pdf';
  }

  // PDF palette
  static final _brand = PdfColor.fromHex('#FF6B4A');
  static final _brandLight = PdfColor.fromHex('#FFF1EC');
  static final _ink = PdfColor.fromHex('#1F2937');
  static final _muted = PdfColor.fromHex('#6B7280');
  static final _line = PdfColor.fromHex('#E5E7EB');
  static final _track = PdfColor.fromHex('#F3F4F6');

  pw.Widget _pdfSectionTitle(String text) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 10),
        child: pw.Text(text,
            style: pw.TextStyle(
                fontSize: 13, fontWeight: pw.FontWeight.bold, color: _ink)),
      );

  pw.Widget _pdfKpi(String label, String value) => pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            color: _brandLight,
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(value,
                  style: pw.TextStyle(
                      fontSize: 20,
                      fontWeight: pw.FontWeight.bold,
                      color: _brand)),
              pw.SizedBox(height: 3),
              pw.Text(label, style: pw.TextStyle(fontSize: 9, color: _muted)),
            ],
          ),
        ),
      );

  pw.Widget _pdfBars(String title, List<MapEntry<String, int>> rows, String empty) {
    final maxValue =
        rows.isEmpty ? 1 : rows.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    const trackWidth = 230.0;
    return pw.Container(
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _line),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _pdfSectionTitle(title),
          if (rows.isEmpty)
            pw.Text(empty, style: pw.TextStyle(fontSize: 10, color: _muted))
          else
            for (final r in rows)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 8),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.SizedBox(
                      width: 140,
                      child: pw.Text(r.key,
                          maxLines: 1,
                          style: pw.TextStyle(fontSize: 10, color: _ink)),
                    ),
                    pw.Container(
                      width: trackWidth,
                      height: 8,
                      decoration: pw.BoxDecoration(
                        color: _track,
                        borderRadius: pw.BorderRadius.circular(4),
                      ),
                      child: pw.Align(
                        alignment: pw.Alignment.centerLeft,
                        child: pw.Container(
                          width: maxValue == 0
                              ? 0
                              : (trackWidth * r.value / maxValue).toDouble(),
                          height: 8,
                          decoration: pw.BoxDecoration(
                            color: _brand,
                            borderRadius: pw.BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                    pw.SizedBox(width: 10),
                    pw.Text('${r.value}',
                        style: pw.TextStyle(
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                            color: _ink)),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Future<Uint8List> _buildPdf(Map<String, dynamic> s, PdfPageFormat format) async {
    // Roboto supports accents (Café, Karinderyá). Falls back to the built-in
    // font if the font cannot be downloaded.
    pw.ThemeData theme = pw.ThemeData();
    try {
      final base = await PdfGoogleFonts.robotoRegular();
      final bold = await PdfGoogleFonts.robotoBold();
      theme = pw.ThemeData.withFont(base: base, bold: bold);
    } catch (_) {}

    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June', 'July',
      'August', 'September', 'October', 'November', 'December'
    ];
    final generated =
        '${months[now.month - 1]} ${now.day}, ${now.year} at ${two(now.hour)}:${two(now.minute)}';

    final doc = pw.Document(
      theme: theme,
      title: 'SARAP Admin Report',
      author: 'SARAP',
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: format,
        margin: const pw.EdgeInsets.fromLTRB(40, 36, 40, 40),
        footer: (ctx) => pw.Column(
          children: [
            pw.Divider(color: _line, thickness: 0.8),
            pw.SizedBox(height: 4),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('SARAP Admin Report  |  Confidential',
                    style: pw.TextStyle(fontSize: 8, color: _muted)),
                pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}',
                    style: pw.TextStyle(fontSize: 8, color: _muted)),
              ],
            ),
          ],
        ),
        build: (ctx) => [
          // Header band
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(horizontal: 22, vertical: 20),
            decoration: pw.BoxDecoration(
              color: _brand,
              borderRadius: pw.BorderRadius.circular(10),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('SARAP',
                    style: pw.TextStyle(
                        fontSize: 11,
                        letterSpacing: 2,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white)),
                pw.SizedBox(height: 6),
                pw.Text('Admin Engagement Report',
                    style: pw.TextStyle(
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white)),
                pw.SizedBox(height: 4),
                pw.Text('Generated $generated',
                    style: const pw.TextStyle(
                        fontSize: 10, color: PdfColors.white)),
              ],
            ),
          ),
          pw.SizedBox(height: 22),

          // Key figures
          _pdfSectionTitle('Key figures'),
          pw.Row(children: [
            _pdfKpi('Registered users', '${s['users']}'),
            pw.SizedBox(width: 10),
            _pdfKpi('New users (7 days)', '${s['newUsers']}'),
            pw.SizedBox(width: 10),
            _pdfKpi('Restaurants', '${s['restaurants']}'),
            pw.SizedBox(width: 10),
            _pdfKpi('Menu items', '${s['menuItems']}'),
          ]),
          pw.SizedBox(height: 10),
          pw.Row(children: [
            _pdfKpi('Average rating',
                (s['avgRating'] as double).toStringAsFixed(2)),
            pw.SizedBox(width: 10),
            _pdfKpi('Saved places', '${s['totalSaves']}'),
            pw.SizedBox(width: 10),
            _pdfKpi('Hidden restaurants', '${s['hiddenRestaurants']}'),
            pw.SizedBox(width: 10),
            pw.Expanded(child: pw.SizedBox()),
          ]),
          pw.SizedBox(height: 24),

          // Charts
          _pdfBars(
            'Most saved restaurants',
            _entries(s['mostSaved']),
            s['savedOk'] == true
                ? 'No saved places yet.'
                : 'Saved-place counts were unavailable (Firestore rules).',
          ),
          pw.SizedBox(height: 16),
          _pdfBars('Restaurants by type', _entries(s['byType']),
              'No restaurants yet.'),
        ],
      ),
    );
    return doc.save();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Opens the PDF so it can be printed / saved.
  Future<void> _printReport(Map<String, dynamic> s) async {
    try {
      final bytes = await _buildPdf(s, PdfPageFormat.a4);
      await printPdfBytes(bytes, _pdfName());
    } catch (e) {
      _snack('Could not open the print dialog: $e');
    }
  }

  /// Saves the report straight to a PDF file.
  Future<void> _downloadPdf(Map<String, dynamic> s) async {
    try {
      final bytes = await _buildPdf(s, PdfPageFormat.a4);
      await downloadPdfBytes(bytes, _pdfName());
    } catch (e) {
      _snack('Could not create the PDF: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _stats;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard & reports'),
        actions: [
          IconButton(
            tooltip: 'Reload',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
          if (s != null)
            IconButton(
              tooltip: 'Copy report',
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: _reportText(s)));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Report copied to clipboard')),
                  );
                }
              },
              icon: const Icon(Icons.copy_all_outlined),
            ),
          if (s != null)
            IconButton(
              tooltip: 'Print / Save as PDF',
              onPressed: () => _printReport(s),
              icon: const Icon(Icons.print_outlined),
            ),
          if (s != null)
            IconButton(
              tooltip: 'Download PDF',
              onPressed: () => _downloadPdf(s),
              icon: const Icon(Icons.picture_as_pdf_outlined),
            ),
        ],
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Could not load the dashboard: $_error',
                    textAlign: TextAlign.center),
              ),
            )
          : s == null
              ? const Center(child: CircularProgressIndicator())
              : Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            _StatCard(
                                icon: Icons.people_outline,
                                label: 'Registered users',
                                value: '${s['users']}'),
                            _StatCard(
                                icon: Icons.person_add_alt_1_outlined,
                                label: 'New users (7 days)',
                                value: '${s['newUsers']}'),
                            _StatCard(
                                icon: Icons.storefront_outlined,
                                label: 'Restaurants',
                                value: '${s['restaurants']}'),
                            _StatCard(
                                icon: Icons.restaurant_menu,
                                label: 'Menu items',
                                value: '${s['menuItems']}'),
                            _StatCard(
                                icon: Icons.star_outline,
                                label: 'Average rating',
                                value: (s['avgRating'] as double).toStringAsFixed(1)),
                            _StatCard(
                                icon: Icons.favorite_border,
                                label: 'Saved places',
                                value: '${s['totalSaves']}'),
                            _StatCard(
                                icon: Icons.visibility_off_outlined,
                                label: 'Hidden restaurants',
                                value: '${s['hiddenRestaurants']}'),
                          ],
                        ),
                        const SizedBox(height: 20),
                        _BarSection(
                          title: 'Most saved restaurants',
                          rows: _entries(s['mostSaved']),
                          empty: s['savedOk'] == true
                              ? 'No saved places yet.'
                              : 'Saved-place counts are unavailable: your Firestore rules '
                                  'must let admins read the "saved" collection group.',
                        ),
                        const SizedBox(height: 16),
                        _BarSection(
                          title: 'Restaurants by type',
                          rows: _entries(s['byType']),
                          empty: 'No restaurants yet.',
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _StatCard({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 210,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppShadows.soft,
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.chipSelectedBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.primaryDark),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
                const SizedBox(height: 2),
                Text(label,
                    style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BarSection extends StatelessWidget {
  final String title;
  final List<MapEntry<String, int>> rows;
  final String empty;
  const _BarSection({required this.title, required this.rows, required this.empty});

  @override
  Widget build(BuildContext context) {
    final maxValue = rows.isEmpty ? 1 : rows.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 14),
          if (rows.isEmpty)
            Text(empty, style: const TextStyle(color: AppColors.muted, fontSize: 13))
          else
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 160,
                      child: Text(r.key,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13)),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: maxValue == 0 ? 0 : r.value / maxValue,
                          minHeight: 12,
                          backgroundColor: AppColors.chipBg,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text('${r.value}',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}