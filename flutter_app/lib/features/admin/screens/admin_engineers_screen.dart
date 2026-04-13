import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/models.dart';

class AdminEngineersScreen extends StatefulWidget {
  const AdminEngineersScreen({super.key});

  @override
  State<AdminEngineersScreen> createState() => _AdminEngineersScreenState();
}

class _AdminEngineersScreenState extends State<AdminEngineersScreen> {
  List<Map<String, dynamic>> _engineerStats = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final client = Supabase.instance.client;

      // Get all engineers only (not admins)
      final engineers = await client
          .from('profiles')
          .select()
          .eq('role', 'engineer');

      final stats = <Map<String, dynamic>>[];
      for (final eng in engineers as List) {
        final profile = Profile.fromJson(eng);

        // Count assigned reports
        final assigned = await client
            .from('reports')
            .select('id, status')
            .eq('assigned_to', profile.id);

        final assignedList = assigned as List;
        final total    = assignedList.length;
        final fixed    = assignedList.where((r) => r['status'] == 'fixed').length;
        final active   = assignedList
            .where((r) => ['assigned', 'in_progress'].contains(r['status']))
            .length;

        stats.add({
          'profile':  profile,
          'total':    total,
          'fixed':    fixed,
          'active':   active,
          'rate':     total == 0 ? 0.0 : fixed / total,
        });
      }

      // Sort by completion rate
      stats.sort((a, b) =>
          (b['rate'] as double).compareTo(a['rate'] as double));

      if (mounted) setState(() { _engineerStats = stats; _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _promoteToAdmin(Profile profile) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Promote to admin?'),
        content: Text(
            '${profile.displayName} will get full admin access to all reports and analytics.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Promote')),
        ],
      ),
    );
    if (confirm != true) return;

    await Supabase.instance.client
        .from('profiles')
        .update({'role': 'admin'}).eq('id', profile.id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Engineer Team'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _engineerStats.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.engineering_outlined,
                          size: 64, color: Colors.grey),
                      const SizedBox(height: 12),
                      const Text('No engineers yet'),
                      const SizedBox(height: 8),
                      const Text(
                        'Go to Supabase → profiles table\nand set role = engineer',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _engineerStats.length,
                    itemBuilder: (_, i) {
                      final stat    = _engineerStats[i];
                      final profile = stat['profile'] as Profile;
                      final rate    = stat['rate'] as double;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            // Header
                            Row(children: [
                              CircleAvatar(
                                radius: 22,
                                backgroundColor: theme
                                    .colorScheme.primaryContainer,
                                child: Text(profile.initials,
                                    style: TextStyle(
                                        color: theme.colorScheme.primary,
                                        fontWeight: FontWeight.w700)),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Text(profile.displayName,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 15)),
                                  Row(children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: profile.isAdmin
                                            ? Colors.purple.shade50
                                            : Colors.blue.shade50,
                                        borderRadius:
                                            BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        profile.role.toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: profile.isAdmin
                                              ? Colors.purple
                                              : Colors.blue,
                                        ),
                                      ),
                                    ),
                                  ]),
                                ]),
                              ),
                              if (!profile.isAdmin)
                                IconButton(
                                  icon: const Icon(Icons.arrow_upward,
                                      size: 18),
                                  tooltip: 'Promote to admin',
                                  onPressed: () =>
                                      _promoteToAdmin(profile),
                                ),
                            ]),
                            const SizedBox(height: 12),

                            // Stats row
                            Row(children: [
                              _StatBox('Assigned', stat['total'].toString(),
                                  Colors.blue),
                              const SizedBox(width: 8),
                              _StatBox('Active', stat['active'].toString(),
                                  Colors.orange),
                              const SizedBox(width: 8),
                              _StatBox('Fixed', stat['fixed'].toString(),
                                  Colors.green),
                            ]),
                            const SizedBox(height: 10),

                            // Completion rate bar
                            Row(children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: LinearProgressIndicator(
                                    value: rate,
                                    minHeight: 8,
                                    backgroundColor: Colors.grey.shade200,
                                    valueColor:
                                        AlwaysStoppedAnimation(Colors.green),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${(rate * 100).toStringAsFixed(0)}%',
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600),
                              ),
                            ]),
                            const SizedBox(height: 2),
                            Text('completion rate',
                                style: theme.textTheme.bodySmall),
                          ]),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String label, value;
  final Color  color;
  const _StatBox(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(children: [
            Text(value,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: color)),
            Text(label,
                style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ]),
        ),
      );
}