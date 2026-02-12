import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'screens/driver_jobs_screen.dart';
import 'screens/driver_notifications_screen.dart';
import 'screens/driver_profile_screen.dart';
import 'screens/driver_route_screen.dart';

class DriverShell extends StatefulWidget {
  const DriverShell({super.key});

  @override
  State<DriverShell> createState() => _DriverShellState();
}

class _DriverShellState extends State<DriverShell> {
  int _index = 0;

  final _pages = const [
    DriverJobsScreen(),
    DriverRouteScreen(),
    DriverNotificationsScreen(),
    DriverProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return DriverNotificationListener(
      child: Scaffold(
        body: IndexedStack(index: _index, children: _pages),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: [
          const NavigationDestination(
            icon: Icon(Icons.work_rounded),
            label: "Jobs",
          ),
          const NavigationDestination(
            icon: Icon(Icons.route_rounded),
            label: "Route",
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
