import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/providers.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/state_views.dart';
import '../reports_service.dart';

/// S19 — Reports catalog.
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<ReportDef>>{};
    for (final r in ReportsService.all) {
      groups.putIfAbsent(r.group, () => []).add(r);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('التقارير')),
      body: ListView(children: [
        for (final g in groups.entries) ...[
          Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 4), child: Text(g.key, style: Theme.of(context).textTheme.titleMedium)),
          for (final r in g.value)
            ListTile(
              leading: const Icon(Icons.table_chart_outlined),
              title: Text(r.title),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReportViewScreen(def: r))),
            ),
        ],
      ]),
    );
  }
}

class ReportViewScreen extends ConsumerStatefulWidget {
  const ReportViewScreen({super.key, required this.def});
  final ReportDef def;
  @override
  ConsumerState<ReportViewScreen> createState() => _ReportViewScreenState();
}

class _ReportViewScreenState extends ConsumerState<ReportViewScreen> {
  late DateTimeRange _range = _thisMonth();
  ReportTable? _table;

  static DateTimeRange _thisMonth() {
    final n = DateTime.now();
    return DateTimeRange(start: DateTime(n.year, n.month, 1), end: DateTime(n.year, n.month, n.day));
  }

  DateTime get _from => _range.start;
  DateTime get _to => DateTime(_range.end.year, _range.end.month, _range.end.day).add(const Duration(days: 1));

  @override
  Widget build(BuildContext context) {
    final svc = ref.read(reportsServiceProvider);
    return Scaffold(
      appBar: AppBar(title: Text(widget.def.title), actions: [
        IconButton(
          tooltip: 'تصدير CSV',
          icon: const Icon(Icons.ios_share),
          onPressed: _table == null
              ? null
              : () => runAction(context, () async {
                    final f = await _table!.writeCsv();
                    await Share.shareXFiles([XFile(f.path, mimeType: 'text/csv')], subject: widget.def.title);
                  }),
        ),
      ]),
      body: Column(children: [
        if (widget.def.usesDates)
          ListTile(
            leading: const Icon(Icons.date_range),
            title: Text('من ${Fmt.date(_range.start)} إلى ${Fmt.date(_range.end)}'),
            trailing: Wrap(spacing: 4, children: [
              ActionChip(label: const Text('اليوم'), onPressed: () {
                final n = DateTime.now();
                setState(() => _range = DateTimeRange(start: DateTime(n.year, n.month, n.day), end: DateTime(n.year, n.month, n.day)));
              }),
              ActionChip(label: const Text('الشهر'), onPressed: () => setState(() => _range = _thisMonth())),
            ]),
            onTap: () async {
              final r = await showDateRangePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime(2100), initialDateRange: _range);
              if (r != null) setState(() => _range = r);
            },
          ),
        Expanded(
          child: FutureLoader<ReportTable>(
            reloadKey: '${_range.start}|${_range.end}',
            load: () async {
              final t = await widget.def.build(svc, _from, _to);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _table = t);
              });
              return t;
            },
            builder: (c, t, _) => t.rows.isEmpty
                ? const EmptyView(icon: Icons.table_chart_outlined, title: 'لا توجد بيانات في هذه الفترة')
                : _TableView(t, showTotals: widget.def.id != 'gross_profit'),
          ),
        ),
      ]),
    );
  }
}

class _TableView extends StatelessWidget {
  const _TableView(this.t, {required this.showTotals});
  final ReportTable t;
  final bool showTotals;
  @override
  Widget build(BuildContext context) {
    final totals = t.totals();
    final bold = const TextStyle(fontWeight: FontWeight.bold);
    return ListView(children: [
      if (t.note != null) Padding(padding: const EdgeInsets.all(12), child: Text(t.note!, style: const TextStyle(fontSize: 12))),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStatePropertyAll(Theme.of(context).colorScheme.primaryContainer),
          columnSpacing: 20,
          columns: [
            for (final c in t.columns) DataColumn(label: Text(c.title, style: bold), numeric: c.kind != ColKind.text),
          ],
          rows: [
            for (var r = 0; r < t.rows.length; r++)
              DataRow(cells: [for (var c = 0; c < t.columns.length; c++) DataCell(Text(t.cell(r, c)))]),
            if (showTotals && t.columns.any((c) => c.kind == ColKind.money || c.kind == ColKind.qty))
              DataRow(
                color: WidgetStatePropertyAll(Theme.of(context).colorScheme.surfaceContainerHighest),
                cells: [for (final v in totals) DataCell(Text(v, style: bold))],
              ),
          ],
        ),
      ),
      Padding(padding: const EdgeInsets.all(12), child: Text('${t.rows.length} صف')),
    ]);
  }
}

/// S20 — Activity history.
class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key});
  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final db = ref.read(databaseProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('سجل العمليات')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'بحث في السجل'),
            onChanged: (v) => setState(() => _q = v.trim()),
          ),
        ),
        Expanded(
          child: FutureLoader<List<ActivityLogEntry>>(
            reloadKey: _q,
            load: () {
              final s = db.select(db.activityLogs);
              if (_q.isNotEmpty) s.where((t) => t.description.like('%$_q%'));
              s
                ..orderBy([(t) => OrderingTerm.desc(t.id)])
                ..limit(500);
              return s.get();
            },
            builder: (c, list, _) => list.isEmpty
                ? const EmptyView(icon: Icons.history, title: 'لا توجد عمليات')
                : ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (c, i) => ListTile(
                      dense: true,
                      title: Text(list[i].description),
                      subtitle: Text(Fmt.dateTime(list[i].createdAt)),
                    ),
                  ),
          ),
        ),
      ]),
    );
  }
}
