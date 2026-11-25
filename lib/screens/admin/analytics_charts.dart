import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../theme.dart';

/// The four chart styles used by the admin analytics.
enum ChartKind { bars, columns, line, donut }

/// One data point: a label, a number that sets the size, and the text shown.
class ChartRow {
  final String label;
  final num value;
  final String text;
  const ChartRow(this.label, this.value, this.text);
}

const _palette = <Color>[
  Color(0xFFFF6B4A),
  Color(0xFF2F6FED),
  Color(0xFF22A06B),
  Color(0xFFF2B01E),
  Color(0xFF8B5CF6),
  Color(0xFF14B8A6),
  Color(0xFFEC4899),
  Color(0xFF94A3B8),
];

/// A white card with a title and one chart inside.
class ChartCard extends StatelessWidget {
  final String title;
  final List<ChartRow> rows;
  final String empty;
  final ChartKind kind;
  const ChartCard({
    super.key,
    required this.title,
    required this.rows,
    required this.empty,
    this.kind = ChartKind.bars,
  });

  @override
  Widget build(BuildContext context) {
    final phone = MediaQuery.of(context).size.width < 600;
    final nothing = rows.isEmpty ||
        ((kind == ChartKind.donut) && rows.every((r) => r.value <= 0));

    Widget body;
    if (nothing) {
      body = Text(empty,
          style: const TextStyle(color: AppColors.muted, fontSize: 13));
    } else {
      switch (kind) {
        case ChartKind.bars:
          body = _Bars(rows: rows.take(6).toList(), phone: phone);
          break;
        case ChartKind.columns:
          body = SizedBox(
            height: 200,
            width: double.infinity,
            child: CustomPaint(painter: _ColumnsPainter(rows)),
          );
          break;
        case ChartKind.line:
          body = SizedBox(
            height: 200,
            width: double.infinity,
            child: CustomPaint(painter: _LinePainter(rows)),
          );
          break;
        case ChartKind.donut:
          body = _Donut(rows: rows);
          break;
      }
    }

    return Container(
      padding: EdgeInsets.all(phone ? 14 : 18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: AppColors.navy)),
          const SizedBox(height: 16),
          body,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Horizontal bars
// ---------------------------------------------------------------------------

class _Bars extends StatelessWidget {
  final List<ChartRow> rows;
  final bool phone;
  const _Bars({required this.rows, required this.phone});

  @override
  Widget build(BuildContext context) {
    final maxValue =
        rows.map((e) => e.value.toDouble()).reduce((a, b) => a > b ? a : b);
    return Column(
      children: [
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
    );
  }
}

// ---------------------------------------------------------------------------
// Shared text helper for the painters
// ---------------------------------------------------------------------------

void _drawText(
  Canvas canvas,
  String text,
  double centerX,
  double y, {
  double size = 10,
  Color color = AppColors.muted,
  FontWeight weight = FontWeight.w500,
  double maxWidth = 60,
  bool anchorBottom = false,
}) {
  final tp = TextPainter(
    text: TextSpan(
        text: text,
        style: TextStyle(fontSize: size, color: color, fontWeight: weight)),
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
    maxLines: 2,
    ellipsis: '…',
  )..layout(maxWidth: maxWidth);
  tp.paint(canvas,
      Offset(centerX - tp.width / 2, anchorBottom ? y - tp.height : y));
}

double _maxOf(List<ChartRow> rows) {
  final m = rows.map((e) => e.value.toDouble()).fold<double>(0, math.max);
  return m <= 0 ? 1 : m;
}

// ---------------------------------------------------------------------------
// Vertical columns
// ---------------------------------------------------------------------------

class _ColumnsPainter extends CustomPainter {
  final List<ChartRow> rows;
  _ColumnsPainter(this.rows);

  @override
  void paint(Canvas canvas, Size size) {
    const top = 20.0, bottom = 38.0;
    final chartH = size.height - top - bottom;
    final maxV = _maxOf(rows);
    final slot = size.width / rows.length;

    final base = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, top + chartH), Offset(size.width, top + chartH), base);

    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      final h = chartH * (r.value.toDouble() / maxV);
      final left = slot * i + slot * 0.2;
      final rect = RRect.fromRectAndCorners(
        Rect.fromLTWH(left, top + chartH - h, slot * 0.6, h),
        topLeft: const Radius.circular(6),
        topRight: const Radius.circular(6),
      );
      canvas.drawRRect(rect, Paint()..color = _palette[0]);
      _drawText(canvas, r.text, slot * i + slot / 2, top + chartH - h - 2,
          size: 11,
          color: AppColors.navy,
          weight: FontWeight.w700,
          maxWidth: slot,
          anchorBottom: true);
      _drawText(canvas, r.label, slot * i + slot / 2, top + chartH + 6,
          maxWidth: slot - 4);
    }
  }

