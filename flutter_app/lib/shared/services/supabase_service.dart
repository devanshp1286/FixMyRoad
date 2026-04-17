import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import '../../core/constants.dart';

final supabaseServiceProvider = Provider((ref) => SupabaseService());

class SupabaseService {
  final _client = Supabase.instance.client;

  // ── Auth ────────────────────────────────────────────────────────────────
  User? get currentUser => _client.auth.currentUser;
  bool  get isLoggedIn  => currentUser != null;

  Future<AuthResponse> signInWithEmail(String email, String password) =>
      _client.auth.signInWithPassword(email: email, password: password);

  Future<AuthResponse> signUpWithEmail(
      String email, String password, String fullName) async {
    final res = await _client.auth.signUp(
      email: email,
      password: password,
      data: {'full_name': fullName},
    );
    return res;
  }

  Future<void> signOut() => _client.auth.signOut();

  // ── Profile ─────────────────────────────────────────────────────────────
  Future<Profile> getProfile(String userId) async {
    final data = await _client
        .from('profiles')
        .select()
        .eq('id', userId)
        .single();
    return Profile.fromJson(data);
  }

  // Auto-create profile if trigger failed
  Future<void> createProfileIfMissing(String userId, String email) async {
    try {
      await _client.from('profiles').insert({
        'id': userId,
        'full_name': email.split('@').first,
        'role': 'citizen',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {
      // Profile already exists, ignore
    }
  }

  Future<void> updateProfile({
    String? fullName,
    String? phone,
    String? fcmToken,
  }) async {
    final updates = <String, dynamic>{
      if (fullName  != null) 'full_name': fullName,
      if (phone     != null) 'phone': phone,
      if (fcmToken  != null) 'fcm_token': fcmToken,
      'updated_at': DateTime.now().toIso8601String(),
    };
    await _client
        .from('profiles')
        .update(updates)
        .eq('id', currentUser!.id);
  }

  // ── Reports ─────────────────────────────────────────────────────────────
  Future<List<Report>> getMyReports() async {
    final data = await _client
        .from('reports')
        .select('''
          *,
          ai_results (*),
          upvotes(count)
        ''')
        .eq('citizen_id', currentUser!.id)
        .order('submitted_at', ascending: false);
    return (data as List).map((e) {
      // Rename upvotes → upvote_count for model parsing
      e['upvote_count'] = e['upvotes'];
      return Report.fromJson(e);
    }).toList();
  }

  Future<Report> getReport(String reportId) async {
    final data = await _client
        .from('reports')
        .select('''
          *,
          ai_results (*),
          citizen:profiles!citizen_id (id, full_name, avatar_url),
          engineer:profiles!assigned_to (id, full_name),
          upvotes(count)
        ''')
        .eq('id', reportId)
        .single();
    data['upvote_count'] = data['upvotes'];
    return Report.fromJson(data);
  }

  Future<List<Report>> getPublicReports() async {
    final data = await _client
        .from('reports')
        .select('id, latitude, longitude, status, address, ai_results(severity)')
        .neq('status', 'rejected')
        .order('submitted_at', ascending: false)
        .limit(500);
    return (data as List).map((e) {
      e['upvote_count'] = 0;
      return Report.fromJson(e);
    }).toList();
  }

  Future<List<Report>> getAllReports({String? status}) async {
    var query = _client.from('reports').select('''
      *,
      ai_results (*),
      citizen:profiles!citizen_id (id, full_name),
      upvote_count:upvotes(count)
    ''');
    if (status != null) query = query.eq('status', status);
    final data = await query.order('submitted_at', ascending: false);
    return (data as List).map((e) {
      e['upvote_count'] = e.containsKey('upvotes') ? e['upvotes'] : 0;
      return Report.fromJson(e);
    }).toList();
  }

  // Check for duplicate within radius
  Future<Report?> findNearbyReport(double lat, double lng) async {
    final data = await _client.rpc('find_nearby_open_report', params: {
      'p_lat': lat,
      'p_lng': lng,
      'p_radius': AppConstants.duplicateRadiusMetres,
    });
    if (data == null || (data as List).isEmpty) return null;
    return Report.fromJson(data[0]);
  }

  Future<String> submitReport({
    required File imageFile,
    required double latitude,
    required double longitude,
    required String? address,
    required String? description,
  }) async {
    // 1. Upload image to Supabase Storage
    final fileName =
        '${currentUser!.id}/${DateTime.now().millisecondsSinceEpoch}.jpg';
    print('[Report] Uploading image to: $fileName');
    await _client.storage
        .from(AppConstants.bucketPotholeImages)
        .upload(fileName, imageFile);
    final imageUrl = _client.storage
        .from(AppConstants.bucketPotholeImages)
        .getPublicUrl(fileName);
    print('[Report] Image uploaded. URL: $imageUrl');

    // 2. Insert report
    print('[Report] Inserting report into Supabase...');
    final data = await _client.from('reports').insert({
      'citizen_id': currentUser!.id,
      'image_url': imageUrl,
      'latitude': latitude,
      'longitude': longitude,
      'address': address,
      'description': description,
    }).select().single();

    final reportId = data['id'] as String;
    print('[Report] ✓ Report created with ID: $reportId');
    print('[Report] Status in database: ${data['status']}');

    // 3. Directly call AI worker (fire and forget - doesn't block UI)
    print('[Report] Triggering AI analysis in background...');
    _callAiWorker(reportId, imageUrl);

    return reportId;
  }

  // Fire and forget — does not block the UI
  Future<void> _callAiWorker(String reportId, String imageUrl) async {
    try {
      final startTime = DateTime.now();
      print('[AI Worker] ═══════════════════════════════════════════════════════');
      print('[AI Worker] Calling AI worker...');
      print('[AI Worker] URL: ${AppConstants.aiWorkerUrl}/analyze');
      print('[AI Worker] Report ID: $reportId');
      print('[AI Worker] Image URL: $imageUrl');
      print('[AI Worker] ═══════════════════════════════════════════════════════');
      
      final uri = Uri.parse('${AppConstants.aiWorkerUrl}/analyze');
      print('[AI Worker] [T:0s] Creating HTTP request...');
      
      final request = http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'report_id': reportId,
          'image_url': imageUrl,
        }),
      ).timeout(const Duration(seconds: 60), onTimeout: () {
        print('[AI Worker] [TIMEOUT] Request timed out after 60 seconds');
        throw TimeoutException('AI worker did not respond within 60 seconds');
      });

      print('[AI Worker] [T:0s] Sending request to ${uri.host}:${uri.port}...');
      
      final response = await request;
      
      final elapsed = DateTime.now().difference(startTime).inSeconds;
      print('[AI Worker] [T:${elapsed}s] Got response from server');
      print('[AI Worker] [T:${elapsed}s] Status code: ${response.statusCode}');

      if (response.statusCode == 200) {
        print('[AI Worker] [T:${elapsed}s] ✓✓✓ SUCCESS ✓✓✓');
        print('[AI Worker] [T:${elapsed}s] Report $reportId sent to AI worker');
        print('[AI Worker] [T:${elapsed}s] Response body: ${response.body.length} chars');
        print('[AI Worker] ═══════════════════════════════════════════════════════');
      } else {
        print('[AI Worker] [T:${elapsed}s] ✗ FAILED - Status ${response.statusCode}');
        print('[AI Worker] Error response: ${response.body}');
        print('[AI Worker] ═══════════════════════════════════════════════════════');
      }
    } on TimeoutException catch (e) {
      print('[AI Worker] ✗ TIMEOUT: $e');
      print('[AI Worker] The server took too long to respond');
      print('[AI Worker] This could mean:');
      print('[AI Worker]   1. AI worker is not running (python main.py)');
      print('[AI Worker]   2. Network connection is unstable');
      print('[AI Worker]   3. Firewall is blocking port 8000');
      print('[AI Worker] ═══════════════════════════════════════════════════════');
    } catch (e) {
      print('[AI Worker] ✗ CONNECTION ERROR: $e');
      print('[AI Worker] Failed to reach: ${AppConstants.aiWorkerUrl}');
      print('[AI Worker] Troubleshooting:');
      print('[AI Worker]   1. Check backend is running: python main.py');
      print('[AI Worker]   2. Check laptop IPv4: ipconfig (should be 10.183.62.19)');
      print('[AI Worker]   3. Phone and laptop on same WiFi');
      print('[AI Worker]   4. Windows Firewall allows port 8000');
      print('[AI Worker] ═══════════════════════════════════════════════════════');
    }
  }

