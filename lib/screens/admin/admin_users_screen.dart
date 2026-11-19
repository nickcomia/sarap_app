import 'package:flutter/material.dart';
import '../../theme.dart';
import '../../services/admin_service.dart';

String _two(int n) => n.toString().padLeft(2, '0');
String _fmtDate(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

/// User accounts list with moderation actions.
class AdminUsersScreen extends StatelessWidget {
  const AdminUsersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Users')),
      body: const _UsersTab(),
    );
  }
}

class _UsersTab extends StatefulWidget {
  const _UsersTab();

  @override
  State<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<_UsersTab> {
  List<Map<String, dynamic>>? _users;
  String? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await AdminService.listUsers();
      if (mounted) {
        setState(() {
          _users = list;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    try {
      await action();
      if (!mounted) return;
      _toast(done);
      await _load();
    } catch (e) {
      if (mounted) _toast('Failed: $e');
    }
  }

  Future<void> _ban(Map<String, dynamic> u) async {
    final days = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Ban from posting reviews'),
        children: [
          for (final d in const [1, 3, 7, 14, 30])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, d),
              child: Text('$d day${d == 1 ? '' : 's'}'),
            ),
        ],
      ),
    );
    if (days == null) return;
    await _run(() => AdminService.banUser(u['id'] as String, days),
        'User banned for $days day${days == 1 ? '' : 's'}.');
  }

  Future<void> _disable(Map<String, dynamic> u) async {
    final c = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disable this account?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                'The user will be fully blocked and will see the disabled '
                'screen the next time they open the app.',
                style: TextStyle(fontSize: 13, height: 1.4)),
            const SizedBox(height: 12),
            TextField(
              controller: c,
              maxLines: 2,
              decoration: const InputDecoration(
                hintText: 'Reason shown to the user (optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: const Text('Disable')),
        ],
      ),
    );
    if (reason == null) return;
    await _run(() => AdminService.disableUser(u['id'] as String, reason),
        'Account disabled.');
  }

  Future<void> _restore(Map<String, dynamic> u, bool disabled) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(disabled ? 'Re-enable this account?' : 'Lift the ban?'),
        content: const Text(
            'Strikes will be reset to 0, so the next violation starts again '
            'at a warning.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirm')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() => AdminService.restoreUser(u['id'] as String),
        disabled ? 'Account re-enabled.' : 'Ban lifted.');
  }

  Widget _badge(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text,
            style: TextStyle(
                color: color, fontSize: 11.5, fontWeight: FontWeight.w700)),
      );

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Could not load users: $_error', textAlign: TextAlign.center),
        ),
      );
    }
    final users = _users;
    if (users == null) return const Center(child: CircularProgressIndicator());

    final q = _query.toLowerCase();
    final shown = users
        .where((u) => '${u['name']} ${u['email']}'.toLowerCase().contains(q))
        .toList();

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: const InputDecoration(
                  hintText: 'Search by name or email',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('${shown.length} of ${users.length} users',
                    style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                itemCount: shown.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final u = shown[i];
                  final name = (u['name'] ?? '').toString();
                  final email = (u['email'] ?? '').toString();
                  final joined = u['createdAt'];
                  final strikes =
                      u['strikes'] is num ? (u['strikes'] as num).toInt() : 0;
                  final until = u['bannedUntil'];
                  final banned = until is DateTime && until.isAfter(DateTime.now());
                  final disabled = u['status'] == 'disabled';

                  return Container(
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppColors.chipSelectedBg,
                        child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
                            style: const TextStyle(color: AppColors.primaryDark)),
                      ),
                      title: Text(name.isEmpty ? '(no name)' : name,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(joined is DateTime
                              ? '$email • Joined ${_fmtDate(joined)}'
                              : email),
                          if (disabled || banned || strikes > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  if (disabled)
                                    _badge('Disabled', Colors.red.shade700),
                                  if (banned)
                                    _badge('Banned until ${_fmtDate(until)}',
                                        Colors.orange.shade800),
                                  if (strikes > 0)
                                    _badge('$strikes strike${strikes == 1 ? '' : 's'}',
                                        Colors.amber.shade900),
                                ],
                              ),
                            ),
                        ],
                      ),
                      trailing: PopupMenuButton<String>(
                        tooltip: 'Moderation actions',
                        onSelected: (v) {
                          switch (v) {
                            case 'ban':
                              _ban(u);
                              break;
                            case 'disable':
                              _disable(u);
                              break;
                            case 'restore':
                              _restore(u, disabled);
                              break;
                          }
                        },
                        itemBuilder: (_) => [
                          if (!disabled)
                            const PopupMenuItem(
                                value: 'ban', child: Text('Ban from reviews…')),
                          if (!disabled)
                            const PopupMenuItem(
                                value: 'disable', child: Text('Disable account…')),
                          if (disabled)
                            const PopupMenuItem(
                                value: 'restore', child: Text('Re-enable account')),
                          if (!disabled && (banned || strikes > 0))
                            const PopupMenuItem(
                                value: 'restore',
                                child: Text('Lift ban & reset strikes')),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}