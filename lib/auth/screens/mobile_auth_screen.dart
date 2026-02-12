import 'package:flutter/material.dart';
import 'package:ugswms/auth/screens/apply_driver_screen.dart';
import 'login_screen.dart';
import 'register_customer_screen.dart';


class MobileAuthScreen extends StatefulWidget {
  const MobileAuthScreen({super.key});

  @override
  State<MobileAuthScreen> createState() => _MobileAuthScreenState();
}

class _MobileAuthScreenState extends State<MobileAuthScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("UGSWMS")),
      body: Column(
        children: [
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: _TabBtn(
                    active: _tab == 0,
                    label: "Login",
                    onTap: () => setState(() => _tab = 0),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _TabBtn(
                    active: _tab == 1,
                    label: "Register User",
                    onTap: () => setState(() => _tab = 1),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _TabBtn(
                    active: _tab == 2,
                    label: "Apply Driver",
                    onTap: () => setState(() => _tab = 2),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: [
                const LoginScreen(),
                const RegisterCustomerScreen(),
                const ApplyDriverScreen(),
              ],
              
            ),
          ),
        ],
      ),
    );
  }
}

class _TabBtn extends StatelessWidget {
  const _TabBtn({
    required this.active,
    required this.label,
    required this.onTap,
  });

  final bool active;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: active ? Theme.of(context).colorScheme.primary : Colors.black12,
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: active ? Colors.white : Colors.black87,
              fontWeight: FontWeight.w800,
              fontSize: 12.5,
            ),
          ),
        ),
      ),
    );
  }
}
