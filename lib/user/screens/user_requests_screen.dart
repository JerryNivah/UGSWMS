import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:ugswms/user/screens/request_details.dart';

class UserRequestsScreen extends StatelessWidget {
  const UserRequestsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(body: Center(child: Text("Please login first.")));
    }

    final q = FirebaseFirestore.instance
        .collection('service_requests')
        .where('userUid', isEqualTo: user.uid)
        .orderBy('createdAt', descending: true);

    return Scaffold(
        appBar: AppBar(
          title: const Text("My Requests"),
          actions: [
            IconButton(
              tooltip: "New request",
              icon: const Icon(Icons.add_circle_outline_rounded),
              onPressed: () => _openCreateRequest(context),
            ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: q.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text("Error: ${snap.error}"));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Text("No requests yet. Tap + to create one."),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final doc = docs[i];
              final d = doc.data();
              final serviceType = (d['serviceType'] ?? 'pickup').toString();
              final status = (d['status'] ?? 'pending').toString();
              final address = (d['pickupAddressText'] ?? '').toString();
              final wasteType = (d['wasteType'] ?? '').toString();

              return Card(
                child: ListTile(
                  title: Text("${serviceType.toUpperCase()} - $status"),
                  subtitle: Text(
                    [
                      if (wasteType.isNotEmpty) "Waste: $wasteType",
                      if (address.isNotEmpty) "Addr: $address",
                    ].join("\n"),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => RequestDetailsScreen(requestId: doc.id),
    ),
  );
},

                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openCreateRequest(context),
        icon: const Icon(Icons.add),
        label: const Text("New request"),
      ),
    );
  }
}

void _openCreateRequest(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _CreateRequestSheet(),
  );
}

class _CreateRequestSheet extends StatefulWidget {
  const _CreateRequestSheet();

  @override
  State<_CreateRequestSheet> createState() => _CreateRequestSheetState();
}

  class _CreateRequestSheetState extends State<_CreateRequestSheet> {
    final _address = TextEditingController();
    final _notes = TextEditingController();

    String _serviceType = "pickup"; // pickup/cleanup
    String _wasteType = "general";
    String _quantity = "1 bag";
    String _pickupArea = "";

    static const List<String> _eldoretAreas = [
      "Eldoret CBD",
      "Langas",
      "Huruma",
      "Pioneer",
      "Kapsoya",
      "Elgon View",
      "Annex",
      "West Indies",
      "Sosiani",
      "Kimumu",
      "Chepkoilel",
      "Maili Nne",
      "Racecourse",
      "Kenyatta",
      "Munyaka",
    ];

  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _address.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser!;
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, top: 14, bottom: bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text("Create Request", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),

          DropdownButtonFormField<String>(
            value: _serviceType,
            items: const [
              DropdownMenuItem(value: "pickup", child: Text("Request Pickup")),
              DropdownMenuItem(value: "cleanup", child: Text("Request Cleanup")),
            ],
            onChanged: (v) => setState(() => _serviceType = v ?? "pickup"),
            decoration: const InputDecoration(labelText: "Service type"),
          ),
          const SizedBox(height: 10),

          DropdownButtonFormField<String>(
            value: _wasteType,
            items: const [
              DropdownMenuItem(value: "general", child: Text("General waste")),
              DropdownMenuItem(value: "plastic", child: Text("Plastic")),
              DropdownMenuItem(value: "organic", child: Text("Organic")),
              DropdownMenuItem(value: "glass", child: Text("Glass")),
            ],
            onChanged: (v) => setState(() => _wasteType = v ?? "general"),
            decoration: const InputDecoration(labelText: "Waste type"),
          ),
          const SizedBox(height: 10),

            DropdownButtonFormField<String>(
              value: _quantity,
              items: const [
                DropdownMenuItem(value: "1 bag", child: Text("1 bag")),
                DropdownMenuItem(value: "2 bags", child: Text("2 bags")),
                DropdownMenuItem(value: "3+ bags", child: Text("3+ bags")),
                DropdownMenuItem(value: "1 bin", child: Text("1 bin")),
              ],
              onChanged: (v) => setState(() => _quantity = v ?? "1 bag"),
              decoration: const InputDecoration(labelText: "Quantity"),
            ),
            const SizedBox(height: 10),

            DropdownButtonFormField<String>(
              value: _pickupArea,
              items: [
                const DropdownMenuItem(value: "", child: Text("Not set")),
                ..._eldoretAreas.map(
                  (a) => DropdownMenuItem(value: a, child: Text(a)),
                ),
              ],
              onChanged: (v) => setState(() => _pickupArea = v ?? ""),
              decoration: const InputDecoration(labelText: "Area (optional)"),
            ),
            const SizedBox(height: 10),

            TextField(
              controller: _address,
              decoration: const InputDecoration(
                labelText: "Pickup address / landmark",
                hintText: "e.g. Near Naivas, Gate B",
            ),
          ),
          const SizedBox(height: 10),

          TextField(
            controller: _notes,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: "Notes (optional)",
              hintText: "Anything the driver should know?",
            ),
          ),

          const SizedBox(height: 10),
          if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 10),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: _loading
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check_rounded),
              label: Text(_loading ? "Creating..." : "Create request"),
              onPressed: _loading
                  ? null
                  : () async {
                      if (_address.text.trim().isEmpty) {
                        setState(() => _error = "Please enter an address/landmark.");
                        return;
                      }

                      setState(() {
                        _loading = true;
                        _error = null;
                      });

                      try {
                          await FirebaseFirestore.instance
                              .collection('service_requests')
                              .add({
                            'userUid': user.uid,
                            'userEmail': user.email,
                              'serviceType': _serviceType,
                              'wasteType': _wasteType,
                              'quantity': _quantity,
                              if (_pickupArea.trim().isNotEmpty)
                                'pickupArea': _pickupArea.trim(),
                              'pickupAddressText': _address.text.trim(),
                              'notes': _notes.text.trim(),
                              'status': 'pending',
                              'source': 'user_request',
                            'requestType': 'private',
                            'paymentRequired': true,
                            'createdAt': FieldValue.serverTimestamp(),
                            'updatedAt': FieldValue.serverTimestamp(),
                          });

                        if (mounted) Navigator.pop(context);
                      } catch (e) {
                        setState(() => _error = "Failed: $e");
                      } finally {
                        if (mounted) setState(() => _loading = false);
                      }
                    },
            ),
          ),
        ],
      ),
    );
  }
}

void _showRequestDetails(BuildContext context, String requestId, Map<String, dynamic> d) {
  final serviceType = (d['serviceType'] ?? '').toString();
  final status = (d['status'] ?? '').toString();
  final wasteType = (d['wasteType'] ?? '').toString();
  final quantity = (d['quantity'] ?? '').toString();
  final address = (d['pickupAddressText'] ?? '').toString();
  final notes = (d['notes'] ?? '').toString();

  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: Text("Request - $status"),
      content: Text(
        "Type: $serviceType\nWaste: $wasteType\nQty: $quantity\nAddress: $address\n\nNotes: ${notes.isEmpty ? 'â€”' : notes}",
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close")),
      ],
    ),
  );
}


