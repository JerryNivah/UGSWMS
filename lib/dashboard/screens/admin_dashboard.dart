import 'dart:async';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:ugswms/core/screens/eldoret_bins_map_screen.dart';
import 'package:ugswms/core/services/osrm_service.dart';
import 'package:ugswms/dashboard/screens/bin_simulation_screen.dart';
import 'package:ugswms/dashboard/screens/admin_assignments_panel.dart';
import 'package:ugswms/dashboard/screens/reports/admin_reports_page.dart';
import 'package:ugswms/dashboard/services/bin_alert_watcher.dart';
import 'package:ugswms/dashboard/services/bin_simulator.dart';
import 'package:ugswms/dashboard/services/auto_allocator_service.dart';
import 'package:ugswms/dashboard/services/truck_simulator.dart';
import 'package:ugswms/shared/notifications_inbox.dart';

final ValueNotifier<bool> _adminDarkMode = ValueNotifier(false);

Color get _text => _adminDarkMode.value ? const Color(0xFFE2E8F0) : const Color(0xFF0F172A); // slate-200/900
Color get _textSoft => _adminDarkMode.value ? const Color(0xFF94A3B8) : const Color(0xFF475569); // slate-400/600
Color get _surface => _adminDarkMode.value ? const Color(0xE60B1220) : const Color(0xF2FFFFFF); // dark glass / ~95% white
Color get _border => _adminDarkMode.value ? const Color(0x33E2E8F0) : const Color(0x1F0F172A); // subtle border
Color get _bgTop => _adminDarkMode.value ? const Color(0xFF0B1120) : const Color(0xFFF8FAFC);
Color get _bgMid => _adminDarkMode.value ? const Color(0xFF0F172A) : const Color(0xFFFFFFFF);
Color get _bgBot => _adminDarkMode.value ? const Color(0xFF111827) : const Color(0xFFF1F5F9);

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({
    super.key,
    required this.isSuperAdmin,
    required this.onLogout,
  });

  final bool isSuperAdmin;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) {
      return const _BlockedScreen(
        title: "Admin Dashboard (Web Only)",
        message: "This admin dashboard is only accessible on the web.",
      );
    }

    if (!isSuperAdmin) {
      return const _BlockedScreen(
        title: "Access denied",
        message: "You don't have permission to access the admin dashboard.",
      );
    }

    return _AdminDashboardScaffold(onLogout: onLogout);
  }
}

class _AdminDashboardScaffold extends StatefulWidget {
  const _AdminDashboardScaffold({required this.onLogout});
  final VoidCallback onLogout;

  @override
  State<_AdminDashboardScaffold> createState() =>
      _AdminDashboardScaffoldState();
}

class _AdminDashboardScaffoldState extends State<_AdminDashboardScaffold> {
  static const Color _accent = Color(0xFF3B82F6);

  late final AutoAllocatorService _allocator;
  late final TruckSimulator _truckSimulator;
  bool _truckDemoRunning = false;
  String? _truckDemoDriverUid;
  bool _showAnalyticsButton = true;
  bool _showRecentActivity = true;
  bool _compactCards = false;
  bool _autoRefresh = true;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _completionSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _assignmentSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _requestsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _driverPendingSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _supportSub;

  // âœ… Light theme background constants (add here if you haven't yet)

  void _goTo(int index, {String? searchPreset}) {
    setState(() {
      _selectedIndex = index;
    });

    if (searchPreset != null) {
      _searchController.text = searchPreset;
      _setSearch(searchPreset);
    }
  }

  int _selectedIndex = 0;

  final TextEditingController _searchController = TextEditingController();
  String _search = "";

  final _navItems = const [
    _NavItem(icon: Icons.dashboard_rounded, label: "Overview"),
    _NavItem(icon: Icons.people_alt_rounded, label: "Users"),
    _NavItem(icon: Icons.local_shipping_rounded, label: "Drivers"),
    _NavItem(icon: Icons.mail_rounded, label: "Messages"),
    _NavItem(icon: Icons.bar_chart_rounded, label: "Reports"),
    _NavItem(icon: Icons.settings_rounded, label: "Settings"),
    _NavItem(icon: Icons.assignment_ind_rounded, label: "Assignments"),
  ];

  @override
  void initState() {
    super.initState();
    BinAlertWatcher.instance.start();
    _allocator = AutoAllocatorService();
    _allocator.start();
    _truckSimulator = TruckSimulator();
    if (kDebugMode) {
      Future.microtask(() async {
        final snap =
            await FirebaseFirestore.instance.collection('routes').limit(5).get();
        debugPrint("ROUTES GET() size = ${snap.size}");
        for (final d in snap.docs) {
          debugPrint("ROUTE: ${d.id} => ${d.data()}");
        }
      });
    }
    if (_autoRefresh) {
      _startWorkers();
    }
  }

  @override
  void dispose() {
    _stopWorkers();
    BinAlertWatcher.instance.stop();
    BinSimulator.instance.stop();
    _allocator.stop();
    _truckSimulator.stop();
    _searchController.dispose();
    super.dispose();
  }

  void _setSearch(String value) {
    setState(() => _search = value.trim());
  }

