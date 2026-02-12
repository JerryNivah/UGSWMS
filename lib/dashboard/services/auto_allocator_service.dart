import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class AutoAllocatorService {
  AutoAllocatorService({
    this.maxStopsPerRoute = 6,
    this.clusterRadiusKm = 2.5,
  });

  final int maxStopsPerRoute;
  final double clusterRadiusKm;

  StreamSubscription? _binsSub;
  StreamSubscription? _driversSub;
  Timer? _debounce;
  bool _running = false;

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _criticalBins = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _availableDrivers = [];

  void start() {
    if (!kIsWeb) return;
    stop();

    // Critical unassigned bins
    _binsSub = FirebaseFirestore.instance
        .collection('bins')
        .where('status', isEqualTo: 'critical')
        .where('assignedDriverUid', isEqualTo: null)
        .snapshots()
        .listen((snap) {
      _criticalBins = snap.docs;
      _scheduleRun();
    });

    // Available drivers (drivers in users collection)
    _driversSub = FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'driver')
        .where('status', isEqualTo: 'active') // account status field
        .where('driverStatus', isEqualTo: 'available')
        .snapshots()
        .listen((snap) {
      _availableDrivers = snap.docs;
      _scheduleRun();
    });
  }

  void stop() {
    _binsSub?.cancel();
    _driversSub?.cancel();
    _debounce?.cancel();
    _binsSub = null;
    _driversSub = null;
    _debounce = null;
    _running = false;
  }

  void _scheduleRun() {
    // debounce to avoid multiple triggers per second
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      _runOnce();
    });
  }

  bool _isAutoLocked(Map<String, dynamic> data) {
    final until = data['autoAllocateLockedUntil'];
    if (until is Timestamp) {
      return DateTime.now().isBefore(until.toDate());
    }
    return false;
  }

  Future<void> _runOnce() async {
    if (_running) return;
    if (_criticalBins.isEmpty) return;
    if (_availableDrivers.isEmpty) return;

    _running = true;
    try {
      final bins = <_Bin>[];
      for (final d in _criticalBins) {
        final data = d.data();
        if (_isAutoLocked(data)) continue;
        final lat = (data['lat'] as num?)?.toDouble();
        final lng = (data['lng'] as num?)?.toDouble();
        if (lat == null || lng == null) continue;
        bins.add(_Bin(id: d.id, data: data, lat: lat, lng: lng));
      }

      if (bins.isEmpty) return;

      final drivers = _availableDrivers.map((d) => _Driver(d.id, d.data())).toList();

      // Greedy: for each driver, take nearest bin then cluster nearby bins
      for (final drv in drivers) {
        if (bins.isEmpty) break;

        final dLat = (drv.data['lastLat'] as num?)?.toDouble();
        final dLng = (drv.data['lastLng'] as num?)?.toDouble();
        if (dLat == null || dLng == null) continue; // no location yet

        bins.sort((a, b) {
          final da = _haversineKm(dLat, dLng, a.lat, a.lng);
          final db = _haversineKm(dLat, dLng, b.lat, b.lng);
          return da.compareTo(db);
        });

        final first = bins.removeAt(0);
        final cluster = <_Bin>[first];

        final remaining = <_Bin>[];
        for (final b in bins) {
          final dist = _haversineKm(first.lat, first.lng, b.lat, b.lng);
          if (dist <= clusterRadiusKm && cluster.length < maxStopsPerRoute) {
            cluster.add(b);
          } else {
            remaining.add(b);
          }
        }
        bins
          ..clear()
          ..addAll(remaining);

        await _assignRoute(driverUid: drv.uid, bins: cluster);
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _assignRoute({
    required String driverUid,
    required List<_Bin> bins,
  }) async {
    if (bins.isEmpty) return;

    final db = FirebaseFirestore.instance;
    final routeRef = db.collection('routes').doc();
    final driverRef = db.collection('users').doc(driverUid);

    await db.runTransaction((tx) async {
      // Re-check driver is still available
      final driverSnap = await tx.get(driverRef);
      if (!driverSnap.exists) return;

      final d = driverSnap.data() as Map<String, dynamic>;
      if (d['role'] != 'driver') return;
      if (d['status'] != 'active') return;
      if (d['driverStatus'] != 'available') return;

      // Re-check bins still unassigned
      final confirmedBins = <_Bin>[];
      for (final b in bins) {
        final binRef = db.collection('bins').doc(b.id);
        final binSnap = await tx.get(binRef);
        if (!binSnap.exists) continue;

        final bd = binSnap.data() as Map<String, dynamic>;
        final stillCritical = bd['status'] == 'critical';
        final stillUnassigned = bd['assignedDriverUid'] == null;
        final lat = (bd['lat'] as num?)?.toDouble();
        final lng = (bd['lng'] as num?)?.toDouble();

        if (_isAutoLocked(bd)) continue;
        if (stillCritical && stillUnassigned && lat != null && lng != null) {
          confirmedBins.add(_Bin(id: b.id, data: bd, lat: lat, lng: lng));
        }
      }

      if (confirmedBins.isEmpty) return;

      final stops = confirmedBins.map((b) {
        return {
          'refType': 'bin',
          'refId': b.id,
          'title': (b.data['name'] ?? 'Bin').toString(),
          'lat': b.lat,
          'lng': b.lng,
          'etaMin': null,
          'done': false,
        };
      }).toList();

      // Create route
      tx.set(routeRef, {
        'driverUid': driverUid,
        'status': 'active',
        'currentStopIndex': 0,
        'animationState': 'moving',
        'stops': stops,
        'polyline': null,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'createdBy': 'system_demo',
      });

      // Mark driver busy
      tx.update(driverRef, {
        'driverStatus': 'busy',
        'activeRouteId': routeRef.id,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Assign bins
      for (final b in confirmedBins) {
        final binRef = db.collection('bins').doc(b.id);
        tx.update(binRef, {
          'assignedDriverUid': driverUid,
          'assignedRouteId': routeRef.id,
          'assignedAt': FieldValue.serverTimestamp(),
        });
      }

      // "Notification" doc (billing-free)
      tx.set(db.collection('notifications').doc(), {
        'toUid': driverUid,
        'type': 'route_assigned',
        'title': 'New route assigned',
        'body': 'You have been assigned ${confirmedBins.length} bin(s) to collect.',
        'routeId': routeRef.id,
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  double _haversineKm(double aLat, double aLng, double bLat, double bLng) {
    const r = 6371.0;
    final dLat = _deg2rad(bLat - aLat);
    final dLng = _deg2rad(bLng - aLng);
    final s1 = math.sin(dLat / 2);
    final s2 = math.sin(dLng / 2);
    final q = s1 * s1 + math.cos(_deg2rad(aLat)) * math.cos(_deg2rad(bLat)) * s2 * s2;
    return 2 * r * math.asin(math.min(1, math.sqrt(q)));
  }

  double _deg2rad(double d) => d * 3.141592653589793 / 180.0;
}

class _Driver {
  _Driver(this.uid, this.data);
  final String uid;
  final Map<String, dynamic> data;
}

class _Bin {
  _Bin({required this.id, required this.data, required this.lat, required this.lng});

  final String id;
  final Map<String, dynamic> data;
  final double lat;
  final double lng;
}
