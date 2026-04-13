import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../shared/models/models.dart';
import '../../../shared/services/offline_draft_service.dart';
import '../../../shared/services/photo_quality_checker.dart';
import '../../../shared/services/supabase_service.dart';
import '../../../shared/services/ai_trigger_service.dart';

class ReportSubmitScreen extends ConsumerStatefulWidget {
  const ReportSubmitScreen({super.key});

  @override
  ConsumerState<ReportSubmitScreen> createState() => _ReportSubmitScreenState();
}

class _ReportSubmitScreenState extends ConsumerState<ReportSubmitScreen> {
  File?     _image;
  Position? _position;
  String?   _address;
  String?   _qualityError;
  bool      _loadingLocation = false;
  bool      _submitting      = false;
  final _descCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _getLocation();
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _getLocation() async {
    setState(() => _loadingLocation = true);
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) {
        if (mounted) setState(() => _loadingLocation = false);
        return;
      }
      try {
        _position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
        ).timeout(const Duration(seconds: 10));
      } catch (_) {
        _position = await Geolocator.getLastKnownPosition();
      }
      if (_position != null) {
        try {
          final placemarks = await placemarkFromCoordinates(
            _position!.latitude, _position!.longitude,
          ).timeout(const Duration(seconds: 5));
          if (placemarks.isNotEmpty) {
            final p = placemarks.first;
            _address = [p.street, p.subLocality, p.locality]
                .where((s) => s != null && s.isNotEmpty)
                .join(', ');
          }
        } catch (_) {
          _address =
              '${_position!.latitude.toStringAsFixed(5)}, ${_position!.longitude.toStringAsFixed(5)}';
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingLocation = false);
  }

  Future<void> _pickImage(ImageSource source) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1280,
    );
    if (picked == null) return;
    final file = File(picked.path);
    final result = await PhotoQualityChecker.check(file);
    if (!result.isAccepted) {
      setState(() { _qualityError = result.rejectionReason; _image = null; });
      return;
    }
    setState(() { _image = file; _qualityError = null; });
  }

  // ── Duplicate dialog — uses showGeneralDialog to avoid GoRouter conflict ──
  Future<bool> _showDuplicateDialog(Report nearby) async {
    final result = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      pageBuilder: (ctx, _, __) => AlertDialog(
        title: const Text('Pothole already reported'),
        content: Text(
          'A pothole has already been reported '
          '${nearby.address != null && nearby.address!.isNotEmpty ? "at ${nearby.address}" : "near this location"}. '
          'Do you want to submit a new report anyway?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Go back'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Submit anyway'),
          ),
        ],
      ),
    );
    // null means dialog was dismissed without selection — treat as cancel
    return result == true;
  }

  Future<void> _submit() async {
    if (_image == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a photo first.')));
      return;
    }

    final lat = _position?.latitude  ?? 20.5937;
    final lng = _position?.longitude ?? 78.9629;

    setState(() => _submitting = true);

    // ── Offline check ────────────────────────────────────────────────────
    final connectivity = await Connectivity().checkConnectivity();
    final isOnline = connectivity != ConnectivityResult.none;

    if (!isOnline) {
      await OfflineDraftService.saveDraft(DraftReport(
        imagePath: _image!.path,
        latitude: lat,
        longitude: lng,
        address: _address,
        description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        createdAt: DateTime.now(),
      ));
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Saved offline. Will submit when reconnected.'),
          backgroundColor: Colors.orange,
        ));
        context.go('/reports');
      }
      return;
    }

    try {
      final service = ref.read(supabaseServiceProvider);

      // ── Duplicate detection ──────────────────────────────────────────
      bool proceedWithSubmit = true;
      try {
        final nearby = await service.findNearbyReport(lat, lng);
        if (nearby != null && mounted) {
          final userChose = await _showDuplicateDialog(nearby);
          if (!userChose) {
            // User chose "Go back" — return to submit screen, not black page
            if (mounted) setState(() => _submitting = false);
            return;
          }
          proceedWithSubmit = true;
        }
      } catch (_) {
        // Duplicate detection failed — proceed with submission anyway
        proceedWithSubmit = true;
      }

      if (!proceedWithSubmit) {
        if (mounted) setState(() => _submitting = false);
        return;
      }

      // ── Submit report ────────────────────────────────────────────────
      final reportId = await service.submitReport(
        imageFile: _image!,
        latitude: lat,
        longitude: lng,
        address: _address,
        description: _descCtrl.text.trim().isEmpty
            ? null
            : _descCtrl.text.trim(),
      );

      // Trigger AI analysis in background
      try {
        final report = await service.getReport(reportId);
        AiTriggerService.triggerAnalysis(
          reportId: reportId,
          imageUrl: report.imageUrl,
        );
      } catch (_) {
        // AI trigger failure is non-critical — report was saved
      }

      if (mounted) context.go('/result/$reportId');

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Submission failed: $e')));
        setState(() => _submitting = false);
      }
    }
  }

  void _showImageSourceSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take a photo'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Report a pothole')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // ── Photo ─────────────────────────────────────────────────────
          Text('Photo', style: theme.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: _showImageSourceSheet,
            child: Container(
              width: double.infinity,
              height: 220,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _qualityError != null
                      ? theme.colorScheme.error
                      : theme.colorScheme.outline.withOpacity(0.3),
                ),
              ),
              child: _image != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(15),
                      child: Image.file(_image!, fit: BoxFit.cover),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_a_photo_outlined,
                            size: 48,
                            color: theme.colorScheme.primary.withOpacity(0.5)),
                        const SizedBox(height: 8),
                        Text('Tap to take or choose a photo',
                            style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant)),
                      ],
                    ),
            ),
          ),
          if (_qualityError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(children: [
                Icon(Icons.warning_amber, size: 16, color: theme.colorScheme.error),
                const SizedBox(width: 6),
                Expanded(child: Text(_qualityError!,
                    style: TextStyle(color: theme.colorScheme.error, fontSize: 13))),
              ]),
            ),
          const SizedBox(height: 20),

          // ── Location ──────────────────────────────────────────────────
          Text('Location', style: theme.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.colorScheme.outline.withOpacity(0.2)),
            ),
            child: Row(children: [
              Icon(Icons.location_on, color: theme.colorScheme.primary, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: _loadingLocation
                    ? const Row(children: [
                        SizedBox(width: 14, height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                        SizedBox(width: 8),
                        Text('Getting location...'),
                      ])
                    : Text(_address ??
                        (_position != null
                            ? '${_position!.latitude.toStringAsFixed(5)}, '
                              '${_position!.longitude.toStringAsFixed(5)}'
                            : 'Location unavailable — tap refresh')),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: _getLocation,
                tooltip: 'Refresh location',
              ),
            ]),
          ),
          const SizedBox(height: 20),

          // ── Description ───────────────────────────────────────────────
          Text('Description (optional)', style: theme.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          TextField(
            controller: _descCtrl,
            maxLines: 3,
            maxLength: 300,
            decoration: const InputDecoration(
              hintText: 'Describe the pothole — size, depth, nearby landmarks...',
            ),
          ),
          const SizedBox(height: 32),

          // ── Submit ────────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_rounded),
              label: Text(_submitting ? 'Submitting...' : 'Submit report'),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              _position == null
                  ? 'No GPS — report will use default location'
                  : 'GPS location tagged to this report.',
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ]),
      ),
    );
  }
}