import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../services/firebase_service.dart';

/// Admin screen for account appeals. Lists what users sent from the
/// "account disabled" screen and lets an administrator decide each one.
///
/// Each card shows the CURRENT state of the user's account, and the actions
/// follow from it:
///  - account still disabled + appeal pending: Approve (re-activates the
///    account) or Reject.
///  - account already active + appeal pending (for example it was
///    re-enabled from the Users page): Close appeal, which marks the appeal
///    as approved without touching the account.
///  - account still disabled + appeal already decided: Re-enable account.
///
/// Approving re-activates the account (status = active, ban cleared) and
/// leaves the user with [_strikesAfterApproval] strikes, so one more
/// violation disables the account again. Every decision is also written to
/// the `moderationActions` audit trail.
///
/// This widget is content only (no Scaffold), so it can sit inside the
/// admin console's page area like the other admin screens.
class AdminAppealsScreen extends StatefulWidget {
  const AdminAppealsScreen({super.key});

  @override
  State<AdminAppealsScreen> createState() => _AdminAppealsScreenState();
}

class _AdminAppealsScreenState extends State<AdminAppealsScreen> {
  /// Strikes a user keeps after an approved appeal (last chance).
  static const _strikesAfterApproval = 3;

  List<Map<String, dynamic>>? _appeals;
  Map<String, Map<String, dynamic>> _users = {};
  String? _error;
  bool _pendingOnly = true;
  String? _busyId;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await FirebaseService.adminListDocs('appeals');

