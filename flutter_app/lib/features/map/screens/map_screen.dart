import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme.dart';
import '../../../core/constants.dart';

class MapScreen extends StatefulWidget {
  final bool publicMode;
  const MapScreen({super.key, this.publicMode = false});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();

  List<Marker> _markers   = [];
  bool         _loading   = true;
  String       _statusMsg = 'Loading map...';
  Position?    _myPosition;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await Future.wait([_getMyLocation(), _loadReports()]);
  }

  // ── Get device location ──────────────────────────────────────────────
  Future<void> _getMyLocation() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) return;

      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 10),
        );
      } catch (_) {
        pos = await Geolocator.getLastKnownPosition();
      }

      if (pos == null || !mounted) return;
      setState(() => _myPosition = pos);

      _animateTo(LatLng(pos.latitude, pos.longitude), 15);
    } catch (e) {
      debugPrint('Location: $e');
    }
  }

  // ── Load pothole markers ─────────────────────────────────────────────
  Future<void> _loadReports() async {
    if (mounted) {
      setState(() {
        _loading   = true;
        _statusMsg = 'Loading potholes...';
      });
    }

    try {
      final data = await Supabase.instance.client
          .from('reports')
          .select(
              'id, latitude, longitude, status, address, ai_results(severity)')
          .neq('status', 'rejected')
          .order('submitted_at', ascending: false)
          .limit(500);

      final list    = data as List;
      final markers = <Marker>[];

      for (final r in list) {
        final lat = (r['latitude'] as num?)?.toDouble();
        final lng = (r['longitude'] as num?)?.toDouble();
        if (lat == null || lng == null) continue;

        final ai       = r['ai_results'];
        final severity = (ai is Map ? ai['severity'] as String? : null) ?? 'shallow';
        final id       = r['id'] as String;
        final addr     = r['address'] as String? ??
            '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';

        markers.add(
          Marker(
            width: 40,
            height: 40,
            point: LatLng(lat, lng),
            child: GestureDetector(
              onTap: widget.publicMode ? null : () => context.push('/reports/$id'),
              child: Icon(
                Icons.location_on,
                color: _color(severity),
                size: 32,
              ),
            ),
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _markers   = markers;
        _loading   = false;
        _statusMsg = markers.isEmpty
            ? 'No potholes reported yet'
            : '${markers.length} pothole${markers.length == 1 ? "" : "s"} reported';
      });

      // If no GPS yet, zoom to first marker so user can see something
      if (_myPosition == null && markers.isNotEmpty) {
        _animateTo(markers.first.point, 14);
      }
    } catch (e) {
      debugPrint('Map load error: $e');
      if (mounted) {
        setState(() {
          _loading   = false;
          _statusMsg = 'Could not load potholes. Pull to refresh.';
        });
      }
    }
  }

  void _animateTo(LatLng target, double zoom) {
    _mapController.move(target, zoom);
  }

  void _goToMyLocation() {
    if (_myPosition != null) {
      _animateTo(LatLng(_myPosition!.latitude, _myPosition!.longitude), 15);
    } else {
      _getMyLocation();
    }
  }

  // Map hue (severity) → color for OSM markers
  Color _color(String s) {
    switch (s) {
      case 'deep':
        return AppTheme.deep;
      case 'moderate':
        return AppTheme.moderate;
      default:
        return AppTheme.shallow;
    }
  }

  String _label(String s) {
    switch (s) {
      case 'deep':
        return 'Deep';
      case 'moderate':
        return 'Moderate';
      default:
        return 'Shallow';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final initialCenter = _myPosition != null
        ? LatLng(_myPosition!.latitude, _myPosition!.longitude)
        : const LatLng(AppConstants.defaultLat, AppConstants.defaultLng);
    final initialZoom = _myPosition != null ? 14.0 : 5.0;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.publicMode ? 'Live pothole map' : 'Pothole map'),
        actions: [
          if (widget.publicMode)
            TextButton(
              onPressed: () => context.go('/login'),
              child: const Text('Sign in'),
            )
          else ...[
            IconButton(
              icon: const Icon(Icons.my_location),
              onPressed: _goToMyLocation,
              tooltip: 'Go to my location',
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadReports,
              tooltip: 'Refresh pins',
            ),
          ],
        ],
      ),
      body: Stack(
        children: [
          // ── OpenStreetMap via flutter_map ──────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: initialCenter,
              initialZoom: initialZoom,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.flutter_app',
              ),
              MarkerLayer(markers: _markers),
            ],
          ),

          // ── Status bar ────────────────────────────────────────────
          Positioned(
            top: 10,
            left: 12,
            right: 12,
            child: Material(
              elevation: 2,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                child: Row(
                  children: [
                    if (_loading)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      Icon(
                        _markers.isEmpty
                            ? Icons.info_outline
                            : Icons.location_on,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                    const SizedBox(width: 8),
                    Expanded(
                      child:
                          Text(_statusMsg, style: const TextStyle(fontSize: 13)),
                    ),
                    if (_markers.isNotEmpty && !_loading)
                      GestureDetector(
                        onTap: () => _animateTo(_markers.first.point, 14),
                        child: Text(
                          'Show pins',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // ── Legend ────────────────────────────────────────────────
          Positioned(
            bottom: widget.publicMode ? 20 : 110,
            right: 12,
            child: Material(
              elevation: 2,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    _LegendDot(color: AppTheme.deep, label: 'Deep'),
                    SizedBox(height: 5),
                    _LegendDot(color: AppTheme.moderate, label: 'Moderate'),
                    SizedBox(height: 5),
                    _LegendDot(color: AppTheme.shallow, label: 'Shallow'),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),

      // ── FABs ─────────────────────────────────────────────────────
      floatingActionButton: widget.publicMode
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.small(
                  heroTag: 'loc',
                  onPressed: _goToMyLocation,
                  tooltip: 'My location',
                  child: const Icon(Icons.my_location, size: 20),
                ),
                const SizedBox(height: 10),
                FloatingActionButton.extended(
                  heroTag: 'rep',
                  onPressed: () => context.go('/submit'),
                  icon: const Icon(Icons.add_road),
                  label: const Text('Report pothole'),
                ),
              ],
            ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 11,
            height: 11,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      );
}