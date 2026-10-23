import 'package:flutter/material.dart';
import '../../theme.dart';
import '../../services/firebase_service.dart';

/// Firestore collection that holds user reports/feedback. Change this if
/// report_service.dart writes to a different collection name.
const String _kReportsCollection = 'reports';

String _two(int n) => n.toString().padLeft(2, '0');
String _fmtDate(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

/// User accounts + moderation of reports/feedback.
class AdminUsersScreen extends StatelessWidget {
  const AdminUsersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Users & moderation'),
          bottom: const TabBar(
            tabs: [Tab(text: 'Users'), Tab(text: 'Reports & feedback')],
          ),
        ),
        body: const TabBarView(children: [_UsersTab(), _ReportsTab()]),
      ),
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
      final list = await FirebaseService.adminListDocs('users');
      if (mounted) setState(() => _users = list);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

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
                      subtitle: Text(
                          joined is DateTime ? '$email • Joined ${_fmtDate(joined)}' : email),
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

class _ReportsTab extends StatefulWidget {
  const _ReportsTab();

  @override
  State<_ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<_ReportsTab> {
  List<Map<String, dynamic>>? _reports;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await FirebaseService.adminListDocs(_kReportsCollection);
      if (mounted) setState(() => _reports = list);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _resolve(Map<String, dynamic> r) async {
    try {
      await FirebaseService.adminSaveDoc(
          _kReportsCollection, r['id'] as String, {'resolved': true});
      _load();
    } catch (e) {
      _snack('Could not update: $e');
    }
  }

  Future<void> _delete(Map<String, dynamic> r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this report?'),
        content: const Text('It will be permanently removed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await FirebaseService.adminDeleteDoc(_kReportsCollection, r['id'] as String);
      _load();
    } catch (e) {
      _snack('Could not delete: $e');
    }
  }

  String _show(dynamic v) => v is DateTime ? _fmtDate(v) : v.toString();

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Could not load reports: $_error', textAlign: TextAlign.center),
        ),
      );
    }
    final reports = _reports;
    if (reports == null) return const Center(child: CircularProgressIndicator());
    if (reports.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'No reports or feedback yet.\n'
            'Looking in the "$_kReportsCollection" collection.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted),
          ),
        ),
      );
    }

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: ListView.separated(
          padding: const EdgeInsets.all(20),
          itemCount: reports.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final r = reports[i];
            final resolved = r['resolved'] == true;
            final fields = r.entries.where((e) => e.key != 'id' && e.value != null);
            return Opacity(
              opacity: resolved ? 0.6 : 1,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final e in fields)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('${e.key}: ${_show(e.value)}',
                            style: const TextStyle(fontSize: 13)),
                      ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (!resolved)
                          TextButton(
                              onPressed: () => _resolve(r),
                              child: const Text('Mark resolved')),
                        TextButton(
                            onPressed: () => _delete(r), child: const Text('Delete')),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}