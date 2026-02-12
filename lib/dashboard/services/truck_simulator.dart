import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

class TruckSimulator {
  Timer? _timer;
  bool _running = false;
  bool _tickRunning = false;
  int _index = 0;
  String? _driverUid;
  List<LatLng> _path = const [];

  bool get isRunning => _running;
  String? get driverUid => _driverUid;

  void start({
    required String driverUid,
    required List<LatLng> path,
    int intervalMs = 700,
    bool loop = true,
  }) {
    if (path.isEmpty) return;

    stop();
    _driverUid = driverUid;
    _path = path;
    _index = 0;
    _running = true;

    _timer = Timer.periodic(Duration(milliseconds: intervalMs), (_) async {
      if (!_running || _tickRunning) return;
      _tickRunning = true;

      try {
        if (_index >= _path.length) {
          if (loop) {
            _index = 0;
          } else {
            stop();
            return;
          }
        }

        final p = _path[_index];
        _index += 1;

        await FirebaseFirestore.instance
            .collection('users')
            .doc(driverUid)
            .update({
          'lastLat': p.latitude,
          'lastLng': p.longitude,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } finally {
        _tickRunning = false;
      }
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _running = false;
    _tickRunning = false;
    _index = 0;
    _driverUid = null;
    _path = const [];
  }
}
