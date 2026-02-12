import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ugswms/dashboard/screens/pending_approval.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:ugswms/driver/driver_shell.dart';
import 'package:ugswms/user/screens/user_dashboard.dart';
import 'package:ugswms/user/screens/user_shell.dart';
import 'auth/screens/login_screen.dart';
import 'dashboard/screens/driver_home.dart';
import 'dashboard/screens/admin_dashboard.dart';
import 'auth/screens/mobile_auth_screen.dart';
import 'package:ugswms/driver/driver_shell.dart';

class RoleRouter extends StatefulWidget {
  const RoleRouter({super.key});

  @override
  State<RoleRouter> createState() => _RoleRouterState();
}

class _RoleRouterState extends State<RoleRouter> {
  Future<DocumentSnapshot<Map<String, dynamic>>> _ensureUserDoc(
    User user,
  ) async {
    final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
    if (kDebugMode) {
      debugPrint('User logged in uid=${user.uid}, checking profile doc');
    }
    final snap = await ref.get();
    if (snap.exists) return snap;

    if (kDebugMode) debugPrint('Profile missing: creating...');
    final data = <String, dynamic>{
      'uid': user.uid,
      'email': user.email,
      'name': user.displayName,
      'role': 'user',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    data.removeWhere((k, v) => v == null);
    await ref.set(data, SetOptions(merge: true));
    if (kDebugMode) debugPrint('Profile created OK');
    return ref.get();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnapshot) {
        // 1) Still checking auth
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // 2) Not logged in
        if (!authSnapshot.hasData) {
          //  Web uses your existing admin login UI
          if (kIsWeb) return const LoginScreen();

          //  Mobile uses a dedicated mobile auth UI
          return const MobileAuthScreen();
        }

        final user = authSnapshot.data!;

        // 3) Logged in → fetch role
        return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future: _ensureUserDoc(user),
          builder: (context, roleSnapshot) {
            if (roleSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            // ✅ Show Firestore errors clearly
            if (roleSnapshot.hasError) {
              return Scaffold(
                body: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Firestore error:\n${roleSnapshot.error}\n\nUID: ${user.uid}\nEmail: ${user.email}',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: () => setState(() {}),
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              );
            }

            // ✅ If snapshot missing
            if (!roleSnapshot.hasData) {
              return Scaffold(
                body: Center(
                  child: Text(
                    'No snapshot data.\n\nUID: ${user.uid}\nEmail: ${user.email}',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            // ✅ If document does not exist
            if (!roleSnapshot.data!.exists) {
              return Scaffold(
                body: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'User doc does not exist.\n\nExpected:\nusers/${user.uid}\n\nUID: ${user.uid}\nEmail: ${user.email}',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: () => setState(() {}),
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              );
            }

            final data = roleSnapshot.data!.data();
            final role = (data?['role'] as String?)?.toLowerCase().trim();

            if (role == null || role.isEmpty) {
              return Scaffold(
                body: Center(
                  child: Text(
                    'Role field missing.\n\nDoc: users/${user.uid}\nUID: ${user.uid}\nEmail: ${user.email}',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            switch (role) {
              case 'admin':
                // Admin allowed ONLY on web
                if (!kIsWeb) {
                  return Scaffold(
                    body: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            "Admin is web-only",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            "Please use the web app to access the Admin Dashboard.",
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 14),
                          ElevatedButton(
                            onPressed: () async =>
                                FirebaseAuth.instance.signOut(),
                            child: const Text("Logout"),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return AdminDashboardScreen(
                  isSuperAdmin:
                      user.email?.toLowerCase().trim() == 'admin@ugswms.com',
                  onLogout: () async {
                    await FirebaseAuth.instance.signOut();
                  },
                );

              case 'driver':
              case 'staff':
                if (kIsWeb) {
                  return _Blocked(
                    title: "Driver app is mobile-only",
                    message: "Please use the Android app to login as a driver.",
                  );
                }
                return const DriverShell();
              case 'user':
                if (kIsWeb) {
                  return const _Blocked(
                    title: "User app is mobile-only",
                    message: "Please use the Android app to login as a user.",
                  );
                }
                return const UserShell();

              case 'driver_pending':
                if (kIsWeb) {
                  return _Blocked(
                    title: "Driver application is mobile-only",
                    message: "Please use the Android app to apply as a driver.",
                  );
                }
                return const PendingApprovalScreen();

              default:
                return Scaffold(
                  body: Center(
                    child: Text(
                      'Invalid role: $role\n\nDoc: users/${user.uid}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
            }
          },
        );
      },
    );
  }
}

class _Blocked extends StatelessWidget {
  const _Blocked({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 14),
              ElevatedButton.icon(
                onPressed: () async {
                  await FirebaseAuth.instance.signOut();
                },
                icon: const Icon(Icons.logout),
                label: const Text("Logout"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
