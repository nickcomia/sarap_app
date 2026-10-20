import 'package:flutter/material.dart';

/// A simple latitude/longitude pair.
class LatLngPoint {
  final double lat;
  final double lng;
  const LatLngPoint(this.lat, this.lng);
}

/// Reads a location from text. Accepts:
///   - plain coordinates:         14.0863, 121.1497
///   - a full Google Maps link:   .../@14.0863,121.1497,17z
///                                ...!3d14.0863!4d121.1497
///                                ...?q=14.0863,121.1497
/// Returns null if nothing valid is found. Short links (maps.app.goo.gl)
/// do not contain coordinates, so open them first and copy the long URL.
LatLngPoint? parseLatLng(String input) {
  final text = input.trim();
  if (text.isEmpty) return null;

  final patterns = <RegExp>[
    RegExp(r'@(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)'),
    RegExp(r'!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)'),
    RegExp(r'[?&](?:q|ll|query)=(-?\d+(?:\.\d+)?)(?:,|%2C)\s*(-?\d+(?:\.\d+)?)'),
    RegExp(r'^\s*(-?\d+(?:\.\d+)?)\s*[,\s]\s*(-?\d+(?:\.\d+)?)\s*$'),
  ];

  for (final p in patterns) {
    final m = p.firstMatch(text);
    if (m == null) continue;
    final lat = double.tryParse(m.group(1)!);
    final lng = double.tryParse(m.group(2)!);
    if (lat == null || lng == null) continue;
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) continue;
    return LatLngPoint(lat, lng);
  }
  return null;
}

/// Form field for entering a restaurant's location.
class LocationField extends StatelessWidget {
  final TextEditingController controller;
  const LocationField({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.url,
      decoration: const InputDecoration(
        labelText: 'Location (coordinates or Google Maps link)',
        hintText: '14.0863, 121.1497',
        helperText:
            'In Google Maps, right-click the place and click the coordinates to copy them.',
        helperMaxLines: 2,
        prefixIcon: Icon(Icons.place_outlined),
      ),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return 'Required';
        if (parseLatLng(v) == null) {
          return 'Could not read a location. Use "lat, lng" or a full Maps link.';
        }
        return null;
      },
    );
  }
}