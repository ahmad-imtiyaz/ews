import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../screens/notifications_screen.dart';
import '../services/notification_inbox.dart';

class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key, required this.inbox});

  final NotificationInbox inbox;

  void _open(BuildContext context) {
    inbox.markRead();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            NotificationsScreen(entries: inbox.entries, service: inbox.service),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: inbox,
      builder: (context, _) {
        final unread = inbox.unread;
        return Tooltip(
          message: 'Notifikasi',
          child: Semantics(
            label: unread > 0
                ? 'Notifikasi, $unread belum dibaca'
                : 'Notifikasi',
            excludeSemantics: true,
            child: OutlinedButton(
              onPressed: () => _open(context),
              style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
              child: Badge.count(
                count: unread,
                isLabelVisible: unread > 0,
                backgroundColor: AppColors.ink,
                textColor: Colors.white,
                child: const Icon(Icons.notifications_none, size: 22),
              ),
            ),
          ),
        );
      },
    );
  }
}
