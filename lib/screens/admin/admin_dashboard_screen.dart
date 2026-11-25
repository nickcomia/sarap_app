import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../theme.dart';
import '../../services/firebase_service.dart';
import '../../services/pdf_actions.dart';
import 'analytics_charts.dart';

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
  final ChartKind kind; // how the chart is drawn on screen
  const _Chart(this.title, this.rows, this.empty, [this.kind = ChartKind.bars]);
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

    final activeUsers =
        _n(s, 'users') - _n(s, 'bannedNow') - _n(s, 'disabledUsers');

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
              'No sign-ups yet.', ChartKind.line),
          _Chart('Health goals of diners', _countRows(s['goalMix']),
              'No diner has finished onboarding yet.', ChartKind.donut),
          _Chart(
            'Account status',
            [
              _Row('Active', activeUsers, '$activeUsers'),
              _Row('Banned now', _n(s, 'bannedNow'), '${_n(s, 'bannedNow')}'),
              _Row('Disabled', _n(s, 'disabledUsers'),
                  '${_n(s, 'disabledUsers')}'),
            ],
            'No users yet.',
            ChartKind.donut,
          ),
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
              'No restaurants yet.', ChartKind.donut),
          _Chart('Restaurants by cuisine', _countRows(s['byCuisine']),
              'No restaurants yet.'),
          _Chart('Rating distribution', _countRows(s['ratingBuckets']),
              'No ratings yet.', ChartKind.columns),
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
          _Chart(
            'Reviews by status',
            [
              _Row('Approved', _n(s, 'reviewsApproved'),
                  '${_n(s, 'reviewsApproved')}'),
              _Row('Waiting', _n(s, 'reviewsPending'),
                  '${_n(s, 'reviewsPending')}'),
              _Row('Rejected', _n(s, 'reviewsRejected'),
                  '${_n(s, 'reviewsRejected')}'),
            ],
            reviewsOk ? 'No reviews yet.' : 'Review numbers are unavailable.',
            ChartKind.donut,
          ),
          _Chart('Moderation actions taken', _countRows(s['actionsByType']),
              actionsOk ? 'No moderation actions yet.' : 'Action log is unavailable.',
              ChartKind.donut),
          _Chart(
            'Appeals by decision',
            [
              _Row('Waiting', _n(s, 'appealsPending'), '${_n(s, 'appealsPending')}'),
              _Row('Approved', _n(s, 'appealsApproved'), '${_n(s, 'appealsApproved')}'),
              _Row('Rejected', _n(s, 'appealsRejected'), '${_n(s, 'appealsRejected')}'),
            ],
            'No appeals yet.',
            ChartKind.columns,
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
          padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: pw.BoxDecoration(
            color: PdfColors.white,
            border: pw.Border.all(color: _line),
            borderRadius: pw.BorderRadius.circular(10),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(k.value,
                  style: pw.TextStyle(
                      fontSize: 18, fontWeight: pw.FontWeight.bold, color: _ink)),
              pw.SizedBox(height: 2),
              pw.Text(k.label, style: pw.TextStyle(fontSize: 8.5, color: _muted)),
            ],
          ),
        ),
      );

  /// Same even-row rule as the on-screen cards (6 become 3 + 3, 8 become
  /// 4 + 4); a shorter last row stretches to the full width.
  List<pw.Widget> _pdfKpiRows(List<_Kpi> kpis) {
    final cols = _kpiCols(kpis.length, 900);
    final rows = <pw.Widget>[];
    for (var i = 0; i < kpis.length; i += cols) {
      final chunk = kpis.skip(i).take(cols).toList();
      rows.add(pw.Row(children: [
        for (var j = 0; j < chunk.length; j++) ...[
          if (j > 0) pw.SizedBox(width: 10),
          _pdfKpi(chunk[j]),
        ],
      ]));
      rows.add(pw.SizedBox(height: 10));
    }
    return rows;
  }

  /// Keeps its children on one page. A Table row is never split, so if the
  /// block does not fit in the space left, the whole block moves to the next
  /// page instead of being cut in half.
  pw.Widget _keep(List<pw.Widget> children) => pw.Table(
        columnWidths: {0: const pw.FlexColumnWidth()},
        children: [
          pw.TableRow(children: [
            pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: children),
          ]),
        ],
      );

  // -------------------------------------------------------------------
  // PDF charts: drawn the same way as on the dashboard (donut, line,
  // columns, bars), with the same colors.
  // -------------------------------------------------------------------

  static final List<PdfColor> _sliceColors = [
    PdfColor.fromHex('#FF6B4A'),
    PdfColor.fromHex('#2F6FED'),
    PdfColor.fromHex('#22A06B'),
    PdfColor.fromHex('#F2B01E'),
    PdfColor.fromHex('#8B5CF6'),
    PdfColor.fromHex('#14B8A6'),
    PdfColor.fromHex('#EC4899'),
    PdfColor.fromHex('#94A3B8'),
  ];
  static final _areaFill = PdfColor.fromHex('#FFEDE9');

  String _clip(String text, double width) {
    final max = (width / 4.8).floor();
    if (text.length <= max || max < 4) return text;
    return '${text.substring(0, max - 1)}…';
  }

  /// Rough height of a card, so the two cards in a row can be the same height.
  double _pdfChartHeight(_Chart c, double width) {
    const chrome = 46.0;
    if (c.rows.isEmpty) return chrome + 14;
    final n = c.rows.length;
    switch (c.kind) {
      case ChartKind.donut:
        return chrome +
            (width - 24 >= 330 ? math.max(120.0, 15.0 * n) : 132.0 + 15.0 * n);
      case ChartKind.line:
        return chrome + 140;
      case ChartKind.columns:
        return chrome + 122;
      default:
        return chrome + 17.0 * n;
    }
  }

  pw.Widget _pdfCard(_Chart c, double width, {double? minHeight}) {
    return pw.Container(
      width: width,
      constraints: pw.BoxConstraints(
          minHeight: minHeight ?? _pdfChartHeight(c, width)),
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border.all(color: _line),
        borderRadius: pw.BorderRadius.circular(10),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _pdfSectionTitle(c.title),
          _pdfChartBody(c, width - 24),
        ],
      ),
    );
  }

  pw.Widget _pdfChartBody(_Chart c, double w) {
    if (c.rows.isEmpty) {
      return pw.Text(c.empty, style: pw.TextStyle(fontSize: 9, color: _muted));
    }
    switch (c.kind) {
      case ChartKind.donut:
        return _pdfDonutBody(c, w);
      case ChartKind.line:
        return _pdfLineBody(c, w);
      case ChartKind.columns:
        return _pdfColumnsBody(c, w);
      default:
        return _pdfBarsBody(c, w);
    }
  }

  double _maxOf(_Chart c) {
    var m = 0.0;
    for (final r in c.rows) {
      if (r.value.toDouble() > m) m = r.value.toDouble();
    }
    return m <= 0 ? 1.0 : m;
  }

  pw.Widget _pdfBarsBody(_Chart c, double w) {
    final maxValue = _maxOf(c);
    final labelW = w >= 400 ? 165.0 : 100.0;
    final track = w - labelW - 8 - 28;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (final r in c.rows)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 6),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.SizedBox(
                  width: labelW,
                  child: pw.Text(_clip(r.label, labelW),
                      maxLines: 1, style: pw.TextStyle(fontSize: 9, color: _ink)),
                ),
                pw.Container(
                  width: track,
                  height: 7,
                  decoration: pw.BoxDecoration(
                    color: _track,
                    borderRadius: pw.BorderRadius.circular(3.5),
                  ),
                  // Zero draws nothing; any other value gets at least a dot.
                  child: r.value <= 0
                      ? null
                      : pw.Align(
                          alignment: pw.Alignment.centerLeft,
                          child: pw.Container(
                            width: (track * r.value.toDouble() / maxValue)
                                .clamp(7.0, track)
                                .toDouble(),
                            height: 7,
                            decoration: pw.BoxDecoration(
                              color: _brand,
                              borderRadius: pw.BorderRadius.circular(3.5),
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
    );
  }

  pw.Widget _pdfDonutBody(_Chart c, double w) {
    final total = c.rows.fold<double>(0, (a, r) => a + r.value.toDouble());
    final totalText = total == total.roundToDouble()
        ? '${total.round()}'
        : total.toStringAsFixed(1);
    final wide = w >= 330;
    final size = wide ? 120.0 : 110.0;

    final donut = pw.SizedBox(
      width: size,
      height: size,
      child: pw.Stack(
        alignment: pw.Alignment.center,
        children: [
          pw.CustomPaint(
            size: PdfPoint(size, size),
            painter: (PdfGraphics g, PdfPoint sz) {
              final cx = sz.x / 2, cy = sz.y / 2;
              final outer = sz.x / 2, inner = outer * 0.62;
              void ring(double from, double to, PdfColor color) {
                const step = math.pi / 60;
                final n = math.max(2, ((from - to) / step).ceil());
                g.setFillColor(color);
                for (var i = 0; i <= n; i++) {
                  final t = from + (to - from) * i / n;
                  final x = cx + outer * math.cos(t), y = cy + outer * math.sin(t);
                  i == 0 ? g.moveTo(x, y) : g.lineTo(x, y);
                }
                for (var i = n; i >= 0; i--) {
                  final t = from + (to - from) * i / n;
                  g.lineTo(cx + inner * math.cos(t), cy + inner * math.sin(t));
                }
                g.closePath();
                g.fillPath();
              }

              if (total <= 0) {
                ring(math.pi / 2, math.pi / 2 - 2 * math.pi + 0.0001, _track);
                return;
              }
              var start = math.pi / 2; // 12 o'clock, then clockwise
              for (var i = 0; i < c.rows.length; i++) {
                final v = c.rows[i].value.toDouble();
                if (v <= 0) continue;
                final sweep = 2 * math.pi * v / total;
                // a thin white gap between slices
                final gap = c.rows.length > 1 ? 0.012 : 0.0;
                ring(start - gap, start - sweep + gap,
                    _sliceColors[i % _sliceColors.length]);
                start -= sweep;
              }
            },
          ),
          pw.Column(
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.Text(totalText,
                  style: pw.TextStyle(
                      fontSize: 16, fontWeight: pw.FontWeight.bold, color: _ink)),
              pw.Text('total', style: pw.TextStyle(fontSize: 8, color: _muted)),
            ],
          ),
        ],
      ),
    );

    final legend = pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        for (var i = 0; i < c.rows.length; i++)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 5),
            child: pw.Row(
              children: [
                pw.Container(
                  width: 7,
                  height: 7,
                  decoration: pw.BoxDecoration(
                    color: _sliceColors[i % _sliceColors.length],
                    shape: pw.BoxShape.circle,
                  ),
                ),
                pw.SizedBox(width: 6),
                pw.Expanded(
                  child: pw.Text(c.rows[i].label,
                      maxLines: 1,
                      style: pw.TextStyle(fontSize: 9, color: _muted)),
                ),
                pw.SizedBox(width: 6),
                pw.Text(
                  total <= 0
                      ? c.rows[i].text
                      : '${c.rows[i].text} (${(c.rows[i].value.toDouble() * 100 / total).round()}%)',
                  style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                      color: _ink),
                ),
              ],
            ),
          ),
      ],
    );

    if (wide) {
      return pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          donut,
          pw.SizedBox(width: 26),
          pw.Expanded(child: legend),
        ],
      );
    }
    return pw.Column(
      children: [
        pw.Center(child: donut),
        pw.SizedBox(height: 12),
        legend,
      ],
    );
  }

  pw.Widget _pdfLineBody(_Chart c, double w) {
    const h = 124.0;
    const padX = 14.0, base = 4.0, top = h - 18;
    final n = c.rows.length;
    final maxV = _maxOf(c);
    final xs = <double>[
      for (var i = 0; i < n; i++)
        n == 1 ? w / 2 : padX + i * (w - 2 * padX) / (n - 1)
    ];
    final ys = <double>[
      for (final r in c.rows)
        base + (top - base) * (r.value.toDouble() <= 0 ? 0 : r.value.toDouble() / maxV)
    ];

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: w,
          height: h,
          child: pw.Stack(
            children: [
              pw.CustomPaint(
                size: PdfPoint(w, h),
                painter: (PdfGraphics g, PdfPoint sz) {
                  g.setStrokeColor(_line);
                  g.setLineWidth(0.6);
                  g.moveTo(0, base);
                  g.lineTo(sz.x, base);
                  g.strokePath();

                  if (n > 1) {
                    g.setFillColor(_areaFill);
                    g.moveTo(xs.first, base);
                    for (var i = 0; i < n; i++) {
                      g.lineTo(xs[i], ys[i]);
                    }
                    g.lineTo(xs.last, base);
                    g.closePath();
                    g.fillPath();

                    g.setStrokeColor(_brand);
                    g.setLineWidth(1.6);
                    g.moveTo(xs[0], ys[0]);
                    for (var i = 1; i < n; i++) {
                      g.lineTo(xs[i], ys[i]);
                    }
                    g.strokePath();
                  }
                  g.setFillColor(_brand);
                  for (var i = 0; i < n; i++) {
                    g.drawEllipse(xs[i], ys[i], 2.6, 2.6);
                    g.fillPath();
                  }
                },
              ),
              for (var i = 0; i < n; i++)
                pw.Positioned(
                  left: xs[i] - 12,
                  bottom: ys[i] + 5,
                  child: pw.SizedBox(
                    width: 24,
                    child: pw.Text(c.rows[i].text,
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                            color: _ink)),
                  ),
                ),
            ],
          ),
        ),
        pw.SizedBox(
          width: w,
          height: 14,
          child: pw.Stack(
            children: [
              for (var i = 0; i < n; i++)
                pw.Positioned(
                  left: xs[i] - 16,
                  top: 3,
                  child: pw.SizedBox(
                    width: 32,
                    child: pw.Text(c.rows[i].label,
                        maxLines: 1,
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(fontSize: 7, color: _muted)),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  pw.Widget _pdfColumnsBody(_Chart c, double w) {
    const h = 100.0, maxBar = 80.0;
    final n = c.rows.length;
    final slot = w / n;
    final barW = math.min(slot * 0.6, 34.0);
    final maxV = _maxOf(c);
    double barH(_Row r) =>
        r.value.toDouble() <= 0 ? 0 : math.max(2.0, maxBar * r.value.toDouble() / maxV);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: w,
          height: h,
          child: pw.Stack(
            children: [
              pw.CustomPaint(
                size: PdfPoint(w, h),
                painter: (PdfGraphics g, PdfPoint sz) {
                  g.setStrokeColor(_line);
                  g.setLineWidth(0.6);
                  g.moveTo(0, 0.3);
                  g.lineTo(sz.x, 0.3);
                  g.strokePath();
                  g.setFillColor(_brand);
                  for (var i = 0; i < n; i++) {
                    final bh = barH(c.rows[i]);
                    if (bh <= 0) continue;
                    g.drawRRect(slot * i + (slot - barW) / 2, 0.6, barW, bh, 3, 3);
                    g.fillPath();
                  }
                },
              ),
              for (var i = 0; i < n; i++)
                pw.Positioned(
                  left: slot * i + slot / 2 - 14,
                  bottom: barH(c.rows[i]) + 4,
                  child: pw.SizedBox(
                    width: 28,
                    child: pw.Text(c.rows[i].text,
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                            color: _ink)),
                  ),
                ),
            ],
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            for (final r in c.rows)
              pw.SizedBox(
                width: slot,
                child: pw.Text(r.label,
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(fontSize: 7.5, color: _muted)),
              ),
          ],
        ),
      ],
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

    final contentWidth = format.width - 80;
    const gap = 12.0;
    final half = (contentWidth - gap) / 2;
    for (final g in _groups(s)) {
      // Heading, number tiles and the first row of charts stay together, so a
      // heading is never left alone at the bottom of a page.
      final head = <pw.Widget>[
        _pdfGroupTitle(g.title, g.subtitle),
        ..._pdfKpiRows(g.kpis),
        for (final n in g.notes)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 8),
            child: pw.Text(n, style: pw.TextStyle(fontSize: 8.5, color: _muted)),
          ),
      ];
      // Charts two per row, like the dashboard; a lone last chart is full width.
      final chartRows = <pw.Widget>[];
      for (var i = 0; i < g.charts.length; i += 2) {
        final a = g.charts[i];
        final b = i + 1 < g.charts.length ? g.charts[i + 1] : null;
        chartRows.add(pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: gap),
          child: b == null
              ? _pdfCard(a, contentWidth)
              : pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _pdfCard(a, half,
                        minHeight: math.max(
                            _pdfChartHeight(a, half), _pdfChartHeight(b, half))),
                    pw.SizedBox(width: gap),
                    _pdfCard(b, half,
                        minHeight: math.max(
                            _pdfChartHeight(a, half), _pdfChartHeight(b, half))),
                  ],
                ),
        ));
      }
      if (chartRows.isEmpty) {
        body.add(_keep(head));
      } else {
        body.add(_keep([...head, chartRows.first]));
        for (final r in chartRows.skip(1)) {
          body.add(_keep([r]));
        }
      }
    }

    final insights = _insights(s);
    pw.Widget bullet(String i) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 5),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('•  ', style: pw.TextStyle(fontSize: 10, color: _brand)),
              pw.Expanded(
                  child: pw.Text(i, style: pw.TextStyle(fontSize: 10, color: _ink))),
            ],
          ),
        );
    body.add(_keep([
      _pdfGroupTitle('Insights & suggested actions',
          'Rule-based suggestions generated from the numbers above.'),
      for (final i in insights.take(2)) bullet(i),
    ]));
    for (final i in insights.skip(2)) {
      body.add(bullet(i));
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

  static const _tabNames = [
    'Users',
    'Restaurants',
    'Popularity',
    'Diner demand',
    'Moderation',
    'Insights',
  ];

  @override
  Widget build(BuildContext context) {
    final s = _stats;
    final phone = MediaQuery.of(context).size.width < 600;

    return DefaultTabController(
      length: _tabNames.length,
      child: Scaffold(
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
                  PopupMenuItem(
                      value: 'print', child: Text('Print / Save as PDF')),
                  PopupMenuItem(value: 'pdf', child: Text('Download PDF')),
                ],
              ),
          ],
          bottom: s == null
              ? null
              : TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [for (final t in _tabNames) Tab(text: t)],
                ),
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
                : TabBarView(
                    children: [
                      for (final g in _groups(s)) _page(_groupView(g)),
                      _page(_InsightsCard(items: _insights(s))),
                    ],
                  ),
      ),
    );
  }

  /// One tab: centered, scrollable, with a comfortable maximum width.
  Widget _page(Widget child) {
    final phone = MediaQuery.of(context).size.width < 600;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: ListView(
          padding: EdgeInsets.fromLTRB(
              phone ? 16 : 24, phone ? 18 : 24, phone ? 16 : 24, 40),
          children: [child],
        ),
      ),
    );
  }

  Widget _groupView(_Group g) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(g.title,
            style: const TextStyle(
                fontWeight: FontWeight.w800, fontSize: 20, color: AppColors.navy)),
        const SizedBox(height: 4),
        Text(g.subtitle,
            style: const TextStyle(color: AppColors.muted, fontSize: 13.5)),
        const SizedBox(height: 20),
        LayoutBuilder(builder: (context, c) => _kpiGrid(g.kpis, c.maxWidth)),
        for (final n in g.notes) ...[
          const SizedBox(height: 10),
          Text(n, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
        ],
        const SizedBox(height: 24),
        LayoutBuilder(builder: (context, c) => _chartGrid(g.charts, c.maxWidth)),
      ],
    );
  }

  /// Picks how many number cards go in a row so the last row is never a lone
  /// orphan card (6 cards become 3 + 3, 8 become 4 + 4).
  int _kpiCols(int n, double width) {
    final maxCols = width >= 860 ? 4 : (width >= 560 ? 3 : 2);
    if (n <= maxCols) return n < 1 ? 1 : n;
    var best = maxCols;
    var bestLast = n % maxCols == 0 ? maxCols : n % maxCols;
    for (var c = maxCols - 1; c >= 2; c--) {
      final last = n % c == 0 ? c : n % c;
      if (last > bestLast) {
        best = c;
        bestLast = last;
      }
    }
    return best;
  }

  /// Number cards in even rows; a shorter last row stretches to full width.
  Widget _kpiGrid(List<_Kpi> kpis, double width) {
    const gap = 12.0;
    final cols = _kpiCols(kpis.length, width);
    final rows = <Widget>[];
    for (var i = 0; i < kpis.length; i += cols) {
      final chunk = kpis.skip(i).take(cols).toList();
      rows.add(Padding(
        padding: EdgeInsets.only(top: i == 0 ? 0 : gap),
        child: Row(
          children: [
            for (var j = 0; j < chunk.length; j++) ...[
              if (j > 0) const SizedBox(width: gap),
              Expanded(
                child: _StatCard(
                    icon: chunk[j].icon,
                    label: chunk[j].label,
                    value: chunk[j].value),
              ),
            ],
          ],
        ),
      ));
    }
    return Column(children: rows);
  }

  Widget _chartCard(_Chart ch) => ChartCard(
        title: ch.title,
        kind: ch.kind,
        empty: ch.empty,
        rows: [for (final r in ch.rows) ChartRow(r.label, r.value, r.text)],
      );

  /// Charts two per row on wide screens, each pair the same height; one per
  /// row on narrow screens. A lone last chart spans the full width.
  Widget _chartGrid(List<_Chart> charts, double width) {
    const gap = 14.0;
    if (width < 780) {
      return Column(children: [
        for (final ch in charts)
          Padding(
              padding: const EdgeInsets.only(bottom: gap), child: _chartCard(ch)),
      ]);
    }
    final rows = <Widget>[];
    for (var i = 0; i < charts.length; i += 2) {
      final b = i + 1 < charts.length ? charts[i + 1] : null;
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: gap),
        child: b == null
            ? _chartCard(charts[i])
            : IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _chartCard(charts[i])),
                    const SizedBox(width: gap),
                    Expanded(child: _chartCard(b)),
                  ],
                ),
              ),
      ));
    }
    return Column(children: rows);
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