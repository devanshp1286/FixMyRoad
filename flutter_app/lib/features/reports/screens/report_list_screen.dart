import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/models.dart';
import '../../../shared/services/supabase_service.dart';
import '../../../shared/widgets/widgets.dart';

class ReportListScreen extends ConsumerStatefulWidget {
  const ReportListScreen({super.key});
  @override
  ConsumerState<ReportListScreen> createState() => _ReportListScreenState();
}

class _ReportListScreenState extends ConsumerState<ReportListScreen> {
  List<Report> _reports   = [];
  bool         _loading   = true;
  bool         _hasError  = false;
  RealtimeChannel? _channel;  

  @override
  void initState() {
    super.initState();
    _load();
    // Subscribe to reports table changes (not notifications)
    _channel = ref.read(supabaseServiceProvider).subscribeToMyReports(_onUpdate);
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  void _onUpdate(Map<String, dynamic> _) => _load();

  Future<void> _load() async {
    if (!mounted) return;
    setState(() { _loading = true; _hasError = false; });
    try {
      final reports = await ref.read(supabaseServiceProvider).getMyReports();
      if (mounted) setState(() { _reports = reports; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _hasError = true; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My reports'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const ShimmerList()
          : _hasError
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.wifi_off_outlined, size: 48, color: Colors.grey),
                    const SizedBox(height: 12),
                    const Text('Could not load reports'),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Try again'),
                    ),
                  ]),
                )
              : _reports.isEmpty
                  ? EmptyState(
                      icon: Icons.report_outlined,
                      title: 'No reports yet',
                      subtitle: 'Tap the + button to report a pothole.',
                      action: ElevatedButton(
                        onPressed: () => context.go('/submit'),
                        child: const Text('Report a pothole'),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        itemCount: _reports.length,
                        itemBuilder: (_, i) => ReportCard(
                          report: _reports[i],
                          onTap: () =>
                              context.push('/reports/${_reports[i].id}'),
                        ),
                      ),
                    ),
    );
  }
}