import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
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
  GoogleMapController? _mapController;
  Set<Marker>  _markers     = {};
  bool         _mapReady    = false;
  bool         _loading     = true;
  String       _statusMsg   = 'Loading map...';
  Position?    _myPosition;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    // Run location + reports in parallel
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
        // Fall back to last known
        pos = await Geolocator.getLastKnownPosition();
      }

      if (pos == null || !mounted) return;
      setState(() => _myPosition = pos);

      // Move camera if map is already ready
      _animateTo(LatLng(pos.latitude, pos.longitude), 15);
    } catch (e) {
      debugPrint('Location: $e');
    }
  }

  // ── Load pothole markers ─────────────────────────────────────────────
  Future<void> _loadReports() async {
    if (mounted) setState(() { _loading = true; _statusMsg = 'Loading potholes...'; });
    try {
      final data = await Supabase.instance.client
          .from('reports')
          .select('id, latitude, longitude, status, address, ai_results(severity)')
          .neq('status', 'rejected')
          .order('submitted_at', ascending: false)
          .limit(500);

      final list   = data as List;
      final markers = <Marker>{};

      for (final r in list) {
        final lat = (r['latitude']  as num?)?.toDouble();
        final lng = (r['longitude'] as num?)?.toDouble();
        if (lat == null || lng == null) continue;

        final ai       = r['ai_results'];
        final severity = (ai is Map ? ai['severity'] as String? : null) ?? 'shallow';
        final id       = r['id']      as String;
        final addr     = r['address'] as String?
            ?? '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';

        markers.add(Marker(
          markerId: MarkerId(id),
          position: LatLng(lat, lng),
          icon: BitmapDescriptor.defaultMarkerWithHue(_hue(severity)),
          infoWindow: InfoWindow(
            title: '${_label(severity)} pothole',
            snippet: addr,
            onTap: widget.publicMode ? null : () => context.push('/reports/$id'),
          ),
        ));
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
        _animateTo(markers.first.position, 14);
      }
    } catch (e) {
      debugPrint('Map load error: $e');
      if (mounted) setState(() {
        _loading   = false;
        _statusMsg = 'Could not load potholes. Pull to refresh.';
      });
    }
  }

  void _animateTo(LatLng target, double zoom) {
    if (_mapController == null) return;
    _mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: target, zoom: zoom),
      ),
    );
  }

  void _goToMyLocation() {
    if (_myPosition != null) {
      _animateTo(LatLng(_myPosition!.latitude, _myPosition!.longitude), 15);
    } else {
      _getMyLocation();
    }
  }

  double _hue(String s) {
    switch (s) {
      case 'deep':     return BitmapDescriptor.hueRed;
      case 'moderate': return BitmapDescriptor.hueOrange;
      default:         return BitmapDescriptor.hueGreen;
    }
  }

  String _label(String s) {
    switch (s) {
      case 'deep':     return 'Deep';
      case 'moderate': return 'Moderate';
      default:         return 'Shallow';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
      body: Stack(children: [

        // ── Google Map ───────────────────────────────────────────────
        GoogleMap(
          onMapCreated: (controller) async {
            _mapController = controller;
            setState(() => _mapReady = true);
            // Small delay so the map tiles render before animating
            await Future.delayed(const Duration(milliseconds: 400));
            if (!mounted) return;
            if (_myPosition != null) {
              _animateTo(
                  LatLng(_myPosition!.latitude, _myPosition!.longitude), 15);
            } else if (_markers.isNotEmpty) {
              _animateTo(_markers.first.position, 14);
            }
          },
          // Start at device location if known, else India centre
          initialCameraPosition: CameraPosition(
            target: _myPosition != null
                ? LatLng(_myPosition!.latitude, _myPosition!.longitude)
                : const LatLng(AppConstants.defaultLat, AppConstants.defaultLng),
            zoom: _myPosition != null ? 14 : 5,
          ),
          markers: _markers,
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          mapToolbarEnabled: true,
          zoomControlsEnabled: true,
          compassEnabled: true,
        ),

        // ── Status bar ───────────────────────────────────────────────
        Positioned(
          top: 10,
          left: 12,
          right: 12,
          child: Material(
            elevation: 2,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Row(children: [
                if (_loading)
                  const SizedBox(
                    width: 14, height: 14,
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
                  child: Text(_statusMsg,
                      style: const TextStyle(fontSize: 13)),
                ),
                if (_markers.isNotEmpty && !_loading)
                  GestureDetector(
                    onTap: () => _animateTo(_markers.first.position, 14),
                    child: Text('Show pins',
                        style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600)),
                  ),
              ]),
            ),
          ),
        ),

        // ── Legend ───────────────────────────────────────────────────
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
                  _LegendDot(color: AppTheme.deep,     label: 'Deep'),
                  SizedBox(height: 5),
                  _LegendDot(color: AppTheme.moderate, label: 'Moderate'),
                  SizedBox(height: 5),
                  _LegendDot(color: AppTheme.shallow,  label: 'Shallow'),
                ],
              ),
            ),
          ),
        ),
      ]),

      // ── FABs ─────────────────────────────────────────────────────────
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
  final Color  color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 11, height: 11,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      );
}