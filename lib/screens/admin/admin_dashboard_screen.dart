import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../theme.dart';
import '../../services/firebase_service.dart';
import '../../services/pdf_actions.dart';

/// Analytics dashboard for the administrator.
///
/// Descriptive analytics (what is happening): user growth, restaurant
/// coverage and ratings, popularity through saved places and reviews,
/// diner demand, and moderation activity.
/// Prescriptive analytics (what to do next): a rule-based "Insights" list
/// that turns those numbers into suggested actions for the administrator.
///
/// Everything here is a count or a total. No single diner is shown.
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

// ---------------------------------------------------------------------------
// Small data holders shared by the screen, the text report and the PDF
// ---------------------------------------------------------------------------

class _Kpi {
  final IconData icon;
  final String label;
  final String value;
  const _Kpi(this.icon, this.label, this.value);
}

class _Row {
  final String label;
  final num value; // bar length
  final String text; // shown at the end of the bar
  const _Row(this.label, this.value, this.text);
}

class _Chart {
  final String title;
  final List<_Row> rows;
  final String empty;
  const _Chart(this.title, this.rows, this.empty);
}

class _Group {
  final String title;
  final String subtitle;
  final List<_Kpi> kpis;
  final List<_Chart> charts;
  final List<String> notes; // e.g. "unavailable: check Firestore rules"
  const _Group(this.title, this.subtitle, this.kpis, this.charts,
      [this.notes = const []]);
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

  // ---------------------------------------------------------------
  // Reading the stats map
  // ---------------------------------------------------------------

  int _n(Map<String, dynamic> s, String k) => (s[k] as num?)?.toInt() ?? 0;

  List<MapEntry<String, int>> _entries(dynamic v) {
    return ((v as List?) ?? const []).map((e) {
      final m = e as Map;
      return MapEntry(m['name'].toString(), (m['count'] as num).toInt());
    }).toList();
  }

  List<_Row> _countRows(dynamic v) =>
      _entries(v).map((e) => _Row(e.key, e.value, '${e.value}')).toList();

  List<_Row> _ratingRows(dynamic v) {
    return ((v as List?) ?? const []).map((e) {
      final m = e as Map;
      final r = (m['rating'] as num).toDouble();
      return _Row(m['name'].toString(), r, r.toStringAsFixed(1));
    }).toList();
  }

  // ---------------------------------------------------------------
  // The dashboard content, grouped by what the administrator wants to know
  // ---------------------------------------------------------------

