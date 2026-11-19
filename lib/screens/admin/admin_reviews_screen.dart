import 'package:flutter/material.dart';
import '../../services/admin_service.dart';
import '../../theme.dart';

String _two(int n) => n.toString().padLeft(2, '0');
String _fmt(DateTime d) =>
    '${d.year}-${_two(d.month)}-${_two(d.day)} ${_two(d.hour)}:${_two(d.minute)}';

/// Pending reviews waiting for an admin decision.
class AdminReviewsScreen extends StatefulWidget {
  const AdminReviewsScreen({super.key});

  @override
  State<AdminReviewsScreen> createState() => _AdminReviewsScreenState();
}

class _AdminReviewsScreenState extends State<AdminReviewsScreen> {
  List<Map<String, dynamic>>? _reviews;
  String? _error;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
    });
    try {
      final list = await AdminService.fetchPendingReviews();
      if (mounted) setState(() => _reviews = list);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Runs one admin action on a review and removes it from the queue.
  Future<void> _run(String id, Future<String?> Function() action) async {
    setState(() => _busy.add(id));
    try {
      final msg = await action();
      if (!mounted) return;
      setState(() {
        _reviews?.removeWhere((r) => r['id'] == id);
      });
      if (msg != null) _toast(msg);
    } catch (e) {
      if (mounted) _toast('Failed: $e');
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Future<String?> _askReason({
    required String title,
    required String body,
    required String confirm,
    String initial = '',
  }) {
    final c = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(body, style: const TextStyle(fontSize: 13, height: 1.4)),
            const SizedBox(height: 12),
            TextField(
              controller: c,
              maxLines: 2,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Reason',
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
              child: Text(confirm)),
        ],
      ),
    );
  }

  Future<void> _approve(Map<String, dynamic> r) {
    final id = r['id'] as String;
    return _run(id, () async {
      await AdminService.approveReview(id);
      return 'Review approved.';
    });
  }

  Future<void> _reject(Map<String, dynamic> r) async {
    final reason = await _askReason(
      title: 'Reject this review?',
      body: 'The review will not be shown. The user is not penalised.',
      confirm: 'Reject',
    );
    if (reason == null) return;
    final id = r['id'] as String;
    await _run(id, () async {
      await AdminService.rejectReview(id, reason);
      return 'Review rejected.';
    });
  }

  Future<void> _rejectViolation(Map<String, dynamic> r) async {
    final reason = await _askReason(
      title: 'Reject for violation?',
      body: 'The review is rejected and ${r['userName'] ?? 'the user'} '
          'gets a strike: warning, then a 3-day ban, a 7-day ban, and '
          'finally the account is disabled.',
      confirm: 'Reject + strike',
      initial: 'Hateful or abusive language',
    );
    if (reason == null) return;
    final id = r['id'] as String;
    final uid = (r['userId'] ?? '').toString();
    if (uid.isEmpty) {
      _toast('This review has no userId, so no strike can be applied.');
      return;
    }
    await _run(id, () {
      return AdminService.rejectForViolation(
          reviewId: id, userId: uid, reason: reason);
    });
  }

  Widget _stars(int rating) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 5; i++)
            Icon(i < rating ? Icons.star : Icons.star_border,
                size: 16, color: Colors.amber.shade600),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Review queue'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Could not load reviews: $_error',
              textAlign: TextAlign.center),
        ),
      );
    }
    final reviews = _reviews;
    if (reviews == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('${reviews.length} waiting for approval',
                    style:
                        const TextStyle(color: AppColors.muted, fontSize: 12.5)),
              ),
            ),
            Expanded(
              child: reviews.isEmpty
                  ? const Center(
                      child: Text('Nothing to review. All caught up!',
                          style: TextStyle(color: AppColors.muted)))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      itemCount: reviews.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, i) => _card(reviews[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(Map<String, dynamic> r) {
    final id = r['id'] as String;
    final busy = _busy.contains(id);
    final rating = (r['rating'] is num) ? (r['rating'] as num).toInt() : 0;
    final dish = (r['dish'] ?? '').toString();
    final created = r['createdAt'];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text((r['restaurantName'] ?? 'Restaurant').toString(),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                        color: AppColors.navy)),
              ),
              if (created is DateTime)
                Text(_fmt(created),
                    style:
                        const TextStyle(color: AppColors.muted, fontSize: 11.5)),
            ],
          ),
          const SizedBox(height: 4),
          Text('by ${(r['userName'] ?? 'SARAP user')}',
              style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
          const SizedBox(height: 8),
          _stars(rating),
          if (dish.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Ate: $dish',
                style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
          ],
          const SizedBox(height: 8),
          Text((r['text'] ?? '').toString(),
              style: const TextStyle(
                  color: AppColors.navy, fontSize: 14, height: 1.4)),
          const SizedBox(height: 14),
          if (busy)
            const Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _approve(r),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Approve'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _reject(r),
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Reject'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _rejectViolation(r),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade700),
                  icon: const Icon(Icons.gavel, size: 18),
                  label: const Text('Reject for violation'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}