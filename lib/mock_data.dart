import 'dart:math';
import 'models.dart';

/// Sample local data standing in for the AI recommendation engine / GIS
/// backend described in the manuscript. Everything here is fictional
/// but modeled after "everyday diner" spots around Tanauan City.
class MockData {
  static List<Restaurant> restaurants() => [
        Restaurant(
          id: 'r1',
          name: "Aling Nena's Karinderyá",
          type: 'Karinderyá',
          cuisine: 'Filipino',
          distanceKm: 0.6,
          matchPercent: 96,
          priceRange: '₱',
          rating: 4.6,
          address: 'J.P. Laurel St, Tanauan City',
          description:
              'A neighborhood turo-turo serving home-style Filipino ulam, budget-friendly rice meals, and daily comfort-food specials.',
          tags: const ['Comfort food', 'Budget-friendly', 'Silog meals'],
          accentColorValue: 0xFFFFB199,
          latitude: 14.0809,
          longitude: 121.1497,
        ),
        Restaurant(
          id: 'r2',
          name: 'Green Bowl Café',
          type: 'Café',
          cuisine: 'Comfort food',
          distanceKm: 1.2,
          matchPercent: 91,
          priceRange: '₱₱',
          rating: 4.7,
          address: 'P. Gomez St, Tanauan City',
          description:
              'Bright café known for salad bowls, grilled chicken plates, and fresh fruit shakes — a favorite among health-conscious diners.',
          tags: const ['Healthy', 'Salads', 'Gluten-free options'],
          accentColorValue: 0xFF9BE6C0,
          latitude: 14.0863,
          longitude: 121.1609,
        ),
        Restaurant(
          id: 'r3',
          name: 'Sizzling Plaza Grill',
          type: 'Restaurant',
          cuisine: 'Filipino',
          distanceKm: 2.1,
          matchPercent: 88,
          priceRange: '₱₱',
          rating: 4.4,
          address: 'National Highway, Tanauan City',
          description:
              'Family restaurant famous for sizzling plates, grilled seafood, and generous rice meals perfect for group dining.',
          tags: const ['Seafood', 'Group-friendly', 'Sizzling plates'],
          accentColorValue: 0xFFFFD59E,
          latitude: 14.0998,
          longitude: 121.1637,
        ),
        Restaurant(
          id: 'r4',
          name: 'Kusina ni Manang',
          type: 'Karinderyá',
          cuisine: 'Filipino',
          distanceKm: 0.9,
          matchPercent: 85,
          priceRange: '₱',
          rating: 4.3,
          address: 'Barangay Sala, Tanauan City',
          description:
              'Classic eatery offering rotating home-cooked ulam like adobo, sinigang, and tinola at wallet-friendly prices.',
          tags: const ['No pork options', 'Budget-friendly'],
          accentColorValue: 0xFFB7C6FF,
          latitude: 14.0809,
          longitude: 121.1441,
        ),
        Restaurant(
          id: 'r5',
          name: 'Streetside Isaw & Silog Hub',
          type: 'Street food',
          cuisine: 'Silog meals',
          distanceKm: 0.4,
          matchPercent: 82,
          priceRange: '₱',
          rating: 4.2,
          address: 'Talisay Rd corner, Tanauan City',
          description:
              'Late-night favorite for isaw, silog combos, and grilled street eats — quick, cheap, and always crowded.',
          tags: const ['Late night', 'Street food', 'Budget-friendly'],
          accentColorValue: 0xFFFFC1CF,
          latitude: 14.0899,
          longitude: 121.1497,
        ),
        Restaurant(
          id: 'r6',
          name: 'Halal Corner Kitchenette',
          type: 'Restaurant',
          cuisine: 'Asian fusion',
          distanceKm: 1.7,
          matchPercent: 79,
          priceRange: '₱₱',
          rating: 4.5,
          address: 'Wesville Ave, Tanauan City',
          description:
              'Asian-fusion favorites cooked halal, from beef curry rice bowls to grilled satay skewers.',
          tags: const ['Halal', 'Asian fusion'],
          accentColorValue: 0xFFB2E0FF,
          latitude: 14.0863,
          longitude: 121.1339,
        ),
        Restaurant(
          id: 'r7',
          name: 'The Bakeshop Corner',
          type: 'Café',
          cuisine: 'Bakery',
          distanceKm: 1.0,
          matchPercent: 75,
          priceRange: '₱',
          rating: 4.6,
          address: 'Market Site, Tanauan City',
          description:
              'Neighborhood bakery-café for pandesal, ensaymada, coffee, and light breakfast or merienda bites.',
          tags: const ['Bakery', 'Breakfast', 'Merienda'],
          accentColorValue: 0xFFE7C9A9,
          latitude: 14.0926,
          longitude: 121.1432,
        ),
        Restaurant(
          id: 'r8',
          name: 'West Grill & Steakhouse',
          type: 'Restaurant',
          cuisine: 'Western',
          distanceKm: 2.8,
          matchPercent: 70,
          priceRange: '₱₱₱',
          rating: 4.5,
          address: 'Diversion Rd, Tanauan City',
          description:
              'Casual Western-style steakhouse offering hearty steak, pasta, and burger plates for special dinners out.',
          tags: const ['Western', 'Dinner', 'Group-friendly'],
          accentColorValue: 0xFFD8B4FE,
          latitude: 14.0683,
          longitude: 121.1683,
        ),
      ];

