import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme.dart';
import '../../../shared/models/models.dart';
import '../../../shared/services/supabase_service.dart';
import '../../../shared/widgets/widgets.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Engineer Home — shell with bottom nav
// ══════════════════════════════════════════════════════════════════════════════
class EngineerHomeScreen extends ConsumerStatefulWidget {
  const EngineerHomeScreen({super.key});

  @override
  ConsumerState<EngineerHomeScreen> createState() => _EngineerHomeScreenState();
}

class _EngineerHomeScreenState extends ConsumerState<EngineerHomeScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: const [
          _EngineerRepairsTab(),
          _EngineerStatsTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.construction_outlined),
            selectedIcon: Icon(Icons.construction),
            label: 'My Repairs',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label: 'My Stats',
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Tab 1 — Assigned Repairs List
// ══════════════════════════════════════════════════════════════════════════════
class _EngineerRepairsTab extends ConsumerStatefulWidget {
  const _EngineerRepairsTab();

  @override
  ConsumerState<_EngineerRepairsTab> createState() =>
      _EngineerRepairsTabState();
}

class _EngineerRepairsTabState extends ConsumerState<_EngineerRepairsTab> {
  List<Report> _reports = [];
  bool _loading = true;
  String _filter = 'active'; // active | fixed | all

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final uid = Supabase.instance.client.auth.currentUser!.id;
      var query = Supabase.instance.client
          .from('reports')
          .select('''
            *,
            ai_results (*),
            citizen:profiles!citizen_id (id, full_name, phone),
            upvotes(count)
          ''')
          .eq('assigned_to', uid);

      if (_filter == 'active') {
        query = query.inFilter('status', ['assigned', 'in_progress']);
      } else if (_filter == 'fixed') {
        query = query.eq('status', 'fixed');
      }

      final data = await query.order('submitted_at', ascending: false);
      final reports = (data as List).map((e) {
        e['upvote_count'] = e['upvotes'];
        return Report.fromJson(e);
      }).toList();

      // Sort by priority score
      reports.sort((a, b) => (b.aiResult?.priorityScore ?? 0)
          .compareTo(a.aiResult?.priorityScore ?? 0));

      if (mounted) setState(() { _reports = reports; _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signOut() async {
    await ref.read(supabaseServiceProvider).signOut();
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Repairs'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          IconButton(icon: const Icon(Icons.logout), onPressed: _signOut),
        ],
      ),
      body: Column(children: [
        // Filter chips
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: [
              for (final f in ['active', 'fixed', 'all'])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(f[0].toUpperCase() + f.substring(1)),
                    selected: _filter == f,
                    onSelected: (_) {
                      setState(() => _filter = f);
                      _load();
                    },
                  ),
                ),
            ],
          ),
        ),

        Expanded(
          child: _loading
              ? const ShimmerList()
              : _reports.isEmpty
                  ? EmptyState(
                      icon: Icons.engineering_outlined,
                      title: _filter == 'active'
                          ? 'No active repairs'
                          : 'No repairs found',
                      subtitle: _filter == 'active'
                          ? 'New assignments will appear here.'
                          : 'Try changing the filter above.',
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.only(bottom: 24),
                        itemCount: _reports.length,
                        itemBuilder: (_, i) => _EngineerRepairCard(
                          report: _reports[i],
                          onUpdate: _load,
                        ),
                      ),
                    ),
        ),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Engineer Repair Card — full featured
// ══════════════════════════════════════════════════════════════════════════════
class _EngineerRepairCard extends StatefulWidget {
  final Report       report;
  final VoidCallback onUpdate;
  const _EngineerRepairCard({required this.report, required this.onUpdate});

  @override
  State<_EngineerRepairCard> createState() => _EngineerRepairCardState();
}

