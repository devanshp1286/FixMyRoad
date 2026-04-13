import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/widgets.dart';

class AdminReportDetailScreen extends StatefulWidget {
  final String reportId;
  const AdminReportDetailScreen({super.key, required this.reportId});

  @override
  State<AdminReportDetailScreen> createState() =>
      _AdminReportDetailScreenState();
}

class _AdminReportDetailScreenState extends State<AdminReportDetailScreen> {
  Report?            _report;
  List<Profile>      _engineers = [];
  List<StatusHistory> _history  = [];
  bool               _loading   = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final client = Supabase.instance.client;

      final data = await client.from('reports').select('''
        *,
        ai_results (*),
        citizen:profiles!citizen_id (id, full_name, phone),
        engineer:profiles!assigned_to (id, full_name),
        upvotes(count)
      ''').eq('id', widget.reportId).single();

      data['upvote_count'] = data['upvotes'];
      final report = Report.fromJson(data);

      final engData = await client
          .from('profiles')
          .select()
          .inFilter('role', ['engineer', 'admin']);
      final engineers =
          (engData as List).map((e) => Profile.fromJson(e)).toList();

      final histData = await client
          .from('status_history')
          .select('*, changer:profiles!changed_by(id, full_name)')
          .eq('report_id', widget.reportId)
          .order('changed_at', ascending: true);
      final history =
          (histData as List).map((e) => StatusHistory.fromJson(e)).toList();

      if (mounted) {
        setState(() {
          _report    = report;
          _engineers = engineers;
          _history   = history;
          _loading   = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _assignEngineer() async {
    if (_engineers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No engineers found.')));
      return;
    }

    final selected = await showDialog<Profile>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Assign engineer'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _engineers.length,
            itemBuilder: (_, i) {
              final eng = _engineers[i];
              return ListTile(
                leading: CircleAvatar(child: Text(eng.initials)),
                title: Text(eng.displayName),
                subtitle: Text(eng.role),
                trailing: _report?.assignedTo == eng.id
                    ? const Icon(Icons.check, color: Colors.green)
                    : null,
                onTap: () => Navigator.pop(context, eng),
              );
            },
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
        ],
      ),
    );

    if (selected == null) return;
    await _updateReport({'assigned_to': selected.id, 'status': 'assigned'});
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Assigned to ${selected.displayName}')));
  }

  Future<void> _updateStatus(String status) async {
    await _updateReport({'status': status});
  }

  Future<void> _updateReport(Map<String, dynamic> data) async {
    try {
      data['updated_at'] = DateTime.now().toIso8601String();
      await Supabase.instance.client
          .from('reports')
          .update(data)
          .eq('id', widget.reportId);
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_report == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Report')),
        body: const Center(child: Text('Report not found')),
      );
    }

    final r  = _report!;
    final ai = r.aiResult;

    return Scaffold(
      body: CustomScrollView(slivers: [
        // Hero image
        SliverAppBar(
          expandedHeight: 240,
          pinned: true,
          title: const Text('Report Detail'),
          flexibleSpace: FlexibleSpaceBar(
            background: r.imageUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: r.imageUrl,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.image_not_supported, size: 48),
                    ),
                  )
                : Container(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: const Icon(Icons.image_not_supported, size: 48),
                  ),
          ),
        ),

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

              // Status + severity
              Row(children: [
                StatusChip(status: r.status),
                const SizedBox(width: 8),
                if (ai?.severity != null)
                  SeverityBadge(severity: ai!.severity!, large: true),
              ]),
              const SizedBox(height: 12),

              // Citizen info
              _InfoCard(children: [
                _Row('Reported by', r.citizen?.displayName ?? '—'),
                _Row('Phone', r.citizen?.phone ?? '—'),
                _Row('Location', r.address ?? '${r.latitude}, ${r.longitude}'),
                _Row('Submitted', _formatDate(r.submittedAt)),
                _Row('Upvotes', '${r.upvoteCount}'),
                if (r.engineer != null)
                  _Row('Assigned to', r.engineer!.displayName),
              ]),
              const SizedBox(height: 12),

