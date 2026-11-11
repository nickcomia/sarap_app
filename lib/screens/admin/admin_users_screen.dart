import 'package:flutter/material.dart';
import '../../theme.dart';
import '../../services/firebase_service.dart';

String _two(int n) => n.toString().padLeft(2, '0');
String _fmtDate(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

/// User accounts list.
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
      final list = await FirebaseService.adminListDocs('users');
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