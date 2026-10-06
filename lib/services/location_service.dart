import 'package:geolocator/geolocator.dart';

/// Thin wrapper around the geolocator package — handles permission
/// requests, getting the current GPS position, and computing real
/// distance between two points (used for the "X km away" figures shown
/// on restaurant cards and the detail screen).
class LocationService {
  /// Returns the current position, or null if location services are off,
  /// permission was denied, or something else went wrong. Never throws —
  /// callers should treat null as "fall back to the estimated distance".
  static Future<Position?> getCurrentLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return null;
      }
      if (permission == LocationPermission.deniedForever) return null;

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
    } catch (_) {
      return null;
    }
  }

  /// Straight-line distance between two lat/lng points, in kilometers.
  static double distanceKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    return Geolocator.distanceBetween(lat1, lon1, lat2, lon2) / 1000;
  }
}
