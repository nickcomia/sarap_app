/// Helpers for price ranges written as text, e.g. "₱200 – ₱1,240" or "₱400 – ₱3,850+".
///
/// Imported data is not always consistent ("₱15 - ₱100", "95 - ₱350", "₱50 -₱135"),
/// so parsing ignores the peso sign, commas, spaces and the kind of dash.
typedef PriceRange = ({int min, int max, bool openEnded});

/// Returns null when the text is not a "min - max" range (for example "₱₱").
PriceRange? parsePriceRange(String? text) {
  if (text == null) return null;
  final cleaned = text.replaceAll('₱', '').replaceAll(',', '').replaceAll(RegExp(r'\s+'), '');
  final m = RegExp(r'^(\d+)[-–—](\d+)(\+?)$').firstMatch(cleaned);
  if (m == null) return null;
  return (
    min: int.parse(m.group(1)!),
    max: int.parse(m.group(2)!),
    openEnded: m.group(3) == '+',
  );
}

String _withCommas(int n) {
  final s = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}

/// Always produces the same format: "₱200 – ₱1,240" (with "+" when open-ended).
String formatPriceRange(int min, int max, {bool openEnded = false}) =>
    '₱${_withCommas(min)} – ₱${_withCommas(max)}${openEnded ? '+' : ''}';