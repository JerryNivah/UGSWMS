import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'report_issue_screen.dart';
import 'my_reports_screen.dart';

class UserDashboard extends StatelessWidget {
  const UserDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("UGSWMS - User"),
        actions: [
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              // RoleRouter will automatically redirect to login
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              "Welcome 👋",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),

            ElevatedButton.icon(
              icon: const Icon(Icons.report_problem_rounded),
              label: const Text("Report an Issue"),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ReportIssueScreen(),
                  ),
                );
              },
            ),

            const SizedBox(height: 12),

           OutlinedButton.icon(
  icon: const Icon(Icons.history_rounded),
  label: const Text("My Reports"),
  onPressed: () {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MyReportsScreen()),
    );
  },
),

          ],
        ),
      ),
    );
  }
}
