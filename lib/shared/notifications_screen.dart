import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:ugswms/shared/notifications_inbox.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({
    super.key,
    this.title = "Notifications",
    this.recipientRole,
  });

  final String title;
  final String? recipientRole;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(
        body: Center(child: Text("Please login first.")),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: NotificationsInbox(
        recipientUid: user.uid,
        recipientRole: recipientRole,
      ),
    );
  }
}