              // AI results
              if (ai != null) ...[
                const Text('AI Analysis',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 8),
                _InfoCard(children: [
                  _Row('Severity', ai.severity ?? '—'),
                  _Row('Depth score', ai.relativeDepth?.toStringAsFixed(4) ?? '—'),
                  _Row('Max depth', ai.maxDepth?.toStringAsFixed(4) ?? '—'),
                  _Row('Confidence',
                      '${((ai.confidence ?? 0) * 100).toStringAsFixed(1)}%'),
                  _Row('Repair cost', ai.costRangeLabel),
                  _Row('Asphalt needed',
                      '${ai.asphaltKg?.toStringAsFixed(1) ?? "—"} kg'),
                  _Row('Labour', '${ai.labourHours?.toStringAsFixed(1) ?? "—"} hrs'),
                  _Row('Priority score',
                      ai.priorityScore?.toStringAsFixed(1) ?? '—'),
                ]),
                const SizedBox(height: 12),
              ],

              // Admin action buttons
              const Text('Actions',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                ElevatedButton.icon(
                  onPressed: _assignEngineer,
                  icon: const Icon(Icons.person_add, size: 16),
                  label: Text(r.assignedTo == null ? 'Assign' : 'Reassign'),
                ),
                if (r.status == 'submitted')
                  OutlinedButton.icon(
                    onPressed: () => _updateStatus('under_review'),
                    icon: const Icon(Icons.rate_review, size: 16),
                    label: const Text('Mark under review'),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.orange),
                  ),
                if (r.status == 'in_progress')
                  OutlinedButton.icon(
                    onPressed: () => _updateStatus('fixed'),
                    icon: const Icon(Icons.check_circle, size: 16),
                    label: const Text('Mark fixed'),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.green),
                  ),
                if (!['fixed', 'rejected'].contains(r.status))
                  OutlinedButton.icon(
                    onPressed: () => _updateStatus('rejected'),
                    icon: const Icon(Icons.cancel, size: 16),
                    label: const Text('Reject'),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red),
                  ),
                if (r.status == 'rejected')
                  OutlinedButton.icon(
                    onPressed: () => _updateStatus('submitted'),
                    icon: const Icon(Icons.restore, size: 16),
                    label: const Text('Restore'),
                  ),
              ]),
              const SizedBox(height: 16),

              // Status history
              if (_history.isNotEmpty) ...[
                const Text('Status history',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 8),
                ..._history.map((h) => _HistoryItem(h)),
              ],

              const SizedBox(height: 32),
            ]),
          ),
        ),
      ]),
    );
  }

  String _formatDate(DateTime dt) =>
      '${dt.day}/${dt.month}/${dt.year}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

class _InfoCard extends StatelessWidget {
  final List<Widget> children;
  const _InfoCard({required this.children});

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(children: children),
        ),
      );
}

class _Row extends StatelessWidget {
  final String label, value;
  const _Row(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Text(label,
              style: const TextStyle(fontSize: 13, color: Colors.grey)),
          const Spacer(),
          Flexible(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500),
                textAlign: TextAlign.right),
          ),
        ]),
      );
}

class _HistoryItem extends StatelessWidget {
  final StatusHistory h;
  const _HistoryItem(this.h);

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.statusColor(h.newStatus);
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Column(children: [
          Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          Container(width: 2, height: 36, color: color.withOpacity(0.2)),
        ]),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(h.newStatus.replaceAll('_', ' ').toUpperCase(),
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, color: color)),
            if (h.changer != null)
              Text('by ${h.changer!.displayName}',
                  style: Theme.of(context).textTheme.bodySmall),
            if (h.note != null)
              Text(h.note!, style: Theme.of(context).textTheme.bodySmall),
            Text(
              '${h.changedAt.day}/${h.changedAt.month}/${h.changedAt.year}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ]),
        ),
      ]),
    );
  }
}
