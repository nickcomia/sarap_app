/// Checks review text for hateful, abusive or profane language.
///
/// Handles repeated letters ("tangaaa"), simple symbol swaps ("g4g0"),
/// dots/dashes between letters ("t.a.n.g.a") and whole words only, so
/// "putahe" or "class" are not flagged. It cannot catch everything, which
/// is why an admin still reads every review before it goes public.
class FilterResult {
  final bool blocked;
  final String? term;
  const FilterResult.clean()
      : blocked = false,
        term = null;
  const FilterResult.blocked(this.term) : blocked = true;
}

class ContentFilter {
  ContentFilter._();

  /// Starter list. Extend it with more slurs and local insults over time.
  static const List<String> _terms = [
    // English profanity / abuse
    'fuck', 'fucking', 'fucker', 'motherfucker', 'shit', 'shitty',
    'bullshit', 'bitch', 'bitches', 'asshole', 'bastard', 'dickhead',
    'cunt', 'slut', 'whore',
    // Hate terms
    'nigger', 'nigga', 'faggot', 'retard', 'retarded', 'tranny', 'chink',
    // Filipino / Taglish
    'putangina', 'putang ina', 'tangina', 'tang ina', 'puta', 'gago',
    'gaga', 'ulol', 'bobo', 'tanga', 'punyeta', 'pakshet', 'tarantado',
    'siraulo', 'pokpok', 'hinayupak', 'kupal',
  ];

  static const Map<String, String> _leet = {
    '@': 'a',
    '0': 'o',
    '1': 'i',
    '3': 'e',
    '\$': 's',
    '5': 's',
    '4': 'a',
    '7': 't',
  };

  static final List<MapEntry<String, RegExp>> _patterns = [
    for (final t in _terms) MapEntry(t, _buildPattern(t)),
  ];

  static RegExp _buildPattern(String term) {
    const sep = r'[.\-_]?';
    final pieces = <String>[];
    for (final ch in term.split('')) {
      pieces.add(ch == ' ' ? r'[\s.\-_]*' : '$ch+');
    }
    return RegExp('(?<![a-z0-9])${pieces.join(sep)}(?![a-z0-9])');
  }

  static String _normalize(String input) {
    final b = StringBuffer();
    for (final ch in input.toLowerCase().split('')) {
      b.write(_leet[ch] ?? ch);
    }
    return b.toString();
  }

  static FilterResult check(String text) {
    final normalized = _normalize(text);
    for (final p in _patterns) {
      if (p.value.hasMatch(normalized)) return FilterResult.blocked(p.key);
    }
    return const FilterResult.clean();
  }
}