  Future<void> updateReportStatus(
      String reportId, String status, {String? note}) async {
    await _client.from('reports').update({
      'status': status,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', reportId);

    if (note != null) {
      // Update the auto-created status_history row's note
      await _client
          .from('status_history')
          .update({'note': note})
          .eq('report_id', reportId)
          .eq('new_status', status)
          .order('changed_at', ascending: false)
          .limit(1);
    }
  }

  Future<void> assignReport(String reportId, String engineerId) async {
    await _client.from('reports').update({
      'assigned_to': engineerId,
      'status': 'assigned',
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', reportId);
  }

  // ── Upvotes ─────────────────────────────────────────────────────────────
  Future<void> upvoteReport(String reportId) async {
    await _client.from('upvotes').upsert({
      'report_id': reportId,
      'citizen_id': currentUser!.id,
    });
  }

  Future<bool> hasUpvoted(String reportId) async {
    final data = await _client
        .from('upvotes')
        .select('id')
        .eq('report_id', reportId)
        .eq('citizen_id', currentUser!.id)
        .maybeSingle();
    return data != null;
  }

  // ── Status History ───────────────────────────────────────────────────────
  Future<List<StatusHistory>> getStatusHistory(String reportId) async {
    final data = await _client
        .from('status_history')
        .select('*, changer:profiles!changed_by(id, full_name)')
        .eq('report_id', reportId)
        .order('changed_at', ascending: true);
    return (data as List).map((e) => StatusHistory.fromJson(e)).toList();
  }

  // ── Notifications ────────────────────────────────────────────────────────
  Future<List<NotificationModel>> getNotifications() async {
    final data = await _client
        .from('notifications')
        .select()
        .eq('user_id', currentUser!.id)
        .order('created_at', ascending: false)
        .limit(50);
    return (data as List).map((e) => NotificationModel.fromJson(e)).toList();
  }

  Future<void> markNotificationRead(String notificationId) async {
    await _client
        .from('notifications')
        .update({'is_read': true})
        .eq('id', notificationId);
  }

  Future<int> getUnreadCount() async {
    final data = await _client
        .from('notifications')
        .select('id')
        .eq('user_id', currentUser!.id)
        .eq('is_read', false);
    return (data as List).length;
  }

  // ── Realtime ─────────────────────────────────────────────────────────────
  RealtimeChannel subscribeToMyReports(
      void Function(Map<String, dynamic>) onUpdate) {
    final uid = currentUser?.id ?? '';
    return _client
        .channel('my_reports_$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'reports',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'citizen_id',
            value: uid,
          ),
          callback: (payload) => onUpdate(payload.newRecord),
        )
        .subscribe();
  }

  RealtimeChannel subscribeToReport(
      String reportId, void Function(Map<String, dynamic>) onUpdate) {
    return _client
        .channel('report_$reportId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'reports',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: reportId,
          ),
          callback: (payload) => onUpdate(payload.newRecord),
        )
        .subscribe();
  }

  RealtimeChannel subscribeToNotifications(
      void Function(Map<String, dynamic>) onNew) {
    return _client
        .channel('notifications_${currentUser!.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: currentUser!.id,
          ),
          callback: (payload) => onNew(payload.newRecord),
        )
        .subscribe();
  }

  // ── Engineer ─────────────────────────────────────────────────────────────
  Future<List<Report>> getAssignedReports() async {
    final data = await _client
        .from('reports')
        .select('''
          *,
          ai_results (*),
          citizen:profiles!citizen_id (id, full_name, phone),
          upvotes(count)
        ''')
        .eq('assigned_to', currentUser!.id)
        .inFilter('status', ['assigned', 'in_progress'])
        .order('submitted_at', ascending: false);
    return (data as List).map((e) {
      e['upvote_count'] = e['upvotes'];
      return Report.fromJson(e);
    }).toList();
  }

  Future<void> uploadRepairPhoto(String reportId, File photo) async {
    final fileName =
        '$reportId/${DateTime.now().millisecondsSinceEpoch}_repair.jpg';
    await _client.storage
        .from(AppConstants.bucketRepairPhotos)
        .upload(fileName, photo);
  }
}