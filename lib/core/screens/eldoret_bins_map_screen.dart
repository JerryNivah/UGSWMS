import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:ugswms/shared/bin_simulation_panel.dart';

class EldoretBinsMapScreen extends StatefulWidget {
  const EldoretBinsMapScreen({
    super.key,
    this.showSimulationControls = false,
  });

  final bool showSimulationControls;

  @override
  State<EldoretBinsMapScreen> createState() => _EldoretBinsMapScreenState();
}

class _EldoretBinsMapScreenState extends State<EldoretBinsMapScreen> {
  final MapController _mapController = MapController();

  static const LatLng _eldoretCenter = LatLng(0.5143, 35.2698);

  Timer? _routeTimer;
  double _routeSpeed = 1.0;
  int _routeSegment = 0;
  int _routeTargetIndex = 0;
  double _routeT = 0.0;
  final ValueNotifier<LatLng?> _truckPosNotifier = ValueNotifier(null);
  int _routeTick = 0;
  int _lastPausedStopIndex = -1;
  int _lastAnimatedStopIndex = -1;

  List<_RouteStop> _routeStops = [];
  List<LatLng> _routePoints = [];
  String? _routeId;
  String? _routeStatus;
  String? _routeDriverUid;
  String? _animationState;
  int _currentStopIndex = 0;
  String? _routeKey;
  String? _routeFilterDriverUid;

  bool _routeBuilderMode = false;
  final List<_SelectedStop> _selectedStops = [];
  String? _selectedDriverUid;
  bool _onlyAvailableDrivers = false;

  @override
  void dispose() {
    _stopRouteAnimation(reset: false);
    _truckPosNotifier.dispose();
    super.dispose();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _routeStream() {
    var q = FirebaseFirestore.instance
        .collection('routes')
        .where('status', whereIn: ['active', 'planned']);

    if (_routeFilterDriverUid != null && _routeFilterDriverUid!.isNotEmpty) {
      q = q.where('driverUid', isEqualTo: _routeFilterDriverUid);
    }

    return q.orderBy('createdAt', descending: true).limit(1).snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _routeOptionsStream() {
    return FirebaseFirestore.instance
        .collection('routes')
        .where('status', whereIn: ['active', 'planned'])
        .orderBy('createdAt', descending: true)
        .limit(20)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    final q = FirebaseFirestore.instance
        .collection('bins')
        .where('isActive', isEqualTo: true);

    return Scaffold(
      appBar: AppBar(
        title: const Text("UGSWMS Bins - Eldoret"),
        actions: [
          if (widget.showSimulationControls)
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _routeBuilderMode = !_routeBuilderMode;
                  if (!_routeBuilderMode) {
                    _selectedStops.clear();
                    _selectedDriverUid = null;
                  }
                });
              },
                icon: Icon(
                  _routeBuilderMode ? Icons.route : Icons.route_outlined,
                  color: Colors.black,
                ),
                label: const Text(
                  "Route Builder",
                  style: TextStyle(color: Colors.black),
                ),
              ),
          IconButton(
            tooltip: "Re-center",
            icon: const Icon(Icons.my_location),
            onPressed: () => _mapController.move(_eldoretCenter, 14),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: q.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text("Error: ${snap.error}"));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snap.data!.docs;

          final binMarkers = docs.map((d) {
            final data = d.data();
            final lat = (data['lat'] as num?)?.toDouble();
            final lng = (data['lng'] as num?)?.toDouble();
            final name = (data['name'] ?? 'Bin').toString();
            final level = (data['level'] as num?)?.toInt() ?? 0;
            final fillLevel = (data['fillLevel'] as num?)?.toInt();
            final status = (data['status'] ?? 'normal').toString();

            if (lat == null || lng == null) return null;
            if (_routeBuilderMode && status != 'critical') return null;

            final color = _statusColor(status, fillLevel ?? level);
            final isSelected = _isSelectedStop(d.id);

            return Marker(
              point: LatLng(lat, lng),
              width: 44,
              height: 44,
              child: GestureDetector(
                onTap: () {
                  if (_routeBuilderMode) {
                    _toggleSelectedStop(
                      id: d.id,
                      name: name,
                      lat: lat,
                      lng: lng,
                    );
                  } else {
                    _showBinSheet(
                      id: d.id,
                      name: name,
                      level: level,
                      status: status,
                      pos: LatLng(lat, lng),
                    );
                  }
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.92),
                    shape: BoxShape.circle,
                    boxShadow: const [
                      BoxShadow(blurRadius: 8, offset: Offset(0, 2))
                    ],
                    border: isSelected
                        ? Border.all(color: Colors.white, width: 3)
                        : null,
                  ),
                  child: const Icon(Icons.delete_outline, color: Colors.white),
                ),
              ),
            );
          }).whereType<Marker>().toList();

