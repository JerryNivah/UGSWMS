import 'dart:ui';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ugswms/dashboard/services/reports_service.dart';
import 'package:ugswms/dashboard/services/reports_exporter.dart';

// Keep the Reports page styling aligned with the Admin dashboard light theme.
const Color _surface = Color(0xCCFFFFFF); // white glass
const Color _border = Color(0x1F0F172A); // subtle border
const Color _text = Color(0xFF0F172A); // slate-900
const Color _textSoft = Color(0xFF475569); // slate-600

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key, required this.accent});
  final Color accent;

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  final ReportsService _service = ReportsService();

  _RangePreset _preset = _RangePreset.days30;
  ReportsSnapshot? _snapshot;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  DateTimeRange? _rangeForPreset(_RangePreset p) {
    final now = DateTime.now();
    switch (p) {
      case _RangePreset.days7:
        return DateTimeRange(start: now.subtract(const Duration(days: 7)), end: now);
      case _RangePreset.days30:
        return DateTimeRange(start: now.subtract(const Duration(days: 30)), end: now);
      case _RangePreset.days90:
        return DateTimeRange(start: now.subtract(const Duration(days: 90)), end: now);
      case _RangePreset.all:
        return null;
    }
  }

  String _rangeLabel() {
    switch (_preset) {
      case _RangePreset.days7:
        return "Last 7 days";
      case _RangePreset.days30:
        return "Last 30 days";
      case _RangePreset.days90:
        return "Last 90 days";
      case _RangePreset.all:
        return "All time";
    }
  }

  String _fileLabel() {
    return _rangeLabel()
        .toLowerCase()
        .replaceAll(' ', '_')
        .replaceAll('/', '_');
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _exportCsv() async {
    if (!kIsWeb) {
      _showSnack("Export is available on web only.");
      return;
    }
    final snap = _snapshot;
    if (snap == null) {
      _showSnack("No data to export yet.");
      return;
    }
    final csv = _buildCsv(snap);
    final filename = "reports_${_fileLabel()}.csv";
    await downloadTextFile(filename: filename, content: csv, mime: "text/csv");
    _showSnack("CSV downloaded.");
  }

  Future<void> _exportRtf() async {
    if (!kIsWeb) {
      _showSnack("Export is available on web only.");
      return;
    }
    final snap = _snapshot;
    if (snap == null) {
      _showSnack("No data to export yet.");
      return;
    }
    final rtf = _buildRtf(snap);
    final filename = "reports_${_fileLabel()}.rtf";
    await downloadTextFile(
      filename: filename,
      content: rtf,
      mime: "application/rtf",
    );
    _showSnack("RTF downloaded.");
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snap = await _service.fetch(range: _rangeForPreset(_preset));
      if (!mounted) return;
      setState(() {
        _snapshot = snap;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    final isWide = MediaQuery.of(context).size.width >= 1000;

    return DefaultTabController(
      length: 5,
      child: Column(
        children: [
          _headerRow(accent, isWide),
          const SizedBox(height: 12),
          TabBar(
            labelColor: _text,
            indicatorColor: accent,
            unselectedLabelColor: _textSoft,
            tabs: const [
              Tab(text: "Overview"),
              Tab(text: "Users"),
              Tab(text: "Requests"),
              Tab(text: "Routes"),
              Tab(text: "Drivers"),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _buildBody(),
          ),
        ],
      ),
    );
  }

  Widget _headerRow(Color accent, bool isWide) {
    final controls = Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _rangeChip("7D", _RangePreset.days7),
        _rangeChip("30D", _RangePreset.days30),
        _rangeChip("90D", _RangePreset.days90),
        _rangeChip("ALL", _RangePreset.all),
        IconButton(
          tooltip: "Refresh",
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded),
          color: _text,
        ),
        Tooltip(
          message: "Download Word (RTF)",
          child: OutlinedButton.icon(
            onPressed: _exportRtf,
            icon: const Icon(Icons.description_outlined),
            label: const Text("Word"),
          ),
        ),
        Tooltip(
          message: "Download Excel (CSV)",
          child: OutlinedButton.icon(
            onPressed: _exportCsv,
            icon: const Icon(Icons.table_chart_rounded),
            label: const Text("Excel"),
          ),
        ),
      ],
    );

    if (isWide) {
      return Row(
        children: [
          Text(
            "Reports",
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: _text,
            ),
          ),
          const Spacer(),
          controls,
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Reports",
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: _text,
          ),
        ),
        const SizedBox(height: 10),
        controls,
      ],
    );
  }

  Widget _rangeChip(String label, _RangePreset value) {
    final selected = _preset == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        setState(() => _preset = value);
        _load();
      },
      selectedColor: widget.accent.withOpacity(0.15),
      labelStyle: TextStyle(
        color: selected ? _text : _textSoft,
        fontWeight: FontWeight.w700,
      ),
      shape: StadiumBorder(
        side: BorderSide(color: _border.withOpacity(0.8)),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return _loadingState();
    if (_error != null) return _errorState();
    final snap = _snapshot;
    if (snap == null) return _emptyState();

    return TabBarView(
      children: [
        _overviewTab(snap),
        _usersTab(snap),
        _requestsTab(snap),
        _routesTab(snap),
        _driversTab(snap),
      ],
    );
  }

  Widget _loadingState() {
    return ListView(
      padding: const EdgeInsets.all(4),
      children: [
        _skeletonGrid(),
        const SizedBox(height: 12),
        _skeletonCard(height: 220),
        const SizedBox(height: 12),
        _skeletonCard(height: 220),
      ],
    );
  }

  Widget _errorState() {
    return Center(
      child: _ReportsGlassCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.redAccent),
            const SizedBox(height: 8),
            const Text("Failed to load reports."),
            const SizedBox(height: 6),
            Text(
              _error ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(color: _textSoft),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text("Retry"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: _ReportsGlassCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inbox_rounded, color: Colors.black45),
            const SizedBox(height: 8),
            Text(
              "No data for ${_rangeLabel()}",
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }

  Widget _overviewTab(ReportsSnapshot snap) {
    if (!snap.hasRangeData) return _emptyState();
    return SingleChildScrollView(
      child: Column(
        children: [
          _metricGrid(snap),
          const SizedBox(height: 12),
          _ReportsGlassCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "Range: ${_rangeLabel()}",
                    style: TextStyle(color: _textSoft),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _usersTab(ReportsSnapshot snap) {
    if (!snap.hasRangeData) return _emptyState();
    return SingleChildScrollView(
      child: _ReportsGlassCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle("Users"),
            const SizedBox(height: 8),
            _kvRow("Total Users", snap.totalUsers.toString()),
            _kvRow("New Users (${_rangeLabel()})", snap.newUsers.toString()),
          ],
        ),
      ),
    );
  }

  Widget _requestsTab(ReportsSnapshot snap) {
    if (!snap.hasRangeData) return _emptyState();
    return SingleChildScrollView(
      child: Column(
        children: [
          _ReportsGlassCard(
            padding: const EdgeInsets.all(16),
            child: _breakdownList("Requests by Status", snap.requestStatusCounts),
          ),
          const SizedBox(height: 12),
          _ReportsGlassCard(
            padding: const EdgeInsets.all(16),
            child: _breakdownList("Requests by Type", snap.requestTypeCounts),
          ),
        ],
      ),
    );
  }

  Widget _routesTab(ReportsSnapshot snap) {
    if (!snap.hasRangeData) return _emptyState();
    return SingleChildScrollView(
      child: _ReportsGlassCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle("Routes"),
            const SizedBox(height: 8),
            _kvRow("Created (${_rangeLabel()})", snap.routesCreated.toString()),
            _kvRow("Completed (${_rangeLabel()})", snap.routesCompleted.toString()),
            _kvRow("Avg stops per route", snap.avgStopsPerRoute.toStringAsFixed(1)),
          ],
        ),
      ),
    );
  }

  Widget _driversTab(ReportsSnapshot snap) {
    if (!snap.hasRangeData) return _emptyState();
    final topUids = snap.driverStats.take(5).map((d) => d.uid).toSet();
    return SingleChildScrollView(
      child: _ReportsGlassCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle("Drivers (Top 5 highlighted)"),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text("Driver")),
                  DataColumn(label: Text("Assigned")),
                  DataColumn(label: Text("Completed")),
                  DataColumn(label: Text("Completion %")),
                ],
                rows: snap.driverStats.map((d) {
                  final highlight = topUids.contains(d.uid);
                  return DataRow(
                    color: highlight
                        ? MaterialStateProperty.all(
                            widget.accent.withOpacity(0.08),
                          )
                        : null,
                    cells: [
                      DataCell(Text(d.name)),
                      DataCell(Text(d.assigned.toString())),
                      DataCell(Text(d.completed.toString())),
                      DataCell(Text(d.completionRate.toStringAsFixed(0))),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricGrid(ReportsSnapshot snap) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _MetricCard(
          title: "Total Users",
          value: snap.totalUsers.toString(),
          subtitle: "All time",
          icon: Icons.people_alt_rounded,
          accent: widget.accent,
        ),
        _MetricCard(
          title: "New Users",
          value: snap.newUsers.toString(),
          subtitle: _rangeLabel(),
          icon: Icons.person_add_alt_rounded,
          accent: widget.accent,
        ),
        _MetricCard(
          title: "Service Requests",
          value: snap.serviceRequests.toString(),
          subtitle: _rangeLabel(),
          icon: Icons.inbox_rounded,
          accent: widget.accent,
        ),
        _MetricCard(
          title: "Completed Jobs",
          value: snap.completedJobs.toString(),
          subtitle: _rangeLabel(),
          icon: Icons.check_circle_rounded,
          accent: widget.accent,
        ),
      ],
    );
  }

  Widget _skeletonGrid() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: List.generate(
        4,
        (_) => _skeletonCard(width: 240, height: 110),
      ),
    );
  }

  Widget _skeletonCard({double? width, double height = 100}) {
    return _ReportsGlassCard(
      width: width,
      padding: const EdgeInsets.all(16),
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontWeight: FontWeight.w900,
        fontSize: 15,
        color: _text,
      ),
    );
  }

  Widget _kvRow(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(k, style: TextStyle(color: _textSoft))),
          Text(v, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _breakdownList(String title, Map<String, int> data) {
    final entries = data.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(title),
        const SizedBox(height: 8),
        if (entries.isEmpty)
          Text("No data in ${_rangeLabel()}",
              style: TextStyle(color: _textSoft))
        else
          for (final e in entries)
            _kvRow(e.key, e.value.toString()),
      ],
    );
  }

  String _csvCell(String value) {
    final escaped = value.replaceAll('"', '""');
    return '"$escaped"';
  }

  String _buildCsv(ReportsSnapshot snap) {
    final lines = <String>[];
    lines.add("Section,Metric,Value,Extra");
    lines.add(
      "${_csvCell("Overview")},${_csvCell("Range")},${_csvCell(_rangeLabel())},",
    );
    lines.add(
      "${_csvCell("Overview")},${_csvCell("Total Users")},${_csvCell(snap.totalUsers.toString())},",
    );
    lines.add(
      "${_csvCell("Overview")},${_csvCell("New Users")},${_csvCell(snap.newUsers.toString())},${_csvCell(_rangeLabel())}",
    );
    lines.add(
      "${_csvCell("Overview")},${_csvCell("Service Requests")},${_csvCell(snap.serviceRequests.toString())},${_csvCell(_rangeLabel())}",
    );
    lines.add(
      "${_csvCell("Overview")},${_csvCell("Completed Jobs")},${_csvCell(snap.completedJobs.toString())},${_csvCell(_rangeLabel())}",
    );
    lines.add(
      "${_csvCell("Routes")},${_csvCell("Created")},${_csvCell(snap.routesCreated.toString())},${_csvCell(_rangeLabel())}",
    );
    lines.add(
      "${_csvCell("Routes")},${_csvCell("Completed")},${_csvCell(snap.routesCompleted.toString())},${_csvCell(_rangeLabel())}",
    );
    lines.add(
      "${_csvCell("Routes")},${_csvCell("Avg stops per route")},${_csvCell(snap.avgStopsPerRoute.toStringAsFixed(1))},",
    );

    for (final entry in snap.requestStatusCounts.entries) {
      lines.add(
        "${_csvCell("Requests by Status")},${_csvCell(entry.key)},${_csvCell(entry.value.toString())},",
      );
    }
    for (final entry in snap.requestTypeCounts.entries) {
      lines.add(
        "${_csvCell("Requests by Type")},${_csvCell(entry.key)},${_csvCell(entry.value.toString())},",
      );
    }

    lines.add("Section,Driver,Assigned,Completed,Completion %");
    for (final d in snap.driverStats) {
      lines.add(
        "${_csvCell("Drivers")},${_csvCell(d.name)},${_csvCell(d.assigned.toString())},${_csvCell(d.completed.toString())},${_csvCell(d.completionRate.toStringAsFixed(0))}",
      );
    }

    return const LineSplitter().convert(lines.join("\n")).join("\n");
  }

  String _buildRtf(ReportsSnapshot snap) {
    String esc(String value) =>
        value.replaceAll('\\', r'\\').replaceAll('{', r'\{').replaceAll('}', r'\}');

    final buffer = StringBuffer();
    buffer.writeln(r'{\rtf1\ansi');
    buffer.writeln(r'\b Reports \b0\par');
    buffer.writeln(r'\par');
    buffer.writeln(r'\b Range:\b0 ' + esc(_rangeLabel()) + r'\par');
    buffer.writeln(r'\par');

    buffer.writeln(r'\b Overview\b0\par');
    buffer.writeln('Total Users: ${snap.totalUsers}\\par');
    buffer.writeln('New Users: ${snap.newUsers}\\par');
    buffer.writeln('Service Requests: ${snap.serviceRequests}\\par');
    buffer.writeln('Completed Jobs: ${snap.completedJobs}\\par');
    buffer.writeln(r'\par');

    buffer.writeln(r'\b Requests by Status\b0\par');
    if (snap.requestStatusCounts.isEmpty) {
      buffer.writeln('No data\\par');
    } else {
      for (final entry in snap.requestStatusCounts.entries) {
        buffer.writeln('${esc(entry.key)}: ${entry.value}\\par');
      }
    }
    buffer.writeln(r'\par');

    buffer.writeln(r'\b Requests by Type\b0\par');
    if (snap.requestTypeCounts.isEmpty) {
      buffer.writeln('No data\\par');
    } else {
      for (final entry in snap.requestTypeCounts.entries) {
        buffer.writeln('${esc(entry.key)}: ${entry.value}\\par');
      }
    }
    buffer.writeln(r'\par');

    buffer.writeln(r'\b Routes\b0\par');
    buffer.writeln('Created: ${snap.routesCreated}\\par');
    buffer.writeln('Completed: ${snap.routesCompleted}\\par');
    buffer.writeln(
      'Avg stops per route: ${snap.avgStopsPerRoute.toStringAsFixed(1)}\\par',
    );
    buffer.writeln(r'\par');

    buffer.writeln(r'\b Drivers\b0\par');
    if (snap.driverStats.isEmpty) {
      buffer.writeln('No drivers\\par');
    } else {
      for (final d in snap.driverStats) {
        buffer.writeln(
          '${esc(d.name)} - Assigned: ${d.assigned}, Completed: ${d.completed}, Completion: ${d.completionRate.toStringAsFixed(0)}%\\par',
        );
      }
    }

    buffer.writeln('}');
    return buffer.toString();
  }
}

enum _RangePreset { days7, days30, days90, all }

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.accent,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return _ReportsGlassCard(
      width: 240,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            height: 46,
            width: 46,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: accent.withOpacity(0.16),
              border: Border.all(color: accent.withOpacity(0.28)),
            ),
            child: Icon(icon, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                      color: _textSoft,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    )),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: const TextStyle(
                    color: _text,
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: _textSoft.withOpacity(0.7),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportsGlassCard extends StatelessWidget {
  const _ReportsGlassCard({required this.child, this.padding, this.width});

  final Widget child;
  final EdgeInsets? padding;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            padding: padding ?? const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: DefaultTextStyle(
              style: TextStyle(
                color: _text,
                fontWeight: FontWeight.w700,
              ),
              child: IconTheme(
                data: IconThemeData(color: _textSoft),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
