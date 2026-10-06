/// A bundled reference table of approximate calorie values for common
/// Filipino dishes, based on figures published in the FNRI (Food and
/// Nutrition Research Institute, Philippines) Philippine Food
/// Composition Tables and general WHO dietary energy reference
/// guidance. Values are per typical single serving.
///
/// This isn't a live API (none exists publicly for this), but a
/// bundled reference used to suggest realistic calorie values when
/// adding a menu item in the admin screen — so entries aren't just
/// guessed from scratch, and stay consistent with published nutrition
/// data for the same dish across different restaurants.
///
/// Matching is fuzzy (case-insensitive substring) so "Chicken Adobo"
/// and "adobo rice" both find the "adobo" reference entry.
class FoodCompositionReference {
  static const Map<String, int> _referenceCalories = {
    // Breakfast / silog meals
    'tapsilog': 480,
    'tocilog': 520,
    'longsilog': 500,
    'hotsilog': 460,
    'bangsilog': 470,
    'spamsilog': 540,
    'champorado': 260,
    'pandesal': 90,
    'ensaymada': 300,
    'taho': 180,
    'daing na bangus': 310,
    'longganisa': 280,

    // Rice meals / ulam
    'adobo': 400,
    'sinigang': 250,
    'tinola': 220,
    'kare-kare': 480,
    'sisig': 460,
    'bicol express': 420,
    'menudo': 380,
    'caldereta': 430,
    'afritada': 400,
    'pinakbet': 180,
    'lechon kawali': 520,
    'crispy pata': 600,
    'dinuguan': 380,
    'bulalo': 350,
    'nilaga': 300,
    'paksiw': 280,
    'chicken curry': 400,
    'beef curry': 430,
    'pork steak': 420,
    'chicken inasal': 380,
    'fried chicken': 450,
    'grilled chicken': 320,
    'grilled bangus': 280,
    'grilled tilapia': 260,
    'pancit': 350,
    'lumpia': 220,
    'fresh lumpia': 150,

    // Rice / staples
    'plain rice': 200,
    'garlic rice': 240,

    // Merienda / snacks
    'banana cue': 180,
    'turon': 200,
    'kwek-kwek': 250,
    'fish ball': 150,
    'squid ball': 160,
    'isaw': 120,
    'siomai': 200,
    'empanada': 280,

    // Western / fusion
    'burger': 550,
    'steak': 480,
    'pasta': 420,
    'spaghetti': 400,
    'pizza slice': 285,
    'fried rice': 350,
    'satay': 220,

    // Bakery / drinks
    'coffee': 5,
    'iced coffee': 120,
    'milk tea': 320,
    'fruit shake': 220,
    'halo-halo': 350,

    // Salads / healthy options
    'salad bowl': 280,
    'chicken salad': 320,
    'fruit bowl': 150,
  };

  /// Returns a suggested calorie estimate for [dishName] if a reference
  /// entry matches (fuzzy substring match, case-insensitive), or null
  /// if nothing in the table matches closely enough to suggest.
  static int? suggestCalories(String dishName) {
    final query = dishName.toLowerCase().trim();
    if (query.isEmpty) return null;

    // Exact match first.
    if (_referenceCalories.containsKey(query)) return _referenceCalories[query];

    // Fuzzy: does the dish name contain a reference key, or vice versa?
    for (final entry in _referenceCalories.entries) {
      if (query.contains(entry.key) || entry.key.contains(query)) {
        return entry.value;
      }
    }
    return null;
  }
}
