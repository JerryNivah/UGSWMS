import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:ugswms/core/app_flags.dart';

// ===== Light Admin Theme Tokens =====
const Color _accent = Color(0xFF3B82F6);

const Color _bgTop = Color(0xFFF8FAFC); // slate-50
const Color _bgMid = Color(0xFFF1F5F9); // slate-100
const Color _bgBot = Color(0xFFFFFFFF); // white

const Color _surface = Color(0xCCFFFFFF); // white glass
const Color _border = Color(0x1F0F172A);  // subtle border
const Color _text = Color(0xFF0F172A);    // slate-900
const Color _textSoft = Color(0xFF475569); // slate-600


class AssignmentsPage extends StatefulWidget {
  const AssignmentsPage({super.key, required this.accent});
  final Color accent;

  @override
  State<AssignmentsPage> createState() => _AssignmentsPageState();
}

class _AssignmentsPageState extends State<AssignmentsPage> {
  static const String requestsCol = 'service_requests';
  static const String usersCol = 'users';
  static const String assignmentsCol = 'assignments';
  static const String _filterAll = 'all';
  static const String _filterPrivate = 'private';
  static const String _filterPublic = 'public_bin';

  String? _selectedRequestId;
  Map<String, dynamic>? _selectedRequest;

  String? _selectedDriverUid;
  Map<String, dynamic>? _selectedDriver;

  bool _busy = false;
  String _search = "";
  String _requestTypeFilter = _filterAll;

  // Cache driver names so "Recent Assignments" can show names (not UIDs)
  final Map<String, String> _driverNameByUid = {};
  StreamSubscription? _driversSub;

  @override
  void initState() {
    super.initState();
    _listenDrivers();
  }

  @override
  void dispose() {
    _driversSub?.cancel();
    super.dispose();
  }

  void _listenDrivers() {
    _driversSub = FirebaseFirestore.instance
        .collection(usersCol)
        .where('role', isEqualTo: 'driver')
        .snapshots()
        .listen((snap) {
      final next = <String, String>{};
      for (final d in snap.docs) {
        final data = d.data();
        next[d.id] = _driverName(data);
      }
      if (mounted) {
        setState(() {
          _driverNameByUid
            ..clear()
            ..addAll(next);
        });
      }
    });
  }

  bool _isRequestVisibleInFilter(Map<String, dynamic> r) {
    if (_requestTypeFilter == _filterAll) return true;
    return _requestType(r) == _requestTypeFilter;
  }

  // Only show pending requests
  Query<Map<String, dynamic>> _requestsQ() {
    var q = FirebaseFirestore.instance
        .collection(requestsCol)
        .where('status', isEqualTo: 'pending');

    if (_requestTypeFilter != _filterAll) {
      q = q.where('requestType', isEqualTo: _requestTypeFilter);
    }

    return q.orderBy('createdAt', descending: true).limit(80);
  }

  Query<Map<String, dynamic>> _driversQ() {
    return FirebaseFirestore.instance
        .collection(usersCol)
        .where('role', isEqualTo: 'driver')
        .where('status', isEqualTo: 'active')
        .orderBy('createdAt', descending: true)
        .limit(80);
  }

  Query<Map<String, dynamic>> _recentAssignmentsQ() {
    return FirebaseFirestore.instance
        .collection(assignmentsCol)
        .orderBy('createdAt', descending: true)
        .limit(25);
  }

  // Helpers for button rules
  bool _isCancelledOrDone(Map<String, dynamic> r) {
    final s = (r['status'] ?? '').toString().toLowerCase();
    return s == 'cancelled' || s == 'completed' || s == 'done';
  }

  bool _alreadyAssigned(Map<String, dynamic> r) {
    final v = r['assignedDriverUid'];
    if (v == null) return false;
    if (v is String && v.trim().isEmpty) return false;
    return true;
  }

  bool _isUnassigned(Map<String, dynamic> r) {
    final v = r['assignedDriverUid'];
    if (v == null) return true;
    if (v is String && v.trim().isEmpty) return true;
    return false;
  }