      // Current account state of every user, so each card can show whether
      // the account is still disabled.
      var users = <String, Map<String, dynamic>>{};
      try {
        final u = await FirebaseService.adminListDocs('users');
        users = {for (final x in u) x['id'].toString(): x};
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _appeals = list;
        _users = users;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _appeals = [];
        _error = 'Could not load appeals: $e';
      });
    }
  }

  String _date(dynamic v) {
    if (v is! DateTime) return '';
    final h = v.hour % 12 == 0 ? 12 : v.hour % 12;
    final m = v.minute.toString().padLeft(2, '0');
    final ap = v.hour >= 12 ? 'PM' : 'AM';
    return '${_months[v.month - 1]} ${v.day}, ${v.year} $h:$m $ap';
  }

  String _uidOf(Map<String, dynamic> a) =>
      (a['userId'] ?? a['id']).toString();

  /// 'disabled', 'active', or 'unknown' (user document not found).
  String _accountState(Map<String, dynamic> a) {
    final u = _users[_uidOf(a)];
    if (u == null) return 'unknown';
    return u['status'] == 'disabled' ? 'disabled' : 'active';
  }

  Future<void> _audit(String uid, String action, dynamic reason) async {
    try {
      final reviewer = FirebaseAuth.instance.currentUser?.email ?? 'admin';
      await FirebaseService.adminSaveDoc('moderationActions', null, {
        'userId': uid,
        'action': action,
        'reason': reason,
        'source': 'admin_appeal',
        'by': reviewer,
      });
    } catch (_) {}
  }

  Future<void> _decide(Map<String, dynamic> a, {required bool approve}) async {
    final appealId = a['id'].toString();
    final uid = _uidOf(a);
    final name = (a['name'] ?? 'this user').toString();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(approve ? 'Approve appeal?' : 'Reject appeal?'),
        content: Text(approve
            ? '$name will be able to use SARAP again. They keep '
                '$_strikesAfterApproval strikes, so one more violation '
                'disables the account again.'
            : 'The account of $name stays disabled. They can send a new '
                'appeal if they have new information.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(approve ? 'Approve' : 'Reject'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busyId = appealId);
    try {
      final reviewer = FirebaseAuth.instance.currentUser?.email ?? 'admin';

      // Re-activate the account first: if this fails, the appeal stays
      // as it was and nothing looks approved by mistake.
      if (approve) {
        await FirebaseService.adminSaveDoc('users', uid, {
          'status': 'active',
          'disabledReason': null,
          'bannedUntil': null,
          'strikes': _strikesAfterApproval,
        });
      }

      await FirebaseService.adminSaveDoc('appeals', appealId, {
        'status': approve ? 'approved' : 'rejected',
        'reviewedBy': reviewer,
        'reviewedAt': DateTime.now(),
      });

      await _audit(uid, approve ? 'appeal_approved' : 'appeal_rejected',
          a['message']);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(approve
            ? 'Appeal approved. Account re-activated.'
            : 'Appeal rejected.'),
      ));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save the decision: $e')),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  /// The account is already active (re-enabled elsewhere): just close the
  /// appeal as approved, without changing the account.
  Future<void> _closeAppeal(Map<String, dynamic> a) async {
    final appealId = a['id'].toString();
    final uid = _uidOf(a);
    final name = (a['name'] ?? 'this user').toString();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Close this appeal?'),
        content: Text('The account of $name is already active. The appeal '
            'will be marked as approved and removed from the pending list. '
            'The account itself is not changed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Close appeal'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busyId = appealId);
    try {
      final reviewer = FirebaseAuth.instance.currentUser?.email ?? 'admin';
      await FirebaseService.adminSaveDoc('appeals', appealId, {
        'status': 'approved',
        'reviewedBy': reviewer,
        'reviewedAt': DateTime.now(),
        'note': 'Account was already active when the appeal was closed.',
      });
      await _audit(uid, 'appeal_closed', 'Account already active');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Appeal closed.')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not close the appeal: $e')),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_appeals == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
    }

    final all = _appeals!;
    final pendingCount = all.where((a) => a['status'] == 'pending').length;
    final shown = _pendingOnly
        ? all.where((a) => a['status'] == 'pending').toList()
        : all;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Appeals', style: theme.textTheme.titleLarge),
              ),
              FilterChip(
                label: Text('Pending only ($pendingCount)'),
                selected: _pendingOnly,
                onSelected: (v) => setState(() => _pendingOnly = v),
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: _load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!, style: TextStyle(color: Colors.red.shade700)),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: shown.isEmpty
                ? Center(
                    child: Text(
                      _pendingOnly
                          ? 'No appeals waiting for review.'
                          : 'No appeals yet.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  )
                : ListView.separated(
                    itemCount: shown.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, i) => _appealCard(context, shown[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text,
            style: TextStyle(
                color: color, fontWeight: FontWeight.w700, fontSize: 11.5)),
      );

  Widget _appealCard(BuildContext context, Map<String, dynamic> a) {
    final theme = Theme.of(context);
    final status = (a['status'] ?? 'pending').toString();
    final busy = _busyId == a['id'];
    final isPending = status == 'pending';
    final account = _accountState(a);

    Color statusColor;
    switch (status) {
      case 'approved':
        statusColor = Colors.green.shade700;
        break;
      case 'rejected':
        statusColor = Colors.red.shade700;
        break;
      default:
        statusColor = Colors.orange.shade800;
    }

    Color accountColor;
    String accountLabel;
    switch (account) {
      case 'disabled':
        accountColor = Colors.red.shade700;
        accountLabel = 'ACCOUNT DISABLED';
        break;
      case 'active':
        accountColor = Colors.green.shade700;
        accountLabel = 'ACCOUNT ACTIVE';
        break;
      default:
        accountColor = Colors.grey.shade700;
        accountLabel = 'ACCOUNT NOT FOUND';
    }

    final approveStyle = FilledButton.styleFrom(
      backgroundColor: Colors.green.shade700,
      foregroundColor: Colors.white,
    );
    final rejectStyle = OutlinedButton.styleFrom(
      foregroundColor: Colors.red.shade700,
      side: BorderSide(color: Colors.red.shade300),
    );

    Widget spinner() => const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white));

    Widget? actions;
    if (isPending && account == 'active') {
      actions = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This account is already active, so there is nothing left to '
            'approve. Close the appeal to remove it from the pending list.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            style: approveStyle,
            onPressed: busy ? null : () => _closeAppeal(a),
            icon: busy ? spinner() : const Icon(Icons.done_all),
            label: const Text('Close appeal'),
          ),
        ],
      );
    } else if (isPending) {
      actions = Wrap(
        spacing: 10,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            style: approveStyle,
            onPressed: busy ? null : () => _decide(a, approve: true),
            icon: busy ? spinner() : const Icon(Icons.check),
            label: const Text('Approve & re-enable'),
          ),
          OutlinedButton.icon(
            style: rejectStyle,
            onPressed: busy ? null : () => _decide(a, approve: false),
            icon: const Icon(Icons.close),
            label: const Text('Reject'),
          ),
        ],
      );
    } else if (account == 'disabled') {
      actions = FilledButton.icon(
        style: approveStyle,
        onPressed: busy ? null : () => _decide(a, approve: true),
        icon: busy ? spinner() : const Icon(Icons.lock_open),
        label: const Text('Re-enable account'),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text((a['name'] ?? 'Unknown user').toString(),
                      style: theme.textTheme.titleMedium),
                ),
                _chip(accountLabel, accountColor),
                const SizedBox(width: 8),
                _chip(status.toUpperCase(), statusColor),
              ],
            ),
            const SizedBox(height: 2),
            Text('${a['email'] ?? ''}  •  ${_date(a['createdAt'])}',
                style: theme.textTheme.bodySmall),
            if ((a['disabledReason'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('Disabled because:',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              Text(a['disabledReason'].toString()),
            ],
            const SizedBox(height: 10),
            Text('Appeal message:',
                style: theme.textTheme.labelMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            Text((a['message'] ?? '').toString()),
            if (!isPending && a['reviewedBy'] != null) ...[
              const SizedBox(height: 8),
              Text('Reviewed by ${a['reviewedBy']}  •  ${_date(a['reviewedAt'])}',
                  style: theme.textTheme.bodySmall),
            ],
            if (actions != null) ...[
              const SizedBox(height: 14),
              actions,
            ],
          ],
        ),
      ),
    );
  }
}