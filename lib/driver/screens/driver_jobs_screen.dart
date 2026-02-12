import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:ugswms/driver/screens/driver_route_screen.dart';
import 'package:ugswms/shared/notifications_screen.dart';

/// Driver Jobs Screen
/// - Lists assignments for the logged-in driver
/// - Shows live status from Firestore
/// - Accept / Complete updates BOTH:
///   1) assignments/{assignmentId}.status
///   2) service_requests/{requestId}.assignmentStatus
///   3) service_requests/{requestId}.status  âœ… (what user app reads)
///
/// NOTE:
/// This requires indexes if you use orderBy(createdAt):
/// assignments: driverUid (ASC) + createdAt (DESC)
class DriverJobsScreen extends StatelessWidget {
  const DriverJobsScreen({super.key});

  static const String assignmentsCol = 'assignments';
  static const String requestsCol = 'service_requests';

  // âœ… Match the admin mapping logic (so user app stays in sync)
  String _requestStatusFromAssignmentStatus(String s) {
    final v = s.toLowerCase().trim();
    if (v == 'pending') return 'assigned'; // assigned but not accepted yet
    if (v == 'accepted') return 'accepted';
    if (v == 'completed' || v == 'done') return 'completed';
    if (v == 'cancelled') return 'cancelled';
    return 'assigned';
  }

  Future<void> _driverSetStatus({
    required BuildContext context,
    required String assignmentId,
    required String requestId,
    required String newStatus,
  }) async {
    try {
      final db = FirebaseFirestore.instance;
      final batch = db.batch();
      final now = FieldValue.serverTimestamp();

      final aRef = db.collection(assignmentsCol).doc(assignmentId);
      DocumentReference<Map<String, dynamic>>? rRef;

      if (requestId.trim().isNotEmpty) {
        rRef = db.collection(requestsCol).doc(requestId);
      } else {
        final driverUid = FirebaseAuth.instance.currentUser?.uid;
        final q = await db
            .collection(requestsCol)
            .where('assignmentId', isEqualTo: assignmentId)
            .where('assignedDriverUid', isEqualTo: driverUid)
            .limit(1)
            .get();
        if (q.docs.isEmpty) {
          throw Exception(
            "Service request not found for assignment $assignmentId.",
          );
        }
        rRef = q.docs.first.reference;
      }

      // âœ… Update assignment
      batch.update(aRef, {'status': newStatus, 'updatedAt': now});

      // âœ… Update service request (user app reads this!)
      final requestStatus = _requestStatusFromAssignmentStatus(newStatus);

      batch.update(rRef, {
        'assignmentStatus': newStatus,
        'status': requestStatus,
        'updatedAt': now,
        if (newStatus == 'completed') 'completedAt': now,
        if (newStatus == 'cancelled') 'cancelledAt': now,
      });

      await batch.commit();

      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Updated â†’ $newStatus âœ…")));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Update failed âŒ: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(body: Center(child: Text("Please login first.")));
    }

    final q = FirebaseFirestore.instance
        .collection(assignmentsCol)
        .where('driverUid', isEqualTo: user.uid)
        .orderBy('createdAt', descending: true)
        .limit(50);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Jobs"),
        actions: [
          IconButton(
            tooltip: "Map",
            icon: const Icon(Icons.map_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const DriverRouteScreen(),
                ),
              );
            },
          ),
          IconButton(
            tooltip: "Notifications",
            icon: const Icon(Icons.notifications_rounded),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const NotificationsScreen(
                    recipientRole: 'driver',
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: q.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Text("Failed to load jobs: ${snap.error}"),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return const Center(child: Text("No assignments yet."));
          }

          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final assignmentDoc = docs[i];
              final a = assignmentDoc.data();

              final assignmentId = assignmentDoc.id;
              final requestId = (a['requestId'] ?? '').toString();

              final serviceType = (a['serviceType'] ?? 'Assignment').toString();
              final pickup = (a['pickupAddressText'] ?? '').toString();
              final qty = (a['quantity'] ?? '').toString();
              final requestType = (a['requestType'] ?? 'unknown').toString();
              final source = (a['source'] ?? 'unknown').toString();
              final paymentRequired = (a['paymentRequired'] ?? false) == true;

              final status = (a['status'] ?? 'pending')
                  .toString()
                  .toLowerCase();

              // Simple UI state
              final canAccept = status == 'pending';
              final canComplete = status == 'accepted';

              return ListTile(
                title: Text(serviceType),
                subtitle: Text(
                  [
                    if (pickup.isNotEmpty) pickup,
                    if (qty.isNotEmpty) "qty: $qty",
                    "status: $status",
                    if (requestId.isNotEmpty) "req: $requestId",
                    if (requestType != 'unknown') "type: $requestType",
                    if (source != 'unknown') "source: $source",
                    if (paymentRequired) "paid",
                  ].join(" - "),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: PopupMenuButton<String>(
                  enabled: requestId.isNotEmpty,
                  onSelected: (v) async {
                    // guard: don't allow invalid jumps
                    final vv = v.toLowerCase();
                    if (vv == 'accepted' && !canAccept) return;
                    if (vv == 'completed' && !canComplete) return;

                    await _driverSetStatus(
                      context: context,
                      assignmentId: assignmentId,
                      requestId: requestId,
                      newStatus: vv,
                    );
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'accepted',
                      enabled: canAccept,
                      child: const Text('Accept'),
                    ),
                    PopupMenuItem(
                      value: 'completed',
                      enabled: canComplete,
                      child: const Text('Complete'),
                    ),
                    // optional but useful
                    PopupMenuItem(
                      value: 'cancelled',
                      enabled: status != 'completed' && status != 'cancelled',
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}


