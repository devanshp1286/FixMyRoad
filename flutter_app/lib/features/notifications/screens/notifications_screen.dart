import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/models/models.dart';
import '../../../shared/services/supabase_service.dart';
import '../../../shared/widgets/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  List<NotificationModel> _notifications = [];
  bool _loading = true;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _load();
    _channel = ref.read(supabaseServiceProvider).subscribeToNotifications((_) => _load());
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> _load() async {
    final data =
        await ref.read(supabaseServiceProvider).getNotifications();
    if (mounted) setState(() { _notifications = data; _loading = false; });
  }

  Future<void> _markRead(NotificationModel n) async {
    if (n.isRead) return;
    await ref.read(supabaseServiceProvider).markNotificationRead(n.id);
    _load();
    if (n.reportId != null && mounted) {
      context.push('/reports/${n.reportId}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: _loading
          ? const ShimmerList(count: 6)
          : _notifications.isEmpty
              ? const EmptyState(
                  icon: Icons.notifications_none_outlined,
                  title: 'No notifications',
                  subtitle: 'You will be notified when your report status changes.',
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    itemCount: _notifications.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 72),
                    itemBuilder: (_, i) {
                      final n = _notifications[i];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: n.isRead
                              ? theme.colorScheme.surfaceContainerHighest
                              : theme.colorScheme.primaryContainer,
                          child: Icon(
                            Icons.notifications_outlined,
                            color: n.isRead
                                ? theme.colorScheme.onSurfaceVariant
                                : theme.colorScheme.primary,
                            size: 20,
                          ),
                        ),
                        title: Text(n.title,
                            style: TextStyle(
                              fontWeight: n.isRead
                                  ? FontWeight.w400
                                  : FontWeight.w600,
                              fontSize: 14,
                            )),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(n.body,
                                style: const TextStyle(fontSize: 13)),
                            const SizedBox(height: 2),
                            Text(
                              _timeAgo(n.createdAt),
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        trailing: n.isRead
                            ? null
                            : Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                        onTap: () => _markRead(n),
                      );
                    },
                  ),
                ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays > 0)    return '${diff.inDays}d ago';
    if (diff.inHours > 0)   return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'Just now';
  }
}