  List<_Group> _groups(Map<String, dynamic> s) {
    final profilesOk = s['profilesOk'] == true;
    final plansOk = s['plansOk'] == true;
    final reviewsOk = s['reviewsOk'] == true;
    final appealsOk = s['appealsOk'] == true;
    final actionsOk = s['actionsOk'] == true;
    final savedOk = s['savedOk'] == true;

    final profileCount = _n(s, 'profileCount');
    final onboarded = _n(s, 'onboardedCount');
    final rate = profileCount == 0 ? 0 : (onboarded * 100 / profileCount).round();
    final avgBudget = (s['avgBudget'] as num?)?.toDouble();
    final avgReview = (s['avgReviewRating'] as num?)?.toDouble();

    String dash(bool ok, String v) => ok ? v : '—';

    return [
      _Group(
        'Users & engagement',
        'How the diner base is growing and how much it uses the app.',
        [
          _Kpi(Icons.people_outline, 'Registered users', '${s['users']}'),
          _Kpi(Icons.person_add_alt_1_outlined, 'New users (7 days)',
              '${s['newUsers']}'),
          _Kpi(Icons.task_alt_outlined, 'Finished onboarding',
              dash(profilesOk, '$rate%')),
          _Kpi(Icons.calendar_month_outlined, 'Diners with a meal plan',
              dash(plansOk, '${s['usersWithPlan']}')),
          _Kpi(Icons.favorite_border, 'Saved places', '${s['totalSaves']}'),
          _Kpi(Icons.rate_review_outlined, 'Diners who reviewed',
              dash(reviewsOk, '${s['reviewers']}')),
        ],
        [
          _Chart('New users per week (last 8 weeks)', _countRows(s['signups']),
              'No sign-ups yet.'),
          _Chart('Health goals of diners', _countRows(s['goalMix']),
              'No diner has finished onboarding yet.'),
        ],
        [
          if (!profilesOk)
            'Diner profile numbers are unavailable. Publish the updated '
                'Firestore rules so admins can read "profiles".',
          if (!plansOk)
            'Meal plan counts are unavailable. Publish the updated Firestore '
                'rules so admins can read "mealPlan".',
        ],
      ),
      _Group(
        'Restaurant coverage & performance',
        'How many places are listed, how complete they are, and how they are rated.',
        [
          _Kpi(Icons.storefront_outlined, 'Restaurants', '${s['restaurants']}'),
          _Kpi(Icons.visibility_off_outlined, 'Hidden restaurants',
              '${s['hiddenRestaurants']}'),
          _Kpi(Icons.restaurant_menu, 'Menu items', '${s['menuItems']}'),
          _Kpi(Icons.star_outline, 'Average rating',
              (s['avgRating'] as num).toDouble().toStringAsFixed(1)),
          _Kpi(Icons.menu_book_outlined, 'Restaurants with no menu',
              '${s['noMenuCount']}'),
        ],
        [
          _Chart('Restaurants by type', _countRows(s['byType']),
              'No restaurants yet.'),
          _Chart('Restaurants by cuisine', _countRows(s['byCuisine']),
              'No restaurants yet.'),
          _Chart('Rating distribution', _countRows(s['ratingBuckets']),
              'No ratings yet.'),
          _Chart('Highest rated', _ratingRows(s['topRated']), 'No ratings yet.'),
          _Chart('Lowest rated', _ratingRows(s['lowRated']), 'No ratings yet.'),
        ],
      ),
      _Group(
        'Popularity',
        'Which places diners save and review. A save shows interest in a place.',
        [
          _Kpi(Icons.favorite_border, 'Total saves', '${s['totalSaves']}'),
          _Kpi(Icons.heart_broken_outlined, 'Restaurants never saved',
              dash(savedOk, '${s['noSaveCount']}')),
        ],
        [
          _Chart(
            'Most saved restaurants',
            _countRows(s['mostSaved']),
            savedOk
                ? 'No saved places yet.'
                : 'Saved-place counts are unavailable: your Firestore rules '
                    'must let admins read the "saved" collection group.',
          ),
          _Chart('Saves by cuisine', _countRows(s['savesByCuisine']),
              'No saved places yet.'),
          _Chart('Most reviewed restaurants', _countRows(s['mostReviewed']),
              reviewsOk ? 'No approved reviews yet.' : 'Review numbers are unavailable.'),
        ],
      ),
      _Group(
        'What diners ask for',
        'The preferences diners set in their profile, compared with what is listed.',
        [
          _Kpi(Icons.payments_outlined, 'Average budget per meal',
              avgBudget == null ? '—' : '₱${avgBudget.round()}'),
          _Kpi(Icons.groups_outlined, 'Diners counted', dash(profilesOk, '$onboarded')),
        ],
        [
          _Chart('Preferred cuisines (diners)', _countRows(s['demandCuisines']),
              'No cuisine preferences yet.'),
          _Chart('Dietary restrictions (diners)', _countRows(s['demandDiets']),
              'No dietary restrictions set yet.'),
        ],
        [
          if (!profilesOk)
            'Diner preference numbers are unavailable. Publish the updated '
                'Firestore rules so admins can read "profiles".',
        ],
      ),
      _Group(
        'Reviews & moderation',
        'Review queue status and how the penalty system is being used.',
        [
          _Kpi(Icons.pending_actions_outlined, 'Reviews waiting',
              dash(reviewsOk, '${s['reviewsPending']}')),
          _Kpi(Icons.check_circle_outline, 'Reviews approved',
              dash(reviewsOk, '${s['reviewsApproved']}')),
          _Kpi(Icons.cancel_outlined, 'Reviews rejected',
              dash(reviewsOk, '${s['reviewsRejected']}')),
          _Kpi(Icons.grade_outlined, 'Average review rating',
              avgReview == null ? '—' : avgReview.toStringAsFixed(1)),
          _Kpi(Icons.warning_amber_outlined, 'Users with strikes',
              '${s['usersWithStrikes']}'),
          _Kpi(Icons.timer_off_outlined, 'Banned right now', '${s['bannedNow']}'),
          _Kpi(Icons.block, 'Disabled accounts', '${s['disabledUsers']}'),
          _Kpi(Icons.forum_outlined, 'Appeals waiting',
              dash(appealsOk, '${s['appealsPending']}')),
        ],
        [
          _Chart('Moderation actions taken', _countRows(s['actionsByType']),
              actionsOk ? 'No moderation actions yet.' : 'Action log is unavailable.'),
          _Chart(
            'Appeals by decision',
            [
              _Row('Waiting', _n(s, 'appealsPending'), '${_n(s, 'appealsPending')}'),
              _Row('Approved', _n(s, 'appealsApproved'), '${_n(s, 'appealsApproved')}'),
              _Row('Rejected', _n(s, 'appealsRejected'), '${_n(s, 'appealsRejected')}'),
            ],
            'No appeals yet.',
          ),
        ],
        [
          if (!reviewsOk) 'Review numbers are unavailable. Check the Firestore rules for "reviews".',
          if (!appealsOk) 'Appeal numbers are unavailable. Check the Firestore rules for "appeals".',
        ],
      ),
    ];
  }