  @override
  bool shouldRepaint(covariant _ColumnsPainter old) => true;
}

// ---------------------------------------------------------------------------
// Line (trend over time)
// ---------------------------------------------------------------------------

class _LinePainter extends CustomPainter {
  final List<ChartRow> rows;
  _LinePainter(this.rows);

  @override
  void paint(Canvas canvas, Size size) {
    const top = 24.0, bottom = 34.0, pad = 18.0;
    final w = size.width - pad * 2;
    final chartH = size.height - top - bottom;
    final maxV = _maxOf(rows);
    final n = rows.length;

    final grid = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    for (var g = 0; g <= 2; g++) {
      final y = top + chartH * g / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    Offset point(int i) {
      final x = n == 1 ? pad + w / 2 : pad + w * i / (n - 1);
      final y = top + chartH - chartH * (rows[i].value.toDouble() / maxV);
      return Offset(x, y);
    }

    final line = Path()..moveTo(point(0).dx, point(0).dy);
    for (var i = 1; i < n; i++) {
      line.lineTo(point(i).dx, point(i).dy);
    }
    final area = Path.from(line)
      ..lineTo(point(n - 1).dx, top + chartH)
      ..lineTo(point(0).dx, top + chartH)
      ..close();
    canvas.drawPath(
        area, Paint()..color = AppColors.primary.withValues(alpha: 0.12));
    canvas.drawPath(
        line,
        Paint()
          ..color = AppColors.primary
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeJoin = StrokeJoin.round);

    final slot = n == 1 ? w : w / (n - 1);
    for (var i = 0; i < n; i++) {
      final p = point(i);
      canvas.drawCircle(p, 5, Paint()..color = Colors.white);
      canvas.drawCircle(p, 3.5, Paint()..color = AppColors.primary);
      _drawText(canvas, rows[i].text, p.dx, p.dy - 8,
          size: 11,
          color: AppColors.navy,
          weight: FontWeight.w700,
          maxWidth: 40,
          anchorBottom: true);
      _drawText(canvas, rows[i].label, p.dx, top + chartH + 8,
          size: 9.5, maxWidth: math.max(slot, 36));
    }
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) => true;
}

// ---------------------------------------------------------------------------
// Donut (share of a whole)
// ---------------------------------------------------------------------------

class _Donut extends StatelessWidget {
  final List<ChartRow> rows;
  const _Donut({required this.rows});

  @override
  Widget build(BuildContext context) {
    // Keep the 7 biggest slices and group the rest as "Other".
    final sorted = [...rows.where((r) => r.value > 0)]
      ..sort((a, b) => b.value.compareTo(a.value));
    final slices = <ChartRow>[];
    var otherSum = 0.0;
    for (var i = 0; i < sorted.length; i++) {
      if (i < 7 || sorted.length == 8) {
        slices.add(sorted[i]);
      } else {
        otherSum += sorted[i].value.toDouble();
      }
    }
    if (otherSum > 0) {
      slices.add(ChartRow('Other', otherSum, '${otherSum.round()}'));
    }
    final total = slices.fold<double>(0, (a, r) => a + r.value.toDouble());

    final ring = SizedBox(
      width: 130,
      height: 130,
      child: CustomPaint(painter: _DonutPainter(slices, total)),
    );

    final legend = Column(
      children: [
        for (var i = 0; i < slices.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _palette[i % _palette.length],
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(slices[i].label,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5)),
                ),
                Text(
                    '${slices[i].text}  (${(slices[i].value * 100 / total).round()}%)',
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
      ],
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [ring, const SizedBox(width: 18), Expanded(child: legend)],
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<ChartRow> slices;
  final double total;
  _DonutPainter(this.slices, this.total);

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 22.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - stroke / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    var start = -math.pi / 2;
    for (var i = 0; i < slices.length; i++) {
      var sweep = 2 * math.pi * slices[i].value.toDouble() / total;
      final gap = slices.length > 1 ? 0.03 : 0.0;
      canvas.drawArc(
        rect,
        start + gap / 2,
        math.max(sweep - gap, 0.001),
        false,
        Paint()
          ..color = _palette[i % _palette.length]
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke,
      );
      start += sweep;
    }

    _drawText(canvas, total.round().toString(), center.dx, center.dy - 14,
        size: 24, color: AppColors.navy, weight: FontWeight.w800, maxWidth: 80);
    _drawText(canvas, 'total', center.dx, center.dy + 12,
        size: 11, maxWidth: 80);
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) => true;
}