import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ugswms/core/utils/validators.dart';

class ApplyDriverScreen extends StatefulWidget {
  const ApplyDriverScreen({super.key});

  @override
  State<ApplyDriverScreen> createState() => _ApplyDriverScreenState();
}

class _ApplyDriverScreenState extends State<ApplyDriverScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _licenseNo = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _loading = false;
  String? _error;

  bool _obscurePass = true;
  bool _obscureConfirm = true;
  bool _formValid = false;

  void _updateFormValidity() {
    final valid = _formKey.currentState?.validate() ?? false;
    if (valid != _formValid) {
      setState(() => _formValid = valid);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    _name.dispose();
    _phone.dispose();
    _licenseNo.dispose();
    super.dispose();
  }

  String _friendlyAuthError(Object e) {
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'email-already-in-use':
          return 'This email is already registered.';
        case 'weak-password':
          return 'Password must be at least 6 characters.';
        case 'invalid-email':
          return 'Invalid email address.';
        case 'too-many-requests':
          return 'Too many attempts. Try again later.';
        default:
          return e.message ?? 'Application failed. Please try again.';
      }
    }
    return 'Application failed. $e';
  }

  Future<void> _apply() async {
    setState(() {
      _error = null;
    });

    final email = _email.text.trim();
    final password = _password.text;
    final confirm = _confirmPassword.text;
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    final licenseNo = _licenseNo.text.trim();

    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) return;

    String phoneE164;
    try {
      phoneE164 = normalizeKenyanPhoneToE164(phone);
    } catch (_) {
      setState(() => _error = 'Enter a valid Kenyan phone number.');
      return;
    }

    setState(() => _loading = true);

    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final uid = cred.user!.uid;

      // ✅ Store user profile in users/
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'uid': uid,
        'email': email,
        'name': name,
        'phone': phoneE164,
        'role': 'driver_pending', // ✅ IMPORTANT: pending role for RoleRouter
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

      // ✅ Store application in driver_applications/
      await FirebaseFirestore.instance
          .collection('driver_applications')
          .doc(uid)
          .set({
        'uid': uid,
        'email': email,
        'name': name,
        'phone': phoneE164,
        'licenseNo': licenseNo,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Driver application submitted ✅')),
      );

      Navigator.pop(context);
    } catch (e) {
      setState(() => _error = _friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Apply as Driver')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          onChanged: _updateFormValidity,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            children: [
            if (_error != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.withOpacity(0.25)),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 12),
            ],

            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Full Name',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Full name is required.' : null,
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone',
                border: OutlineInputBorder(),
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\+?\d*$')),
              ],
              validator: (v) => validateKenyanPhone(v ?? ''),
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _licenseNo,
              decoration: const InputDecoration(
                labelText: 'License Number',
                border: OutlineInputBorder(),
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
              ],
              validator: (v) => validateKenyanDrivingLicense(v ?? ''),
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                final value = (v ?? '').trim();
                if (value.isEmpty) return 'Email is required.';
                if (!value.contains('@')) return 'Enter a valid email.';
                return null;
              },
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _password,
              obscureText: _obscurePass,
              decoration: InputDecoration(
                labelText: 'Password',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePass ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePass = !_obscurePass),
                ),
              ),
              inputFormatters: [
                FilteringTextInputFormatter.deny(RegExp(r'\s')),
              ],
              validator: (v) => validateStrongPassword(v ?? ''),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'At least 8 chars, uppercase, lowercase, number, special, no spaces.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.grey.shade600),
              ),
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _confirmPassword,
              obscureText: _obscureConfirm,
              decoration: InputDecoration(
                labelText: 'Confirm Password',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureConfirm ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () =>
                      setState(() => _obscureConfirm = !_obscureConfirm),
                ),
              ),
              inputFormatters: [
                FilteringTextInputFormatter.deny(RegExp(r'\s')),
              ],
              validator: (v) {
                if ((v ?? '').isEmpty) {
                  return 'Please confirm your password.';
                }
                if (v != _password.text) return 'Passwords do not match.';
                return null;
              },
            ),
            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: (_loading || !_formValid) ? null : _apply,
                child: _loading
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(
                        'Submit Application',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}