          if (!widget.showSimulationControls) {
            return FlutterMap(
              mapController: _mapController,
              options: const MapOptions(
                initialCenter: _eldoretCenter,
                initialZoom: 14,
                interactionOptions: InteractionOptions(flags: InteractiveFlag.all),
              ),
              children: [
                TileLayer(
                  urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                  userAgentPackageName: "com.yourcompany.ugswms",
                ),
                MarkerLayer(markers: binMarkers),
              ],
            );
          }

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _routeStream(),
            builder: (context, routeSnap) {
              final routeDoc = routeSnap.data?.docs.isNotEmpty == true
                  ? routeSnap.data!.docs.first
                  : null;
              _syncRoute(routeDoc);

              final stopMarkers = _buildStopMarkers();
              final selectedStopMarkers = _buildSelectedStopMarkers();
              final selectedPolylinePoints =
                  _selectedStops.map((s) => s.position).toList();

              return Stack(
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: const MapOptions(
                      initialCenter: _eldoretCenter,
                      initialZoom: 14,
                      interactionOptions: InteractionOptions(flags: InteractiveFlag.all),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                        userAgentPackageName: "com.yourcompany.ugswms",
                      ),
                      if (_routePoints.length >= 2)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: _routePoints,
                              strokeWidth: 4,
                              color: Colors.blueAccent.withOpacity(0.85),
                            ),
                          ],
                        ),
                      if (_routeBuilderMode && selectedPolylinePoints.length >= 2)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: selectedPolylinePoints,
                              strokeWidth: 4,
                              color: Colors.deepPurpleAccent.withOpacity(0.9),
                            ),
                          ],
                        ),
                      if (stopMarkers.isNotEmpty)
                        MarkerLayer(markers: stopMarkers),
                      MarkerLayer(markers: binMarkers),
                      if (selectedStopMarkers.isNotEmpty)
                        MarkerLayer(markers: selectedStopMarkers),
                      ValueListenableBuilder<LatLng?>(
                        valueListenable: _truckPosNotifier,
                        builder: (_, pos, __) {
                          if (pos == null) return const SizedBox.shrink();
                          return MarkerLayer(
                            markers: [
                              Marker(
                                point: pos,
                                width: 48,
                                height: 48,
                                child: const Icon(
                                  Icons.local_shipping,
                                  size: 40,
                                  color: Colors.black87,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                  _routeDemoPanel(),
                  if (_routeBuilderMode) _routeBuilderPanel(),
                ],
              );
            },
          );
        },
      ),
      bottomNavigationBar: _bottomPanel(),
    );
  }

  void _syncRoute(QueryDocumentSnapshot<Map<String, dynamic>>? doc) {
    if (doc == null) {
      if (_routeId == null && _routeStops.isEmpty) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _clearRoute();
      });
      return;
    }

    final data = doc.data();
    final stops = _parseRouteStops(data);
    final key = '${doc.id}|${stops.map((s) => s.position).join('|')}';
    final rawStopIndex =
        (data['currentStopIndex'] as num?)?.toInt() ?? 0;
    final animationState = (data['animationState'] ?? 'moving').toString();
    final status = (data['status'] ?? 'active').toString();
    final driverUid = (data['driverUid'] ?? '').toString();
    final currentStopIndex = status == 'planned' ? 0 : rawStopIndex;

    if (key == _routeKey) {
      // Same route + same geometry: only update done flags without resetting animation.
      final updatedStops = _mergeStopDone(_routeStops, stops);
      final stopChanged = updatedStops != null;
      final indexChanged = _currentStopIndex != currentStopIndex;
      final animChanged = _animationState != animationState;
      final statusChanged = _routeStatus != status;
      final driverChanged = _routeDriverUid != driverUid;
      final stateChanged =
          indexChanged || animChanged || statusChanged || driverChanged;
      if (stopChanged || stateChanged) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            if (updatedStops != null) {
              _routeStops = updatedStops;
            }
            _routeStatus = status;
            _routeDriverUid = driverUid;
            _currentStopIndex = currentStopIndex;
            _animationState = animationState;
          });
          if (stateChanged) {
            _prepareSegmentAndMaybeAnimate();
          }
        });
      }
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _applyRoute(
        id: doc.id,
        status: status,
        driverUid: driverUid,
        stops: stops,
        currentStopIndex: currentStopIndex,
        animationState: animationState,
      );
    });
  }

  void _applyRoute({
    required String id,
    required String status,
    required String driverUid,
    required List<_RouteStop> stops,
    required int currentStopIndex,
    required String animationState,
  }) {
    _routeId = id;
    _routeStatus = status;
    _routeDriverUid = driverUid;
    _routeStops = stops;
    _routePoints = stops.map((s) => s.position).toList();
    _routeKey = '$id|${stops.map((s) => s.position).join('|')}';
    _routeSegment = 0;
    _routeTargetIndex = 0;
    _routeT = 0.0;
    _routeTick = 0;
    _currentStopIndex = status == 'planned' ? 0 : currentStopIndex;
    _animationState = animationState;
    _lastAnimatedStopIndex = -1;
    final startIndex = _currentStopIndex <= 0 ? 0 : _currentStopIndex - 1;
    final initialPos = _routePoints.isNotEmpty
        ? _routePoints[startIndex.clamp(0, _routePoints.length - 1)]
        : null;
    _truckPosNotifier.value = initialPos;
    debugPrint('Route points: ${_routePoints.length}');
    debugPrint('Initial truckPos: $initialPos');
    _lastPausedStopIndex = -1;
    _prepareSegmentAndMaybeAnimate();
    setState(() {});
  }

  void _clearRoute() {
    _stopRouteAnimation(reset: true);
    setState(() {
      _routeId = null;
      _routeStatus = null;
      _routeDriverUid = null;
      _animationState = null;
      _currentStopIndex = 0;
      _routeStops = [];
      _routePoints = [];
      _routeKey = null;
      _truckPosNotifier.value = null;
    });
  }

  void _prepareSegmentAndMaybeAnimate() {
    _stopRouteAnimation(reset: false);
    if (_routePoints.isEmpty) {
      _truckPosNotifier.value = null;
      return;
    }

    if ((_animationState ?? 'moving') == 'moving' &&
        _lastAnimatedStopIndex == _currentStopIndex &&
        _routeStatus != 'planned') {
      return;
    }
    _lastAnimatedStopIndex = _currentStopIndex;

    if (_routeStatus == 'completed') {
      _currentStopIndex = _routePoints.length - 1;
      _routeTargetIndex = _currentStopIndex;
      _routeSegment = _currentStopIndex;
      _snapTruckToCurrentStop();
      return;
    }

    final targetIndex = _currentStopIndex.clamp(0, _routePoints.length - 1);
    _routeTargetIndex = targetIndex;
    _routeSegment = targetIndex <= 0 ? 0 : targetIndex - 1;
    _routeT = 0.0;

    if (_routeSegment == _routeTargetIndex) {
      _snapTruckToCurrentStop();
      if ((_animationState ?? 'moving') == 'moving') {
        _pauseAtStopIfNeeded(_routeTargetIndex);
      }
      return;
    }
    if ((_animationState ?? 'moving') != 'moving') {
      _snapTruckToCurrentStop();
      return;
    }

    _truckPosNotifier.value = _routePoints[_routeSegment];
    _startRouteAnimation();
  }

  void _snapTruckToCurrentStop() {
    if (_routePoints.isEmpty) {
      _truckPosNotifier.value = null;
      return;
    }
    final idx = _currentStopIndex.clamp(0, _routePoints.length - 1);
    _truckPosNotifier.value = _routePoints[idx];
  }

  void _startRouteAnimation() {
    if ((_animationState ?? 'moving') != 'moving') return;
    if (_routePoints.length < 2) {
      _snapTruckToCurrentStop();
      return;
    }
    if (_routeTargetIndex <= _routeSegment) {
      _snapTruckToCurrentStop();
      return;
    }

    _routeTimer?.cancel();
    _routeTick = 0;
    _routeTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (_routePoints.length < 2) return;

      final step = 0.02 * _routeSpeed;
      _routeT += step;

      if (_routeT >= 1.0) {
        _routeT = 1.0;
        final target = _routePoints[_routeTargetIndex];
        _truckPosNotifier.value = target;
        _stopRouteAnimation(reset: false);
        _pauseAtStopIfNeeded(_routeTargetIndex);
        return;
      }

      final p1 = _routePoints[_routeSegment];
      final p2 = _routePoints[_routeTargetIndex];
      final p = _lerpLatLng(p1, p2, _routeT);

      _routeTick += 1;
      if (_routeTick % 20 == 0) {
        debugPrint('Truck update: segment=$_routeSegment t=$_routeT pos=$p');
      }

      if (!mounted) return;
      _truckPosNotifier.value = p;
    });
  }

  void _stopRouteAnimation({required bool reset}) {
    _routeTimer?.cancel();
    _routeTimer = null;

    if (reset) {
      _routeT = 0.0;
      _snapTruckToCurrentStop();
    }
  }

  Future<void> _pauseAtStopIfNeeded(int stopIndex) async {
    if (_routeId == null) return;
    if (stopIndex < 0 || stopIndex >= _routeStops.length) return;
    if ((_animationState ?? 'moving') != 'moving') return;
    if (stopIndex != _currentStopIndex) return;
    if (_lastPausedStopIndex == stopIndex) return;

    final stop = _routeStops[stopIndex];
    if (stop.done) return;

    _lastPausedStopIndex = stopIndex;
    await FirebaseFirestore.instance
        .collection('routes')
        .doc(_routeId!)
        .update({
      'animationState': 'paused',
      'updatedAt': FieldValue.serverTimestamp(),
    });
    if (!mounted) return;
    setState(() => _animationState = 'paused');
  }

  LatLng _lerpLatLng(LatLng a, LatLng b, double t) {
    return LatLng(
      a.latitude + (b.latitude - a.latitude) * t,
      a.longitude + (b.longitude - a.longitude) * t,
    );
  }

  List<_RouteStop>? _mergeStopDone(List<_RouteStop> current, List<_RouteStop> next) {
    if (current.length != next.length) return null;
    bool changed = false;
    final merged = <_RouteStop>[];
    for (var i = 0; i < current.length; i++) {
      final a = current[i];
      final b = next[i];
      if (a.position.latitude != b.position.latitude ||
          a.position.longitude != b.position.longitude) {
        return null;
      }
      if (a.done != b.done) {
        changed = true;
        merged.add(a.copyWith(done: b.done));
      } else {
        merged.add(a);
      }
    }
    return changed ? merged : null;
  }

  void _fitToRoute() {
    if (_routePoints.isEmpty) return;
    final bounds = LatLngBounds.fromPoints(_routePoints);
    _mapController.fitCamera(
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(48)),
    );
  }

  List<_RouteStop> _parseRouteStops(Map<String, dynamic> data) {
    final rawStops = data['stops'];
    if (rawStops is! List) return [];

    return rawStops
        .map((s) => s is Map<String, dynamic> ? s : null)
        .whereType<Map<String, dynamic>>()
        .map((s) {
          final lat = (s['lat'] as num?)?.toDouble();
          final lng = (s['lng'] as num?)?.toDouble();
          if (lat == null || lng == null) return null;
          return _RouteStop(
            refId: (s['refId'] ?? '').toString(),
            title: (s['title'] ?? 'Stop').toString(),
            done: (s['done'] ?? false) == true,
            raw: Map<String, dynamic>.from(s),
            position: LatLng(lat, lng),
          );
        })
        .whereType<_RouteStop>()
        .toList();
  }

  List<Marker> _buildStopMarkers() {
    return _routeStops.asMap().entries.map((entry) {
      final index = entry.key + 1;
      final stop = entry.value;
      final color = stop.done ? Colors.green : Colors.orange;

      return Marker(
        point: stop.position,
        width: 36,
        height: 36,
        child: Tooltip(
          message: '${stop.title} • ${stop.done ? 'done' : 'pending'}',
          child: Container(
            decoration: BoxDecoration(
              color: color.withOpacity(0.95),
              shape: BoxShape.circle,
              boxShadow: const [
                BoxShadow(blurRadius: 6, offset: Offset(0, 2))
              ],
            ),
            child: Center(
              child: Text(
                '$index',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  Widget _routeDemoPanel() {
    if (!widget.showSimulationControls) return const SizedBox.shrink();

    final routeStatus = _routeStatus ?? 'n/a';
    final driverUid = _routeDriverUid ?? '—';
    final stopsCount = _routeStops.length;
    final isMoving = (_animationState ?? 'paused') == 'moving';

    return Positioned(
      right: 16,
      top: 16,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Material(
          elevation: 6,
          borderRadius: BorderRadius.circular(16),
          color: Theme.of(context).colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Text(
                      "Route Demo",
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const Spacer(),
                    if (_routeId == null)
                      Text(
                        "No active/planned routes",
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  "Route: $routeStatus • Stops: $stopsCount",
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                ),
                const SizedBox(height: 2),
                Text(
                  "Driver: $driverUid",
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    OutlinedButton(
                      onPressed: _routePoints.isEmpty ? null : _fitToRoute,
                      child: const Text("Fit"),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _routeId == null
                          ? null
                          : () => _setRouteAnimationState(
                                isMoving ? 'paused' : 'moving',
                              ),
                      child: Text(isMoving ? "Pause" : "Play"),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _routePoints.isEmpty
                          ? null
                          : () => _stopRouteAnimation(reset: true),
                      child: const Text("Stop"),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _adminClearRouteButton(),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text("Speed"),
                    const SizedBox(width: 8),
                    DropdownButton<double>(
                      value: _routeSpeed,
                      items: const [0.5, 1.0, 2.0, 4.0]
                          .map(
                            (s) => DropdownMenuItem(
                              value: s,
                              child: Text("${s}x"),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _routeSpeed = v);
                      },
                    ),
                    const Spacer(),
                    const Text("Source"),
                    const SizedBox(width: 6),
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _routeOptionsStream(),
                      builder: (context, snap) {
                        final options = <String>{};
                        for (final d in snap.data?.docs ?? const []) {
                          final uid = (d.data()['driverUid'] ?? '').toString();
                          if (uid.isNotEmpty) options.add(uid);
                        }
                        final items = <String>["Latest", ...options];
                        final hasFilter = _routeFilterDriverUid != null &&
                            items.contains(_routeFilterDriverUid);
                        final current = hasFilter ? _routeFilterDriverUid! : "Latest";

                        if (!hasFilter && _routeFilterDriverUid != null) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!mounted) return;
                            setState(() => _routeFilterDriverUid = null);
                          });
                        }

                        return DropdownButton<String>(
                          value: current,
                          items: items
                              .map(
                                (v) => DropdownMenuItem(
                                  value: v,
                                  child: Text(
                                    v == "Latest" ? "Latest" : v,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            setState(() {
                              _routeFilterDriverUid =
                                  (v == null || v == "Latest") ? null : v;
                              _routeKey = null;
                              _routeId = null;
                              _routeStops = [];
                              _routePoints = [];
                            });
                            _stopRouteAnimation(reset: true);
                          },
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _setRouteAnimationState(String state) async {
    if (_routeId == null) return;
    await FirebaseFirestore.instance.collection('routes').doc(_routeId!).update({
      'animationState': state,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    if (!mounted) return;
    setState(() => _animationState = state);
    _prepareSegmentAndMaybeAnimate();
  }

  Widget _adminClearRouteButton() {
    if (!widget.showSimulationControls) return const SizedBox.shrink();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream:
          FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
      builder: (context, snap) {
        final role = (snap.data?.data()?['role'] ?? '').toString();
        if (role != 'admin') return const SizedBox.shrink();

        return SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _routeId == null ? null : _clearCurrentRoute,
            icon: const Icon(Icons.delete_outline),
            label: const Text("Clear Route"),
          ),
        );
      },
    );
  }

  Future<void> _clearCurrentRoute() async {
    if (_routeId == null) return;

    final db = FirebaseFirestore.instance;
    final now = FieldValue.serverTimestamp();
    final batch = db.batch();

    final routeRef = db.collection('routes').doc(_routeId!);
    batch.update(routeRef, {
      'status': 'cancelled',
      'animationState': 'completed',
      'updatedAt': now,
    });

    if (_routeDriverUid != null && _routeDriverUid!.isNotEmpty) {
      batch.update(db.collection('users').doc(_routeDriverUid!), {
        'driverStatus': 'available',
        'activeRouteId': null,
        'updatedAt': now,
      });
    }

    for (final stop in _routeStops) {
      if (stop.refId.isEmpty) continue;
      batch.update(db.collection('bins').doc(stop.refId), {
        'autoAllocateLockedUntil': Timestamp.fromDate(
          DateTime.now().add(const Duration(seconds: 120)),
        ),
        'assignedDriverUid': null,
        'assignedRouteId': null,
        'updatedAt': now,
      });
    }

    await batch.commit();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Route cleared")),
    );
  }

  Widget _routeBuilderPanel() {
    return Positioned(
      left: 16,
      top: 16,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Material(
          elevation: 6,
          borderRadius: BorderRadius.circular(16),
          color: Theme.of(context).colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Text(
                      "Route Builder",
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const Spacer(),
                    Text(
                      "Critical bins only",
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _selectedStops.length,
                    itemBuilder: (context, index) {
                      final stop = _selectedStops[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Container(
                              width: 24,
                              height: 24,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: Colors.deepPurple.withOpacity(0.9),
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '${index + 1}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                stop.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              tooltip: "Move up",
                              onPressed: index == 0
                                  ? null
                                  : () => _moveSelectedStop(index, -1),
                              icon: const Icon(Icons.keyboard_arrow_up),
                            ),
                            IconButton(
                              tooltip: "Move down",
                              onPressed: index == _selectedStops.length - 1
                                  ? null
                                  : () => _moveSelectedStop(index, 1),
                              icon: const Icon(Icons.keyboard_arrow_down),
                            ),
                            IconButton(
                              tooltip: "Remove",
                              onPressed: () => _removeSelectedStop(index),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                if (_selectedStops.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      "Select critical bins on the map.",
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    ),
                  ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Text("Driver"),
                    const SizedBox(width: 8),
                    Expanded(
                      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance
                            .collection('users')
                            .where('role', isEqualTo: 'driver')
                            .where('status', isEqualTo: 'active')
                            .snapshots(),
                        builder: (context, snap) {
                          final docs = snap.data?.docs ?? const [];
                          final drivers = docs.where((d) {
                            if (!_onlyAvailableDrivers) return true;
                            final st =
                                (d.data()['driverStatus'] ?? '').toString();
                            return st == 'available';
                          }).toList();

                          final items = drivers
                              .map((d) {
                                final data = d.data();
                                final name = (data['name'] ?? '').toString();
                                final email = (data['email'] ?? '').toString();
                                final label =
                                    name.isNotEmpty ? name : (email.isNotEmpty ? email : d.id);
                                return DropdownMenuItem<String>(
                                  value: d.id,
                                  child: Text(
                                    label,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              })
                              .toList();

                          return DropdownButton<String>(
                            isExpanded: true,
                            value: items.any((i) => i.value == _selectedDriverUid)
                                ? _selectedDriverUid
                                : null,
                            hint: const Text("Select driver"),
                            items: items,
                            onChanged: (v) {
                              setState(() => _selectedDriverUid = v);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text("Only available drivers"),
                  value: _onlyAvailableDrivers,
                  onChanged: (v) => setState(() => _onlyAvailableDrivers = v),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    OutlinedButton(
                      onPressed: _selectedStops.isEmpty ? null : _fitToSelectedStops,
                      child: const Text("Fit"),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _selectedStops.isEmpty
                          ? null
                          : () => setState(_selectedStops.clear),
                      child: const Text("Clear"),
                    ),
                    const Spacer(),
                    ElevatedButton(
                      onPressed: _selectedStops.isEmpty || _selectedDriverUid == null
                          ? null
                          : _createManualRoute,
                      child: const Text("Create Route"),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _isSelectedStop(String id) =>
      _selectedStops.any((s) => s.id == id);

  void _toggleSelectedStop({
    required String id,
    required String name,
    required double lat,
    required double lng,
  }) {
    final index = _selectedStops.indexWhere((s) => s.id == id);
    setState(() {
      if (index >= 0) {
        _selectedStops.removeAt(index);
      } else {
        _selectedStops.add(
          _SelectedStop(
            id: id,
            title: name,
            position: LatLng(lat, lng),
          ),
        );
      }
    });
  }

  void _moveSelectedStop(int index, int delta) {
    final next = index + delta;
    if (next < 0 || next >= _selectedStops.length) return;
    setState(() {
      final item = _selectedStops.removeAt(index);
      _selectedStops.insert(next, item);
    });
  }

  void _removeSelectedStop(int index) {
    setState(() => _selectedStops.removeAt(index));
  }

  void _fitToSelectedStops() {
    if (_selectedStops.isEmpty) return;
    final points = _selectedStops.map((s) => s.position).toList();
    final bounds = LatLngBounds.fromPoints(points);
    _mapController.fitCamera(
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(48)),
    );
  }

  Future<void> _createManualRoute() async {
    final driverUid = _selectedDriverUid;
    if (driverUid == null || _selectedStops.isEmpty) return;

    final db = FirebaseFirestore.instance;
    final routeRef = db.collection('routes').doc();
    final now = FieldValue.serverTimestamp();

    final stops = _selectedStops.map((s) {
      return {
        'refType': 'bin',
        'refId': s.id,
        'title': s.title,
        'lat': s.position.latitude,
        'lng': s.position.longitude,
        'etaMin': null,
        'done': false,
      };
    }).toList();

    final polylinePoints = _selectedStops.map((s) {
      return {
        'lat': s.position.latitude,
        'lng': s.position.longitude,
      };
    }).toList();

    final batch = db.batch();
    batch.set(routeRef, {
      'driverUid': driverUid,
      'status': 'planned',
      'createdAt': now,
      'updatedAt': now,
      'createdBy': 'admin_manual',
      'currentStopIndex': 0,
      'animationState': 'moving',
      'stops': stops,
      'polylinePoints': polylinePoints,
    });

    batch.update(db.collection('users').doc(driverUid), {
      'driverStatus': 'busy',
      'activeRouteId': routeRef.id,
      'updatedAt': now,
    });

    for (final stop in _selectedStops) {
      batch.update(db.collection('bins').doc(stop.id), {
        'assignedDriverUid': driverUid,
        'assignedRouteId': routeRef.id,
        'assignedAt': now,
      });
    }

    await batch.commit();

    if (!mounted) return;
    setState(() {
      _selectedStops.clear();
      _selectedDriverUid = null;
      _routeBuilderMode = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Route created.")),
    );
  }

  List<Marker> _buildSelectedStopMarkers() {
    return _selectedStops.asMap().entries.map((entry) {
      final index = entry.key + 1;
      final stop = entry.value;

      return Marker(
        point: stop.position,
        width: 36,
        height: 36,
        child: Tooltip(
          message: stop.title,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.deepPurple.withOpacity(0.95),
              shape: BoxShape.circle,
              boxShadow: const [
                BoxShadow(blurRadius: 6, offset: Offset(0, 2))
              ],
            ),
            child: Center(
              child: Text(
                '$index',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  Color _statusColor(String status, int level) {
    if (level <= 0 || status == 'normal') return Colors.green;
    switch (status) {
      case 'critical':
        return Colors.red;
      case 'warning':
        return Colors.orange;
      default:
        return Colors.green;
    }
  }

  Widget _legend() {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          _legendItem(color: Colors.green, label: "Normal"),
          const SizedBox(width: 14),
          _legendItem(color: Colors.orange, label: "Warning"),
          const SizedBox(width: 14),
          _legendItem(color: Colors.red, label: "Critical"),
        ],
      ),
    );
  }

  Widget _legendItem({required Color color, required String label}) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(label),
      ],
    );
  }

  Widget _bottomPanel() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.showSimulationControls)
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                maintainState: true,
                tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                title: const Text("Simulation"),
                subtitle: const Text("Auto + manual controls"),
                children: const [
                  Padding(
                    padding: EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: BinSimulationPanel(
                      maxListHeight: 280,
                      compact: true,
                    ),
                  ),
                ],
              ),
            ),
          _legend(),
        ],
      ),
    );
  }

  void _showBinSheet({
    required String id,
    required String name,
    required int level,
    required String status,
    required LatLng pos,
  }) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text("Level: $level% - Status: $status"),
            const SizedBox(height: 10),
            Text(
              "Lat: ${pos.latitude.toStringAsFixed(5)}, Lng: ${pos.longitude.toStringAsFixed(5)}",
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _mapController.move(pos, 17);
                },
                icon: const Icon(Icons.zoom_in),
                label: const Text("Zoom here"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteStop {
  const _RouteStop({
    required this.refId,
    required this.title,
    required this.position,
    required this.done,
    required this.raw,
  });

  final String refId;
  final String title;
  final LatLng position;
  final bool done;
  final Map<String, dynamic> raw;

  _RouteStop copyWith({bool? done}) {
    return _RouteStop(
      refId: refId,
      title: title,
      position: position,
      done: done ?? this.done,
      raw: raw,
    );
  }
}

class _SelectedStop {
  const _SelectedStop({
    required this.id,
    required this.title,
    required this.position,
  });

  final String id;
  final String title;
  final LatLng position;
}
