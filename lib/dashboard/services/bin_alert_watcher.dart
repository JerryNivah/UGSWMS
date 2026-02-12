import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

class BinAlertWatcher {
  BinAlertWatcher._();
  static final instance = BinAlertWatcher._();

  StreamSubscription? _sub;
  final _db = FirebaseFirestore.instance;

  void start() {
    _sub?.cancel();

    _sub = _db
        .collection('bins')
        .where('isActive', isEqualTo: true)
        .snapshots()
        .listen((snap) async {
      for (final change in snap.docChanges) {
        if (change.type != DocumentChangeType.modified &&
            change.type != DocumentChangeType.added) continue;

        final binRef = change.doc.reference;
        final data = change.doc.data() ?? {};

        final status = (data['status'] ?? 'normal').toString();
        final name = (data['name'] ?? 'Bin').toString();
        final area = (data['area'] ?? '').toString();
        final level = (data['level'] as num?)?.toInt() ?? 0;

        final lat = (data['lat'] as num?)?.toDouble();
        final lng = (data['lng'] as num?)?.toDouble();

        final openAlertRequestId = (data['openAlertRequestId'] ?? '').toString();

        // Only trigger when critical and no open alert exists
        if (status != 'critical') continue;
        if (openAlertRequestId.isNotEmpty) continue;
        if (lat == null || lng == null) continue;

        // Create a service_request representing "bin full alert"
        final reqRef = _db.collection('service_requests').doc();

        final now = FieldValue.serverTimestamp();

        // NOTE: This is an admin-created request.
        // For demo, we can set userUid to admin or a system user.
        // If you want, we can create a dedicated system user later.
        const systemEmail = "admin@ugswms.com";

        await _db.runTransaction((tx) async {
          // Re-check inside transaction to avoid duplicates
          final fresh = await tx.get(binRef);
          final freshData = fresh.data() as Map<String, dynamic>? ?? {};
          final freshStatus = (freshData['status'] ?? 'normal').toString();
          final freshOpen = (freshData['openAlertRequestId'] ?? '').toString();

          if (freshStatus != 'critical' || freshOpen.isNotEmpty) return;

          tx.set(reqRef, {
            'serviceType': 'bin_alert',
            'wasteType': 'general',
            'quantity': '1 bin',
            'pickupAddressText': area.isEmpty ? name : area,
            'notes': 'AUTO: Bin is critical ($level%). Please dispatch.',
            'status': 'pending',
            'source': 'bin_alert',
            'requestType': 'public_bin',
            'paymentRequired': false,
            'assignmentStatus': null,
            'assignmentId': null,
            'assignedDriverUid': null,
            'createdAt': now,
            'updatedAt': now,

            // "system" fields to link back to bin
            'binId': change.doc.id,
            'binName': name,
            'lat': lat,
            'lng': lng,

            // use admin as creator for now
            'userEmail': systemEmail,
            'userUid': 'SYSTEM', // you can keep 'SYSTEM' for demo
          });

          tx.update(binRef, {
            'openAlertRequestId': reqRef.id,
            'openAlertStatus': 'pending',
            'lastUpdatedAt': now,
          });
        });
      }
    });
  }

  void stop() => _sub?.cancel();
}
