import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/models/models.dart';
import '../../../shared/services/supabase_service.dart';
import '../../../shared/widgets/widgets.dart';
import '../../../core/theme.dart';

class ReportResultScreen extends ConsumerStatefulWidget {
  final String reportId;
  const ReportResultScreen({super.key, required this.reportId});

  @override
  ConsumerState<ReportResultScreen> createState() => _ReportResultScreenState();
}

class _ReportResultScreenState extends ConsumerState<ReportResultScreen> {
  Report?  _report;
  bool     _loading    = true;
  bool     _aiTimedOut = false;
  int      _pollCount  = 0;
  Timer?   _pollTimer;
  static const _maxPolls = 20; // 20 × 5s = 100s

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    await _fetchReport();
    if (_report?.aiResult == null) _startPolling();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!mounted) { _pollTimer?.cancel(); return; }
      _pollCount++;
      await _fetchReport();
      if (_report?.aiResult != null) { _pollTimer?.cancel(); return; }
      if (_pollCount >= _maxPolls) {
        _pollTimer?.cancel();
        if (mounted) setState(() => _aiTimedOut = true);
      }
    });
  }

  Future<void> _fetchReport() async {
    try {
      final r = await ref.read(supabaseServiceProvider).getReport(widget.reportId);
      if (mounted) setState(() {
        _report  = r;
        _loading = false;
        if (r.aiResult != null) _aiTimedOut = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _retry() {
    setState(() { _aiTimedOut = false; _pollCount = 0; });
    _startPolling();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final ai = _report?.aiResult;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Report submitted'),
        automaticallyImplyLeading: false,
        actions: [
          TextButton(
            onPressed: () => context.go('/home'),
            child: const Text('Back to map'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchReport,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [

            // ── Success icon ─────────────────────────────────────────
            const SizedBox(height: 8),
            Container(
              width: 68, height: 68,
              decoration: const BoxDecoration(
                  color: AppTheme.primary, shape: BoxShape.circle),
              child: const Icon(Icons.check_rounded,
                  color: Colors.white, size: 38),
            ),
            const SizedBox(height: 14),
            Text('Report submitted!',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              ai == null
                  ? 'AI is analysing your photo. Results appear automatically.'
                  : 'Your pothole has been recorded and will be reviewed.',
              style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // ── Pothole photo ─────────────────────────────────────────
            if (_report?.imageUrl.isNotEmpty == true)
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: CachedNetworkImage(
                  imageUrl: _report!.imageUrl,
                  width: double.infinity,
                  height: 180,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Container(
                    height: 180,
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: const Icon(Icons.image_not_supported,
                        size: 40, color: Colors.grey),
                  ),
                ),
              ),
            const SizedBox(height: 20),

            // ── AI result — CITIZEN VIEW (severity only, no cost/depth) ──
            if (ai != null) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Row(children: [
                      const Icon(Icons.auto_awesome,
                          color: AppTheme.primary, size: 18),
                      const SizedBox(width: 8),
                      Text('AI Analysis',
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                    ]),
                    const SizedBox(height: 14),

                    // Severity badge — centred, prominent
                    Center(
                      child: Column(children: [
                        if (ai.severity != null)
                          SeverityBadge(severity: ai.severity!, large: true),
                        const SizedBox(height: 10),
                        Text(
                          _severityMessage(ai.severity ?? 'shallow'),
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                          textAlign: TextAlign.center,
                        ),
                      ]),
                    ),
                    const SizedBox(height: 16),
                    const Divider(height: 1),
                    const SizedBox(height: 14),

                    // What citizen needs to know — NO cost or depth values
                    _InfoRow(
                      icon: Icons.info_outline,
                      label: 'Status',
                      value: _report!.statusLabel,
                      valueColor: AppTheme.statusColor(_report!.status),
                    ),
                    const SizedBox(height: 8),
                    _InfoRow(
                      icon: Icons.location_on_outlined,
                      label: 'Location',
                      value: _report!.address ?? 'GPS coordinates recorded',
                    ),
                    const SizedBox(height: 8),
                    _InfoRow(
                      icon: Icons.access_time_outlined,
                      label: 'Submitted',
                      value: _formatDate(_report!.submittedAt),
                    ),
                    const SizedBox(height: 8),
                    _InfoRow(
                      icon: Icons.thumb_up_outlined,
                      label: 'Community votes',
                      value: '${_report!.upvoteCount}',
                    ),
                  ]),
                ),
              ),

              // Heatmap image (visual only — no numbers shown to citizen)
              if (ai.heatmapUrl != null) ...[
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(
                    imageUrl: ai.heatmapUrl!,
                    width: double.infinity,
                    fit: BoxFit.fitWidth,
                    placeholder: (_, __) => Container(
                      height: 160,
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                    errorWidget: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('AI severity heatmap',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                      textAlign: TextAlign.center),
                ),
              ],

            ] else if (_aiTimedOut) ...[
              // Timed out card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(children: [
                    const Icon(Icons.schedule_outlined,
                        size: 40, color: Colors.orange),
                    const SizedBox(height: 10),
                    Text('Analysis is taking longer than expected.',
                        style: theme.textTheme.bodyMedium,
                        textAlign: TextAlign.center),
                    const SizedBox(height: 6),
                    Text(
                      'Your report was saved successfully. '
                      'Results will appear when analysis completes.',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: _retry,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Check again'),
                    ),
                  ]),
                ),
              ),
            ] else ...[
              // Still analysing
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(children: [
                    Row(children: [
                      const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                          child: Text('AI analysis in progress...')),
                    ]),
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: (_pollCount / _maxPolls).clamp(0.0, 1.0),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Checking every 5 seconds (${_pollCount * 5}s elapsed)',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ]),
                ),
              ),
            ],

            const SizedBox(height: 20),

            // ── Upvote hint ───────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                Icon(Icons.info_outline,
                    size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Know another pothole at the same spot? Upvote this '
                    'report to increase its repair priority.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 20),

            // ── Actions ───────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => context.go('/reports/${widget.reportId}'),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('View full report'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => context.go('/home'),
                icon: const Icon(Icons.map_outlined, size: 16),
                label: const Text('Back to map'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () => context.go('/submit'),
                icon: const Icon(Icons.add_road, size: 16),
                label: const Text('Report another pothole'),
              ),
            ),
            const SizedBox(height: 24),
          ]),
        ),
      ),
    );
  }

  String _severityMessage(String s) {
    switch (s) {
      case 'deep':
        return 'This pothole is deep and poses a significant hazard.\nIt has been marked high priority for repair.';
      case 'moderate':
        return 'This pothole is moderate in depth.\nIt has been added to the repair queue.';
      default:
        return 'This pothole is relatively shallow.\nIt has been recorded for routine maintenance.';
    }
  }

  String _formatDate(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24)   return '${diff.inHours}h ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String   value;
  final Color?   valueColor;
  const _InfoRow({required this.icon, required this.label,
      required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Text('$label: ',
              style: const TextStyle(fontSize: 13, color: Colors.grey)),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: valueColor)),
          ),
        ],
      );
}