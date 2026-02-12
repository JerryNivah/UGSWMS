import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:ugswms/core/constants/services/user_service.dart';
import 'package:ugswms/core/utils/validators.dart';

class RegisterCustomerScreen extends StatefulWidget {
  const RegisterCustomerScreen({super.key});

  @override
  State<RegisterCustomerScreen> createState() => _RegisterCustomerScreenState();
}

class _RegisterCustomerScreenState extends State<RegisterCustomerScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _loading = false;
  bool _obscure = true;
  bool _obscure2 = true;
  String? _error;
  bool _formValid = false;

  void _updateFormValidity() {
    final valid = _formKey.currentState?.validate() ?? false;
    if (valid != _formValid) {
      setState(() => _formValid = valid);
    }
  }

  Future<void> _register() async {
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    final email = _email.text.trim().toLowerCase();
    final pass = _password.text.trim();
    final confirm = _confirmPassword.text.trim();

    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) return;

    String phoneE164;
    try {
      phoneE164 = normalizeKenyanPhoneToE164(phone);
    } catch (_) {
      setState(() => _error = 'Enter a valid Kenyan phone number.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (kDebugMode) debugPrint('Register start');
      // 1) Create auth account
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: pass,
      );

      final uid = cred.user!.uid;
      if (kDebugMode) debugPrint('Auth created uid=$uid');

      // 2) Create Firestore profile (doc id = uid)
      if (kDebugMode) debugPrint('Writing users doc...');
      await UserService().upsertUserProfile(
        uid: uid,
        email: email,
        role: 'user',
        name: name,
        phone: phoneE164,
      );
      if (kDebugMode) debugPrint('Users doc write OK');

      if (!mounted) return;
      Navigator.pop(context); // go back to login
    } on FirebaseAuthException catch (e) {
      if (kDebugMode) {
        debugPrint('Auth error: ${e.code} ${e.message}');
      }
      String msg;
      switch (e.code) {
        case 'email-already-in-use':
          msg = 'This email is already registered.';
          break;
        case 'weak-password':
          msg = 'Password is too weak.';
          break;
        case 'invalid-email':
          msg = 'Invalid email address.';
          break;
        default:
          msg = e.message ?? 'Registration failed. Please try again.';
      }
      setState(() => _error = msg);
    } on FirebaseException catch (e) {
      if (kDebugMode) {
        debugPrint('Firestore error: ${e.code} ${e.message}');
      }
      setState(
        () => _error = e.message ??
            'Profile save failed. Check permissions or network.',
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Unknown register error: $e');
        debugPrint('$st');
      }
      setState(() => _error = 'Something went wrong.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(title: const Text('Register Customer')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bottomInset = MediaQuery.of(context).viewInsets.bottom;
            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(16, 12, 16, 24 + bottomInset),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Form(
                    key: _formKey,
                    onChanged: _updateFormValidity,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _name,
                          decoration: const InputDecoration(labelText: 'Full Name'),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Full name is required.'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _phone,
                          decoration:
                              const InputDecoration(labelText: 'Phone Number'),
                          keyboardType: TextInputType.phone,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'^\+?\d*$')),
                          ],
                          validator: (v) => validateKenyanPhone(v ?? ''),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _email,
                          decoration: const InputDecoration(labelText: 'Email'),
                          keyboardType: TextInputType.emailAddress,
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
                          obscureText: _obscure,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscure ? Icons.visibility_off : Icons.visibility,
                              ),
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
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
                          obscureText: _obscure2,
                          decoration: InputDecoration(
                            labelText: 'Confirm Password',
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscure2 ? Icons.visibility_off : Icons.visibility,
                              ),
                              onPressed: () =>
                                  setState(() => _obscure2 = !_obscure2),
                            ),
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.deny(RegExp(r'\s')),
                          ],
                          validator: (v) {
                            if ((v ?? '').trim().isEmpty) {
                              return 'Please confirm your password.';
                            }
                            if (v != _password.text) return 'Passwords do not match.';
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        if (_error != null)
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(10),
                              border:
                                  Border.all(color: Colors.red.withOpacity(0.25)),
                            ),
                            child: Text(
                              _error!,
                              softWrap: true,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                        if (_error != null) const SizedBox(height: 10),
                        ElevatedButton(
                          onPressed: (_loading || !_formValid) ? null : _register,
                          child: _loading
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Create Account'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
