import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class BinSimulator {
  BinSimulator._();
  static final instance = BinSimulator._();

  Timer? _timer;
  bool _running = false;

  final _db = FirebaseFirestore.instance;

  bool get isRunning => _running;

  String _statusFromLevel(int level) {
    if (level >= 85) return 'critical';
    if (level >= 60) return 'warning';
    return 'normal';
  }

  bool _isLocked(Map<String, dynamic> data) {
    final now = DateTime.now();
    final lockedUntil = data['lockedUntil'];
    if (lockedUntil is Timestamp) {
      if (now.isBefore(lockedUntil.toDate())) return true;
    }
    final lastCollectedAt = data['lastCollectedAt'];
    if (lastCollectedAt is Timestamp) {
      final diff = now.difference(lastCollectedAt.toDate());
      if (diff.inSeconds < 60) return true;
    }
    return false;
  }

  void start({int intervalSeconds = 15}) {
    if (!kIsWeb) return;        // your admin is web-only
    if (_running) return;       // prevent double timers

    _running = true;

    _timer = Timer.periodic(Duration(seconds: intervalSeconds), (_) async {
      try {
        final snap = await _db
            .collection('bins')
            .where('isActive', isEqualTo: true)
            .get();

        final docs = snap.docs.toList();
        if (docs.isEmpty) return;

        final rnd = Random();

        // Pick 3..6 bins each tick (skip locked/recently collected)
        final eligible = docs.where((d) => !_isLocked(d.data())).toList();
        if (eligible.isEmpty) return;
        eligible.shuffle(rnd);
        final count = eligible.length < 3 ? eligible.length : (3 + rnd.nextInt(4));
        final chosen = eligible.take(count).toList();

        final batch = _db.batch();
        final now = FieldValue.serverTimestamp();

        for (final d in chosen) {
          final current = (d.data()['level'] as num?)?.toInt() ?? 0;
          final delta = [-15, -10, -5, 5, 10, 15][rnd.nextInt(6)];
          final next = (current + delta).clamp(0, 100);

          batch.update(d.reference, {
            'level': next,
            'status': _statusFromLevel(next),
            'lastUpdatedAt': now,
          });
        }

        await batch.commit();
      } catch (_) {
        // ignore errors so timer doesn't die
      }
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _running = false;
  }
}