class _EngineerRepairCardState extends State<_EngineerRepairCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final r      = widget.report;
    final ai     = r.aiResult;
    final isFixed = r.status == 'fixed';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(children: [
        // ── Header ──────────────────────────────────────────────────
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Row(children: [
                if (ai?.severity != null)
                  SeverityBadge(severity: ai!.severity!),
                const SizedBox(width: 6),
                StatusChip(status: r.status),
                const Spacer(),
                if (ai?.priorityScore != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'P: ${ai!.priorityScore!.toStringAsFixed(1)}',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.error),
                    ),
                  ),
                Icon(_expanded
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down),
              ]),
              const SizedBox(height: 6),
              Text(
                r.address ?? 'Location recorded',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Row(children: [
                if (r.citizen != null) ...[
                  Icon(Icons.person_outline,
                      size: 14,
                      color: theme.colorScheme.onSurfaceVariant),
                  Text(' ${r.citizen!.displayName}',
                      style: theme.textTheme.bodySmall),
                  const SizedBox(width: 10),
                ],
                Icon(Icons.thumb_up_outlined,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant),
                Text(' ${r.upvoteCount}',
                    style: theme.textTheme.bodySmall),
                const Spacer(),
                if (ai?.repairCostMax != null)
                  Text(ai!.costRangeLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600)),
              ]),
            ]),
          ),
        ),

        // ── Expanded details ─────────────────────────────────────────
        if (_expanded) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

              // Photo
              if (r.imageUrl.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: CachedNetworkImage(
                    imageUrl: r.imageUrl,
                    width: double.infinity,
                    height: 160,
                    fit: BoxFit.cover,
                  ),
                ),
              const SizedBox(height: 10),

              // AI Metrics
              if (ai != null) ...[
                Text('AI Analysis',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                _InfoRow('Depth score',
                    ai.relativeDepth?.toStringAsFixed(4) ?? '—'),
                _InfoRow('Pothole area',
                    '${ai.potholeAreaPx?.toStringAsFixed(0) ?? "—"} px'),
                _InfoRow('Confidence',
                    '${((ai.confidence ?? 0) * 100).toStringAsFixed(1)}%'),
                _InfoRow('Est. asphalt',
                    '${ai.asphaltKg?.toStringAsFixed(1) ?? "—"} kg'),
                _InfoRow('Est. labour',
                    '${ai.labourHours?.toStringAsFixed(1) ?? "—"} hrs'),
                _InfoRow('Repair cost', ai.costRangeLabel),
                const SizedBox(height: 10),
              ],

              // Action buttons
              if (!isFixed) ...[
                Text('Actions',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  // Navigate
                  OutlinedButton.icon(
                    onPressed: () async {
                      final url = Uri.parse(
                          'https://maps.google.com/?q=${r.latitude},${r.longitude}');
                      if (await canLaunchUrl(url)) launchUrl(url);
                    },
                    icon: const Icon(Icons.directions, size: 16),
                    label: const Text('Navigate'),
                    style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8)),
                  ),
                  // Start repair
                  if (r.status == 'assigned')
                    ElevatedButton.icon(
                      onPressed: () => _updateStatus('in_progress'),
                      icon: const Icon(Icons.play_arrow, size: 16),
                      label: const Text('Start repair'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8)),
                    ),
                  // Mark fixed
                  if (r.status == 'in_progress')
                    ElevatedButton.icon(
                      onPressed: () => _showCompleteDialog(),
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text('Mark fixed'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8)),
                    ),
                  // Call citizen
                  if (r.citizen?.phone != null)
                    OutlinedButton.icon(
                      onPressed: () async {
                        final url =
                            Uri.parse('tel:${r.citizen!.phone}');
                        if (await canLaunchUrl(url)) launchUrl(url);
                      },
                      icon: const Icon(Icons.phone, size: 16),
                      label: const Text('Call citizen'),
                      style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8)),
                    ),
                ]),
              ] else
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(children: [
                    const Icon(Icons.check_circle,
                        color: Colors.green, size: 18),
                    const SizedBox(width: 8),
                    Text('Repair completed',
                        style: TextStyle(
                            color: Colors.green.shade800,
                            fontWeight: FontWeight.w600)),
                  ]),
                ),
            ]),
          ),
        ],
      ]),
    );
  }

  Future<void> _updateStatus(String status) async {
    try {
      await Supabase.instance.client
          .from('reports')
          .update({
            'status':     status,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', widget.report.id);
      widget.onUpdate();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _showCompleteDialog() async {
    File?   repairPhoto;
    final   asphaltCtrl = TextEditingController();
    final   labourCtrl  = TextEditingController();
    final   noteCtrl    = TextEditingController();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
            left: 20, right: 20, top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
              const Text('Complete repair',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),

              // Repair photo
              GestureDetector(
                onTap: () async {
                  final picked = await ImagePicker().pickImage(
                      source: ImageSource.camera, imageQuality: 80);
                  if (picked != null) {
                    setSheet(() => repairPhoto = File(picked.path));
                  }
                },
                child: Container(
                  width: double.infinity,
                  height: 120,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: repairPhoto != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(11),
                          child: Image.file(repairPhoto!,
                              fit: BoxFit.cover),
                        )
                      : const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.camera_alt_outlined,
                                size: 32, color: Colors.grey),
                            SizedBox(height: 4),
                            Text('Take repair photo (optional)',
                                style: TextStyle(
                                    color: Colors.grey, fontSize: 12)),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 12),

              // Material log
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: asphaltCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Asphalt used (kg)',
                      prefixIcon: Icon(Icons.construction, size: 18),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: labourCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Labour (hrs)',
                      prefixIcon: Icon(Icons.access_time, size: 18),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              TextField(
                controller: noteCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Completion note (optional)',
                  hintText: 'e.g. Used cold mix asphalt, surface leveled',
                ),
              ),
              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.pop(context);
                    await _completeRepair(
                      repairPhoto: repairPhoto,
                      asphaltKg:
                          double.tryParse(asphaltCtrl.text) ?? 0,
                      labourHrs:
                          double.tryParse(labourCtrl.text) ?? 0,
                      note: noteCtrl.text.trim(),
                    );
                  },
                  icon: const Icon(Icons.check),
                  label: const Text('Submit & mark fixed'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _completeRepair({
    File?   repairPhoto,
    double  asphaltKg = 0,
    double  labourHrs = 0,
    String  note      = '',
  }) async {
    try {
      final client = Supabase.instance.client;

      // Upload repair photo if provided
      if (repairPhoto != null) {
        final path =
            'repair-photos/${widget.report.id}/${DateTime.now().millisecondsSinceEpoch}.jpg';
        await client.storage
            .from('repair-photos')
            .upload(path, repairPhoto);
      }

      // Update report status
      await client.from('reports').update({
        'status':     'fixed',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', widget.report.id);

      // Log actual materials if provided
      if (asphaltKg > 0 || labourHrs > 0) {
        await client.from('ai_results').update({
          'asphalt_kg':   asphaltKg,
          'labour_hours': labourHrs,
        }).eq('report_id', widget.report.id);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Repair marked as fixed!'),
              backgroundColor: Colors.green,
            ));
        widget.onUpdate();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Tab 2 — Engineer's own stats
// ══════════════════════════════════════════════════════════════════════════════
class _EngineerStatsTab extends ConsumerStatefulWidget {
  const _EngineerStatsTab();

  @override
  ConsumerState<_EngineerStatsTab> createState() => _EngineerStatsTabState();
}

class _EngineerStatsTabState extends ConsumerState<_EngineerStatsTab> {
  bool   _loading = true;
  int    _total   = 0;
  int    _fixed   = 0;
  int    _active  = 0;
  double _asphalt = 0;
  double _labour  = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final uid = Supabase.instance.client.auth.currentUser!.id;
    final data = await Supabase.instance.client
        .from('reports')
        .select('status, ai_results(asphalt_kg, labour_hours)')
        .eq('assigned_to', uid);

    final list = data as List;
    double asphalt = 0, labour = 0;
    for (final r in list) {
      final ai = r['ai_results'];
      if (ai is Map) {
        asphalt += (ai['asphalt_kg'] as num?)?.toDouble() ?? 0;
        labour  += (ai['labour_hours'] as num?)?.toDouble() ?? 0;
      }
    }

    if (mounted) {
      setState(() {
        _total   = list.length;
        _fixed   = list.where((r) => r['status'] == 'fixed').length;
        _active  = list
            .where((r) =>
                ['assigned', 'in_progress'].contains(r['status']))
            .length;
        _asphalt = asphalt;
        _labour  = labour;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final rate = _total == 0 ? 0.0 : _fixed / _total;
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Stats'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // KPI grid
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 1.5,
                  children: [
                    _StatCard('Total assigned', '$_total',
                        Icons.assignment, Colors.blue),
                    _StatCard('Fixed', '$_fixed',
                        Icons.check_circle, Colors.green),
                    _StatCard('Active', '$_active',
                        Icons.pending, Colors.orange),
                    _StatCard('Asphalt used',
                        '${_asphalt.toStringAsFixed(1)} kg',
                        Icons.construction, Colors.brown),
                  ],
                ),
                const SizedBox(height: 20),

                // Completion rate
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      const Text('Completion rate',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: rate,
                          minHeight: 20,
                          backgroundColor: Colors.grey.shade200,
                          valueColor:
                              AlwaysStoppedAnimation(Colors.green),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${(rate * 100).toStringAsFixed(1)}%  ($_fixed of $_total repaired)',
                        style:
                            const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),

                // Labour hours
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.access_time,
                        color: Colors.purple),
                    title: const Text('Total labour logged'),
                    trailing: Text(
                      '${_labour.toStringAsFixed(1)} hrs',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String   title, value;
  final IconData icon;
  final Color    color;
  const _StatCard(this.title, this.value, this.icon, this.color);

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 6),
            Text(value,
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: color)),
            Text(title,
                style: const TextStyle(
                    fontSize: 11, color: Colors.grey)),
          ]),
        ),
      );
}

// ── Shared helper widget ──────────────────────────────────────────────────────
class _InfoRow extends StatelessWidget {
  final String label, value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 12, color: Colors.grey)),
          const Spacer(),
          Text(value,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      );
}
