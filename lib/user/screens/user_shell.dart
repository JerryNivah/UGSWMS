import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:ugswms/user/screens/user_requests_screen.dart';
import 'package:ugswms/user/screens/notifications_screen.dart';
import 'package:ugswms/user/screens/profile_screen.dart';

class UserShell extends StatefulWidget {
  const UserShell({super.key});

  @override
  State<UserShell> createState() => _UserShellState();
}

class _UserShellState extends State<UserShell> {
  int _index = 0;

  final _pages = const [
    UserRequestsScreen(),
    NotificationsScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.assignment_rounded),
            label: "Requests",
          ),
          NavigationDestination(
            icon: _NotificationsBadge(user: user),
            label: "Notifications",
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_rounded),
            label: "Profile",
          ),
        ],
      ),
    );
  }
}

class _NotificationsBadge extends StatelessWidget {
  const _NotificationsBadge({required this.user});

  final User? user;

  @override
  Widget build(BuildContext context) {
    if (user == null) {
      return const Icon(Icons.notifications_rounded);
    }

    final q = FirebaseFirestore.instance
        .collection('notifications')
        .where('toUid', isEqualTo: user!.uid)
        .where('read', isEqualTo: false)
        .limit(99);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snap) {
        final count = snap.data?.docs.length ?? 0;
        if (count == 0) {
          return const Icon(Icons.notifications_rounded);
        }

        return Badge(
          label: Text("$count"),
          child: const Icon(Icons.notifications_rounded),
        );
      },
    );
  }
}
