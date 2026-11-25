import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import '../../theme.dart';

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

/// Form field for a restaurant's location, with an interactive map.
///
/// The admin can tap the map to place the pin (the text field fills in by
/// itself), or type / paste coordinates or a Google Maps link (the pin
/// moves to match). The text in [controller] stays "lat, lng", so the
/// screens that use this field work exactly as before.
class LocationField extends StatefulWidget {
  final TextEditingController controller;
  const LocationField({super.key, required this.controller});

  @override
  State<LocationField> createState() => _LocationFieldState();
}

class _LocationFieldState extends State<LocationField> {
  /// Tanauan City centre: where the map opens when there is no location yet.
  static const _defaultCenter = ll.LatLng(14.0863, 121.1497);

  final _map = MapController();
  bool _mapReady = false;
  bool _fromMap = false; // true while a map tap is writing the text field
  ll.LatLng? _pin;

  @override
  void initState() {
    super.initState();
    _pin = _fromText(widget.controller.text);
    widget.controller.addListener(_onText);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    super.dispose();
  }

  ll.LatLng? _fromText(String text) {
    final p = parseLatLng(text);
    return p == null ? null : ll.LatLng(p.lat, p.lng);
  }

  /// The admin typed or pasted something: move the pin to match.
  void _onText() {
    final p = _fromText(widget.controller.text);
    if (p == null) return;
    final old = _pin;
    if (old != null &&
        old.latitude == p.latitude &&
        old.longitude == p.longitude) {
      return;
    }
    if (mounted) setState(() => _pin = p);
    if (!_fromMap && _mapReady) _map.move(p, 16);
  }

  /// The admin tapped the map: place the pin and fill in the text field.
  void _onTap(TapPosition tapPosition, ll.LatLng point) {
    _fromMap = true;
    widget.controller.text =
        '${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}';
    _fromMap = false;
  }

  @override
  Widget build(BuildContext context) {
    final start = _pin ?? _defaultCenter;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: widget.controller,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'Location (coordinates or Google Maps link)',
            hintText: '14.0863, 121.1497',
            helperText:
                'Tap the map below to place the pin, or paste coordinates or a Google Maps link here.',
            helperMaxLines: 2,
            prefixIcon: Icon(Icons.place_outlined),
          ),
          validator: (v) {
            if (v == null || v.trim().isEmpty) return 'Required';
            if (parseLatLng(v) == null) {
              return 'Could not read a location. Tap the map or use "lat, lng".';
            }
            return null;
          },
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            height: 300,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _map,
                  options: MapOptions(
                    initialCenter: start,
                    initialZoom: _pin == null ? 14 : 16,
                    onMapReady: () => _mapReady = true,
                    onTap: _onTap,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.ph.sarap_app',
                    ),
                    if (_pin != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _pin!,
                            width: 44,
                            height: 44,
                            alignment: Alignment.topCenter,
                            child: const Icon(Icons.location_on,
                                size: 44, color: AppColors.primary),
                          ),
                        ],
                      ),
                  ],
                ),
                Positioned(
                  left: 8,
                  bottom: 6,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      '© OpenStreetMap contributors',
                      style: TextStyle(fontSize: 10.5, color: Colors.black87),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}