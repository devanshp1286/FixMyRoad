import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../shared/models/models.dart';
import '../../../shared/services/supabase_service.dart';
import '../../../shared/widgets/widgets.dart';

class FieldUpdateScreen extends ConsumerStatefulWidget {
  final String reportId;
  const FieldUpdateScreen({super.key, required this.reportId});

  @override
  ConsumerState<FieldUpdateScreen> createState() => _FieldUpdateScreenState();
}

class _FieldUpdateScreenState extends ConsumerState<FieldUpdateScreen> {
  Report?  _report;
  bool     _loading    = true;
  bool     _submitting = false;
  File?    _repairPhoto;
  String?  _selectedStatus;
  final _noteCtrl     = TextEditingController();
  final _asphaltCtrl  = TextEditingController();
  final _labourCtrl   = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    _asphaltCtrl.dispose();
    _labourCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final r = await ref.read(supabaseServiceProvider).getReport(widget.reportId);
    if (mounted) setState(() { _report = r; _loading = false; });
  }

  Future<void> _pickRepairPhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
    );
    if (picked != null && mounted) {
      setState(() => _repairPhoto = File(picked.path));
    }
  }

  Future<void> _submit() async {
    if (_selectedStatus == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a new status.')));
      return;
    }
    setState(() => _submitting = true);
    try {
      final service = ref.read(supabaseServiceProvider);

      // Upload repair photo if provided
      if (_repairPhoto != null) {
        await service.uploadRepairPhoto(widget.reportId, _repairPhoto!);
      }

      // Update status
      await service.updateReportStatus(
        widget.reportId,
        _selectedStatus!,
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Report updated successfully.')));
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_report == null) {
      return const Scaffold(body: Center(child: Text('Report not found.')));
    }

    final r = _report!;
    return Scaffold(
      appBar: AppBar(title: const Text('Update repair')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Report summary
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                if (r.aiResult?.severity != null)
                  SeverityBadge(severity: r.aiResult!.severity!),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(r.address ?? 'Location recorded',
                        style: theme.textTheme.bodyMedium)),
              ]),
            ),
          ),
          const SizedBox(height: 20),

          // Status selection
          Text('New status', style: theme.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, children: [
            for (final s in ['in_progress', 'fixed', 'rejected'])
              ChoiceChip(
                label: Text(_label(s)),
                selected: _selectedStatus == s,
                onSelected: (_) => setState(() => _selectedStatus = s),
                selectedColor: theme.colorScheme.primaryContainer,
              ),
          ]),
          const SizedBox(height: 20),

          // Note
          Text('Note (optional)', style: theme.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          TextField(
            controller: _noteCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
                hintText: 'Add a note for the report history...'),
          ),
          const SizedBox(height: 20),

          // Repair photo
          Text('Repair photo (optional)', style: theme.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _pickRepairPhoto,
            child: Container(
              width: double.infinity,
              height: 140,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: theme.colorScheme.outline.withOpacity(0.3)),
              ),
              child: _repairPhoto != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(11),
                      child: Image.file(_repairPhoto!, fit: BoxFit.cover),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.camera_alt_outlined,
                            size: 36,
                            color: theme.colorScheme.onSurfaceVariant),
                        const SizedBox(height: 6),
                        Text('Tap to take repair photo',
                            style: theme.textTheme.bodySmall),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 20),

          // Material log
          if (_selectedStatus == 'fixed') ...[
            Text('Material used', style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _asphaltCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Asphalt (kg)',
                    prefixIcon: Icon(Icons.construction_outlined, size: 18),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _labourCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Labour (hrs)',
                    prefixIcon: Icon(Icons.access_time_outlined, size: 18),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 20),
          ],

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Submit update'),
            ),
          ),
        ]),
      ),
    );
  }

  String _label(String s) {
    switch (s) {
      case 'in_progress': return 'In Progress';
      case 'fixed':       return 'Fixed';
      case 'rejected':    return 'Reject';
      default:            return s;
    }
  }
}
