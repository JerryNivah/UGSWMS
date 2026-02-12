import 'package:flutter/material.dart';
import 'package:ugswms/shared/notifications_screen.dart';

class UserHome extends StatelessWidget {
  const UserHome({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Home"),
        actions: [
          IconButton(
            tooltip: "Notifications",
            icon: const Icon(Icons.notifications_rounded),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const NotificationsScreen(
                    recipientRole: 'resident',
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: const Center(child: Text('User Home')),
    );
  }
}
