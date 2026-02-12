import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ContactSupportScreen extends StatefulWidget {
  const ContactSupportScreen({
    super.key,
    required this.senderRole, // "user" or "driver"
  });

  final String senderRole;

  @override
  State<ContactSupportScreen> createState() => _ContactSupportScreenState();
}

class _ContactSupportScreenState extends State<ContactSupportScreen> {
  final _formKey = GlobalKey<FormState>();
  final _subject = TextEditingController();
  final _message = TextEditingController();

  String _priority = "low";
  bool _loading = false;

  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You must be logged in.")),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final d = userDoc.data();

      await FirebaseFirestore.instance.collection('support_tickets').add({
        'senderUid': user.uid,
        'senderRole': widget.senderRole,
        'senderName': (d?['name'] ?? '').toString(),
        'senderEmail': (d?['email'] ?? user.email ?? '').toString(),
        'senderPhone': (d?['phone'] ?? '').toString(),
        'subject': _subject.text.trim(),
        'message': _message.text.trim(),
        'priority': _priority, // low/medium/high
        'status': 'open', // open/in_progress/resolved
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Sent to support.")),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed: $e")),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Contact Support")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _subject,
                decoration: const InputDecoration(
                  labelText: "Subject",
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.isEmpty) return "Subject is required";
                  if (t.length < 3) return "Subject too short";
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _message,
                minLines: 5,
                maxLines: 10,
                decoration: const InputDecoration(
                  labelText: "Message",
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.isEmpty) return "Message is required";
                  if (t.length < 10) return "Message too short";
                  return null;
                },
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _priority,
                decoration: const InputDecoration(
                  labelText: "Priority",
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: "low", child: Text("Low")),
                  DropdownMenuItem(value: "medium", child: Text("Medium")),
                  DropdownMenuItem(value: "high", child: Text("High")),
                ],
                onChanged: (v) => setState(() => _priority = v ?? "low"),
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  child: Text(_loading ? "Sending..." : "Send"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
