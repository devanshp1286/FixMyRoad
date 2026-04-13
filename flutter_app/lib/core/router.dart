import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/auth/screens/login_screen.dart';
import '../features/auth/screens/register_screen.dart';
import '../features/auth/screens/profile_screen.dart';
import '../features/map/screens/map_screen.dart';
import '../features/reports/screens/report_submit_screen.dart';
import '../features/reports/screens/report_list_screen.dart';
import '../features/reports/screens/report_detail_screen.dart';
import '../features/reports/screens/report_result_screen.dart';
import '../features/notifications/screens/notifications_screen.dart';
import '../features/chatbot/screens/chatbot_screen.dart';
import '../features/engineer/screens/engineer_home_screen.dart';
import '../features/engineer/screens/field_update_screen.dart';
import '../features/admin/screens/admin_home_screen.dart';
import '../shared/screens/splash_screen.dart';
import '../shared/screens/main_shell.dart';
import '../shared/services/supabase_service.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/splash',
    redirect: (context, state) async {
      final session = Supabase.instance.client.auth.currentSession;
      final isAuth  = session != null;
      final loc     = state.matchedLocation;
      final authRoutes = ['/login', '/register', '/splash', '/map'];

      if (!isAuth && !authRoutes.contains(loc)) return '/login';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/login',  builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
      GoRoute(path: '/map',    builder: (_, __) => const MapScreen(publicMode: true)),

      // ── Admin routes ───────────────────────────────────────────────
      GoRoute(path: '/admin', builder: (_, __) => const AdminHomeScreen()),

      // ── Engineer routes ────────────────────────────────────────────
      GoRoute(
        path: '/engineer',
        builder: (_, __) => const EngineerHomeScreen(),
        routes: [
          GoRoute(
            path: 'update/:id',
            builder: (_, state) =>
                FieldUpdateScreen(reportId: state.pathParameters['id']!),
          ),
        ],
      ),

      // ── Citizen shell ──────────────────────────────────────────────
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(
            path: '/home',
            builder: (_, __) => const MapScreen(publicMode: false),
          ),
          GoRoute(
            path: '/submit',
            builder: (_, __) => const ReportSubmitScreen(),
          ),
          GoRoute(
            path: '/reports',
            builder: (_, __) => const ReportListScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, state) =>
                    ReportDetailScreen(reportId: state.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(
            path: '/result/:id',
            builder: (_, state) =>
                ReportResultScreen(reportId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/notifications',
            builder: (_, __) => const NotificationsScreen(),
          ),
          GoRoute(
            path: '/chatbot',
            builder: (_, __) => const ChatbotScreen(),
          ),
          GoRoute(
            path: '/profile',
            builder: (_, __) => const ProfileScreen(),
          ),
        ],
      ),
    ],
  );
});
