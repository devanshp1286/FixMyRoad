import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/constants.dart';
import 'shared/services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  print('[Init] Starting app initialization...');
  print('[Init] Supabase URL: ${AppConstants.supabaseUrl}');
  
  try {
    await Supabase.initialize(
      url: AppConstants.supabaseUrl,
      anonKey: AppConstants.supabaseAnonKey,
    );
    print('[Init] ✓ Supabase initialized');
  } catch (e) {
    print('[Init] ✗ Supabase init failed: $e');
    rethrow;
  }

  try {
    await NotificationService.initializeLocal();
    print('[Init] ✓ Notifications initialized');
  } catch (e) {
    print('[Init] ✗ Notification init failed: $e');
  }

  print('[Init] App starting...');
  runApp(const ProviderScope(child: FixMyRoadApp()));
}