  // ✅ Map assignment status -> request status (what user app reads)
  String _requestStatusFromAssignmentStatus(String s) {
    final v = s.toLowerCase().trim();
    if (v == 'pending') return 'assigned'; // assigned but not accepted yet
    if (v == 'accepted') return 'accepted';
    if (v == 'completed' || v == 'done') return 'completed';
    if (v == 'cancelled') return 'cancelled';
    return 'assigned';
  }

  bool _matchesSearch(Map<String, dynamic> r) {
    if (_search.trim().isEmpty) return true;
    final s = _search.toLowerCase();

    final serviceType = (r['serviceType'] ?? '').toString().toLowerCase();
    final pickup = (r['pickupAddressText'] ?? '').toString().toLowerCase();
    final qty = (r['quantity'] ?? '').toString().toLowerCase();
    final status = (r['status'] ?? '').toString().toLowerCase();
    final email = (r['userEmail'] ?? '').toString().toLowerCase();
    final notes = (r['notes'] ?? '').toString().toLowerCase();
    final requestType = _requestType(r).toLowerCase();
    final source = _requestSource(r).toLowerCase();

    return serviceType.contains(s) ||
        pickup.contains(s) ||
        qty.contains(s) ||
        status.contains(s) ||
        email.contains(s) ||
        notes.contains(s) ||
        requestType.contains(s) ||
        source.contains(s);
  }

  String _requestTitle(Map<String, dynamic> r) {
    final type = (r['serviceType'] ?? 'request').toString();
    final qty = (r['quantity'] ?? '').toString();
    return qty.isEmpty ? type : "$type • $qty";
  }

  String _requestSubtitle(Map<String, dynamic> r) {
    final addr = (r['pickupAddressText'] ?? '').toString();
    final email = (r['userEmail'] ?? '').toString();
    final status = (r['status'] ?? '').toString();
    final requestType = _requestType(r);
    final source = _requestSource(r);
    final paymentRequired = _paymentRequired(r);
    final parts = <String>[];
    if (addr.isNotEmpty) parts.add(addr);
    if (email.isNotEmpty) parts.add(email);
    if (status.isNotEmpty) parts.add("status: $status");
    if (requestType != 'unknown') parts.add("type: $requestType");
    if (source != 'unknown') parts.add("source: $source");
    if (paymentRequired) parts.add("paid");
    return parts.isEmpty ? "—" : parts.join(" • ");
  }

  String _requestType(Map<String, dynamic> r) =>
      (r['requestType'] ?? 'unknown').toString();

  String _requestSource(Map<String, dynamic> r) =>
      (r['source'] ?? 'unknown').toString();

  bool _paymentRequired(Map<String, dynamic> r) =>
      (r['paymentRequired'] ?? false) == true;

