import 'package:flutter/material.dart';

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.title,
    required this.value,
    this.subtitle,
    this.icon,
    this.accent,
    this.onTap,
    this.loading = false,
  });

  final String title;
  final String value;
  final String? subtitle;
  final IconData? icon;
  final Color? accent;
  final VoidCallback? onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accentColor = accent ?? scheme.primary;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 220;
        final titleStyle = theme.textTheme.labelLarge?.copyWith(
          color: scheme.onSurface.withOpacity(0.7),
          fontSize: isCompact ? 12 : null,
        );
        final valueStyle = theme.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          fontSize: isCompact ? 20 : null,
        );
        final subtitleStyle = theme.textTheme.bodySmall?.copyWith(
          color: scheme.onSurface.withOpacity(0.65),
        );

        final content = loading
            ? _MetricSkeleton(isCompact: isCompact)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (icon != null)
                        Container(
                          width: isCompact ? 32 : 36,
                          height: isCompact ? 32 : 36,
                          decoration: BoxDecoration(
                            color: accentColor.withOpacity(0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(icon, color: accentColor, size: isCompact ? 18 : 20),
                        ),
                      if (icon != null) const SizedBox(width: 10),
                      Expanded(child: Text(title, style: titleStyle)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(value, style: valueStyle),
                  if (subtitle != null) ...[
                    const SizedBox(height: 6),
                    Text(subtitle!, style: subtitleStyle),
                  ],
                ],
              );

        return Card(
          elevation: 0,
          color: scheme.surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: scheme.outline.withOpacity(0.2)),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: content,
            ),
          ),
        );
      },
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.accent,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accentColor = accent ?? scheme.primary;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 4,
          height: subtitle == null ? 22 : 36,
          decoration: BoxDecoration(
            color: accentColor.withOpacity(0.7),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class BreakdownItem {
  const BreakdownItem({
    required this.label,
    required this.value,
    this.color,
  });

  final String label;
  final String value;
  final Color? color;
}

class BreakdownList extends StatelessWidget {
  const BreakdownList({
    super.key,
    required this.items,
    this.title,
    this.accent,
  });

  final List<BreakdownItem> items;
  final String? title;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accentColor = accent ?? scheme.primary;

    return Card(
      elevation: 0,
      color: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outline.withOpacity(0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null) ...[
              Row(
                children: [
                  Icon(Icons.pie_chart_outline, color: accentColor, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    title!,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],
            for (final item in items) ...[
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: (item.color ?? accentColor).withOpacity(0.7),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.label,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  Text(
                    item.value,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              if (item != items.last)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Divider(height: 1, color: scheme.outline.withOpacity(0.2)),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class DriverRow {
  const DriverRow({
    required this.name,
    required this.assigned,
    required this.completed,
    required this.completionRate,
  });

  final String name;
  final int assigned;
  final int completed;
  final double completionRate;
}

class DriversDataTable extends StatelessWidget {
  const DriversDataTable({
    super.key,
    required this.rows,
    this.highlightTopN = 5,
    this.accent,
  });

  final List<DriverRow> rows;
  final int highlightTopN;
  final Color? accent;

  String _formatPercent(double value) {
    if (value.isNaN) return '0%';
    if (value <= 1.0) {
      return '${(value * 100).toStringAsFixed(0)}%';
    }
    return '${value.toStringAsFixed(0)}%';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accentColor = accent ?? scheme.primary;

    return Card(
      elevation: 0,
      color: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outline.withOpacity(0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: DataTable(
                  headingRowHeight: 44,
                  dataRowMinHeight: 44,
                  dataRowMaxHeight: 56,
                  columns: const [
                    DataColumn(label: Text('Driver')),
                    DataColumn(label: Text('Assigned')),
                    DataColumn(label: Text('Completed')),
                    DataColumn(label: Text('Completion %')),
                  ],
                  rows: List.generate(rows.length, (index) {
                    final row = rows[index];
                    final isHighlight = index < highlightTopN;
                    final rowColor = isHighlight
                        ? accentColor.withOpacity(0.08)
                        : Colors.transparent;

                    return DataRow(
                      color: MaterialStateProperty.all(rowColor),
                      cells: [
                        DataCell(Text(row.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                        DataCell(Text(row.assigned.toString())),
                        DataCell(Text(row.completed.toString())),
                        DataCell(Text(_formatPercent(row.completionRate))),
                      ],
                    );
                  }),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MetricSkeleton extends StatelessWidget {
  const _MetricSkeleton({required this.isCompact});

  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final base = scheme.outline.withOpacity(0.15);

    Widget bar(double width, double height) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: base,
          borderRadius: BorderRadius.circular(8),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            bar(isCompact ? 32 : 36, isCompact ? 32 : 36),
            const SizedBox(width: 10),
            Expanded(child: bar(120, 12)),
          ],
        ),
        const SizedBox(height: 12),
        bar(80, isCompact ? 18 : 22),
        const SizedBox(height: 8),
        bar(140, 10),
      ],
    );
  }
}
