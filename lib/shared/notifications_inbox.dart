import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class NotificationsInbox extends StatefulWidget {
  const NotificationsInbox({
    super.key,
    required this.recipientUid,
    this.recipientRole,
    this.limit = 100,
    this.showActions = true,
  });

  final String recipientUid;
  final String? recipientRole;
  final int limit;
  final bool showActions;

  @override
  State<NotificationsInbox> createState() => _NotificationsInboxState();
}

class _NotificationsInboxState extends State<NotificationsInbox> {
  bool _markingAll = false;
  bool _clearingAll = false;

  Query<Map<String, dynamic>> _query() {
    final base = FirebaseFirestore.instance.collection('notifications');
    final role = widget.recipientRole?.trim();
    final uid = widget.recipientUid.trim();

    if (uid.isEmpty && (role == null || role.isEmpty)) {
      return base.orderBy('createdAt', descending: true).limit(widget.limit);
    }

    if (uid.isNotEmpty && role != null && role.isNotEmpty) {
      return base
          .where(
            Filter.or(
              Filter('toUid', isEqualTo: uid),
              Filter('role', isEqualTo: role),
            ),
          )
          .orderBy('createdAt', descending: true)
          .limit(widget.limit);
    }

    if (uid.isNotEmpty) {
      return base
          .where('toUid', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .limit(widget.limit);
    }

    return base
        .where('role', isEqualTo: role)
        .orderBy('createdAt', descending: true)
        .limit(widget.limit);
  }

  Future<void> _markAllRead(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    if (_markingAll) return;
    setState(() => _markingAll = true);

    try {
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in docs) {
        batch.update(doc.reference, {'read': true});
      }
      await batch.commit();
    } finally {
      if (mounted) setState(() => _markingAll = false);
    }
  }

  Future<void> _clearAll(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    if (_clearingAll) return;
    setState(() => _clearingAll = true);

    try {
      // Firestore batch limit is 500
      for (var i = 0; i < docs.length; i += 450) {
        final batch = FirebaseFirestore.instance.batch();
        final slice = docs.skip(i).take(450);
        for (final doc in slice) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }
    } finally {
      if (mounted) setState(() => _clearingAll = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _query().snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              "Failed to load notifications: ${snap.error}",
              style: TextStyle(color: scheme.error),
            ),
          );
        }

        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snap.data!.docs;
        final unread =
            docs.where((d) => (d.data()['read'] ?? false) != true).toList();

        if (docs.isEmpty) {
          return const Center(child: Text("No notifications yet."));
        }

        return Column(
          children: [
            if (widget.showActions)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Row(
                  children: [
                    Text(
                      "Notifications",
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    Text(
                      "Unread: ${unread.length}",
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 10),
                    TextButton(
                      onPressed: unread.isEmpty || _markingAll
                          ? null
                          : () => _markAllRead(unread),
                      child: _markingAll
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text("Mark all read"),
                    ),
                    const SizedBox(width: 6),
                    TextButton(
                      onPressed: docs.isEmpty || _clearingAll
                          ? null
                          : () async {
                              final ok = await showDialog<bool>(
                                context: context,
                                builder: (_) => AlertDialog(
                                  title: const Text("Clear notifications?"),
                                  content: const Text(
                                    "This will delete all visible notifications.",
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: const Text("Cancel"),
                                    ),
                                    ElevatedButton(
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      child: const Text("Clear"),
                                    ),
                                  ],
                                ),
                              );
                              if (ok == true) {
                                await _clearAll(docs);
                              }
                            },
                      child: _clearingAll
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text("Clear"),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final doc = docs[i];
                  final data = doc.data();

                  final title = (data['title'] ?? 'Notification').toString();
                  final body = (data['body'] ?? '').toString();
                  final type = (data['type'] ?? '').toString();
                  final severity = (data['severity'] ?? 'low').toString();
                  final read = (data['read'] ?? false) == true;
                  final createdAt = data['createdAt'] as Timestamp?;

                  final ts = _formatTimestamp(createdAt);
                  final sevColor = _severityColor(severity, scheme);
                  final titleColor = read
                      ? scheme.onSurface.withOpacity(0.75)
                      : scheme.onSurface;
                  final bodyColor = scheme.onSurface.withOpacity(0.65);

                  return InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: read
                        ? null
                        : () => doc.reference.update({'read': true}),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: read
                            ? scheme.surface
                            : scheme.primary.withOpacity(0.06),
                        border: Border.all(
                          color: read
                              ? scheme.outline.withOpacity(0.4)
                              : scheme.primary.withOpacity(0.25),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            height: 10,
                            width: 10,
                            margin: const EdgeInsets.only(top: 4),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: sevColor,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: TextStyle(
                                    color: titleColor,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                if (body.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    body,
                                    style: TextStyle(
                                      color: bodyColor,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 6),
                                Text(
                                  [if (type.isNotEmpty) type, if (ts.isNotEmpty) ts]
                                      .join(" • "),
                                  style: TextStyle(
                                    color: scheme.onSurface.withOpacity(0.5),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (!read)
                            Text(
                              "new",
                              style: TextStyle(
                                color: scheme.primary,
                                fontWeight: FontWeight.w900,
                                fontSize: 11,
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

String _formatTimestamp(Timestamp? ts) {
  if (ts == null) return "";
  final dt = ts.toDate().toLocal();
  final mm = dt.month.toString().padLeft(2, '0');
  final dd = dt.day.toString().padLeft(2, '0');
  final hh = dt.hour.toString().padLeft(2, '0');
  final mi = dt.minute.toString().padLeft(2, '0');
  return "${dt.year}-$mm-$dd $hh:$mi";
}

Color _severityColor(String severity, ColorScheme scheme) {
  switch (severity) {
    case 'high':
      return scheme.error;
    case 'medium':
      return scheme.primary;
    case 'low':
    default:
      return scheme.onSurface.withOpacity(0.5);
  }
}