  Widget _requestTypeBadge(String type) {
    final upper = type.toLowerCase();
    String? label;
    Color? color;
    if (upper == 'private') {
      label = 'PRIVATE';
      color = const Color(0xFF10B981);
    } else if (upper == 'public_bin') {
      label = 'PUBLIC';
      color = const Color(0xFFF59E0B);
    }

    if (label == null) return const SizedBox.shrink();

    final c = color ?? const Color(0xFF64748B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withOpacity(0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withOpacity(0.45)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: c,
          fontWeight: FontWeight.w800,
          fontSize: 10.5,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  String _driverName(Map<String, dynamic> d) {
    return (d['name'] ?? d['fullName'] ?? d['email'] ?? 'Driver').toString();
  }

  String _driverSubtitle(Map<String, dynamic> d) {
    final phone = (d['phone'] ?? '').toString();
    final cls = (d['vehicleClass'] ?? '').toString();
    final email = (d['email'] ?? '').toString();
    final parts = <String>[];
    if (email.isNotEmpty) parts.add(email);
    if (phone.isNotEmpty) parts.add(phone);
    if (cls.isNotEmpty) parts.add("class: $cls");
    return parts.isEmpty ? "—" : parts.join(" • ");
  }

  String _shortId(String id) => id.length <= 8 ? id : "${id.substring(0, 8)}…";

  void _clearSelection() {
    setState(() {
      _selectedRequestId = null;
      _selectedRequest = null;
      _selectedDriverUid = null;
      _selectedDriver = null;
    });
  }

  Future<void> _assignSelected() async {
    if (_selectedRequestId == null || _selectedDriverUid == null) return;
    if (_selectedRequest == null) return;

    if (_isCancelledOrDone(_selectedRequest!)) return;
    if (_alreadyAssigned(_selectedRequest!)) return;
    if (!_isRequestVisibleInFilter(_selectedRequest!)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Selected request is outside current filter.")),
        );
      }
      return;
    }

    if (ENABLE_PAYMENT_GATE) {
      final type = _requestType(_selectedRequest!);
      final requiresPayment = type == 'private' && _paymentRequired(_selectedRequest!);
      if (requiresPayment) {
        final paidSnap = await FirebaseFirestore.instance
            .collection('payments')
            .where('serviceRequestId', isEqualTo: _selectedRequestId)
            .where('status', isEqualTo: 'paid')
            .limit(1)
            .get();
        if (paidSnap.docs.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Payment required before assigning driver."),
              ),
            );
          }
          return;
        }
      }
    }

    setState(() => _busy = true);
    try {
      final admin = FirebaseAuth.instance.currentUser;
      final now = FieldValue.serverTimestamp();

      final reqRef =
          FirebaseFirestore.instance.collection(requestsCol).doc(_selectedRequestId);

      final assignRef =
          FirebaseFirestore.instance.collection(assignmentsCol).doc();

      await assignRef.set({
        'requestId': _selectedRequestId,
        'driverUid': _selectedDriverUid,
        'status': 'pending',
        'createdAt': now,
        'updatedAt': now,
        'createdBy': admin?.uid,
        'serviceType': (_selectedRequest?['serviceType'] ?? '').toString(),
        'pickupAddressText':
            (_selectedRequest?['pickupAddressText'] ?? '').toString(),
        'userUid': (_selectedRequest?['userUid'] ?? '').toString(),
        'userEmail': (_selectedRequest?['userEmail'] ?? '').toString(),
      });

      // ✅ IMPORTANT: also update request status to "assigned"
      await reqRef.update({
        'assignedDriverUid': _selectedDriverUid,
        'assignmentId': assignRef.id,
        'assignmentStatus': 'pending',
        'status': 'assigned',
        'assignedAt': now,
        'updatedAt': now,
      });

      await FirebaseFirestore.instance.collection('notifications').add({
        'toUid': _selectedDriverUid,
        'role': 'driver',
        'title': 'New assignment',
        'body': (_selectedRequest?['serviceType'] ?? 'Service request')
            .toString(),
        'type': 'assignment_assigned',
        'severity': 'medium',
        'refType': 'assignment',
        'refId': assignRef.id,
        'extra': {
          'requestId': _selectedRequestId,
          'serviceType': (_selectedRequest?['serviceType'] ?? '').toString(),
        },
        'read': false,
        'createdAt': now,
      });

      final userUid = (_selectedRequest?['userUid'] ?? '').toString();
      if (userUid.isNotEmpty) {
        await FirebaseFirestore.instance.collection('notifications').add({
          'toUid': userUid,
          'role': 'resident',
          'title': 'Driver assigned',
          'body': 'A driver has been assigned to your request.',
          'type': 'driver_assigned',
          'severity': 'medium',
          'refType': 'service_request',
          'refId': _selectedRequestId,
          'extra': {
            'assignmentId': assignRef.id,
            'driverUid': _selectedDriverUid,
          },
          'read': false,
          'createdAt': now,
        });
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Assigned successfully")));

      _clearSelection();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Assign failed: $e")));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setAssignmentStatus(
    String assignmentId,
    String newStatus, {
    required String requestId,
  }) async {
    try {
      final batch = FirebaseFirestore.instance.batch();

      final aRef =
          FirebaseFirestore.instance.collection(assignmentsCol).doc(assignmentId);

      final rRef =
          FirebaseFirestore.instance.collection(requestsCol).doc(requestId);

      // ✅ Update assignment document
      batch.update(aRef, {
        'status': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // ✅ Update request document (what user app reads)
      batch.update(rRef, {
        'assignmentStatus': newStatus,
        'status': _requestStatusFromAssignmentStatus(newStatus),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await batch.commit();

      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Status updated -> $newStatus")));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Failed: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final requestOk = _selectedRequest != null &&
        !_isCancelledOrDone(_selectedRequest!) &&
        !_alreadyAssigned(_selectedRequest!);

    final canAssign = !_busy &&
        _selectedRequestId != null &&
        _selectedDriverUid != null &&
        requestOk;

    final tileTheme = ListTileThemeData(
      textColor: _text,
      iconColor: _textSoft,
      subtitleTextStyle: TextStyle(
        color: Colors.white.withOpacity(0.70),
        fontWeight: FontWeight.w700,
        fontSize: 12.5,
      ),
      titleTextStyle: const TextStyle(
        color: _text,
        fontWeight: FontWeight.w900,
      ),
    );

    return Padding(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, c) {
          final isWide = c.maxWidth >= 1000;

          final requests = _panel(
            title: "Pending Requests",
            icon: Icons.inbox_rounded,
            child: Column(
                children: [
                  _searchBox(
                    hint: "Search requests: pickup, email, type...",
                    onChanged: (v) => setState(() => _search = v),
                  ),
                  const SizedBox(height: 8),
                  _requestTypeFilters(),
                  const SizedBox(height: 10),
                  ListTileTheme(
                    data: tileTheme,
                    child: SizedBox(height: 420, child: _requestsList()),
                  ),
                ],
            ),
          );

          final drivers = _panel(
            title: "Active Drivers",
            icon: Icons.local_shipping_rounded,
            child: ListTileTheme(
              data: tileTheme,
              child: SizedBox(height: 470, child: _driversList()),
            ),
          );

          final action = _panel(
            title: "Assignment",
            icon: Icons.assignment_ind_rounded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        "Selection",
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    TextButton.icon(
                      onPressed:
                          (_selectedRequestId != null || _selectedDriverUid != null)
                              ? _clearSelection
                              : null,
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      label: const Text("Clear"),
                      style: TextButton.styleFrom(
                        foregroundColor: _text,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text("Selected Request",
                    style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text(
                  _selectedRequest == null
                      ? "—"
                      : "${_requestTitle(_selectedRequest!)}\n${_requestSubtitle(_selectedRequest!)}",
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 12),
                const Text("Selected Driver",
                    style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text(
                  _selectedDriver == null
                      ? "—"
                      : "${_driverName(_selectedDriver!)}\n${_driverSubtitle(_selectedDriver!)}",
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: canAssign ? _assignSelected : null,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
                    label: const Text("Assign Driver"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: widget.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                if (_selectedRequest != null && !requestOk)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _isCancelledOrDone(_selectedRequest!)
                          ? "This request is cancelled/completed."
                          : "This request is already assigned.",
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                if (_selectedRequest == null || _selectedDriverUid == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      "Tip: select a request + driver to enable assignment.",
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.55),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          );

          final recent = _panel(
            title: "Recent Assignments",
            icon: Icons.history_rounded,
            child: ListTileTheme(
              data: tileTheme,
              child: SizedBox(height: 260, child: _recentAssignments()),
            ),
          );

          if (!isWide) {
            return ListView(
              children: [
                requests,
                const SizedBox(height: 12),
                drivers,
                const SizedBox(height: 12),
                action,
                const SizedBox(height: 12),
                recent,
              ],
            );
          }

          return Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: requests),
                  const SizedBox(width: 12),
                  Expanded(child: drivers),
                  const SizedBox(width: 12),
                  SizedBox(width: 360, child: action),
                ],
              ),
              const SizedBox(height: 12),
              recent,
            ],
          );
        },
      ),
    );
  }

  Widget _panel({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Card(
      color: const Color(0xFF0E1629).withOpacity(0.72),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: DefaultTextStyle(
          style: const TextStyle(color: Colors.white),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: widget.accent),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              child,
            ],
          ),
        ),
      ),
    );
  }

  Widget _searchBox({
    required String hint,
    required ValueChanged<String> onChanged,
  }) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded,
              color: _textSoft, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              onChanged: onChanged,
              style: const TextStyle(
                color: _text,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
              cursorColor: _text,
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(
                  color: Colors.white.withOpacity(0.55),
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _requestTypeFilters() {
    final items = [
      {'value': _filterAll, 'label': 'All'},
      {'value': _filterPrivate, 'label': 'Private (User)'},
      {'value': _filterPublic, 'label': 'Public (Bins)'},
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items.map((e) {
        final value = e['value'] as String;
        final label = e['label'] as String;
        final selected = _requestTypeFilter == value;
        return ChoiceChip(
          label: Text(
            label,
            style: TextStyle(
              color: selected ? _text : _textSoft,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          selected: selected,
          onSelected: (_) {
            setState(() {
              _requestTypeFilter = value;
              if (_selectedRequest != null &&
                  !_isRequestVisibleInFilter(_selectedRequest!)) {
                _selectedRequestId = null;
                _selectedRequest = null;
              }
            });
          },
          selectedColor: widget.accent.withOpacity(0.18),
          backgroundColor: Colors.white.withOpacity(0.06),
          shape: StadiumBorder(
            side: BorderSide(color: Colors.white.withOpacity(0.12)),
          ),
        );
      }).toList(),
    );
  }

  Widget _requestsList() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _requestsQ().snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return Text("Failed to load requests: ${snap.error}");
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());

        final docs = snap.data!.docs.where((d) => _matchesSearch(d.data())).toList();

        if (docs.isEmpty) {
          return Center(
            child: Text(
              "No pending requests found.",
              style: TextStyle(
                color: Colors.white.withOpacity(0.75),
                fontWeight: FontWeight.w700,
              ),
            ),
          );
        }

        return ListView.separated(
          itemCount: docs.length,
          separatorBuilder: (_, __) =>
              Divider(height: 1, color: Colors.white.withOpacity(0.08)),
          itemBuilder: (context, i) {
            final doc = docs[i];
            final data = doc.data();
            final selected = doc.id == _selectedRequestId;

            final assignedUid =
                (data['assignedDriverUid'] ?? '').toString().trim();
            final isAssigned = assignedUid.isNotEmpty;

            final assignmentStatus =
                (data['assignmentStatus'] ?? (isAssigned ? 'pending' : ''))
                    .toString()
                    .trim()
                    .toLowerCase();

            final assignedName =
                isAssigned ? (_driverNameByUid[assignedUid] ?? "Driver") : "";

            final disabled = _isCancelledOrDone(data) || isAssigned;

            final baseSub = _requestSubtitle(data);
            final extraParts = <String>[];
            if (isAssigned) extraParts.add("Assigned to: $assignedName");
            if (assignmentStatus.isNotEmpty) extraParts.add("Assign: $assignmentStatus");

            final subtitle =
                extraParts.isEmpty ? baseSub : "$baseSub • ${extraParts.join(' • ')}";

            return Opacity(
              opacity: disabled ? 0.45 : 1,
              child: ListTile(
                enabled: !disabled,
                selected: selected,
                selectedTileColor: widget.accent.withOpacity(0.12),
                leading: Icon(
                  Icons.assignment_late_rounded,
                  color: selected ? widget.accent : Colors.white.withOpacity(0.8),
                ),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _requestTitle(data),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _requestTypeBadge(_requestType(data)),
                  ],
                ),
                subtitle: Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: isAssigned
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _StatusChip(
                            status: assignmentStatus.isEmpty
                                ? 'pending'
                                : assignmentStatus,
                            accent: widget.accent,
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.lock_rounded, color: Colors.white54),
                        ],
                      )
                    : (selected
                        ? Icon(Icons.check_circle_rounded, color: widget.accent)
                        : null),
                onTap: disabled
                    ? null
                    : () {
                        setState(() {
                          _selectedRequestId = doc.id;
                          _selectedRequest = data;
                        });
                      },
              ),
            );
          },
        );
      },
    );
  }

  Widget _driversList() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _driversQ().snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return Text("Failed to load drivers: ${snap.error}");
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());

        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return Center(
            child: Text(
              "No active drivers.",
              style: TextStyle(
                color: Colors.white.withOpacity(0.75),
                fontWeight: FontWeight.w700,
              ),
            ),
          );
        }

        return ListView.separated(
          itemCount: docs.length,
          separatorBuilder: (_, __) =>
              Divider(height: 1, color: Colors.white.withOpacity(0.08)),
          itemBuilder: (context, i) {
            final doc = docs[i];
            final data = doc.data();
            final selected = doc.id == _selectedDriverUid;

            return ListTile(
              selected: selected,
              selectedTileColor: widget.accent.withOpacity(0.12),
              leading: CircleAvatar(
                backgroundColor: selected
                    ? widget.accent.withOpacity(.18)
                    : Colors.white.withOpacity(.10),
                child: Icon(Icons.person_rounded,
                    color: Colors.white.withOpacity(0.92)),
              ),
              title: Text(_driverName(data),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(_driverSubtitle(data),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing:
                  selected ? Icon(Icons.check_circle_rounded, color: widget.accent) : null,
              onTap: () {
                setState(() {
                  _selectedDriverUid = doc.id;
                  _selectedDriver = data;
                });
              },
            );
          },
        );
      },
    );
  }

  Widget _recentAssignments() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _recentAssignmentsQ().snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return Text("Failed to load assignments: ${snap.error}");
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());

        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return Center(
            child: Text(
              "No assignments yet.",
              style: TextStyle(
                color: Colors.white.withOpacity(0.75),
                fontWeight: FontWeight.w700,
              ),
            ),
          );
        }

        return ListView.separated(
          itemCount: docs.length,
          separatorBuilder: (_, __) =>
              Divider(height: 1, color: Colors.white.withOpacity(0.08)),
          itemBuilder: (context, i) {
            final doc = docs[i];
            final a = doc.data();

            final requestId = (a['requestId'] ?? '').toString();
            final driverUid = (a['driverUid'] ?? '').toString();
            final status = (a['status'] ?? 'pending').toString().toLowerCase();

            final serviceType = (a['serviceType'] ?? '').toString();
            final pickup = (a['pickupAddressText'] ?? '').toString();

            final driverName =
                _driverNameByUid[driverUid] ?? (driverUid.isEmpty ? "—" : "Driver");

            final title = [
              if (serviceType.isNotEmpty) serviceType,
              "Req: ${_shortId(requestId)}",
            ].join(" • ");

            final subtitle = [
              if (pickup.isNotEmpty) pickup,
              "Driver: $driverName",
            ].join(" • ");

            return ListTile(
              leading: Icon(Icons.assignment_rounded, color: widget.accent),
              title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _StatusChip(status: status, accent: widget.accent),
                  const SizedBox(width: 6),
                  PopupMenuButton<String>(
                    onSelected: (v) =>
                        _setAssignmentStatus(doc.id, v, requestId: requestId),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'pending', child: Text('Set Pending')),
                      PopupMenuItem(value: 'completed', child: Text('Set Completed')),
                      PopupMenuItem(value: 'cancelled', child: Text('Set Cancelled')),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, required this.accent});
  final String status;
  final Color accent;

  Color _bg() {
    switch (status) {
      case 'accepted':
        return Colors.green.withOpacity(0.18);
      case 'completed':
      case 'done':
        return Colors.blue.withOpacity(0.18);
      case 'cancelled':
        return Colors.red.withOpacity(0.18);
      case 'pending':
      default:
        return accent.withOpacity(0.18);
    }
  }

  Color _fg() {
    switch (status) {
      case 'accepted':
        return Colors.greenAccent;
      case 'completed':
      case 'done':
        return Colors.lightBlueAccent;
      case 'cancelled':
        return Colors.redAccent;
      case 'pending':
      default:
        return Colors.white.withOpacity(0.92);
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = status.trim().isEmpty ? 'pending' : status;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _bg(),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: _fg(),
          fontWeight: FontWeight.w900,
          fontSize: 11.5,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
