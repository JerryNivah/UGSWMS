import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class ReportsSnapshot {
  ReportsSnapshot({
    required this.totalUsers,
    required this.newUsers,
    required this.serviceRequests,
    required this.completedJobs,
    required this.requestStatusCounts,
    required this.requestTypeCounts,
    required this.routesCreated,
    required this.routesCompleted,
    required this.avgStopsPerRoute,
    required this.driverStats,
    required this.hasRangeData,
  });

  final int totalUsers;
  final int newUsers;
  final int serviceRequests;
  final int completedJobs;

  final Map<String, int> requestStatusCounts;
  final Map<String, int> requestTypeCounts;

  final int routesCreated;
  final int routesCompleted;
  final double avgStopsPerRoute;

  final List<DriverReport> driverStats;

  final bool hasRangeData;
}

class DriverReport {
  DriverReport({
    required this.uid,
    required this.name,
    required this.assigned,
    required this.completed,
  });

  final String uid;
  final String name;
  final int assigned;
  final int completed;

  double get completionRate =>
      assigned == 0 ? 0 : (completed / assigned) * 100.0;
}

class ReportsService {
  ReportsService({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;
  static const int _maxSampleDocs = 1000;

  Future<ReportsSnapshot> fetch({DateTimeRange? range}) async {
    final now = DateTime.now();
    final start = range?.start;
    final end = range?.end ?? now;

    final startTs = start == null ? null : Timestamp.fromDate(start);
    final endTs = Timestamp.fromDate(end);

    // Prefer aggregation counts to avoid reading large collections on web/mobile.
    // When we need docs for breakdowns, use a capped sample to prevent unbounded reads.
    Future<int> _count(Query<Map<String, dynamic>> q) async {
      try {
        final snap = await q.count().get();
        return snap.count ?? 0;
      } catch (_) {
        // Fallback cap: avoid unbounded reads if aggregation is unavailable.
        final snap = await q.limit(_maxSampleDocs).get();
        return snap.docs.length;
      }
    }

    Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _getDocs(
      Query<Map<String, dynamic>> q, {
      int? limit,
    }) async {
      if (limit != null) {
        q = q.limit(limit);
      }
      final snap = await q.get();
      return snap.docs;
    }

    Query<Map<String, dynamic>> _applyRange(
      Query<Map<String, dynamic>> q,
      String field,
    ) {
      if (startTs != null) {
        q = q.where(field, isGreaterThanOrEqualTo: startTs);
      }
      if (endTs != null) {
        q = q.where(field, isLessThanOrEqualTo: endTs);
      }
      return q;
    }

    // Users
    final totalUsers = await _count(_db.collection('users'));

    int newUsers = totalUsers;
    if (startTs != null) {
      newUsers = await _count(
        _applyRange(_db.collection('users').orderBy('createdAt'), 'createdAt'),
      );
    }

    // Service requests
    final serviceRequests = await _count(
      _applyRange(
        _db.collection('service_requests').orderBy('createdAt'),
        'createdAt',
      ),
    );
    final reqDocs = await _getDocs(
      _applyRange(
        _db.collection('service_requests').orderBy('createdAt'),
        'createdAt',
      ),
      limit: _maxSampleDocs,
    );

    final requestStatusCounts = <String, int>{};
    final requestTypeCounts = <String, int>{};
    for (final d in reqDocs) {
      final data = d.data();
      final status = (data['status'] ?? 'unknown').toString();
      final type = (data['requestType'] ?? 'unknown').toString();
      requestStatusCounts[status] = (requestStatusCounts[status] ?? 0) + 1;
      requestTypeCounts[type] = (requestTypeCounts[type] ?? 0) + 1;
    }

    // Assignments (jobs)
    final assignedDocs = await _getDocs(
      _applyRange(
        _db.collection('assignments').orderBy('createdAt'),
        'createdAt',
      ),
      limit: _maxSampleDocs,
    );

    // Use updatedAt so completed docs without completedAt are still counted.
    // Composite index required: assignments(status ASC, updatedAt DESC)
    final completedJobs = await _count(
      _applyRange(
        _db
            .collection('assignments')
            .where('status', isEqualTo: 'completed')
            .orderBy('updatedAt', descending: true),
        'updatedAt',
      ),
    );
    final completedDocs = await _getDocs(
      _applyRange(
        _db
            .collection('assignments')
            .where('status', isEqualTo: 'completed')
            .orderBy('updatedAt', descending: true),
        'updatedAt',
      ),
      limit: _maxSampleDocs,
    );

    final assignedByDriver = <String, int>{};
    final completedByDriver = <String, int>{};

    for (final d in assignedDocs) {
      final uid = (d.data()['driverUid'] ?? '').toString();
      if (uid.isEmpty) continue;
      assignedByDriver[uid] = (assignedByDriver[uid] ?? 0) + 1;
    }
    for (final d in completedDocs) {
      final uid = (d.data()['driverUid'] ?? '').toString();
      if (uid.isEmpty) continue;
      completedByDriver[uid] = (completedByDriver[uid] ?? 0) + 1;
    }

    final driverNameByUid = <String, String>{};
    final driverDocs = await _getDocs(
      _db.collection('users').where('role', isEqualTo: 'driver'),
      limit: _maxSampleDocs,
    );
    for (final d in driverDocs) {
      final data = d.data();
      final name = (data['name'] ??
              data['fullName'] ??
              data['email'] ??
              'Driver')
          .toString();
      driverNameByUid[d.id] = name;
    }

    final driverUids = <String>{
      ...assignedByDriver.keys,
      ...completedByDriver.keys,
    };

    final driverStats = driverUids
        .map(
          (uid) => DriverReport(
            uid: uid,
            name: driverNameByUid[uid] ?? 'Driver',
            assigned: assignedByDriver[uid] ?? 0,
            completed: completedByDriver[uid] ?? 0,
          ),
        )
        .toList()
      ..sort((a, b) => b.completed.compareTo(a.completed));

    // Routes
    final routesCreated = await _count(
      _applyRange(_db.collection('routes').orderBy('createdAt'), 'createdAt'),
    );
    final routesCreatedDocs = await _getDocs(
      _applyRange(_db.collection('routes').orderBy('createdAt'), 'createdAt'),
      limit: _maxSampleDocs,
    );

    int stopsTotal = 0;
    for (final d in routesCreatedDocs) {
      final stops = d.data()['stops'];
      if (stops is List) {
        stopsTotal += stops.length;
      }
    }
    final avgStopsPerRoute =
        routesCreated == 0 ? 0.0 : (stopsTotal / routesCreated);

    // Composite index required: routes(status ASC, completedAt DESC)
    final routesCompleted = await _count(
      _applyRange(
        _db
            .collection('routes')
            .where('status', isEqualTo: 'completed')
            .orderBy('completedAt', descending: true),
        'completedAt',
      ),
    );

    final hasRangeData = serviceRequests > 0 ||
        newUsers > 0 ||
        completedJobs > 0 ||
        routesCreated > 0 ||
        routesCompleted > 0 ||
        assignedDocs.isNotEmpty ||
        completedDocs.isNotEmpty;

    return ReportsSnapshot(
      totalUsers: totalUsers,
      newUsers: newUsers,
      serviceRequests: serviceRequests,
      completedJobs: completedJobs,
      requestStatusCounts: requestStatusCounts,
      requestTypeCounts: requestTypeCounts,
      routesCreated: routesCreated,
      routesCompleted: routesCompleted,
      avgStopsPerRoute: avgStopsPerRoute,
      driverStats: driverStats,
      hasRangeData: hasRangeData,
    );
  }
}
