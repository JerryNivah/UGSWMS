import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class DriverProfileScreen extends StatelessWidget {
  const DriverProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text("Please login.")));
    }

    final docRef = FirebaseFirestore.instance.collection('users').doc(user.uid);

    return Scaffold(
      appBar: AppBar(title: const Text("Profile")),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: docRef.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Text("Failed to load profile: ${snap.error}"),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snap.data!.data() ?? {};
          final name = (data['name'] ?? data['fullName'] ?? 'Driver').toString();
          final email = (data['email'] ?? user.email ?? '').toString();
          final phone = (data['phone'] ?? '').toString();
          final status = (data['status'] ?? '').toString();
          final cls = (data['vehicleClass'] ?? '').toString();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ListTile(title: const Text("Name"), subtitle: Text(name)),
              ListTile(title: const Text("Email"), subtitle: Text(email)),
              ListTile(title: const Text("Phone"), subtitle: Text(phone.isEmpty ? "—" : phone)),
              ListTile(title: const Text("Status"), subtitle: Text(status.isEmpty ? "—" : status)),
              ListTile(title: const Text("Vehicle class"), subtitle: Text(cls.isEmpty ? "—" : cls)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () async {
                  await FirebaseAuth.instance.signOut();
                  if (context.mounted) Navigator.popUntil(context, (r) => r.isFirst);
                },
                icon: const Icon(Icons.logout),
                label: const Text("Logout"),
              ),
            ],
          );
        },
      ),
    );
  }
}