  // ---------------------------------------------------------------
  // Insights: fixed rules that turn the numbers into suggested actions
  // ---------------------------------------------------------------

  String _names(dynamic v) =>
      ((v as List?) ?? const []).take(3).map((e) => e.toString()).join(', ');

  List<String> _insights(Map<String, dynamic> s) {
    final out = <String>[];
    final restaurants = _n(s, 'restaurants');
    final onboarded = _n(s, 'onboardedCount');
    final profilesOk = s['profilesOk'] == true;

    // 1) Demand vs supply: cuisines
    if (profilesOk && onboarded >= 3 && restaurants > 0) {
      final supply = {
        for (final e in _entries(s['byCuisine'])) e.key.toLowerCase(): e.value
      };
      for (final d in _entries(s['demandCuisines']).take(3)) {
        final demandShare = d.value * 100 / onboarded;
        final supplyShare = (supply[d.key.toLowerCase()] ?? 0) * 100 / restaurants;
        if (demandShare - supplyShare >= 15) {
          out.add('${demandShare.round()}% of diners chose ${d.key}, but only '
              '${supplyShare.round()}% of the listings serve it. Consider adding '
              'more ${d.key} places.');
        }
      }

      // 2) Demand vs supply: dietary restrictions
      final tags = (s['tagSupply'] as Map?) ?? const {};
      for (final d in _entries(s['demandDiets']).take(3)) {
        final have = (tags[d.key.toLowerCase()] as num?)?.toInt() ?? 0;
        if (have < 3) {
          out.add('${d.value} of $onboarded diners set "${d.key}" as a dietary '
              'restriction, but only $have restaurants are tagged for it. Tag '
              'suitable restaurants or add some.');
        }
      }

      // 3) Onboarding drop-off
      final profileCount = _n(s, 'profileCount');
      final rate = profileCount == 0 ? 100 : onboarded * 100 / profileCount;
      if (profileCount >= 3 && rate < 80) {
        out.add('Only ${rate.round()}% of registered users finished onboarding. '
            'Without a finished profile they get weaker recommendations.');
      }
    }

    // 4) Visibility: places nobody saved
    if (s['savedOk'] == true && _n(s, 'noSaveCount') > 0) {
      out.add('${_n(s, 'noSaveCount')} restaurants have not been saved by anyone '
          '(for example ${_names(s['noSaveNames'])}). Improve their photos, '
          'description or menu to raise visibility.');
    }

    // 5) Incomplete listings
    if (_n(s, 'noMenuCount') > 0) {
      out.add('${_n(s, 'noMenuCount')} restaurants have no menu items '
          '(for example ${_names(s['noMenuNames'])}). Diners cannot plan meals '
          'from them until a menu is added.');
    }

    // 6) Satisfaction: weakest rated place
    final low = (s['lowRated'] as List?) ?? const [];
    if (low.isNotEmpty) {
      final m = low.first as Map;
      final r = (m['rating'] as num).toDouble();
      if (r < 3.5) {
        out.add('${m['name']} has the lowest rating (${r.toStringAsFixed(1)}). '
            'Check its details, menu and reviews.');
      }
    }

    // 7) Work waiting for the administrator
    if (s['reviewsOk'] == true && _n(s, 'reviewsPending') > 0) {
      out.add('${_n(s, 'reviewsPending')} reviews are waiting in the Review queue.');
    }
    if (s['appealsOk'] == true && _n(s, 'appealsPending') > 0) {
      out.add('${_n(s, 'appealsPending')} appeals are waiting for a decision.');
    }

    // 8) Growth
    if (_n(s, 'users') > 0 && _n(s, 'newUsers') == 0) {
      out.add('No new users signed up in the last 7 days. Consider promoting '
          'the app.');
    }

    if (out.isEmpty) {
      out.add('Nothing needs attention right now. Suggestions appear here as '
          'more diners and restaurants are added.');
    }
    return out;
  }

