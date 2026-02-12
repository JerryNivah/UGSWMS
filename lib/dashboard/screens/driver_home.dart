import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class DriverHome extends StatelessWidget {
  const DriverHome({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("UGSWMS - Driver"),
        actions: [
          IconButton(
            tooltip: "Logout",
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              // RoleRouter will send user back to login
            },
          ),
        ],
      ),
      body: const Center(
        child: Text(
          "Driver Dashboard",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