  void _openMap() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const EldoretBinsMapScreen(
          showSimulationControls: true,
        ),
      ),
    );
  }

  void _openSimulation() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const BinSimulationScreen(),
      ),
    );
  }

  void _openAnalytics() {
    _goTo(4);
  }

  void _openTruckDemoSheet() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final q = FirebaseFirestore.instance
            .collection('routes')
            .where('status', whereIn: ['active', 'planned'])
            .orderBy('createdAt', descending: true)
            .limit(20);

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: q.snapshots(),
          builder: (context, snap) {
            if (snap.hasError) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Text("Failed to load routes: ${snap.error}"),
              );
            }
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final docs = snap.data!.docs;
            if (docs.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Text("No active/planned routes yet."),
              );
            }

            return ListView.separated(
              shrinkWrap: true,
              itemCount: docs.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final doc = docs[i];
                final data = doc.data();
                final driverUid = (data['driverUid'] ?? '').toString();
                final stops = _routeStopsFromData(data);
                final isRunning =
                    _truckDemoRunning && _truckDemoDriverUid == driverUid;

                return ListTile(
                  title: Text("Driver: $driverUid"),
                  subtitle: Text("Stops: ${stops.length} • ${data['status']}"),
                  trailing: isRunning
                      ? OutlinedButton(
                          onPressed: () {
                            _truckSimulator.stop();
                            setState(() {
                              _truckDemoRunning = false;
                              _truckDemoDriverUid = null;
                            });
                          },
                          child: const Text("Stop"),
                        )
                      : ElevatedButton(
                          onPressed: () async {
                            await _startTruckDemo(driverUid, stops);
                          },
                          child: const Text("Start"),
                        ),
                );
              },
            );
          },
        );
      },
    );
  }

  List<LatLng> _routeStopsFromData(Map<String, dynamic> data) {
    final rawStops = data['stops'];
    if (rawStops is! List) return [];

    final stops = <LatLng>[];
    for (final s in rawStops) {
      if (s is! Map<String, dynamic>) continue;
      final lat = (s['lat'] as num?)?.toDouble();
      final lng = (s['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      stops.add(LatLng(lat, lng));
    }
    return stops;
  }

  Future<void> _startTruckDemo(String driverUid, List<LatLng> stops) async {
    if (driverUid.isEmpty) return;
    if (stops.length < 2) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Route needs at least 2 stops.")),
      );
      return;
    }

    final polyline = await OsrmService.instance.fetchRoutePolyline(stops);
    final path = polyline.isNotEmpty ? polyline : stops;

    _truckSimulator.start(driverUid: driverUid, path: path);

    if (!mounted) return;
    setState(() {
      _truckDemoRunning = true;
      _truckDemoDriverUid = driverUid;
    });
  }

  void _startWorkers() {
    _startCompletionWorker();
    _startAssignmentWorker();
    _startRequestsWorker();
    _startDriverPendingWorker();
    _startSupportTicketWorker();
  }

  void _startCompletionWorker() {
    _completionSub?.cancel();
    _completionSub = FirebaseFirestore.instance
        .collection('assignments')
        .where('status', isEqualTo: 'completed')
        .snapshots()
        .listen((snap) async {
      for (final change in snap.docChanges) {
        if (change.type != DocumentChangeType.modified) continue;
        final data = change.doc.data();
        if (data == null) continue;
        if ((data['status'] ?? '').toString() != 'completed') continue;
        if (data['completionNotified'] == true) continue;

        final assignmentId = change.doc.id;
        var userUid = (data['userUid'] ?? '').toString();
        final driverUid = (data['driverUid'] ?? '').toString();
        final serviceType = (data['serviceType'] ?? '').toString();
        var requestId = (data['requestId'] ?? '').toString();

        if (requestId.isEmpty || userUid.isEmpty) {
          final reqQ = await FirebaseFirestore.instance
              .collection('service_requests')
              .where('assignmentId', isEqualTo: assignmentId)
              .limit(1)
              .get();

          if (reqQ.docs.isNotEmpty) {
            final req = reqQ.docs.first;
            requestId = req.id;
            final reqData = req.data();
            if (userUid.isEmpty) {
              userUid = (reqData['userUid'] ?? '').toString();
            }
          }
        }

        if (userUid.isEmpty) continue;

        await FirebaseFirestore.instance.collection('notifications').add({
          'toUid': userUid,
          'role': 'resident',
          'title': 'Request completed âœ…',
          'body': serviceType.isEmpty
              ? 'Your request has been completed.'
              : 'Your $serviceType request has been completed.',
          'type': 'request_completed',
          'severity': 'low',
          'refType': 'service_request',
          'refId': requestId,
          'extra': {
            'assignmentId': assignmentId,
            'driverUid': driverUid,
            'serviceType': serviceType,
          },
          'read': false,
          'createdAt': FieldValue.serverTimestamp(),
        });

        await FirebaseFirestore.instance.collection('notifications').add({
          'role': 'admin',
          'title': 'Job completed',
          'body': serviceType.isEmpty
              ? 'A driver marked a job as completed.'
              : 'A driver completed: $serviceType.',
          'type': 'assignment_completed',
          'severity': 'low',
          'refType': 'assignment',
          'refId': assignmentId,
          'extra': {
            'assignmentId': assignmentId,
            'driverUid': driverUid,
            'serviceType': serviceType,
          },
          'read': false,
          'createdAt': FieldValue.serverTimestamp(),
        });

        await change.doc.reference.update({
          'completionNotified': true,
          'adminNotifiedCompleted': true,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  void _startAssignmentWorker() {
    _assignmentSub?.cancel();
    _assignmentSub = FirebaseFirestore.instance
        .collection('assignments')
        .where('status', whereIn: ['accepted'])
        .snapshots()
        .listen((snap) async {
      for (final change in snap.docChanges) {
        if (change.type == DocumentChangeType.removed) continue;
        final data = change.doc.data();
        if (data == null) continue;
        if ((data['status'] ?? '').toString() != 'accepted') continue;
        if (data['adminNotifiedAccepted'] == true) continue;

        final assignmentId = change.doc.id;
        final driverUid = (data['driverUid'] ?? '').toString();
        final serviceType = (data['serviceType'] ?? '').toString();
        var userUid = (data['userUid'] ?? '').toString();
        var requestId = (data['requestId'] ?? '').toString();

        await FirebaseFirestore.instance.collection('notifications').add({
          'role': 'admin',
          'title': 'Driver accepted job',
          'body': serviceType.isEmpty
              ? 'A driver accepted an assignment.'
              : 'A driver accepted: $serviceType.',
          'type': 'assignment_accepted',
          'severity': 'medium',
          'refType': 'assignment',
          'refId': assignmentId,
          'extra': {
            'assignmentId': assignmentId,
            'driverUid': driverUid,
            'serviceType': serviceType,
          },
          'read': false,
          'createdAt': FieldValue.serverTimestamp(),
        });

        if (requestId.isEmpty || userUid.isEmpty) {
          final reqQ = await FirebaseFirestore.instance
              .collection('service_requests')
              .where('assignmentId', isEqualTo: assignmentId)
              .limit(1)
              .get();
          if (reqQ.docs.isNotEmpty) {
            final req = reqQ.docs.first;
            requestId = req.id;
            final reqData = req.data();
            if (userUid.isEmpty) {
              userUid = (reqData['userUid'] ?? '').toString();
            }
          }
        }

        if (userUid.isNotEmpty && data['userNotifiedAccepted'] != true) {
          await FirebaseFirestore.instance.collection('notifications').add({
            'toUid': userUid,
            'role': 'resident',
            'title': 'Driver accepted',
            'body': 'Your request has been accepted by a driver.',
            'type': 'driver_accepted',
            'severity': 'medium',
            'refType': 'service_request',
            'refId': requestId,
            'extra': {
              'assignmentId': assignmentId,
              'driverUid': driverUid,
            },
            'read': false,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }

        await change.doc.reference.update({
          'adminNotifiedAccepted': true,
          if (userUid.isNotEmpty) 'userNotifiedAccepted': true,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  void _startRequestsWorker() {
    _requestsSub?.cancel();
    _requestsSub = FirebaseFirestore.instance
        .collection('service_requests')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .listen((snap) async {
      for (final change in snap.docChanges) {
        if (change.type != DocumentChangeType.added) continue;
        final data = change.doc.data();
        if (data == null) continue;
        if (data['adminNotifiedNewRequest'] == true) continue;

        final requestId = change.doc.id;
        final serviceType = (data['serviceType'] ?? 'Service request').toString();
        final userEmail = (data['userEmail'] ?? '').toString();

        await FirebaseFirestore.instance.collection('notifications').add({
          'role': 'admin',
          'title': 'New service request',
          'body': userEmail.isEmpty
              ? serviceType
              : '$serviceType - $userEmail',
          'type': 'service_request',
          'severity': 'medium',
          'refType': 'service_request',
          'refId': requestId,
          'extra': {
            'serviceType': serviceType,
          },
          'read': false,
          'createdAt': FieldValue.serverTimestamp(),
        });

        await change.doc.reference.update({
          'adminNotifiedNewRequest': true,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  void _startDriverPendingWorker() {
    _driverPendingSub?.cancel();
    _driverPendingSub = FirebaseFirestore.instance
        .collection('users')
        .where('role', whereIn: ['driver_pending', 'pending_driver'])
        .snapshots()
        .listen((snap) async {
      for (final change in snap.docChanges) {
        if (change.type == DocumentChangeType.removed) continue;
        final data = change.doc.data();
        if (data == null) continue;
        if (data['adminNotifiedDriverApproval'] == true) continue;

        final driverUid = change.doc.id;
        final name = (data['name'] ?? data['fullName'] ?? 'Driver').toString();
        final email = (data['email'] ?? '').toString();

        await FirebaseFirestore.instance.collection('notifications').add({
          'role': 'admin',
          'title': 'Driver approval needed',
          'body': email.isEmpty ? name : '$name - $email',
          'type': 'driver_approval',
          'severity': 'high',
          'refType': 'user',
          'refId': driverUid,
          'extra': {
            'driverUid': driverUid,
          },
          'read': false,
          'createdAt': FieldValue.serverTimestamp(),
        });

        await change.doc.reference.update({
          'adminNotifiedDriverApproval': true,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  void _startSupportTicketWorker() {
    _supportSub?.cancel();
    _supportSub = FirebaseFirestore.instance
        .collection('support_tickets')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .listen((snap) async {
      for (final change in snap.docChanges) {
        if (change.type != DocumentChangeType.added) continue;
        final data = change.doc.data();
        if (data == null) continue;
        if (data['adminNotifiedNewTicket'] == true) continue;

        final ticketId = change.doc.id;
        final subject = (data['subject'] ?? 'Support ticket').toString();
        final senderRole = (data['senderRole'] ?? '').toString();
        final senderEmail = (data['senderEmail'] ?? '').toString();

        final meta = [
          if (senderRole.isNotEmpty) senderRole,
          if (senderEmail.isNotEmpty) senderEmail,
        ].join(" - ");

        await FirebaseFirestore.instance.collection('notifications').add({
          'role': 'admin',
          'title': 'New support ticket',
          'body': meta.isEmpty ? subject : '$subject - $meta',
          'type': 'support_ticket',
          'severity': 'medium',
          'refType': 'support_ticket',
          'refId': ticketId,
          'extra': {
            'ticketId': ticketId,
          },
          'read': false,
          'createdAt': FieldValue.serverTimestamp(),
        });

        await change.doc.reference.update({
          'adminNotifiedNewTicket': true,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  void _stopWorkers() {
    _completionSub?.cancel();
    _completionSub = null;
    _assignmentSub?.cancel();
    _assignmentSub = null;
    _requestsSub?.cancel();
    _requestsSub = null;
    _driverPendingSub?.cancel();
    _driverPendingSub = null;
    _supportSub?.cancel();
    _supportSub = null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // âœ… Light gradient background
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    _bgTop,
                    _bgMid,
                    _bgBot,
                  ],
                ),
              ),
            ),
          ),

          // âœ… Dot grid subtle on light bg (make sure _DotGridPainter uses black opacity)
          Positioned.fill(
            child: Opacity(
              opacity: 0.10,
              child: CustomPaint(painter: _DotGridPainter()),
            ),
          ),

          // âœ… Very soft radial tint
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0.2, -0.3),
                    radius: 1.2,
                    colors: [
                      Colors.transparent,
                      _adminDarkMode.value
                          ? Colors.white.withOpacity(0.08)
                          : Colors.black.withOpacity(0.06),
                    ],
                  ),
                ),
              ),
            ),
          ),

          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 1000;

                return Row(
                  children: [
                    SizedBox(
                      width: 280,
                      child: _HoverSidebarFixedHoverZone(
                        expandedWidth: 260,
                        collapsedWidth: 72,
                        borderRadius: 18,

                        // âœ… Sidebar now light
                        backgroundColor: Colors.white.withOpacity(0.92),
                        borderColor: _border,

                        items: _navItems,
                        selectedIndex: _selectedIndex,
                        onSelect: (i) => setState(() => _selectedIndex = i),
                        onOpenMap: _openMap,
                        onLogout: widget.onLogout,
                        accent: _accent,
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            _TopBar(
                              title: _navItems[_selectedIndex].label,
                              isWide: isWide,
                              accent: _accent,
                              onLogout: widget.onLogout,
                              onOpenMap: _openMap,
                              searchController: _searchController,
                              onSearchChanged: _setSearch,
                            ),
                            const SizedBox(height: 16),
                            Expanded(
                              child: IndexedStack(
                                index: _selectedIndex,
                                children: [
                                  _OverviewPage(
                                    isWide: isWide,
                                    accent: _accent,
                                    onNavigate: _goTo,
                                    onOpenMap: _openMap,
                                    onOpenSimulation: _openSimulation,
                                    onOpenTruckDemo: _openTruckDemoSheet,
                                    onOpenAnalytics: _openAnalytics,
                                    showAnalyticsButton: _showAnalyticsButton,
                                    showRecentActivity: _showRecentActivity,
                                    compactCards: _compactCards,
                                  ),
                                  UsersPage(accent: _accent, search: _search),
                                  DriversPage(accent: _accent, search: _search),
                                  MessagesPage(accent: _accent),
                                  ReportsPage(accent: _accent),
                                  SettingsPage(
                                    accent: _accent,
                                    isDarkMode: _adminDarkMode.value,
                                    onThemeChanged: (v) {
                                      setState(() {
                                        _adminDarkMode.value = v;
                                      });
                                    },
                                    showAnalyticsButton: _showAnalyticsButton,
                                    onShowAnalyticsChanged: (v) {
                                      setState(() => _showAnalyticsButton = v);
                                    },
                                    showRecentActivity: _showRecentActivity,
                                    onShowRecentActivityChanged: (v) {
                                      setState(() => _showRecentActivity = v);
                                    },
                                    compactCards: _compactCards,
                                    onCompactCardsChanged: (v) {
                                      setState(() => _compactCards = v);
                                    },
                                    autoRefresh: _autoRefresh,
                                    onAutoRefreshChanged: (v) {
                                      setState(() => _autoRefresh = v);
                                      if (v) {
                                        _startWorkers();
                                      } else {
                                        _stopWorkers();
                                      }
                                    },
                                  ),
                                  AssignmentsPage(accent: _accent),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.isWide,
    required this.accent,
    required this.onLogout,
    required this.onOpenMap,
    required this.searchController,
    required this.onSearchChanged,
  });

  final String title;
  final bool isWide;
  final Color accent;
  final VoidCallback onLogout;
  final VoidCallback onOpenMap;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          Text(
            title,
            style:  TextStyle(
              color: _text,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.2,
            ),
          ),
          const Spacer(),
          if (isWide) ...[
            _SearchPill(
              controller: searchController,
              onChanged: onSearchChanged,
            ),
            const SizedBox(width: 12),
          ],
          _IconActionButton(
            tooltip: "Map",
            icon: Icons.map_outlined,
            accent: accent,
            onTap: onOpenMap,
          ),
          const SizedBox(width: 12),
          _NotificationsButton(accent: accent),
          const SizedBox(width: 12),
          _ProfileMenuButton(onLogout: onLogout),
        ],
      ),
    );
  }
}

class _SearchPill extends StatelessWidget {
  const _SearchPill({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 360,
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Icon(
            Icons.search_rounded,
            color: _textSoft,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: TextStyle(
                color: _text,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
              cursorColor: _text,
              decoration: InputDecoration(
                hintText: "Search users, drivers, requests...",
                hintStyle: TextStyle(
                  color: _textSoft.withOpacity(0.85),
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () {
                controller.clear();
                onChanged("");
                FocusScope.of(context).unfocus();
              },
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  Icons.close_rounded,
                  color: _textSoft,
                  size: 18,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NotificationsButton extends StatelessWidget {
  const _NotificationsButton({required this.accent});
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid;

    Query<Map<String, dynamic>> q =
        FirebaseFirestore.instance.collection('notifications');

    if (uid != null && uid.isNotEmpty) {
      q = q.where(
        Filter.or(
          Filter('toUid', isEqualTo: uid),
          Filter('role', isEqualTo: 'admin'),
        ),
      );
    } else {
      q = q.where('role', isEqualTo: 'admin');
    }

    q = q.orderBy('createdAt', descending: true).limit(50);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? const [];
        final count =
            docs.where((d) => (d.data()['read'] ?? false) != true).length;

        return InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            showDialog(
              context: context,
              builder: (_) => _NotificationsDialog(accent: accent),
            );
          },
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _border),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.notifications_rounded,
                  color: _text,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.22),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: accent.withOpacity(0.35)),
                  ),
                  child: Text(
                    "$count",
                    style: TextStyle(
                      color: _text,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _NotificationsDialog extends StatelessWidget {
  const _NotificationsDialog({required this.accent});
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: _GlassCard(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.notifications_rounded, color: accent, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    "Notifications",
                    style: TextStyle(
                      color: _text,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(
                      Icons.close_rounded,
                      color: _textSoft,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (user == null)
                const Padding(
                  padding: EdgeInsets.all(18),
                  child: Text("Please login first."),
                )
              else
                SizedBox(
                  height: 360,
                  child: NotificationsInbox(
                    recipientUid: user.uid,
                    recipientRole: 'admin',
                    showActions: true,
                    limit: 25,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatefulWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: _hover
                ? widget.accent.withOpacity(0.12)
                : _surface,
            border: Border.all(
              color: _hover
                  ? widget.accent.withOpacity(0.30)
                  : _border,
            ),
          ),
          child: Row(
            children: [
              Icon(widget.icon, color: _text, size: 18),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: TextStyle(
                  color: _text,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileMenuButton extends StatelessWidget {
  const _ProfileMenuButton({required this.onLogout});

  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email ?? "Admin";

    return PopupMenuButton<String>(
      tooltip: "Profile",
      onSelected: (value) {
        if (value == 'logout') {
          onLogout();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Text(email),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'logout',
          child: Text("Logout"),
        ),
      ],
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border),
        ),
        child: const Icon(Icons.person_rounded, size: 18),
      ),
    );
  }
}

class _IconActionButton extends StatefulWidget {
  const _IconActionButton({
    required this.icon,
    required this.accent,
    required this.onTap,
    required this.tooltip,
  });

  final IconData icon;
  final Color accent;
  final VoidCallback onTap;
  final String tooltip;

  @override
  State<_IconActionButton> createState() => _IconActionButtonState();
}

class _IconActionButtonState extends State<_IconActionButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: _hover ? widget.accent.withOpacity(0.12) : _surface,
              border: Border.all(
                color: _hover ? widget.accent.withOpacity(0.30) : _border,
              ),
            ),
            child: Icon(widget.icon, color: _text, size: 18),
          ),
        ),
      ),
    );
  }
}

class _QuickAction {
  const _QuickAction({
    required this.title,
    required this.icon,
    required this.onTap,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final VoidCallback onTap;
}

class _QuickActionCard extends StatefulWidget {
  const _QuickActionCard({
    required this.action,
    required this.accent,
  });

  final _QuickAction action;
  final Color accent;

  @override
  State<_QuickActionCard> createState() => _QuickActionCardState();
}

class _QuickActionCardState extends State<_QuickActionCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final action = widget.action;
    final bg = _hover ? widget.accent.withOpacity(0.08) : _surface;
    final border =
        _hover ? widget.accent.withOpacity(0.25) : _border;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: action.onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border),
          ),
          child: Row(
            children: [
              Container(
                height: 40,
                width: 40,
                decoration: BoxDecoration(
                  color: widget.accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: widget.accent.withOpacity(0.22)),
                ),
                child: Icon(action.icon, color: _text, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      action.title,
                      style: TextStyle(
                        color: _text,
                        fontWeight: FontWeight.w900,
                        fontSize: 13.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (action.subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        action.subtitle!,
                        style: TextStyle(
                          color: _textSoft,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OverviewPage extends StatelessWidget {
  const _OverviewPage({
    required this.isWide,
    required this.accent,
    required this.onNavigate,
    required this.onOpenMap,
    required this.onOpenSimulation,
    required this.onOpenTruckDemo,
    required this.onOpenAnalytics,
    required this.showAnalyticsButton,
    required this.showRecentActivity,
    required this.compactCards,
  });
  final bool isWide;
  final Color accent;
  final void Function(int index, {String? searchPreset}) onNavigate;
  final VoidCallback onOpenMap;
  final VoidCallback onOpenSimulation;
  final VoidCallback onOpenTruckDemo;
  final VoidCallback onOpenAnalytics;
  final bool showAnalyticsButton;
  final bool showRecentActivity;
  final bool compactCards;

  Query<Map<String, dynamic>> _role(String role) => FirebaseFirestore.instance
      .collection('users')
      .where('role', isEqualTo: role);

  Query<Map<String, dynamic>> _roleStatus(String role, String status) =>
      FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: role)
          .where('status', isEqualTo: status);

  @override
  Widget build(BuildContext context) {
    final usersTotal = _role('user');
    final usersActive = _roleStatus('user', 'active');
    final usersInactive = _roleStatus('user', 'inactive');

    final driversTotal = _role('driver');
    final driversActive = _roleStatus('driver', 'active');
    final driversPending = FirebaseFirestore.instance
        .collection('users')
        .where('role', whereIn: ['driver_pending', 'pending_driver']);
    final driversInactive = _roleStatus('driver', 'inactive');
    final quickActions = <_QuickAction>[
      _QuickAction(
        title: "Simulate Bin Activity",
        subtitle: "Demo tools",
        icon: Icons.casino,
        onTap: onOpenSimulation,
      ),
      _QuickAction(
        title: "Truck Demo (Route Simulation)",
        subtitle: "Demo tools",
        icon: Icons.local_shipping_rounded,
        onTap: onOpenTruckDemo,
      ),
      _QuickAction(
        title: "View Map",
        subtitle: "Live bins map",
        icon: Icons.map_outlined,
        onTap: onOpenMap,
      ),
      if (showAnalyticsButton)
        _QuickAction(
          title: "View Analytics",
          subtitle: "Reports overview",
          icon: Icons.auto_graph_rounded,
          onTap: onOpenAnalytics,
        ),
    ];

    return SingleChildScrollView(
      child: Column(
        children: [
          _GlassCard(
            padding: EdgeInsets.all(compactCards ? 12 : 18),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    "System overview and quick actions.",
                    style: TextStyle(
                      color: _textSoft.withOpacity(0.92),
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          _GlassCard(
            padding: EdgeInsets.all(compactCards ? 12 : 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Quick Actions",
                  style: TextStyle(
                    color: _text,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                GridView.builder(
                  itemCount: quickActions.length,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 280,
                    mainAxisExtent: 90,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemBuilder: (context, i) {
                    final action = quickActions[i];
                    return _QuickActionCard(
                      action: action,
                      accent: accent,
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _GlassCard(
                  width: isWide ? 540 : double.infinity,
                  padding: EdgeInsets.all(compactCards ? 12 : 18),
                  child: _SystemAlertsCard(
                    accent: accent,
                    driversPendingQuery: driversPending,
                    onNavigate: onNavigate,
                  ),
                ),
                _GlassCard(
                  width: isWide ? 540 : double.infinity,
                  padding: EdgeInsets.all(compactCards ? 12 : 18),
                  child: _PendingApprovalsCard(
                    accent: accent,
                    driversPendingQuery: driversPending,
                  ),
                ),
                _GlassCard(
                  width: isWide ? 540 : double.infinity,
                  padding: EdgeInsets.all(compactCards ? 12 : 18),
                  child: _RouteEventsCard(accent: accent),
                ),
              ],
            ),
          const SizedBox(height: 16),

          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _CountStatCard(
                title: "Users",
                subtitle: "Registered customers",
                icon: Icons.people_alt_rounded,
                width: isWide ? 260 : double.infinity,
                accent: accent,
                query: usersTotal,
                lines: [
                  _CountLine(label: "Active", query: usersActive),
                  _CountLine(label: "Inactive", query: usersInactive),
                ],
              ),
              _CountStatCard(
                title: "Drivers",
                subtitle: "All drivers",
                icon: Icons.local_shipping_rounded,
                width: isWide ? 260 : double.infinity,
                accent: accent,
                query: driversTotal,
                lines: [
                  _CountLine(label: "Active", query: driversActive),
                  _CountLine(label: "Pending", query: driversPending),
                  _CountLine(label: "Inactive", query: driversInactive),
                ],
              ),
              _CountStatCard(
                title: "Pending approvals",
                subtitle: "Awaiting verification",
                icon: Icons.inbox_rounded,
                width: isWide ? 260 : double.infinity,
                accent: accent,
                query: driversPending,
              ),
              _CountStatCard(
                title: "Revenue",
                subtitle: "This month",
                icon: Icons.payments_rounded,
                width: isWide ? 260 : double.infinity,
                accent: accent,
                overrideValueText: "â€”",
              ),
            ],
          ),

          const SizedBox(height: 16),

          if (showRecentActivity)
            _GlassCard(
              padding: EdgeInsets.all(compactCards ? 12 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Recent activity",
                  style: TextStyle(
                    color: _textSoft.withOpacity(0.92),
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                _FakeTable(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SystemAlertsCard extends StatelessWidget {
  const _SystemAlertsCard({
    required this.accent,
    required this.driversPendingQuery,
    required this.onNavigate,
  });

  final Color accent;
  final Query<Map<String, dynamic>> driversPendingQuery;
  final void Function(int index, {String? searchPreset}) onNavigate;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: accent, size: 20),
            const SizedBox(width: 10),
            Text(
              "System alerts",
              style: TextStyle(
                color: _textSoft.withOpacity(0.92),
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
            const Spacer(),
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                onNavigate(2); // Drivers tab
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Text(
                  "View all",
                  style: TextStyle(
                    color: _textSoft.withOpacity(0.7),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: driversPendingQuery.snapshots(),
          builder: (context, snap) {
            if (snap.hasError) {
              return Text(
                "Pending query error: ${snap.error}",
                style: TextStyle(
                  color: _textSoft.withOpacity(0.8),
                  fontWeight: FontWeight.w700,
                ),
              );
            }

            final pending = snap.data?.docs.length ?? 0;
            final sev = pending > 0 ? _Severity.medium : _Severity.low;

            return InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: pending > 0
                  ? () {
                      onNavigate(2); // Drivers tab
                    }
                  : null,
              child: _AlertRow(
                accent: accent,
                title: "Driver approvals pending",
                subtitle: "$pending drivers awaiting review",
                icon: Icons.notifications_rounded,
                severity: sev,
                onTap: () {},
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            onNavigate(4); // Reports tab
          },
          child: _AlertRow(
            accent: accent,
            title: "Payments",
            subtitle: "Revenue analytics will be added later",
            severity: _Severity.low,
            icon: Icons.payments_rounded,
            onTap: () {},
          ),
        ),

        const SizedBox(height: 10),
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            onNavigate(1); // Users tab
          },
          child: _AlertRow(
            accent: accent,
            title: "Accounts",
            subtitle: "Disable or enable users and drivers",
            icon: Icons.warning_rounded,
            severity: _Severity.low,
            onTap: () {},
          ),
        ),
      ],
    );
  }
}

class _PendingApprovalsCard extends StatelessWidget {
  const _PendingApprovalsCard({
    required this.accent,
    required this.driversPendingQuery,
  });

  final Color accent;
  final Query<Map<String, dynamic>> driversPendingQuery;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: driversPendingQuery.limit(1).snapshots(),
      builder: (context, snap) {
        // 1ï¸âƒ£ Show Firestore errors clearly (VERY IMPORTANT)
        if (snap.hasError) {
          return Text(
            "Approvals query error:\n${snap.error}",
            style: TextStyle(
              color: _textSoft.withOpacity(0.8),
              fontWeight: FontWeight.w700,
            ),
          );
        }

        // 2ï¸âƒ£ Loading state
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(18),
            child: CircularProgressIndicator(),
          );
        }

        //  Normal data handling
        final docs = snap.data?.docs ?? [];
        final has = docs.isNotEmpty;
        final doc = has ? docs.first : null;
        final data = doc?.data();

        final name = (data?['name'] ?? 'Driver').toString();
        final phone = (data?['phone'] ?? '').toString();
        final idNumber = (data?['idNumber'] ?? '').toString();
        final license = (data?['licenseNumber'] ?? '').toString();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.fact_check_rounded, color: accent, size: 20),
                const SizedBox(width: 10),
                Text(
                  "Pending approvals",
                  style: TextStyle(
                    color: _textSoft.withOpacity(0.92),
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Spacer(),
                Text(
                  "Open queue",
                  style: TextStyle(
                    color: _textSoft.withOpacity(0.7),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (!has)
              Text(
                "No pending drivers right now.",
                style: TextStyle(
                  color: _textSoft.withOpacity(0.7),
                  fontWeight: FontWeight.w700,
                ),
              )
            else
              _ApprovalRow(
                name: name,
                subtitle: [
                  if (phone.isNotEmpty) phone,
                  if (idNumber.isNotEmpty) "ID: $idNumber",
                  if (license.isNotEmpty) "License: $license",
                ].join(" - "),
                accent: accent,
                onOpen: () {
                  _showProfileDialog(
                    context: context,
                    title: "Driver profile",
                    fields: {
                      "UID": doc!.id,
                      "Email": (data?['email'] ?? '').toString(),
                      "Phone": phone,
                      "Role": (data?['role'] ?? '').toString(),
                      "Status": (data?['status'] ?? '').toString(),
                      "ID number": idNumber,
                      "License number": license,
                      "Vehicle class": (data?['vehicleClass'] ?? '').toString(),
                    },
                    accent: accent,
                  );
                },
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _SmallButton(
                    label: "Reject",
                    icon: Icons.close_rounded,
                    accent: Colors.redAccent,
                    enabled: has,
                    onTap: has
                        ? () async {
                            await FirebaseFirestore.instance
                                .collection('users')
                                .doc(doc!.id)
                                .update({
                                  'status': 'inactive',
                                  'updatedAt': FieldValue.serverTimestamp(),
                                  'rejectedAt': FieldValue.serverTimestamp(),
                                });
                          }
                        : () {},
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _SmallButton(
                    label: "Approve",
                    icon: Icons.check_rounded,
                    accent: accent,
                    enabled: has,
                    onTap: has
                        ? () async {
                              await FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(doc!.id)
                                  .update({
                                    'role': 'driver',
                                    'status': 'active',
                                    'updatedAt': FieldValue.serverTimestamp(),
                                    'approvedAt': FieldValue.serverTimestamp(),
                                  });
                          }
                        : () {},
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _CountLine {
  const _CountLine({required this.label, required this.query});
  final String label;
  final Query<Map<String, dynamic>> query;
}

class _CountStatCard extends StatelessWidget {
  const _CountStatCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.width,
    required this.accent,
    this.query,
    this.lines,
    this.overrideValueText,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final double width;
  final Color accent;
  final Query<Map<String, dynamic>>? query;
  final List<_CountLine>? lines;
  final String? overrideValueText;

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      width: width,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            height: 44,
            width: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: accent.withOpacity(0.14),
              border: Border.all(color: accent.withOpacity(0.22)),
            ),
            child: Icon(icon, color: accent, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: _textSoft.withOpacity(0.75),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                if (overrideValueText != null)
                  Text(
                    overrideValueText!,
                    style: TextStyle(
                      color: _text,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  )
                else
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: query!.snapshots(),
                    builder: (context, snap) {
                      final value = "${snap.data?.docs.length ?? 0}";
                      return Text(
                        value,
                        style: TextStyle(
                          color: _text,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      );
                    },
                  ),
                const SizedBox(height: 8),
                if ((lines ?? []).isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final line in lines!)
                        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: line.query.snapshots(),
                          builder: (context, snap) {
                            final v = snap.data?.docs.length ?? 0;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                "${line.label}: $v",
                                style: TextStyle(
                                  color: _textSoft.withOpacity(0.72),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12.5,
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  )
                else
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: _textSoft.withOpacity(0.65),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
class _CountChip extends StatelessWidget {
  const _CountChip({
    required this.label,
    required this.query,
    required this.accent,
  });

  final String label;
  final Query<Map<String, dynamic>> query;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snap) {
        final count = snap.data?.docs.length ?? 0;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: _surface,
            border: Border.all(color: _border),
          ),
          child: Row(
            children: [
              Container(
                height: 8,
                width: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withOpacity(0.85),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                "$label: ",
                style: TextStyle(
                  color: _textSoft.withOpacity(0.72),
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                "$count",
                style: TextStyle(
                  color: _text,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class UsersPage extends StatelessWidget {
  const UsersPage({super.key, required this.accent, required this.search});
  final Color accent;
  final String search;

  Query<Map<String, dynamic>> get _baseQuery => FirebaseFirestore.instance
      .collection('users')
      .where('role', isEqualTo: 'user');

  Query<Map<String, dynamic>> _statusQuery(String status) => FirebaseFirestore
      .instance
      .collection('users')
      .where('role', isEqualTo: 'user')
      .where('status', isEqualTo: status);

  @override
  Widget build(BuildContext context) {
    final totalQ = _baseQuery;
    final activeQ = _statusQuery('active');
    final inactiveQ = _statusQuery('inactive');

    return SingleChildScrollView(
      child: Column(
        children: [
          _GlassCard(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Icon(Icons.people_alt_rounded, color: accent, size: 20),
                const SizedBox(width: 10),
                Text(
                  "Users",
                  style: TextStyle(
                    color: _text,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                _CountChip(label: "Total", query: totalQ, accent: accent),
                const SizedBox(width: 10),
                _CountChip(label: "Active", query: activeQ, accent: accent),
                const SizedBox(width: 10),
                _CountChip(label: "Inactive", query: inactiveQ, accent: accent),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _UserListCard(accent: accent, search: search),
        ],
      ),
    );
  }
}

class _UserListCard extends StatelessWidget {
  const _UserListCard({required this.accent, required this.search});
  final Color accent;
  final String search;

  bool _matches(Map<String, dynamic> d) {
    if (search.isEmpty) return true;
    final s = search.toLowerCase();

    final name = (d['name'] ?? '').toString().toLowerCase();
    final email = (d['email'] ?? '').toString().toLowerCase();
    final phone = (d['phone'] ?? '').toString().toLowerCase();
    final status = (d['status'] ?? '').toString().toLowerCase();

    return name.contains(s) ||
        email.contains(s) ||
        phone.contains(s) ||
        status.contains(s);
  }

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'user')
        .snapshots();

    return _GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "User list",
            style: TextStyle(
              color: _textSoft.withOpacity(0.92),
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: stream,
            builder: (context, snap) {
              if (snap.hasError) {
                return Text(
                  "Failed to load users: ${snap.error}",
                  style: TextStyle(color: _textSoft.withOpacity(0.75)),
                );
              }
              if (!snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(18),
                  child: CircularProgressIndicator(),
                );
              }

              final docs = snap.data!.docs;
              final filtered = docs.where((e) => _matches(e.data())).toList();

              if (filtered.isEmpty) {
                return Text(
                  "No users found.",
                  style: TextStyle(
                    color: _textSoft.withOpacity(0.75),
                    fontWeight: FontWeight.w700,
                  ),
                );
              }

              return Column(
                children: [
                  for (final doc in filtered.take(60))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _UserCard(
                        uid: doc.id,
                        data: doc.data(),
                        accent: accent,
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({
    required this.uid,
    required this.data,
    required this.accent,
  });

  final String uid;
  final Map<String, dynamic> data;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final name = (data['name'] ?? 'User').toString();
    final email = (data['email'] ?? '').toString();
    final phone = (data['phone'] ?? '').toString();
    final status = (data['status'] ?? '').toString();

    final statusColor = status == 'active'
        ? accent.withOpacity(0.22)
        : Colors.white.withOpacity(0.10);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        _showProfileDialog(
          context: context,
          title: "User profile",
          fields: {
            "UID": uid,
            "Name": name,
            "Email": email,
            "Phone": phone,
            "Role": (data['role'] ?? '').toString(),
            "Status": status,
          },
          accent: accent,
        );
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Colors.white.withOpacity(0.04),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: accent.withOpacity(0.18),
              child: Icon(
                Icons.person_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      color: _text,
                      fontWeight: FontWeight.w900,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [email, phone].where((x) => x.isNotEmpty).join(" - "),
                    style: TextStyle(
                      color: _textSoft.withOpacity(0.7),
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: statusColor,
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Text(
                status.isEmpty ? "unknown" : status,
                style: TextStyle(
                  color: _text,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: 10),
            _SmallButton(
              label: status == 'active' ? "Disable" : "Enable",
              icon: status == 'active'
                  ? Icons.block_rounded
                  : Icons.check_circle_rounded,
              accent: status == 'active' ? Colors.redAccent : accent,
              enabled: true,
              onTap: () async {
                final next = status == 'active' ? 'inactive' : 'active';
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(uid)
                    .update({
                      'status': next,
                      'updatedAt': FieldValue.serverTimestamp(),
                    });
              },
            ),
          ],
        ),
      ),
    );
  }
}

class DriversPage extends StatelessWidget {
  const DriversPage({super.key, required this.accent, required this.search});
  final Color accent;
  final String search;

  Query<Map<String, dynamic>> get _baseQuery => FirebaseFirestore.instance
      .collection('users')
      .where('role', isEqualTo: 'driver');

  Query<Map<String, dynamic>> _statusQuery(String status) => FirebaseFirestore
      .instance
      .collection('users')
      .where('role', isEqualTo: 'driver')
      .where('status', isEqualTo: status);

  @override
  Widget build(BuildContext context) {
    final totalQ = _baseQuery;
    final activeQ = _statusQuery('active');
    final pendingQ = _statusQuery('pending');
    final inactiveQ = _statusQuery('inactive');

    return SingleChildScrollView(
      child: Column(
        children: [
          _GlassCard(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Icon(Icons.local_shipping_rounded, color: accent, size: 20),
                const SizedBox(width: 10),
                Text(
                  "Drivers",
                  style: TextStyle(
                    color: _text,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                _CountChip(label: "Total", query: totalQ, accent: accent),
                const SizedBox(width: 10),
                _CountChip(label: "Active", query: activeQ, accent: accent),
                const SizedBox(width: 10),
                _CountChip(label: "Pending", query: pendingQ, accent: accent),
                const SizedBox(width: 10),
                _CountChip(label: "Inactive", query: inactiveQ, accent: accent),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _DriverListCard(accent: accent, search: search),
        ],
      ),
    );
  }
}

class _DriverListCard extends StatelessWidget {
  const _DriverListCard({required this.accent, required this.search});
  final Color accent;
  final String search;

  bool _matches(Map<String, dynamic> d) {
    if (search.isEmpty) return true;
    final s = search.toLowerCase();

    final name = (d['name'] ?? '').toString().toLowerCase();
    final email = (d['email'] ?? '').toString().toLowerCase();
    final phone = (d['phone'] ?? '').toString().toLowerCase();
    final status = (d['status'] ?? '').toString().toLowerCase();
    final idNumber = (d['idNumber'] ?? '').toString().toLowerCase();
    final license = (d['licenseNumber'] ?? '').toString().toLowerCase();
    final vehicleClass = (d['vehicleClass'] ?? '').toString().toLowerCase();

    return name.contains(s) ||
        email.contains(s) ||
        phone.contains(s) ||
        status.contains(s) ||
        idNumber.contains(s) ||
        license.contains(s) ||
        vehicleClass.contains(s);
  }

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'driver')
        .snapshots();

    return _GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Driver list",
            style: TextStyle(
              color: _textSoft.withOpacity(0.92),
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: stream,
            builder: (context, snap) {
              if (snap.hasError) {
                return Text(
                  "Failed to load drivers: ${snap.error}",
                  style: TextStyle(color: _textSoft.withOpacity(0.75)),
                );
              }
              if (!snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(18),
                  child: CircularProgressIndicator(),
                );
              }

              final docs = snap.data!.docs;
              final filtered = docs.where((e) => _matches(e.data())).toList();

              if (filtered.isEmpty) {
                return Text(
                  "No drivers found.",
                  style: TextStyle(
                    color: _textSoft.withOpacity(0.75),
                    fontWeight: FontWeight.w700,
                  ),
                );
              }

              return Column(
                children: [
                  for (final doc in filtered.take(60))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _DriverCard(
                        uid: doc.id,
                        data: doc.data(),
                        accent: accent,
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DriverCard extends StatelessWidget {
  const _DriverCard({
    required this.uid,
    required this.data,
    required this.accent,
  });

  final String uid;
  final Map<String, dynamic> data;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final email = (data['email'] ?? '').toString();
    final phone = (data['phone'] ?? '').toString();
    final status = (data['status'] ?? '').toString();
    final idNumber = (data['idNumber'] ?? '').toString();
    final license = (data['licenseNumber'] ?? '').toString();
    final vehicleClass = (data['vehicleClass'] ?? '').toString();

    Color chipColor = Colors.white.withOpacity(0.10);
    if (status == 'active') chipColor = accent.withOpacity(0.22);
    if (status == 'pending') chipColor = Colors.amber.withOpacity(0.22);
    if (status == 'inactive') chipColor = Colors.redAccent.withOpacity(0.22);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        _showProfileDialog(
          context: context,
          title: "Driver profile",
          fields: {
            "UID": uid,
            "Email": email,
            "Phone": phone,
            "Role": (data['role'] ?? '').toString(),
            "Status": status,
            "ID number": idNumber,
            "License number": license,
            "Vehicle class": vehicleClass,
          },
          accent: accent,
        );
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Colors.white.withOpacity(0.04),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: accent.withOpacity(0.18),
              child: Icon(
                Icons.local_shipping_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    email.isEmpty ? "Driver" : email,
                    style: TextStyle(
                      color: _text,
                      fontWeight: FontWeight.w900,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (phone.isNotEmpty) phone,
                      if (idNumber.isNotEmpty) "ID: $idNumber",
                      if (license.isNotEmpty) "License: $license",
                      if (vehicleClass.isNotEmpty) "Class: $vehicleClass",
                    ].join(" - "),
                    style: TextStyle(
                      color: _textSoft.withOpacity(0.7),
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: chipColor,
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Text(
                status.isEmpty ? "unknown" : status,
                style: TextStyle(
                  color: _text,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: 10),
            if (status == 'pending') ...[
              _SmallButton(
                label: "Reject",
                icon: Icons.close_rounded,
                accent: Colors.redAccent,
                enabled: true,
                onTap: () async {
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(uid)
                      .update({
                        'status': 'inactive',
                        'updatedAt': FieldValue.serverTimestamp(),
                        'rejectedAt': FieldValue.serverTimestamp(),
                      });
                },
              ),
              const SizedBox(width: 8),
              _SmallButton(
                label: "Approve",
                icon: Icons.check_rounded,
                accent: accent,
                enabled: true,
                onTap: () async {
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(uid)
                      .update({
                        'role': 'driver',
                        'status': 'active',
                        'updatedAt': FieldValue.serverTimestamp(),
                        'approvedAt': FieldValue.serverTimestamp(),
                      });
                },
              ),
            ] else ...[
              _SmallButton(
                label: status == 'active' ? "Disable" : "Enable",
                icon: status == 'active'
                    ? Icons.block_rounded
                    : Icons.check_circle_rounded,
                accent: status == 'active' ? Colors.redAccent : accent,
                enabled: true,
                onTap: () async {
                  final next = status == 'active' ? 'inactive' : 'active';
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(uid)
                      .update({
                        'status': next,
                        'updatedAt': FieldValue.serverTimestamp(),
                      });
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class MessagesPage extends StatelessWidget {
  const MessagesPage({super.key, required this.accent});
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final q = FirebaseFirestore.instance
        .collection('support_tickets')
        .orderBy('createdAt', descending: true);

    return SingleChildScrollView(
      child: Column(
        children: [
          _GlassCard(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Icon(Icons.mail_rounded, color: accent, size: 20),
                const SizedBox(width: 10),
                Text(
                  "Messages",
                  style: TextStyle(
                    color: _text,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),

                // âœ… Create test ticket button
                InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () async {
                    await _createTestTicket(accent: accent);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: Colors.white.withOpacity(0.06),
                      border: Border.all(color: Colors.white.withOpacity(0.10)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.add_rounded,
                          color: Colors.white.withOpacity(0.9),
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          "Create test",
                          style: TextStyle(
                            color: _textSoft.withOpacity(0.9),
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(width: 10),

                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('support_tickets')
                      .where('status', isEqualTo: 'open')
                      .snapshots(),
                  builder: (context, snap) {
                    final openCount = snap.data?.docs.length ?? 0;
                    return _CountPill(
                      label: "Open",
                      value: openCount,
                      accent: accent,
                    );
                  },
                ),
                const SizedBox(width: 10),
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('support_tickets')
                      .where('status', isEqualTo: 'resolved')
                      .snapshots(),
                  builder: (context, snap) {
                    final resolvedCount = snap.data?.docs.length ?? 0;
                    return _CountPill(
                      label: "Resolved",
                      value: resolvedCount,
                      accent: accent,
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          _GlassCard(
            padding: const EdgeInsets.all(18),
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: q.snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Text(
                    "Failed to load tickets: ${snap.error}",
                    style: TextStyle(
                      color: _textSoft.withOpacity(0.75),
                      fontWeight: FontWeight.w700,
                    ),
                  );
                }

                if (!snap.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(18),
                    child: CircularProgressIndicator(),
                  );
                }

                final docs = snap.data!.docs;

                if (docs.isEmpty) {
                  return Text(
                    "No support tickets yet.\n\nTo test, add a document in Firestore:\ncollection: support_tickets\nfields: subject, message, senderRole, senderEmail, status, createdAt",
                    style: TextStyle(
                      color: _textSoft.withOpacity(0.75),
                      fontWeight: FontWeight.w700,
                      height: 1.4,
                    ),
                  );
                }

                return Column(
                  children: [
                    for (final d in docs.take(80))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _TicketCard(accent: accent, doc: d),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TicketCard extends StatelessWidget {
  const _TicketCard({required this.accent, required this.doc});
  final Color accent;
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;

  @override
  Widget build(BuildContext context) {
    final data = doc.data();

    final subject = (data['subject'] ?? 'No subject').toString();
    final message = (data['message'] ?? '').toString();
    final senderRole = (data['senderRole'] ?? '').toString();
    final senderEmail = (data['senderEmail'] ?? '').toString();
    final status = (data['status'] ?? 'open').toString();
    final priority = (data['priority'] ?? 'low').toString();

    Color statusColor = Colors.white.withOpacity(0.10);
    if (status == 'open') statusColor = Colors.redAccent.withOpacity(0.22);
    if (status == 'in_progress') statusColor = accent.withOpacity(0.22);
    if (status == 'resolved') {
      statusColor = Colors.greenAccent.withOpacity(0.18);
    }

    Color prColor = Colors.white.withOpacity(0.10);
    if (priority == 'high') prColor = Colors.redAccent.withOpacity(0.22);
    if (priority == 'medium') prColor = accent.withOpacity(0.22);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        _showTicketDialog(
          context: context,
          docId: doc.id,
          data: data,
          accent: accent,
        );
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Colors.white.withOpacity(0.04),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: accent.withOpacity(0.18),
              child: Icon(
                Icons.mail_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    subject,
                    style: TextStyle(
                      color: _text,
                      fontWeight: FontWeight.w900,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (senderRole.isNotEmpty) senderRole,
                      if (senderEmail.isNotEmpty) senderEmail,
                    ].join(" - "),
                    style: TextStyle(
                      color: _textSoft.withOpacity(0.7),
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (message.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      message,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _textSoft.withOpacity(0.65),
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            _MiniChip(text: priority, color: prColor),
            const SizedBox(width: 8),
            _MiniChip(text: status, color: statusColor),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              color: Colors.white.withOpacity(0.55),
            ),
          ],
        ),
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({
    required this.label,
    required this.value,
    required this.accent,
  });

  final String label;
  final int value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Colors.white.withOpacity(0.06),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Text(
        "$label: $value",
        style: TextStyle(
          color: _textSoft.withOpacity(0.9),
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color,
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: _text,
          fontWeight: FontWeight.w900,
          fontSize: 12,
        ),
      ),
    );
  }
}

void _showTicketDialog({
  required BuildContext context,
  required String docId,
  required Map<String, dynamic> data,
  required Color accent,
}) {
  final subject = (data['subject'] ?? '').toString();
  final message = (data['message'] ?? '').toString();
  final senderRole = (data['senderRole'] ?? '').toString();
  final senderEmail = (data['senderEmail'] ?? '').toString();
  final status = (data['status'] ?? 'open').toString();
  final priority = (data['priority'] ?? 'low').toString();

  showDialog(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: Colors.transparent,
      child: _GlassCard(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    height: 38,
                    width: 38,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: accent.withOpacity(0.14),
                      border: Border.all(color: accent.withOpacity(0.22)),
                    ),
                    child: Icon(
                      Icons.mail_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      subject.isEmpty ? "Support ticket" : subject,
                      style: TextStyle(
                        color: _text,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(
                      Icons.close_rounded,
                      color: Colors.white.withOpacity(0.85),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "From: ${senderRole.isEmpty ? 'unknown' : senderRole} - ${senderEmail.isEmpty ? 'â€”' : senderEmail}\nPriority: $priority - Status: $status",
                  style: TextStyle(
                    color: _textSoft.withOpacity(0.75),
                    fontWeight: FontWeight.w800,
                    height: 1.35,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: Colors.white.withOpacity(0.03),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: Text(
                  message.isEmpty ? "â€”" : message,
                  style: TextStyle(
                    color: _textSoft.withOpacity(0.9),
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _SmallButton(
                      label: "In progress",
                      icon: Icons.timelapse_rounded,
                      accent: accent,
                      enabled: true,
                      onTap: () async {
                        await FirebaseFirestore.instance
                            .collection('support_tickets')
                            .doc(docId)
                            .update({
                              'status': 'in_progress',
                              'updatedAt': FieldValue.serverTimestamp(),
                            });
                        if (context.mounted) Navigator.pop(context);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SmallButton(
                      label: "Resolve",
                      icon: Icons.check_rounded,
                      accent: Colors.greenAccent,
                      enabled: true,
                      onTap: () async {
                        await FirebaseFirestore.instance
                            .collection('support_tickets')
                            .doc(docId)
                            .update({
                              'status': 'resolved',
                              'resolvedAt': FieldValue.serverTimestamp(),
                              'updatedAt': FieldValue.serverTimestamp(),
                            });
                        if (context.mounted) Navigator.pop(context);
                      },
                    ),
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

Future<void> _createTestTicket({required Color accent}) async {
  await FirebaseFirestore.instance.collection('support_tickets').add({
    'subject': 'Test ticket',
    'message': 'This is a test message created from Admin dashboard.',
    'senderRole': 'tester',
    'senderEmail': 'admin@ugswms.com',
    'priority': 'medium',
    'status': 'open',
    'createdAt': FieldValue.serverTimestamp(),
  });
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.accent,
    required this.isDarkMode,
    required this.onThemeChanged,
    required this.showAnalyticsButton,
    required this.onShowAnalyticsChanged,
    required this.showRecentActivity,
    required this.onShowRecentActivityChanged,
    required this.compactCards,
    required this.onCompactCardsChanged,
    required this.autoRefresh,
    required this.onAutoRefreshChanged,
  });

  final Color accent;
  final bool isDarkMode;
  final ValueChanged<bool> onThemeChanged;
  final bool showAnalyticsButton;
  final ValueChanged<bool> onShowAnalyticsChanged;
  final bool showRecentActivity;
  final ValueChanged<bool> onShowRecentActivityChanged;
  final bool compactCards;
  final ValueChanged<bool> onCompactCardsChanged;
  final bool autoRefresh;
  final ValueChanged<bool> onAutoRefreshChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          _GlassCard(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Icon(Icons.settings_rounded, color: accent, size: 20),
                const SizedBox(width: 10),
                Text(
                  "Settings",
                  style: TextStyle(
                    color: _text,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          _GlassCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Appearance",
                  style: TextStyle(
                    color: _text,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 10),
                _SettingsToggle(
                  icon: Icons.dark_mode_rounded,
                  title: "Dark mode",
                  subtitle: "Switch between dark and light admin UI",
                  value: isDarkMode,
                  onChanged: onThemeChanged,
                  accent: accent,
                ),
                const SizedBox(height: 8),
                _SettingsToggle(
                  icon: Icons.view_compact_rounded,
                  title: "Compact cards",
                  subtitle: "Reduce padding on overview cards",
                  value: compactCards,
                  onChanged: onCompactCardsChanged,
                  accent: accent,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          _GlassCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Dashboard",
                  style: TextStyle(
                    color: _text,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 10),
                _SettingsToggle(
                  icon: Icons.auto_graph_rounded,
                  title: "Show analytics button",
                  subtitle: "Display quick analytics in Overview",
                  value: showAnalyticsButton,
                  onChanged: onShowAnalyticsChanged,
                  accent: accent,
                ),
                const SizedBox(height: 8),
                _SettingsToggle(
                  icon: Icons.timeline_rounded,
                  title: "Show recent activity",
                  subtitle: "Display the Recent activity table",
                  value: showRecentActivity,
                  onChanged: onShowRecentActivityChanged,
                  accent: accent,
                ),
                const SizedBox(height: 8),
                _SettingsToggle(
                  icon: Icons.refresh_rounded,
                  title: "Auto refresh",
                  subtitle: "Live updates from Firestore",
                  value: autoRefresh,
                  onChanged: onAutoRefreshChanged,
                  accent: accent,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          _GlassCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Security",
                  style: TextStyle(
                    color: _text,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 10),
                _SettingsTile(
                  icon: Icons.lock_reset_rounded,
                  title: "Force logout other sessions",
                  subtitle: "Invalidate other admin sessions (coming soon)",
                  accent: accent,
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Not wired yet.")),
                    );
                  },
                ),
                const SizedBox(height: 8),
                _SettingsTile(
                  icon: Icons.policy_rounded,
                  title: "Audit logs",
                  subtitle: "View admin audit history (coming soon)",
                  accent: accent,
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Not wired yet.")),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child, this.padding, this.width});

  final Widget child;
  final EdgeInsets? padding;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            padding: padding ?? const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: DefaultTextStyle(
              style: TextStyle(
                color: _text,
                fontWeight: FontWeight.w700,
              ),
              child: IconTheme(
                data: IconThemeData(color: _textSoft),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HoverSidebarFixedHoverZone extends StatefulWidget {
  const _HoverSidebarFixedHoverZone({
    required this.items,
    required this.selectedIndex,
    required this.onSelect,
    required this.onOpenMap,
    required this.onLogout,
    required this.expandedWidth,
    required this.collapsedWidth,
    required this.borderRadius,
    required this.backgroundColor,
    required this.borderColor,
    required this.accent,
  });

  final List<_NavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onOpenMap;
  final VoidCallback onLogout;

  final double expandedWidth;
  final double collapsedWidth;
  final double borderRadius;
  final Color backgroundColor;
  final Color borderColor;
  final Color accent;

  @override
  State<_HoverSidebarFixedHoverZone> createState() =>
      _HoverSidebarFixedHoverZoneState();
}

class _HoverSidebarFixedHoverZoneState
    extends State<_HoverSidebarFixedHoverZone> {
  bool _hovered = false;
  bool _pinnedExpanded = false;

  // âœ… light palette helpers
  Color get _ink => const Color(0xFF0F172A); // slate-900
  Color get _muted => const Color(0xFF475569); // slate-600
  Color get _border => widget.borderColor; // pass from parent
  Color get _surface => widget.backgroundColor;
  Color get _tileHover => const Color(0xFFF1F5F9); // slate-100

  @override
  Widget build(BuildContext context) {
    final allowExpand = MediaQuery.of(context).size.width >= 1100;
    final isExpanded = allowExpand && (_pinnedExpanded || _hovered);
    final primaryEntries = <_SidebarEntry>[
      _SidebarEntry(
        label: widget.items[0].label,
        icon: widget.items[0].icon,
        selected: widget.selectedIndex == 0,
        onTap: () => widget.onSelect(0),
      ),
      _SidebarEntry(
        label: "Map",
        icon: Icons.map_outlined,
        selected: false,
        onTap: widget.onOpenMap,
      ),
      _SidebarEntry(
        label: widget.items[1].label,
        icon: widget.items[1].icon,
        selected: widget.selectedIndex == 1,
        onTap: () => widget.onSelect(1),
      ),
      _SidebarEntry(
        label: widget.items[2].label,
        icon: widget.items[2].icon,
        selected: widget.selectedIndex == 2,
        onTap: () => widget.onSelect(2),
      ),
      _SidebarEntry(
        label: "Support Tickets",
        icon: Icons.support_agent_rounded,
        selected: widget.selectedIndex == 3,
        onTap: () => widget.onSelect(3),
      ),
      _SidebarEntry(
        label: widget.items[4].label,
        icon: widget.items[4].icon,
        selected: widget.selectedIndex == 4,
        onTap: () => widget.onSelect(4),
      ),
      _SidebarEntry(
        label: widget.items[6].label,
        icon: widget.items[6].icon,
        selected: widget.selectedIndex == 6,
        onTap: () => widget.onSelect(6),
      ),
    ];
    final footerEntries = <_SidebarEntry>[
      _SidebarEntry(
        label: widget.items[5].label,
        icon: widget.items[5].icon,
        selected: widget.selectedIndex == 5,
        onTap: () => widget.onSelect(5),
      ),
      _SidebarEntry(
        label: "Help",
        icon: Icons.help_outline_rounded,
        selected: false,
        onTap: () => widget.onSelect(3),
      ),
      _SidebarEntry(
        label: "Logout",
        icon: Icons.logout_rounded,
        selected: false,
        onTap: widget.onLogout,
      ),
    ];

    return MouseRegion(
      onEnter: (_) => allowExpand ? setState(() => _hovered = true) : null,
      onExit: (_) => allowExpand ? setState(() => _hovered = false) : null,
      child: Align(
        alignment: Alignment.centerLeft,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          width: isExpanded ? widget.expandedWidth : widget.collapsedWidth,
          child: Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.symmetric(vertical: 16),
            clipBehavior: Clip.hardEdge,
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(widget.borderRadius),
              border: Border.all(color: _border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            // Before: sidebar used a single scroll list; after: header + scrollable primary + pinned footer.
            child: Column(
              children: [
                // Header
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: isExpanded ? 16 : 8,
                  ),
                  child: Row(
                    children: [
                      Container(
                        height: 42,
                        width: 42,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: widget.accent.withOpacity(0.10),
                          border: Border.all(color: widget.accent.withOpacity(0.18)),
                        ),
                        child: Icon(
                          Icons.shield_rounded,
                          color: widget.accent,
                          size: 22,
                        ),
                      ),
                      if (isExpanded) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            "UGSWMS Admin",
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _ink,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                      if (allowExpand)
                        Tooltip(
                          message: isExpanded ? "Collapse" : "Expand",
                          child: IconButton(
                            onPressed: () {
                              setState(() => _pinnedExpanded = !_pinnedExpanded);
                            },
                            icon: Icon(
                              isExpanded
                                  ? Icons.chevron_left_rounded
                                  : Icons.chevron_right_rounded,
                              color: _muted,
                              size: 20,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                // Primary nav (scrollable only here)
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    children: [
                      for (final entry in primaryEntries) ...[
                        _SidebarItem(
                          isExpanded: isExpanded,
                          icon: entry.icon,
                          label: entry.label,
                          selected: entry.selected,
                          accent: widget.accent,
                          onTap: entry.onTap,
                        ),
                        const SizedBox(height: 8),
                      ],
                      const Divider(height: 16),
                    ],
                  ),
                ),

                // Footer (secondary actions pinned)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Column(
                    children: [
                      for (final entry in footerEntries) ...[
                        _SidebarItem(
                          isExpanded: isExpanded,
                          icon: entry.icon,
                          label: entry.label,
                          selected: entry.selected,
                          accent: widget.accent,
                          onTap: entry.onTap,
                        ),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                // Footer (admin chip)
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: isExpanded ? 16 : 8,
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: _tileHover,
                      border: Border.all(color: _border),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: widget.accent.withOpacity(0.12),
                          child: Icon(
                            Icons.person_rounded,
                            size: 18,
                            color: _ink,
                          ),
                        ),
                        if (isExpanded) ...[
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              "Super Admin",
                              style: TextStyle(
                                color: _ink,
                                fontWeight: FontWeight.w900,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Icon(
                            Icons.verified_rounded,
                            color: widget.accent,
                            size: 18,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarItem extends StatefulWidget {
  const _SidebarItem({
    required this.isExpanded,
    required this.icon,
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final bool isExpanded;
  final IconData icon;
  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hover = false;

  Color get _ink => const Color(0xFF0F172A); // slate-900
  Color get _muted => const Color(0xFF334155); // slate-700
  Color get _border => const Color(0x1F0F172A); // subtle border
  Color get _hoverBg => const Color(0xFFF1F5F9); // slate-100

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;

    final bg = selected
        ? widget.accent.withOpacity(0.10)
        : _hover
            ? _hoverBg
            : Colors.transparent;

    final border = selected
        ? widget.accent.withOpacity(0.25)
        : _border;

    final iconColor = selected ? widget.accent : _muted;
    final textColor = selected ? _ink : _muted;

    return Tooltip(
      message: widget.label,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: widget.onTap,
          child: Stack(
            children: [
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: widget.isExpanded ? 14 : 10,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: bg,
                  border: Border.all(color: border),
                ),
                child: Row(
                  mainAxisAlignment: widget.isExpanded
                      ? MainAxisAlignment.start
                      : MainAxisAlignment.center,
                  children: [
                    Icon(widget.icon, color: iconColor, size: 22),
                    if (widget.isExpanded) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.label,
                          style: TextStyle(
                            color: textColor,
                            fontWeight:
                                selected ? FontWeight.w900 : FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (selected)
                Positioned(
                  left: 0,
                  top: 8,
                  bottom: 8,
                  child: Container(
                    width: 3,
                    decoration: BoxDecoration(
                      color: widget.accent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RouteEventsCard extends StatelessWidget {
  const _RouteEventsCard({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    final q = FirebaseFirestore.instance
        .collection('route_events')
        .orderBy('createdAt', descending: true)
        .limit(50);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Text(
            "Route events error:\n${snap.error}",
            style: TextStyle(
              color: _textSoft.withOpacity(0.8),
              fontWeight: FontWeight.w700,
            ),
          );
        }

        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(18),
            child: CircularProgressIndicator(),
          );
        }

        final docs = snap.data?.docs ?? [];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.route_rounded, color: accent, size: 20),
                const SizedBox(width: 10),
                Text(
                  "Route events",
                  style: TextStyle(
                    color: _textSoft.withOpacity(0.92),
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (docs.isEmpty)
              Text(
                "No route events yet.",
                style: TextStyle(
                  color: _textSoft.withOpacity(0.7),
                  fontWeight: FontWeight.w700,
                ),
              )
            else
              for (final d in docs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _RouteEventRow(data: d.data(), accent: accent),
                ),
          ],
        );
      },
    );
  }
}

class _RouteEventRow extends StatelessWidget {
  const _RouteEventRow({required this.data, required this.accent});

  final Map<String, dynamic> data;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final type = (data['type'] ?? '').toString();
    final binTitle = (data['binTitle'] ?? 'Bin').toString();
    final driverUid = (data['driverUid'] ?? '').toString();
    final routeId = (data['routeId'] ?? '').toString();
    final createdAt = data['createdAt'];
    String timeText = '';
    if (createdAt is Timestamp) {
      final dt = createdAt.toDate().toLocal();
      final hh = dt.hour.toString().padLeft(2, '0');
      final mm = dt.minute.toString().padLeft(2, '0');
      timeText = '$hh:$mm ${dt.day}/${dt.month}/${dt.year}';
    }

    final title = type == 'stop_completed'
        ? "$binTitle assignment completed"
        : "Route event";

    final meta = [
      if (driverUid.isNotEmpty) "Driver: $driverUid",
      if (routeId.isNotEmpty) "Route: $routeId",
      if (timeText.isNotEmpty) timeText,
    ].join(" • ");

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white.withOpacity(0.04),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_rounded, color: accent, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: _text,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    meta,
                    style: TextStyle(
                      color: _textSoft.withOpacity(0.7),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarEntry {
  const _SidebarEntry({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.selected,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool selected;
}

void _showProfileDialog({
  required BuildContext context,
  required String title,
  required Map<String, String> fields,
  required Color accent,
}) {
  const ink = Color(0xFF0F172A);
  const muted = Color(0xFF475569);
  const border = Color(0x1F0F172A);

  showDialog(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: Colors.transparent,
      child: _GlassCard(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    height: 38,
                    width: 38,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: accent.withOpacity(0.10),
                      border: Border.all(color: accent.withOpacity(0.18)),
                    ),
                    child: Icon(
                      Icons.badge_rounded,
                      color: accent,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: ink,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close_rounded, color: ink),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: Colors.white,
                  border: Border.all(color: border),
                ),
                child: Column(
                  children: fields.entries.map((e) {
                    final k = e.key;
                    final v = e.value;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: border),
                        ),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 140,
                            child: Text(
                              k,
                              style: TextStyle(
                                color: muted,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              v.isEmpty ? "â€”" : v,
                              style: TextStyle(
                                color: ink,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}


class _ApprovalRow extends StatelessWidget {
  const _ApprovalRow({
    required this.name,
    required this.subtitle,
    required this.accent,
    required this.onOpen,
  });

  final String name;
  final String subtitle;
  final Color accent;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onOpen,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Colors.white.withOpacity(0.04),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: accent.withOpacity(0.18),
              child: Icon(
                Icons.local_shipping_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      color: _text,
                      fontWeight: FontWeight.w900,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: _textSoft.withOpacity(0.7),
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: Colors.white.withOpacity(0.7),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmallButton extends StatefulWidget {
  const _SmallButton({
    required this.label,
    required this.icon,
    required this.accent,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color accent;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_SmallButton> createState() => _SmallButtonState();
}

class _SettingsToggle extends StatelessWidget {
  const _SettingsToggle({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.accent,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: _surface,
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Container(
            height: 38,
            width: 38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: accent.withOpacity(0.12),
              border: Border.all(color: accent.withOpacity(0.22)),
            ),
            child: Icon(icon, color: accent, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: _text,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: _textSoft,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: accent,
          ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: _surface,
          border: Border.all(color: _border),
        ),
        child: Row(
          children: [
            Container(
              height: 38,
              width: 38,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: accent.withOpacity(0.12),
                border: Border.all(color: accent.withOpacity(0.22)),
              ),
              child: Icon(icon, color: accent, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: _text,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: _textSoft,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: _textSoft,
            ),
          ],
        ),
      ),
    );
  }
}

class _SmallButtonState extends State<_SmallButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: enabled ? widget.onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: enabled
                ? (_hover
                      ? widget.accent.withOpacity(0.18)
                      : Colors.white.withOpacity(0.06))
                : Colors.white.withOpacity(0.03),
            border: Border.all(
              color: enabled
                  ? (_hover
                        ? widget.accent.withOpacity(0.35)
                        : Colors.white.withOpacity(0.08))
                  : Colors.white.withOpacity(0.06),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, color: Colors.white, size: 16),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: TextStyle(
                  color: _textSoft.withOpacity(enabled ? 1 : 0.6),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _Severity { low, medium, high }

class _AlertRow extends StatelessWidget {
  const _AlertRow({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.severity,
    required this.onTap,
    this.enabled = true,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;

  /// low / medium / high â€“ controls styling
  final _Severity severity;

  /// Whether row is clickable
  final bool enabled;

  /// Tap handler (only runs if enabled == true)
  final VoidCallback onTap;

  Color _sevColor() {
    switch (severity) {
      case _Severity.high:
        return Colors.redAccent;
      case _Severity.medium:
        return accent;
      case _Severity.low:
      default:
        return Colors.white;
    }
  }

  @override
  Widget build(BuildContext context) {
    final sev = _sevColor();
    final baseOpacity = enabled ? 1.0 : 0.55;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Colors.white.withOpacity(0.04),
          border: Border.all(color: sev.withOpacity(enabled ? 0.22 : 0.12)),
        ),
        child: Row(
          children: [
            Container(
              height: 42,
              width: 42,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: sev.withOpacity(0.14),
                border: Border.all(color: sev.withOpacity(0.22)),
              ),
              child: Icon(icon, color: Colors.white.withOpacity(baseOpacity)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: _textSoft.withOpacity(baseOpacity),
                      fontWeight: FontWeight.w900,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: _textSoft.withOpacity(0.7 * baseOpacity),
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: sev.withOpacity(0.18),
                border: Border.all(color: sev.withOpacity(0.22)),
              ),
              child: Text(
                severity.name,
                style: TextStyle(
                  color: _textSoft.withOpacity(baseOpacity),
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              color: Colors.white.withOpacity(enabled ? 0.55 : 0.25),
            ),
          ],
        ),
      ),
    );
  }
}

class _FakeTable extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final headers = ["Time", "Type", "User", "Status"];
    final rows = [
      ["â€”", "New user", "â€”", "Success"],
      ["â€”", "New driver", "â€”", "Pending"],
      ["â€”", "Request", "â€”", "Review"],
    ];

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        color: Colors.white.withOpacity(0.03),
      ),
      child: Column(
        children: [
          _TableRowWidget(cells: headers, isHeader: true),
          for (final r in rows) _TableRowWidget(cells: r, isHeader: false),
        ],
      ),
    );
  }
}

class _TableRowWidget extends StatelessWidget {
  const _TableRowWidget({required this.cells, required this.isHeader});

  final List<String> cells;
  final bool isHeader;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: _textSoft.withOpacity(isHeader ? 0.85 : 0.72),
      fontSize: 12.5,
      fontWeight: isHeader ? FontWeight.w900 : FontWeight.w800,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.06)),
        ),
      ),
      child: Row(
        children: [
          for (final c in cells)
            Expanded(
              child: Text(c, style: style, overflow: TextOverflow.ellipsis),
            ),
        ],
      ),
    );
  }
}

class _BlockedScreen extends StatelessWidget {
  const _BlockedScreen({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                color: Colors.white,
                border: Border.all(color: _border),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: _text,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _textSoft.withOpacity(0.8),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem({required this.icon, required this.label});
}

class _DotGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _adminDarkMode.value
          ? Colors.white.withOpacity(0.06)
          : Colors.black.withOpacity(0.06);
    const spacing = 18.0;
    for (double y = 0; y < size.height; y += spacing) {
      for (double x = 0; x < size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), 0.8, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}