  static const List<String> _breakfastDishes = [
    'Tapsilog',
    'Tocilog',
    'Pandesal with coffee',
    'Champorado with tuyo',
    'Oatmeal with fruit',
  ];
  static const List<String> _lunchDishes = [
    'Chicken adobo with rice',
    'Sinigang na baboy',
    'Grilled bangus with rice',
    'Beef curry rice bowl',
    'Vegetable salad bowl',
  ];
  static const List<String> _merienda = [
    'Banana cue',
    'Fruit shake',
    'Ensaymada',
    'Taho',
    'Fresh lumpia',
  ];
  static const List<String> _dinnerDishes = [
    'Sizzling sisig',
    'Grilled seafood platter',
    'Tinolang manok',
    'Beef steak with rice',
    'Halal beef curry',
  ];

  static List<DayPlan> generateMealPlan(
      UserProfile profile, List<Restaurant> restaurants) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final rand = Random(profile.dailyCalorieTarget); // deterministic-ish
    final target = profile.dailyCalorieTarget.clamp(1200, 4000);

    // Rough calorie split across the day.
    final breakfastCal = (target * 0.25).round();
    final lunchCal = (target * 0.35).round();
    final merCal = (target * 0.10).round();
    final dinnerCal = (target * 0.30).round();

    return List.generate(7, (i) {
      final meals = <MealEntry>[];
      for (final slot in MealSlot.values) {
        final cal = switch (slot) {
          MealSlot.breakfast => breakfastCal,
          MealSlot.lunch => lunchCal,
          MealSlot.merienda => merCal,
          MealSlot.dinner => dinnerCal,
        };
        // Leave the last day's dinner slot empty to demonstrate the
        // "Tap to pick a dinner option" prompt shown in Figure 15.
        if (i == days.length - 1 && slot == MealSlot.dinner) {
          meals.add(MealEntry(slot: slot));
          continue;
        }
        final dishList = switch (slot) {
          MealSlot.breakfast => _breakfastDishes,
          MealSlot.lunch => _lunchDishes,
          MealSlot.merienda => _merienda,
          MealSlot.dinner => _dinnerDishes,
        };
        final dish = dishList[rand.nextInt(dishList.length)];
        final restaurant = restaurants[rand.nextInt(restaurants.length)];
        meals.add(MealEntry(
          slot: slot,
          dishName: dish,
          restaurantName: restaurant.name,
          calories: cal,
        ));
      }
      return DayPlan(dayLabel: days[i], meals: meals);
    });
  }

  static MealEntry randomMealFor(
      MealSlot slot, UserProfile profile, List<Restaurant> restaurants) {
    final rand = Random();
    final dishList = switch (slot) {
      MealSlot.breakfast => _breakfastDishes,
      MealSlot.lunch => _lunchDishes,
      MealSlot.merienda => _merienda,
      MealSlot.dinner => _dinnerDishes,
    };
    final target = profile.dailyCalorieTarget.clamp(1200, 4000);
    final calFraction = switch (slot) {
      MealSlot.breakfast => 0.25,
      MealSlot.lunch => 0.35,
      MealSlot.merienda => 0.10,
      MealSlot.dinner => 0.30,
    };
    final dish = dishList[rand.nextInt(dishList.length)];
    final restaurant = restaurants[rand.nextInt(restaurants.length)];
    return MealEntry(
      slot: slot,
      dishName: dish,
      restaurantName: restaurant.name,
      calories: (target * calFraction).round(),
    );
  }
}
