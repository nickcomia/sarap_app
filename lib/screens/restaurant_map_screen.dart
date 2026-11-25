import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../app_state.dart';
import '../models.dart';
import '../services/location_service.dart';
import '../theme.dart';
import 'restaurant_detail_screen.dart';

/// In-app GIS map of Tanauan City, Batangas.
///  - shows every registered restaurant inside the city as a pin
///  - shows the user's location (GPS, or a point they set by long-pressing)
///  - lists restaurants nearest first, with a radius filter
///  - draws a route and its distance on the map itself (no Google Maps)
///
/// Open it with [destination] to start with a route to that restaurant.
class RestaurantMapScreen extends StatefulWidget {
  final Restaurant? destination;
  const RestaurantMapScreen({super.key, this.destination});

  /// The map is limited to Tanauan City. Widen [cityBounds] if a pin is
  /// cut off at the edge.
  static const cityCenter = LatLng(14.0863, 121.1497);
  static final cityBounds = LatLngBounds(
    const LatLng(14.0200, 121.0700), // south-west
    const LatLng(14.1500, 121.2300), // north-east
  );

  @override
  State<RestaurantMapScreen> createState() => _RestaurantMapScreenState();
}

class _Near {
  final Restaurant restaurant;
  final double km;
  _Near(this.restaurant, this.km);
}

class _RestaurantMapScreenState extends State<RestaurantMapScreen> {
  static const _center = RestaurantMapScreen.cityCenter;
  static final _bounds = RestaurantMapScreen.cityBounds;
  static const _radiusOptions = <double?>[1.0, 3.0, 5.0, null]; // null = all

  final _map = MapController();
  final app = AppState.instance;

  LatLng? _manualOrigin; // set by long-press
  Restaurant? _selected;
  double? _radiusKm = 3.0;

  List<LatLng> _route = [];
  double? _routeKm;
  double? _routeMin;
  bool _routing = false;
  String? _routeNote;

  // --- Origin -------------------------------------------------------------

  /// GPS position, only when it is inside Tanauan.
  LatLng? get _gps {
    final lat = app.userLat, lng = app.userLng;
    if (lat == null || lng == null) return null;
    final p = LatLng(lat, lng);
    return _bounds.contains(p) ? p : null;
  }

  LatLng get _origin => _manualOrigin ?? _gps ?? _center;

  String get _originLabel => _manualOrigin != null
      ? 'the point you set'
      : (_gps != null ? 'your location' : 'Tanauan City center');

  List<Restaurant> get _inCity => app.restaurants
      .where((r) => _bounds.contains(LatLng(r.latitude, r.longitude)))
      .toList();

  double _kmFromOrigin(Restaurant r) => LocationService.distanceKm(
      _origin.latitude, _origin.longitude, r.latitude, r.longitude);

  List<_Near> _nearby() {
    final list = <_Near>[];
    for (final r in _inCity) {
      final d = _kmFromOrigin(r);
      if (_radiusKm == null || d <= _radiusKm!) list.add(_Near(r, d));
    }
    list.sort((a, b) => a.km.compareTo(b.km));
    return list;
  }

  // --- Lifecycle ----------------------------------------------------------

