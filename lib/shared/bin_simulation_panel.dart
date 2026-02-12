import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:ugswms/dashboard/services/bin_simulator.dart';

class BinSimulationPanel extends StatefulWidget {
  const BinSimulationPanel({
    super.key,
    this.maxListHeight,
    this.compact = false,
  });

  final double? maxListHeight;
  final bool compact;

  @override
  State<BinSimulationPanel> createState() => _BinSimulationPanelState();
}

class _BinSimulationPanelState extends State<BinSimulationPanel> {
  bool _autoSim = BinSimulator.instance.isRunning;
  int _intervalSeconds = 15;

  String _statusFromLevel(int level) {
    if (level >= 85) return 'critical';
    if (level >= 60) return 'warning';
    return 'normal';
  }

  bool _isLocked(Map<String, dynamic> data) {
    final now = DateTime.now();
    final lockedUntil = data['lockedUntil'];
    if (lockedUntil is Timestamp) {
      if (now.isBefore(lockedUntil.toDate())) return true;
    }
    final lastCollectedAt = data['lastCollectedAt'];
    if (lastCollectedAt is Timestamp) {
      final diff = now.difference(lastCollectedAt.toDate());
      if (diff.inSeconds < 60) return true;
    }
    return false;
  }

  Future<void> _setLevel(DocumentReference ref, int level) async {
    final clamped = level.clamp(0, 100);
    await ref.update({
      'level': clamped,
      'status': _statusFromLevel(clamped),
      'lastUpdatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _randomizeSome(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) async {
    if (docs.isEmpty) return;

    final rnd = Random();

    // Change 3-6 bins per tick (skip locked/recently collected)
    final eligible = docs.where((d) => !_isLocked(d.data())).toList();
    if (eligible.isEmpty) return;
    final count = min(eligible.length, 3 + rnd.nextInt(4)); // 3..6
    eligible.shuffle(rnd);
    final chosen = eligible.take(count).toList();

    final batch = FirebaseFirestore.instance.batch();
    final now = FieldValue.serverTimestamp();

    for (final d in chosen) {
      final current = (d.data()['level'] as num?)?.toInt() ?? 0;

      // Small drift instead of pure random (more realistic)
      final delta = [-15, -10, -5, 5, 10, 15][rnd.nextInt(6)];
      final next = (current + delta).clamp(0, 100);

      batch.update(d.reference, {
        'level': next,
        'status': _statusFromLevel(next),
        'lastUpdatedAt': now,
      });
    }
    await batch.commit();
  }

  void _toggleAuto(bool value) {
    setState(() => _autoSim = value);
    if (value) {
      BinSimulator.instance.start(intervalSeconds: _intervalSeconds);
    } else {
      BinSimulator.instance.stop();
    }
  }

  void _setInterval(int? value) {
    if (value == null) return;
    setState(() => _intervalSeconds = value);
    if (_autoSim) {
      BinSimulator.instance.stop();
      BinSimulator.instance.start(intervalSeconds: _intervalSeconds);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = FirebaseFirestore.instance.collection('bins').orderBy('name');
    final padding = widget.compact
        ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
        : const EdgeInsets.all(12);
    final listDense = widget.compact;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Padding(
            padding: padding,
            child: Text("Error: ${snap.error}"),
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snap.data!.docs;

        final listView = ListView.separated(
          itemCount: docs.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          shrinkWrap: widget.maxListHeight != null,
          physics: widget.maxListHeight != null
              ? const ClampingScrollPhysics()
              : const AlwaysScrollableScrollPhysics(),
          itemBuilder: (context, i) {
            final d = docs[i];
            final data = d.data();
            final name = (data['name'] ?? 'Bin').toString();
            final level = (data['level'] as num?)?.toInt() ?? 0;
            final status = (data['status'] ?? 'normal').toString();

            return ListTile(
              dense: listDense,
              title: Text(name),
              subtitle: Text("Level: $level% - $status"),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: "-10",
                    onPressed: () => _setLevel(d.reference, level - 10),
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  IconButton(
                    tooltip: "+10",
                    onPressed: () => _setLevel(d.reference, level + 10),
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
            );
          },
        );

        return Column(
          children: [
            Padding(
              padding: padding,
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text("Auto-simulate (timer)"),
                    subtitle: Text(
                      "Updates a few bins every $_intervalSeconds seconds",
                    ),
                    value: _autoSim,
                    onChanged: _toggleAuto,
                  ),
                  Row(
                    children: [
                      const Text("Interval: "),
                      const SizedBox(width: 8),
                      DropdownButton<int>(
                        value: _intervalSeconds,
                        items: const [10, 15, 20, 30]
                            .map((s) => DropdownMenuItem(value: s, child: Text("$s sec")))
                            .toList(),
                        onChanged: _setInterval,
                      ),
                      const Spacer(),
                      ElevatedButton.icon(
                        onPressed: () => _randomizeSome(docs),
                        icon: const Icon(Icons.casino),
                        label: const Text("Randomize some"),
                      )
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            if (widget.maxListHeight != null)
              SizedBox(height: widget.maxListHeight, child: listView)
            else
              Expanded(child: listView),
          ],
        );
      },
    );
  }
}
