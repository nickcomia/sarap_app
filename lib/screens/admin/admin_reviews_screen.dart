import 'package:cloud_firestore/cloud_firestore.dart';
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

  /// Simple reason box, used for a plain reject (no penalty).
  Future<String?> _askReason({
    required String title,
    required String body,
    required String confirm,
  }) {
    final c = TextEditingController();
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
                hintText: 'Reason (optional)',
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
      body: 'The review will not be shown to other diners. '
          'The user is not penalised.',
      confirm: 'Reject',
    );
    if (reason == null) return;
    final id = r['id'] as String;
    await _run(id, () async {
      await AdminService.rejectReview(id, reason);
      return 'Review rejected.';
    });
  }

  /// How many strikes the reviewer has now (null if it could not be read).
  Future<int?> _strikesOf(String uid) async {
    try {
      final d =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final v = d.data()?['strikes'];
      return v is num ? v.toInt() : 0;
    } catch (_) {
      return null;
    }
  }

  Future<void> _rejectViolation(Map<String, dynamic> r) async {
    final uid = (r['userId'] ?? '').toString();
    if (uid.isEmpty) {
      _toast('This review has no userId, so no strike can be applied.');
      return;
    }
    final strikes = await _strikesOf(uid);
    if (!mounted) return;

    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _ViolationDialog(
        userName: (r['userName'] ?? 'This user').toString(),
        restaurantName: (r['restaurantName'] ?? 'the restaurant').toString(),
        strikes: strikes,
      ),
    );
    if (reason == null) return;
    final id = r['id'] as String;
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
                  label: const Text('Reject (no penalty)'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _rejectViolation(r),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade700),
                  icon: const Icon(Icons.gavel, size: 18),
                  label: const Text('Reject + strike'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Confirmation for "Reject + strike". Shows the user's current strikes,
/// exactly what this strike will do, and the four penalty steps with the
/// current one highlighted. Returns the reason text, or null on cancel.
class _ViolationDialog extends StatefulWidget {
  final String userName;
  final String restaurantName;
  final int? strikes; // current strikes, null when it could not be read
  const _ViolationDialog({
    required this.userName,
    required this.restaurantName,
    required this.strikes,
  });

  @override
  State<_ViolationDialog> createState() => _ViolationDialogState();
}

class _ViolationDialogState extends State<_ViolationDialog> {
  static const _reasons = [
    'Hateful or abusive language',
    'Spam or advertising',
    'Fake or off-topic review',
    'Other',
  ];
  static const _steps = [
    'Warning',
    '3-day review ban',
    '7-day review ban',
    'Account disabled',
  ];

  String _reason = _reasons.first;
  final _note = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  /// The step (1 to 4) this strike will trigger, or null if unknown.
  int? get _next {
    final s = widget.strikes;
    if (s == null) return null;
    final n = s + 1;
    return n > 4 ? 4 : n;
  }

  void _submit() {
    final note = _note.text.trim();
    if (_reason == 'Other' && note.isEmpty) {
      setState(() => _error = 'Please describe the reason');
      return;
    }
    final result = note.isEmpty
        ? _reason
        : (_reason == 'Other' ? note : '$_reason: $note');
    Navigator.of(context).pop(result);
  }

  Widget _ladder(int? current) {
    return Column(
      children: [
        for (var i = 0; i < _steps.length; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: current == i + 1 ? AppColors.chipSelectedBg : null,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: current == i + 1
                      ? AppColors.primary
                      : AppColors.border),
            ),
            child: Row(
              children: [
                Icon(
                  current != null && i + 1 < current
                      ? Icons.check_circle
                      : Icons.circle_outlined,
                  size: 16,
                  color: current == i + 1
                      ? AppColors.primaryDark
                      : AppColors.muted,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Strike ${i + 1}: ${_steps[i]}',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: current == i + 1
                              ? FontWeight.w800
                              : FontWeight.w500,
                          color: current == i + 1
                              ? AppColors.navy
                              : AppColors.muted)),
                ),
                if (current == i + 1)
                  const Text('This review',
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primaryDark)),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strikes;
    final next = _next;

    final String summary;
    if (s == null || next == null) {
      summary = 'Rejecting adds one strike to ${widget.userName}. '
          'The penalty grows with each strike.';
    } else {
      summary = '${widget.userName} has $s ${s == 1 ? 'strike' : 'strikes'} '
          'so far. Rejecting this review adds strike $next: '
          '${_steps[next - 1].toLowerCase()}.';
    }

    return AlertDialog(
      title: const Text('Reject and add a strike'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  'Review of ${widget.restaurantName} by ${widget.userName}. '
                  'The review will be hidden.',
                  style: const TextStyle(
                      fontSize: 12.5, color: AppColors.muted, height: 1.4)),
              const SizedBox(height: 12),
              Text(summary,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.navy,
                      height: 1.4)),
              const SizedBox(height: 14),
              _ladder(next),
              const SizedBox(height: 12),
              const Text('Reason',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: _reason,
                isExpanded: true,
                decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                items: [
                  for (final r in _reasons)
                    DropdownMenuItem(value: r, child: Text(r)),
                ],
                onChanged: (v) => setState(() {
                  _reason = v ?? _reason;
                  _error = null;
                }),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _note,
                maxLines: 2,
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                decoration: InputDecoration(
                  hintText: _reason == 'Other'
                      ? 'Describe the reason'
                      : 'Add a note (optional)',
                  errorText: _error,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red.shade700,
            foregroundColor: Colors.white,
            minimumSize: const Size(0, 44),
          ),
          child: const Text('Reject + add strike'),
        ),
      ],
    );
  }
}