  @override
  void initState() {
    super.initState();
    if (app.userLat == null) _locate(silent: true);
    final dest = widget.destination;
    if (dest != null) {
      _selected = dest;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showRoute();
      });
    }
  }

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  // --- Actions ------------------------------------------------------------

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _locate({bool silent = false}) async {
    try {
      await app.refreshLocation();
    } catch (_) {}
    if (!mounted) return;
    setState(() => _manualOrigin = null);
    if (app.locationDenied) {
      if (!silent) {
        _snack('Location is off. Long-press the map to set your starting point.');
      }
    } else if (_gps == null) {
      if (!silent) {
        _snack('You are outside Tanauan City. Long-press the map to set a '
            'starting point inside the city.');
      }
    } else {
      _map.move(_gps!, 15);
      if (_selected != null) _showRoute();
    }
  }

  void _setOrigin(LatLng p) {
    if (!_bounds.contains(p)) {
      _snack('Please choose a point inside Tanauan City.');
      return;
    }
    setState(() => _manualOrigin = p);
    if (_selected != null) _showRoute();
  }

  void _select(Restaurant r) {
    setState(() {
      _selected = r;
      _route = [];
      _routeKm = null;
      _routeMin = null;
      _routeNote = null;
    });
    _map.move(LatLng(r.latitude, r.longitude), 16);
  }

  void _clearRoute() {
    setState(() {
      _route = [];
      _routeKm = null;
      _routeMin = null;
      _routeNote = null;
    });
  }

  void _clearSelection() {
    _selected = null;
    _clearRoute();
  }

  /// Asks the public OSRM routing service for a road route and draws it on
  /// the map. If the service can't be reached, a straight line and the
  /// straight-line distance are shown instead.
  Future<void> _showRoute() async {
    final dest = _selected;
    if (dest == null) return;
    final from = _origin;
    final to = LatLng(dest.latitude, dest.longitude);
    setState(() {
      _routing = true;
      _routeNote = null;
    });

    List<LatLng> pts = [];
    double km = 0;
    double? mins;
    String? note;
    try {
      final url = Uri.parse(
          'https://router.project-osrm.org/route/v1/driving/'
          '${from.longitude},${from.latitude};${to.longitude},${to.latitude}'
          '?overview=full&geometries=geojson');
      final res = await http.get(url).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) throw Exception('status ${res.statusCode}');
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final routes = data['routes'] as List;
      if (routes.isEmpty) throw Exception('no route');
      final r0 = routes.first as Map<String, dynamic>;
      final coords = (r0['geometry'] as Map<String, dynamic>)['coordinates'] as List;
      pts = [
        for (final c in coords)
          LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())
      ];
      km = (r0['distance'] as num) / 1000;
      mins = (r0['duration'] as num) / 60;
    } catch (_) {
      pts = [from, to];
      km = LocationService.distanceKm(
          from.latitude, from.longitude, to.latitude, to.longitude);
      mins = null;
      note = 'Route service unavailable. Showing the straight-line distance.';
    }

    if (!mounted || _selected != dest) return; // another restaurant was picked
    setState(() {
      _route = pts;
      _routeKm = km;
      _routeMin = mins;
      _routeNote = note;
      _routing = false;
    });
    _map.fitCamera(CameraFit.bounds(
      bounds: LatLngBounds.fromPoints(pts),
      padding: const EdgeInsets.all(60),
    ));
  }

  // --- UI -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final nearby = _nearby();
        return Scaffold(
          appBar: AppBar(title: const Text('Tanauan Food Map')),
          body: Column(
            children: [
              _radiusBar(context, nearby.length),
              Expanded(child: _mapArea()),
              _bottomPanel(context, nearby),
            ],
          ),
        );
      },
    );
  }

  Widget _radiusBar(BuildContext context, int count) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final o in _radiusOptions)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(o == null ? 'All Tanauan' : '${o.round()} km'),
                        selected: _radiusKm == o,
                        onSelected: (_) => setState(() => _radiusKm = o),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Text('$count found',
              style: TextStyle(fontWeight: FontWeight.w700, color: colors.navy)),
        ],
      ),
    );
  }

  Widget _mapArea() {
    final selected = _selected;
    final others = _inCity.where((r) => r.id != selected?.id);

    final markers = <Marker>[
      for (final r in others)
        Marker(
          point: LatLng(r.latitude, r.longitude),
          width: 40,
          height: 40,
          alignment: Alignment.topCenter,
          child: GestureDetector(
            onTap: () => _select(r),
            child: const Icon(Icons.location_on,
                size: 34, color: AppColors.primaryDark),
          ),
        ),
      if (selected != null)
        Marker(
          point: LatLng(selected.latitude, selected.longitude),
          width: 52,
          height: 52,
          alignment: Alignment.topCenter,
          child: const Icon(Icons.location_on, size: 46, color: Colors.red),
        ),
      if (_manualOrigin != null || _gps != null)
        Marker(
          point: _origin,
          width: 22,
          height: 22,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.blue,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
            ),
          ),
        ),
    ];

    return Stack(
      children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: _center,
            initialZoom: 13,
            minZoom: 11,
            maxZoom: 18,
            cameraConstraint: CameraConstraint.contain(bounds: _bounds),
            onLongPress: (tapPosition, point) => _setOrigin(point),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.sarap_app',
            ),
            if (_radiusKm != null)
              CircleLayer(circles: [
                CircleMarker(
                  point: _origin,
                  radius: _radiusKm! * 1000,
                  useRadiusInMeter: true,
                  color: const Color(0x142196F3),
                  borderColor: const Color(0x802196F3),
                  borderStrokeWidth: 1.5,
                ),
              ]),
            if (_route.isNotEmpty)
              PolylineLayer(polylines: [
                Polyline(
                  points: _route,
                  strokeWidth: 5,
                  color: Colors.blue,
                  borderStrokeWidth: 2,
                  borderColor: Colors.white,
                ),
              ]),
            MarkerLayer(markers: markers),
            const RichAttributionWidget(
              attributions: [
                TextSourceAttribution('© OpenStreetMap contributors'),
                TextSourceAttribution('Routes: OSRM'),
              ],
            ),
          ],
        ),
        Positioned(
          right: 12,
          top: 12,
          child: FloatingActionButton.small(
            heroTag: 'map_locate',
            onPressed: () => _locate(),
            child: const Icon(Icons.my_location),
          ),
        ),
      ],
    );
  }

  Widget _bottomPanel(BuildContext context, List<_Near> nearby) {
    final colors = context.colors;
    final selected = _selected;
    return Material(
      color: colors.card,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: selected != null
              ? _selectedPanel(context, selected)
              : _nearbyPanel(context, nearby),
        ),
      ),
    );
  }

  Widget _nearbyPanel(BuildContext context, List<_Near> nearby) {
    final colors = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Nearest to $_originLabel',
            style: TextStyle(
                fontWeight: FontWeight.w800, fontSize: 14.5, color: colors.navy)),
        if (_manualOrigin == null && _gps == null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'Tap the location button, or long-press the map to set where you are.',
              style: TextStyle(fontSize: 12, color: colors.muted),
            ),
          ),
        const SizedBox(height: 8),
        if (nearby.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text('No restaurants in this range. Try a larger radius.',
                style: TextStyle(color: colors.muted)),
          )
        else
          SizedBox(
            height: 92,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: nearby.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final n = nearby[i];
                return InkWell(
                  onTap: () => _select(n.restaurant),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 210,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: colors.border),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(n.restaurant.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: colors.navy)),
                        const SizedBox(height: 4),
                        Text(
                            '${n.restaurant.cuisine} · ${n.km.toStringAsFixed(1)} km',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12.5, color: colors.muted)),
                        const SizedBox(height: 2),
                        Text('Match ${n.restaurant.matchPercent}%',
                            style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primaryDark)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _selectedPanel(BuildContext context, Restaurant r) {
    final colors = context.colors;
    final hasRoute = _route.isNotEmpty;
    final straight = _kmFromOrigin(r);
    final String distance;
    if (hasRoute && _routeKm != null) {
      distance = '${_routeKm!.toStringAsFixed(1)} km'
          '${_routeMin != null ? ' · about ${_routeMin!.round()} min by road' : ''}';
    } else {
      distance = '${straight.toStringAsFixed(1)} km from $_originLabel '
          '(straight line)';
    }
    // Opened from a restaurant's page: that page is already behind this
    // screen, so "Details" is only offered when opened from the feed.
    final canOpenDetails = widget.destination == null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(r.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: colors.navy)),
            ),
            IconButton(
              tooltip: 'Close',
              onPressed: () => setState(_clearSelection),
              icon: Icon(Icons.close, color: colors.navy),
            ),
          ],
        ),
        Text('${r.cuisine} · ${r.priceLabel} · ★ ${r.rating}',
            style: TextStyle(fontSize: 13, color: colors.muted)),
        const SizedBox(height: 6),
        Text(distance,
            style: TextStyle(
                fontWeight: FontWeight.w700, fontSize: 14, color: colors.navy)),
        if (_routeNote != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(_routeNote!,
                style: TextStyle(fontSize: 12, color: colors.muted)),
          ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            ElevatedButton.icon(
              onPressed: _routing ? null : _showRoute,
              icon: _routing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.directions),
              label: Text(hasRoute ? 'Refresh route' : 'Show route'),
            ),
            if (hasRoute)
              OutlinedButton(
                onPressed: _clearRoute,
                child: const Text('Clear route'),
              ),
            if (canOpenDetails)
              OutlinedButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => RestaurantDetailScreen(restaurant: r))),
                child: const Text('Details'),
              ),
          ],
        ),
      ],
    );
  }
}