import 'package:flutter/material.dart';
import 'package:ugswms/shared/bin_simulation_panel.dart';

class BinSimulationScreen extends StatelessWidget {
  const BinSimulationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Bin Simulation")),
      body: const BinSimulationPanel(),
    );
  }
}
