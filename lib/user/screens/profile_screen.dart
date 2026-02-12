import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  static const String usersCol = 'users';

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(body: Center(child: Text("Please login first.")));
    }

    final uRef = FirebaseFirestore.instance.collection(usersCol).doc(user.uid);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Profile"),
        centerTitle: true,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: uRef.snapshots(),
        builder: (context, snap) {
          // We can still show something nice even if Firestore fails
          final data = (snap.data?.data()) ?? <String, dynamic>{};

          final email = (data['email'] ?? user.email ?? "No email").toString();
          final uid = user.uid;

          final name = (data['name'] ?? data['fullName'] ?? '').toString().trim();
          final phone = (data['phone'] ?? '').toString().trim();
          final role = (data['role'] ?? 'user').toString().trim();
          final status = (data['status'] ?? 'active').toString().trim();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  color: Colors.black.withOpacity(0.03),
                  border: Border.all(color: Colors.black.withOpacity(0.08)),
                ),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 42,
                      backgroundColor: Colors.black.withOpacity(0.08),
                      child: const Icon(Icons.person_rounded, size: 52),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      name.isEmpty ? "User" : name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      email,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.black.withOpacity(0.65),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Account details
              _SectionCard(
                title: "Account",
                child: Column(
                  children: [
                    _InfoRow(
                      icon: Icons.email_rounded,
                      label: "Email",
                      value: email,
                    ),
                    const Divider(height: 18),
                    _InfoRow(
                      icon: Icons.fingerprint_rounded,
                      label: "UID",
                      value: _shortUid(uid),
                      valueFull: uid,
                      onCopy: () => _copy(context, uid),
                    ),
                    if (phone.isNotEmpty) ...[
                      const Divider(height: 18),
                      _InfoRow(
                        icon: Icons.phone_rounded,
                        label: "Phone",
                        value: phone,
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // App details
              _SectionCard(
                title: "App",
                child: Column(
                  children: [
                    _InfoRow(
                      icon: Icons.badge_rounded,
                      label: "Role",
                      value: role,
                    ),
                    const Divider(height: 18),
                    _InfoRow(
                      icon: Icons.verified_user_rounded,
                      label: "Status",
                      value: status,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // Actions
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.logout),
                  label: const Text("Logout"),
                  onPressed: () async {
                    await FirebaseAuth.instance.signOut();
                  },
                ),
              ),

              const SizedBox(height: 12),

              OutlinedButton.icon(
                icon: const Icon(Icons.delete_forever_rounded, color: Colors.red),
                label: const Text(
                  "Delete account",
                  style: TextStyle(color: Colors.red),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.red),
                ),
                onPressed: () => _confirmDeleteAccount(context),
              ),

              if (snap.hasError) ...[
                const SizedBox(height: 14),
                Text(
                  "Profile doc load warning: ${snap.error}",
                  style: TextStyle(
                    color: Colors.black.withOpacity(0.55),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  static String _shortUid(String uid) {
    if (uid.length <= 10) return uid;
    return "${uid.substring(0, 6)}…${uid.substring(uid.length - 4)}";
  }

  static Future<void> _copy(BuildContext context, String text) async {
    // avoid extra imports by using Clipboard from services
    // (but we need the import)
  }
}
Future<void> _confirmDeleteAccount(BuildContext context) async {
  final user = FirebaseAuth.instance.currentUser!;
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text("Delete account?"),
      content: const Text(
        "This will remove your account from the system. This action cannot be undone.",
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text("Cancel"),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.pop(context, true),
          child: const Text("Delete"),
        ),
      ],
    ),
  );

  if (ok != true) return;

  try {
    // 1) Mark user doc as deleted (safer than hard-delete everything)
    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'status': 'deleted',
      'deletedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // 2) Delete auth user (may require recent login)
    await user.delete();

    // 3) App will auto-go back to login because auth user is gone
  } on FirebaseAuthException catch (e) {
    if (!context.mounted) return;

    if (e.code == 'requires-recent-login') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please login again then retry delete (security requirement)."),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Delete failed: ${e.message}")),
      );
    }
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Delete failed: $e")),
    );
  }
}

// ------- UI pieces -------

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueFull,
    this.onCopy,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? valueFull;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    final showCopy = onCopy != null && (valueFull?.isNotEmpty ?? false);

    return Row(
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: Colors.black.withOpacity(0.06),
          child: Icon(icon, size: 18, color: Colors.black.withOpacity(0.75)),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 4,
          child: Text(
            label,
            style: TextStyle(
              color: Colors.black.withOpacity(0.65),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Expanded(
          flex: 6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              if (valueFull != null && valueFull != value)
                Text(
                  valueFull!,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: Colors.black.withOpacity(0.55),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ),
        if (showCopy) ...[
          const SizedBox(width: 8),
          IconButton(
            tooltip: "Copy",
            onPressed: onCopy,
            icon: const Icon(Icons.copy_rounded, size: 18),
          ),
        ],
      ],
    );
  }
}