  // ---------------------------------------------------------------
  // Text report (copy)
  // ---------------------------------------------------------------

  String _reportText(Map<String, dynamic> s) {
    final b = StringBuffer();
    b.writeln('SARAP Admin Report');
    b.writeln('Generated: ${DateTime.now().toIso8601String()}');
    for (final g in _groups(s)) {
      b.writeln();
      b.writeln(g.title.toUpperCase());
      for (final k in g.kpis) {
        b.writeln('${k.label}: ${k.value}');
      }
      for (final c in g.charts) {
        b.writeln();
        b.writeln('${c.title}:');
        if (c.rows.isEmpty) {
          b.writeln('  ${c.empty}');
        } else {
          for (final r in c.rows) {
            b.writeln('  ${r.label}: ${r.text}');
          }
        }
      }
    }
    b.writeln();
    b.writeln('INSIGHTS & SUGGESTED ACTIONS');
    for (final i in _insights(s)) {
      b.writeln('- $i');
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

  static final _brand = PdfColor.fromHex('#FF6B4A');
  static final _brandLight = PdfColor.fromHex('#FFF1EC');
  static final _ink = PdfColor.fromHex('#1F2937');
  static final _muted = PdfColor.fromHex('#6B7280');
  static final _line = PdfColor.fromHex('#E5E7EB');
  static final _track = PdfColor.fromHex('#F3F4F6');

  pw.Widget _pdfGroupTitle(String text, String sub) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 18, bottom: 8),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(text,
                style: pw.TextStyle(
                    fontSize: 14, fontWeight: pw.FontWeight.bold, color: _brand)),
            if (sub.isNotEmpty)
              pw.Text(sub, style: pw.TextStyle(fontSize: 9, color: _muted)),
          ],
        ),
      );

  pw.Widget _pdfSectionTitle(String text) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 8),
        child: pw.Text(text,
            style: pw.TextStyle(
                fontSize: 11, fontWeight: pw.FontWeight.bold, color: _ink)),
      );

  pw.Widget _pdfKpi(_Kpi k) => pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            color: _brandLight,
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(k.value,
                  style: pw.TextStyle(
                      fontSize: 17,
                      fontWeight: pw.FontWeight.bold,
                      color: _brand)),
              pw.SizedBox(height: 2),
              pw.Text(k.label, style: pw.TextStyle(fontSize: 8.5, color: _muted)),
            ],
          ),
        ),
      );

  List<pw.Widget> _pdfKpiRows(List<_Kpi> kpis) {
    final rows = <pw.Widget>[];
    for (var i = 0; i < kpis.length; i += 4) {
      final chunk = kpis.skip(i).take(4).toList();
      rows.add(pw.Row(children: [
        for (var j = 0; j < 4; j++) ...[
          if (j > 0) pw.SizedBox(width: 8),
          j < chunk.length ? _pdfKpi(chunk[j]) : pw.Expanded(child: pw.SizedBox()),
        ],
      ]));
      rows.add(pw.SizedBox(height: 8));
    }
    return rows;
  }

  pw.Widget _pdfBars(_Chart c) {
    final maxValue = c.rows.isEmpty
        ? 1.0
        : c.rows.map((e) => e.value.toDouble()).reduce((a, b) => a > b ? a : b);
    const trackWidth = 220.0;
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 10),
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _line),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _pdfSectionTitle(c.title),
          if (c.rows.isEmpty)
            pw.Text(c.empty, style: pw.TextStyle(fontSize: 9, color: _muted))
          else
            for (final r in c.rows)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 6),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.SizedBox(
                      width: 150,
                      child: pw.Text(r.label,
                          maxLines: 1,
                          style: pw.TextStyle(fontSize: 9, color: _ink)),
                    ),
                    pw.Container(
                      width: trackWidth,
                      height: 7,
                      decoration: pw.BoxDecoration(
                        color: _track,
                        borderRadius: pw.BorderRadius.circular(4),
                      ),
                      child: pw.Align(
                        alignment: pw.Alignment.centerLeft,
                        child: pw.Container(
                          width: maxValue == 0
                              ? 0
                              : (trackWidth * r.value.toDouble() / maxValue),
                          height: 7,
                          decoration: pw.BoxDecoration(
                            color: _brand,
                            borderRadius: pw.BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                    pw.SizedBox(width: 8),
                    pw.Text(r.text,
                        style: pw.TextStyle(
                            fontSize: 9,
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

    final body = <pw.Widget>[
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
            pw.Text('Admin Analytics Report',
                style: pw.TextStyle(
                    fontSize: 24,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white)),
            pw.SizedBox(height: 4),
            pw.Text('Generated $generated',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.white)),
          ],
        ),
      ),
    ];

    for (final g in _groups(s)) {
      body.add(_pdfGroupTitle(g.title, g.subtitle));
      body.addAll(_pdfKpiRows(g.kpis));
      for (final c in g.charts) {
        body.add(_pdfBars(c));
      }
      for (final n in g.notes) {
        body.add(pw.Text(n, style: pw.TextStyle(fontSize: 8.5, color: _muted)));
      }
    }

    body.add(_pdfGroupTitle('Insights & suggested actions',
        'Rule-based suggestions generated from the numbers above.'));
    for (final i in _insights(s)) {
      body.add(pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 5),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('•  ', style: pw.TextStyle(fontSize: 10, color: _brand)),
            pw.Expanded(
                child: pw.Text(i, style: pw.TextStyle(fontSize: 10, color: _ink))),
          ],
        ),
      ));
    }

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
        build: (ctx) => body,
      ),
    );
    return doc.save();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _copyReport(Map<String, dynamic> s) async {
    await Clipboard.setData(ClipboardData(text: _reportText(s)));
    _snack('Report copied to clipboard');
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

  // ---------------------------------------------------------------
  // Screen
  // ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final s = _stats;
    final phone = MediaQuery.of(context).size.width < 600;
    final pad = phone ? 16.0 : 24.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard & reports'),
        actions: [
          IconButton(
            tooltip: 'Reload',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
          if (s != null && !phone) ...[
            IconButton(
              tooltip: 'Copy report',
              onPressed: () => _copyReport(s),
              icon: const Icon(Icons.copy_all_outlined),
            ),
            IconButton(
              tooltip: 'Print / Save as PDF',
              onPressed: () => _printReport(s),
              icon: const Icon(Icons.print_outlined),
            ),
            IconButton(
              tooltip: 'Download PDF',
              onPressed: () => _downloadPdf(s),
              icon: const Icon(Icons.picture_as_pdf_outlined),
            ),
          ],
          // On phones the three report actions share one menu.
          if (s != null && phone)
            PopupMenuButton<String>(
              tooltip: 'Report options',
              icon: const Icon(Icons.more_vert),
              onSelected: (v) {
                if (v == 'copy') _copyReport(s);
                if (v == 'print') _printReport(s);
                if (v == 'pdf') _downloadPdf(s);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'copy', child: Text('Copy report')),
                PopupMenuItem(value: 'print', child: Text('Print / Save as PDF')),
                PopupMenuItem(value: 'pdf', child: Text('Download PDF')),
              ],
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
                    constraints: const BoxConstraints(maxWidth: 1000),
                    child: ListView(
                      padding: EdgeInsets.all(pad),
                      children: [
                        for (final g in _groups(s)) _groupView(g),
                        _InsightsCard(items: _insights(s)),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _groupView(_Group g) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(g.title,
              style: const TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.navy)),
          const SizedBox(height: 3),
          Text(g.subtitle,
              style: const TextStyle(color: AppColors.muted, fontSize: 13)),
          const SizedBox(height: 14),
          LayoutBuilder(builder: (context, c) {
            // 2 cards per row on phones, 4 on wide screens.
            final cols = c.maxWidth >= 860 ? 4 : (c.maxWidth >= 560 ? 3 : 2);
            const gap = 12.0;
            final w = (c.maxWidth - gap * (cols - 1)) / cols;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final k in g.kpis)
                  SizedBox(
                    width: w,
                    child: _StatCard(icon: k.icon, label: k.label, value: k.value),
                  ),
              ],
            );
          }),
          for (final n in g.notes) ...[
            const SizedBox(height: 10),
            Text(n, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
          ],
          const SizedBox(height: 14),
          LayoutBuilder(builder: (context, c) {
            final twoCols = c.maxWidth >= 780;
            const gap = 14.0;
            final w = twoCols ? (c.maxWidth - gap) / 2 : c.maxWidth;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final ch in g.charts)
                  SizedBox(width: w, child: _BarSection(chart: ch)),
              ],
            );
          }),
        ],
      ),
    );
  }
}

