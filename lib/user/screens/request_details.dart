import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class RequestDetailsScreen extends StatelessWidget {
  const RequestDetailsScreen({super.key, required this.requestId});

  final String requestId;

  static const Map<String, int> _unitPrices = {
    'organic': 200,
    'glass': 300,
    'plastic': 250,
  };

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(body: Center(child: Text("Please login first.")));
    }

    final ref =
        FirebaseFirestore.instance.collection('service_requests').doc(requestId);

    return Scaffold(
      appBar: AppBar(title: const Text("Request Details")),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: ref.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text("Error: ${snap.error}"));
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snap.data!.exists) {
            return const Center(child: Text("Request not found."));
          }

          final d = snap.data!.data()!;
          final status = (d['status'] ?? 'pending').toString().toLowerCase();
          final serviceType = (d['serviceType'] ?? '').toString();
            final wasteType = (d['wasteType'] ?? '').toString();
            final quantity = (d['quantity'] ?? '').toString();
            final address = (d['pickupAddressText'] ?? '').toString();
          final notes = (d['notes'] ?? '').toString();
          final source = (d['source'] ?? 'unknown').toString();
          final requestType = (d['requestType'] ?? 'unknown').toString();
          final paymentRequired = (d['paymentRequired'] ?? false) == true;
          final needsPayment = requestType == 'private' && paymentRequired;
          final unitPrice = _unitPriceForWaste(wasteType);
          final qtyCount = _quantityCount(quantity);
          final total = unitPrice * qtyCount;
          final defaultRateApplied = _isDefaultRate(wasteType);

          final assignmentId = (d['assignmentId'] ?? '').toString().trim();
          final assignedDriverUid =
              (d['assignedDriverUid'] ?? '').toString().trim();

          final isPending = status == 'pending';

          final theme = Theme.of(context);

          Widget buildCancelSection() {
            if (isPending) {
              return OutlinedButton.icon(
                icon: const Icon(Icons.cancel_rounded, color: Colors.red),
                label: const Text(
                  "Cancel Request",
                  style: TextStyle(color: Colors.red),
                ),
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text("Cancel request?"),
                      content:
                          const Text("This will mark your request as cancelled."),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text("No"),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red),
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text("Yes, cancel"),
                        ),
                      ],
                    ),
                  );

                  if (ok != true) return;

                  //  Batch: cancel request + cancel assignment if it exists
                  final batch = FirebaseFirestore.instance.batch();
                  final now = FieldValue.serverTimestamp();

                  batch.update(ref, {
                    'status': 'cancelled',
                    'assignmentStatus':
                        assignmentId.isNotEmpty ? 'cancelled' : null,
                    'cancelledAt': now,
                    'updatedAt': now,

                    // optional cleanup to avoid "ghost assigned"
                    if (assignedDriverUid.isNotEmpty)
                      'assignedDriverUid': FieldValue.delete(),
                    if (assignmentId.isNotEmpty)
                      'assignmentId': FieldValue.delete(),
                    'assignedAt': FieldValue.delete(),
                  });

                  if (assignmentId.isNotEmpty) {
                    final aRef = FirebaseFirestore.instance
                        .collection('assignments')
                        .doc(assignmentId);

                    batch.update(aRef, {
                      'status': 'cancelled',
                      'updatedAt': now,
                    });
                  }

                  await batch.commit();

                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Request cancelled.")),
                    );
                  }
                },
              );
            }

            return Text(
              "This request cannot be cancelled because it is '$status'.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black.withOpacity(0.65)),
            );
          }

          Widget buildDetailsContent(Widget paymentContent) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _kv("Status", status),
                const SizedBox(height: 8),
                _kv("Service Type", serviceType),
                const SizedBox(height: 8),
                _kv("Waste Type", wasteType),
                const SizedBox(height: 8),
                _kv("Quantity", quantity),
                const SizedBox(height: 8),
                _kv("Address", address),
                const SizedBox(height: 8),
                _kv("Notes", notes.isEmpty ? "—" : notes),
                const SizedBox(height: 8),
                _kv("Source", source),
                const SizedBox(height: 8),
                _kv("Request Type", requestType),
                const SizedBox(height: 8),
                _kv("Payment Required", paymentRequired ? "Yes" : "No"),
                const SizedBox(height: 8),
                paymentContent,
                const SizedBox(height: 16),
                buildCancelSection(),
                const SizedBox(height: 120),
              ],
            );
          }

          if (!needsPayment) {
            return SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      child: buildDetailsContent(
                        _kv("Payment", "Not required"),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('payments')
                .where('serviceRequestId', isEqualTo: requestId)
                .limit(1)
                .snapshots(),
            builder: (context, paySnap) {
              String statusText = "Not started";
              bool hasPayment = false;

              if (paySnap.hasData &&
                  paySnap.data != null &&
                  paySnap.data!.docs.isNotEmpty) {
                final p = paySnap.data!.docs.first.data();
                statusText = (p['status'] ?? 'draft').toString();
                hasPayment = true;
              }

              final canCreatePayment = !hasPayment;

              final paymentContent = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _kv("Unit price", "KES $unitPrice per bag"),
                  const SizedBox(height: 8),
                  _kv("Quantity", "$qtyCount bag(s)"),
                  const SizedBox(height: 8),
                  _kv("Total", "KES $total"),
                  if (defaultRateApplied) ...[
                    const SizedBox(height: 6),
                    Text(
                      "Default rate applied",
                      style: TextStyle(
                        color: Colors.black.withOpacity(0.6),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  _kv("Payment status", statusText),
                ],
              );

              return SafeArea(
                child: Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                        child: buildDetailsContent(paymentContent),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      decoration: BoxDecoration(
                        color: theme.scaffoldBackgroundColor,
                        boxShadow: const [
                          BoxShadow(
                            blurRadius: 12,
                            offset: Offset(0, -2),
                            color: Colors.black12,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (statusText.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                "Payment status: $statusText",
                                style: TextStyle(
                                  color: Colors.black.withOpacity(0.6),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: canCreatePayment
                                  ? () async {
                                      final exists = await FirebaseFirestore
                                          .instance
                                          .collection('payments')
                                          .where('serviceRequestId',
                                              isEqualTo: requestId)
                                          .limit(1)
                                          .get();
                                      if (exists.docs.isNotEmpty) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                "Payment already created",
                                              ),
                                            ),
                                          );
                                        }
                                        return;
                                      }

                                      await _createPaymentForRequest(
                                        requestId: requestId,
                                        userUid: user.uid,
                                        amount: total,
                                      );
                                    }
                                  : null,
                              icon: const Icon(Icons.add),
                              label:
                                  const Text("Create Payment (Draft)"),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: null,
                              icon: const Icon(Icons.payment),
                              label: const Text(
                                  "Pay with M-Pesa (Coming soon)"),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(k, style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
          Expanded(
            flex: 5,
            child: Text(
              v,
              softWrap: true,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _createPaymentForRequest({
    required String requestId,
    required String userUid,
    required num amount,
  }) async {
    final ref = FirebaseFirestore.instance.collection('payments').doc();
    final now = FieldValue.serverTimestamp();

    await ref.set({
      'serviceRequestId': requestId,
      'userUid': userUid,
      'amount': amount,
      'currency': 'KES',
      'provider': 'mpesa_sandbox',
      'status': 'draft',
      'createdAt': now,
      'updatedAt': now,
    });
  }

  int _unitPriceForWaste(String wasteType) {
    final key = wasteType.toLowerCase().trim();
    if (_unitPrices.containsKey(key)) return _unitPrices[key]!;
    if (key.isEmpty || key == 'general') return 150;
    return 150;
  }

  bool _isDefaultRate(String wasteType) {
    final key = wasteType.toLowerCase().trim();
    return key.isEmpty || key == 'general' || !_unitPrices.containsKey(key);
  }

  int _quantityCount(String quantity) {
    final q = quantity.toLowerCase();
    final digits = RegExp(r'(\d+)').firstMatch(q);
    if (digits != null) {
      final v = int.tryParse(digits.group(1) ?? '');
      if (v != null && v > 0) return v;
    }
    if (q.contains('3+')) return 3;
    if (q.contains('bin')) return 1;
    if (q.contains('bag')) return 1;
    return 1;
  }
}
