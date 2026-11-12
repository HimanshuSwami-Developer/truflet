import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/network/json.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/repositories/notification_repository.dart';
import '../cubit/notifications_cubit.dart';

const _kind = {
  'booking': (LucideIcons.calendar, C.mint, C.green700),
  'squad': (LucideIcons.users, C.blueSoft, C.blue),
  'tournament': (LucideIcons.trophy, C.amberSoft, C.amber),
  'offer': (LucideIcons.tag, C.limeSoft, C.green700),
  'system': (LucideIcons.bell, C.chip, C.muted),
};

/// Bell on Explore → notifications list
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (c) => NotificationsCubit(repository: c.read<NotificationRepository>())..load(),
    child: const _NotificationsView(),
  );
}

class _NotificationsView extends StatelessWidget {
  const _NotificationsView();

  String _ago(String iso) {
    final d = DateTime.now().difference(DateTime.parse(iso).toLocal());
    if (d.inMinutes < 1) return 'Just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) return '${d.inHours} hr ago';
    return '${d.inDays} d ago';
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(20, top + 8, 20, 12),
            child: Row(
              children: [
                const BackSquare(),
                const SizedBox(width: 12),
                Text('Notifications', style: d(20)),
              ],
            ),
          ),
          Expanded(
            child: DataBuilder<NotificationsCubit, Json>(
              builder: (context, r) {
                final items = asList(r['items']);
                if (items.isEmpty) {
                  return Center(
                    child: Text("You're all caught up.", style: t(14, c: C.muted)),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final n = items[i];
                    final k = _kind[n['kind']] ?? _kind['system']!;
                    return CardBox(
                      padding: const EdgeInsets.all(14),
                      radius: 18,
                      border: n['is_read'] == true ? null : Border.all(color: C.brand.withValues(alpha: 0.35)),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(color: k.$2, borderRadius: BorderRadius.circular(12)),
                            child: Icon(k.$1, size: 18, color: k.$3),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(n['title'], style: t(14, w: FontWeight.w700)),
                                if ((n['body'] ?? '').toString().isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(n['body'], style: t(13, c: C.muted, h: 1.4)),
                                ],
                                const SizedBox(height: 4),
                                Text(_ago(n['created_at']), style: t(11, c: C.muted)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
