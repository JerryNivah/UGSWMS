import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class DriverNotificationsScreen extends StatelessWidget {
  const DriverNotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text("Please login.")));
    }

    final q = FirebaseFirestore.instance
        .collection('notifications')
        .where('toUid', isEqualTo: user.uid)
        .orderBy('createdAt', descending: true)
        .limit(50);

    return Scaffold(
      appBar: AppBar(title: const Text("Notifications")),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: q.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Text("Failed to load notifications: ${snap.error}"),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return const Center(child: Text("No notifications yet."));
          }

          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final n = docs[i].data();
              final title = (n['title'] ?? 'Notification').toString();
              final body = (n['body'] ?? '').toString();
              final read = (n['read'] ?? false) == true;

              return ListTile(
                title: Text(title),
                subtitle: body.isEmpty ? null : Text(body, maxLines: 2, overflow: TextOverflow.ellipsis),
                leading: Icon(read ? Icons.notifications_none : Icons.notifications_active),
                trailing: read
                    ? const Text("Read")
                    : TextButton(
                        onPressed: () async {
                          await FirebaseFirestore.instance
                              .collection('notifications')
                              .doc(docs[i].id)
                              .update({'read': true});
                        },
                        child: const Text("Mark read"),
                      ),
                onTap: () async {
                  if (!read) {
                    await FirebaseFirestore.instance
                        .collection('notifications')
                        .doc(docs[i].id)
                        .update({'read': true});
                  }
                },
              );
            },
          );
        },
      ),
    );
  }
}

class DriverNotificationListener extends StatefulWidget {
  const DriverNotificationListener({super.key, required this.child});
  final Widget child;

  @override
  State<DriverNotificationListener> createState() =>
      _DriverNotificationListenerState();
}

class _DriverNotificationListenerState
    extends State<DriverNotificationListener> {
  StreamSubscription? _sub;
  String? _lastNotifiedId;

  @override
  void initState() {
    super.initState();

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _sub = FirebaseFirestore.instance
        .collection('notifications')
        .where('toUid', isEqualTo: user.uid)
        .where('read', isEqualTo: false)
        .orderBy('createdAt', descending: true)
        .limit(1)
        .snapshots()
        .listen((snap) async {
      if (!mounted) return;
      if (snap.docs.isEmpty) return;

      final doc = snap.docs.first;
      if (_lastNotifiedId == doc.id) return;
      _lastNotifiedId = doc.id;

      final data = doc.data();
      final title = (data['title'] ?? 'Notification').toString();
      final body = (data['body'] ?? '').toString();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("$title - $body")),
      );

      await doc.reference.update({'read': true});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