/// Stat card. Lays out icon and text side by side when there is room, and
/// stacks them vertically on narrow (phone) cards so nothing overflows.
class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _StatCard({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final iconBox = Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: AppColors.chipSelectedBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: AppColors.primaryDark),
    );
    final texts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppShadows.soft,
      ),
      child: LayoutBuilder(builder: (context, c) {
        final stacked = c.maxWidth < 190;
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [iconBox, const SizedBox(height: 10), texts],
          );
        }
        return Row(
          children: [
            iconBox,
            const SizedBox(width: 12),
            Expanded(child: texts),
          ],
        );
      }),
    );
  }
}

class _BarSection extends StatelessWidget {
  final _Chart chart;
  const _BarSection({required this.chart});

  @override
  Widget build(BuildContext context) {
    final phone = MediaQuery.of(context).size.width < 600;
    final rows = chart.rows;
    final maxValue = rows.isEmpty
        ? 1.0
        : rows.map((e) => e.value.toDouble()).reduce((a, b) => a > b ? a : b);
    return Container(
      padding: EdgeInsets.all(phone ? 14 : 18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(chart.title,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 14),
          if (rows.isEmpty)
            Text(chart.empty,
                style: const TextStyle(color: AppColors.muted, fontSize: 13))
          else
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    SizedBox(
                      width: phone ? 96 : 140,
                      child: Text(r.label,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13)),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: maxValue == 0 ? 0 : r.value.toDouble() / maxValue,
                          minHeight: 12,
                          backgroundColor: AppColors.chipBg,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(r.text,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13)),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

/// The prescriptive part: suggested actions for the administrator.
class _InsightsCard extends StatelessWidget {
  final List<String> items;
  const _InsightsCard({required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.chipSelectedBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.lightbulb_outline, color: AppColors.primaryDark),
              SizedBox(width: 8),
              Expanded(
                child: Text('Insights & suggested actions',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                        color: AppColors.navy)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
              'Rule-based suggestions generated from the numbers above, not from AI.',
              style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
          const SizedBox(height: 12),
          for (final i in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(Icons.arrow_right_alt,
                        size: 20, color: AppColors.primaryDark),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(i,
                        style: const TextStyle(
                            color: AppColors.navy, fontSize: 13.5, height: 1.4)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}