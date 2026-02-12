import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class DriverRouteScreen extends StatefulWidget {
  const DriverRouteScreen({super.key});

  @override
  State<DriverRouteScreen> createState() => _DriverRouteScreenState();
}

class _DriverRouteScreenState extends State<DriverRouteScreen> {
  final MapController _mapController = MapController();

  Timer? _routeTimer;
  double _routeT = 0.0;
  int _routeSegment = 0;
  int _routeTargetIndex = 0;
  int _routeTick = 0;
  final ValueNotifier<LatLng?> _truckPosNotifier = ValueNotifier(null);
  int _lastPausedStopIndex = -1;
  int _lastAnimatedStopIndex = -1;
  bool _collecting = false;

  List<_RouteStop> _routeStops = [];
  List<LatLng> _routePoints = [];
  String? _routeId;
  String? _routeKey;
  String _routeStatus = 'planned';
  String _animationState = 'paused';
  int _currentStopIndex = 0;

  @override
  void dispose() {
    _stopRouteAnimation(reset: false);
    _truckPosNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text("Please login.")));
    }

    final q = FirebaseFirestore.instance
        .collection('routes')
        .where('driverUid', isEqualTo: user.uid)
        .where('status', whereIn: ['active', 'planned'])
        .limit(1);

    return Scaffold(
      appBar: AppBar(title: const Text("Route")),
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
          if (docs.isEmpty) {
            return const Center(child: Text("No active route."));
          }

          final routeDoc = docs.first;
          _syncRoute(routeDoc);

          final center = _initialCenter();
          final currentStop = _currentStop();

          return Column(
            children: [
              Expanded(
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: center,
                    initialZoom: 14,
                    interactionOptions:
                        const InteractionOptions(flags: InteractiveFlag.all),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                      userAgentPackageName: "com.yourcompany.ugswms",
                    ),
                    if (_routePoints.length >= 2)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: _routePoints,
                            strokeWidth: 4,
                            color: Colors.blueAccent,
                          ),
                        ],
                      ),
                    MarkerLayer(markers: _buildStopMarkers()),
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
              ),
              _buildBottomPanel(currentStop),
            ],
          );
        },
      ),
    );
  }

  void _syncRoute(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final stops = _parseStops(data);
    final key = '${doc.id}|${stops.map((s) => s.position).join('|')}';

    final rawIndex = (data['currentStopIndex'] as num?)?.toInt() ?? 0;
    final nextAnim = (data['animationState'] ?? 'moving').toString();
    final nextStatus = (data['status'] ?? 'planned').toString();
    final nextIndex = nextStatus == 'planned' ? 0 : rawIndex;

    if (key == _routeKey) {
      final updatedStops = _mergeStopDone(_routeStops, stops);
      final stopChanged = updatedStops != null;
      final indexChanged = _currentStopIndex != nextIndex;
      final animChanged = _animationState != nextAnim;
      final statusChanged = _routeStatus != nextStatus;
      final stateChanged = indexChanged || animChanged || statusChanged;

      if (stopChanged || stateChanged) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            if (updatedStops != null) _routeStops = updatedStops;
            _currentStopIndex = nextIndex;
            _animationState = nextAnim;
            _routeStatus = nextStatus;
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
        stops: stops,
        currentStopIndex: nextIndex,
        animationState: nextAnim,
        status: nextStatus,
      );
    });
  }

  void _applyRoute({
    required String id,
    required List<_RouteStop> stops,
    required int currentStopIndex,
    required String animationState,
    required String status,
  }) {
    _routeId = id;
    _routeStops = stops;
    _routePoints = stops.map((s) => s.position).toList();
    _routeKey = '$id|${stops.map((s) => s.position).join('|')}';
    _currentStopIndex = status == 'planned' ? 0 : currentStopIndex;
    _animationState = animationState;
    _routeStatus = status;
    _routeSegment = 0;
    _routeTargetIndex = 0;
    _routeT = 0.0;
    _routeTick = 0;
    _lastPausedStopIndex = -1;
    _lastAnimatedStopIndex = -1;

    final startIndex = _currentStopIndex <= 0 ? 0 : _currentStopIndex - 1;
    _truckPosNotifier.value =
        _routePoints.isNotEmpty
            ? _routePoints[startIndex.clamp(0, _routePoints.length - 1)]
            : null;
    _prepareSegmentAndMaybeAnimate();
  }

  void _prepareSegmentAndMaybeAnimate() {
    _stopRouteAnimation(reset: false);
    if (_routePoints.isEmpty) {
      _truckPosNotifier.value = null;
      return;
    }

    if (_animationState == 'moving' &&
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
      if (_animationState == 'moving') {
        _pauseAtStopIfNeeded(_routeTargetIndex);
      }
      return;
    }
    if (_animationState != 'moving') {
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
    if (_animationState != 'moving') return;
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

      final step = 0.02;
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
        debugPrint('Driver truck update: segment=$_routeSegment t=$_routeT pos=$p');
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
    if (_animationState != 'moving') return;
    if (stopIndex != _currentStopIndex) return;
    if (_lastPausedStopIndex == stopIndex) return;

    final stop = _routeStops[stopIndex];
    if (stop.done) return;

    _lastPausedStopIndex = stopIndex;
    await FirebaseFirestore.instance.collection('routes').doc(_routeId!).update({
      'animationState': 'paused',
      'updatedAt': FieldValue.serverTimestamp(),
    });
    if (!mounted) return;
    setState(() => _animationState = 'paused');
  }

  Future<void> _markCollected() async {
    final routeId = _routeId;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (routeId == null || uid == null) return;
    if (_collecting) return;

    setState(() => _collecting = true);

    String binId = '';
    String binTitle = '';
    int stopIndex = 0;
    bool isLast = false;
    final lockedUntil =
        Timestamp.fromDate(DateTime.now().add(const Duration(seconds: 60)));

    try {
      debugPrint("MARK_COLLECTED pressed route=$routeId uid=$uid");

      await FirebaseFirestore.instance.runTransaction((tx) async {
        final ref =
            FirebaseFirestore.instance.collection('routes').doc(routeId);
        final snap = await tx.get(ref);

        if (!snap.exists) throw Exception("Route doc missing");
        final data = snap.data() as Map<String, dynamic>;

        final int i = (data['currentStopIndex'] ?? 0) as int;
        debugPrint(
            "TX READ currentStopIndex=$i animationState=${data['animationState']}");

        final List stops = List.from(data['stops'] ?? []);
        if (i < 0 || i >= stops.length) {
          throw Exception("Invalid currentStopIndex=$i stopsLen=${stops.length}");
        }

        final stop = Map<String, dynamic>.from(stops[i] as Map);
        stop['done'] = true;
        stops[i] = stop;

        final bool last = (i == stops.length - 1);

        tx.update(ref, {
          'stops': stops,
          'currentStopIndex': last ? i : (i + 1),
          'animationState': last ? 'completed' : 'moving',
          'status': last ? 'completed' : 'active',
          'updatedAt': FieldValue.serverTimestamp(),
          if (last) 'completedAt': FieldValue.serverTimestamp(),
        });

        binId = (stop['refId'] ?? '').toString();
        binTitle = (stop['title'] ?? 'Bin').toString();
        stopIndex = i;
        isLast = last;

        if (binId.isNotEmpty) {
          tx.update(
            FirebaseFirestore.instance.collection('bins').doc(binId),
            {
              'status': 'normal',
              'level': 0,
              'fillLevel': 0,
              'lastCollectedAt': FieldValue.serverTimestamp(),
              'lockedUntil': lockedUntil,
              'assignedDriverUid': null,
              'assignedRouteId': null,
              'updatedAt': FieldValue.serverTimestamp(),
            },
          );
        }

        if (last) {
          tx.update(
            FirebaseFirestore.instance.collection('users').doc(uid),
            {
              'driverStatus': 'available',
              'activeRouteId': null,
              'updatedAt': FieldValue.serverTimestamp(),
            },
          );
        }
      });

      await FirebaseFirestore.instance.collection('route_events').add({
        'type': 'stop_completed',
        'routeId': routeId,
        'stopIndex': stopIndex,
        'binId': binId,
        'binTitle': binTitle,
        'driverUid': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });

      debugPrint("MARK_COLLECTED DONE ✅");
    } catch (e, st) {
      debugPrint("MARK_COLLECTED ERROR ❌ $e");
      debugPrint("$st");
    } finally {
      if (mounted) setState(() => _collecting = false);
    }
  }

  Widget _buildBottomPanel(_RouteStop? currentStop) {
    final total = _routeStops.length;
    final index = _currentStopIndex.clamp(0, total == 0 ? 0 : total - 1);
    final label = currentStop == null
        ? "No stops"
        : "Current stop: ${currentStop.title} (${index + 1} of $total)";

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed:
                  currentStop == null || currentStop.done || _collecting
                      ? null
                      : _markCollected,
              icon: const Icon(Icons.check_circle_outline),
              label: Text(currentStop?.done == true
                  ? "Collected"
                  : "Mark Collected"),
            ),
          ),
        ],
      ),
    );
  }

  List<_RouteStop> _parseStops(Map<String, dynamic> data) {
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

  LatLng _lerpLatLng(LatLng a, LatLng b, double t) {
    return LatLng(
      a.latitude + (b.latitude - a.latitude) * t,
      a.longitude + (b.longitude - a.longitude) * t,
    );
  }

  LatLng _initialCenter() {
    if (_truckPosNotifier.value != null) {
      return _truckPosNotifier.value!;
    }
    if (_routePoints.isNotEmpty) {
      return _routePoints.first;
    }
    return const LatLng(0.5143, 35.2698);
  }

  _RouteStop? _currentStop() {
    if (_routeStops.isEmpty) return null;
    final index = _currentStopIndex.clamp(0, _routeStops.length - 1);
    return _routeStops[index];
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
