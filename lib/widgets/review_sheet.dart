import 'package:flutter/material.dart';
import '../app_state.dart';
import '../models.dart';
import '../screens/disabled_account_screen.dart';
import '../services/content_filter.dart';
import '../services/firebase_service.dart';
import '../theme.dart';

/// Bottom sheet for writing or editing a review. Pops with `true` once it
/// was saved. Pass [existing] to edit the user's current review: the form
/// opens filled in, and saving sends it for approval again.
class ReviewSheet extends StatefulWidget {
  final Restaurant restaurant;
  final Review? existing;
  const ReviewSheet({super.key, required this.restaurant, this.existing});

  @override
  State<ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<ReviewSheet> {
  late final TextEditingController _text;
  late final TextEditingController _dish;
  late int _rating;
  bool _busy = false;
  String? _error;

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _text = TextEditingController(text: e?.text ?? '');
    _dish = TextEditingController(text: e?.dish ?? '');
    _rating = e?.rating ?? 0;
  }

  @override
  void dispose() {
    _text.dispose();
    _dish.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final app = AppState.instance;
    final text = _text.text.trim();
    final dish = _dish.text.trim();

    if (_rating == 0) {
      setState(() => _error = 'Tap a star to rate this place.');
      return;
    }
    if (text.length < 10) {
      setState(() => _error = 'Please write at least 10 characters.');
      return;
    }
    if (app.isBanned) {
      setState(() => _error = 'You cannot post reviews right now.');
      return;
    }

    // 1) Word filter: a hit means a strike and the review is NOT saved.
    //    This applies to edits too.
    final hit = ContentFilter.check('$text $dish');
    if (hit.blocked) {
      setState(() {
        _busy = true;
        _error = null;
      });
      try {
        final outcome = await FirebaseService.recordViolation(
            reason: 'Hateful or abusive language in a review');
        app.applyViolation(outcome);
        if (!mounted) return;
        if (outcome.disabled) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const DisabledAccountScreen()),
            (_) => false,
          );
          return;
        }
        setState(() {
          _busy = false;
          _error = outcome.message;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _error = 'Your review has language that is not allowed. '
              'Please remove it and try again.';
        });
      }
      return;
    }

    // 2) Clean: save as pending for the admin to approve.
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await FirebaseService.submitReview(
        restaurant: widget.restaurant,
        userName: app.profile.name,
        rating: _rating,
        text: text,
        dish: dish,
        reviewId: widget.existing?.id,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error =
              'Could not send your review. Check your connection and try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                _editing
                    ? 'Edit your review of ${widget.restaurant.name}'
                    : 'Review ${widget.restaurant.name}',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            Row(
              children: [
                for (var i = 1; i <= 5; i++)
                  IconButton(
                    onPressed: _busy ? null : () => setState(() => _rating = i),
                    icon: Icon(
                      i <= _rating ? Icons.star : Icons.star_border,
                      color: Colors.amber.shade600,
                      size: 32,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _dish,
              enabled: !_busy,
              maxLength: 60,
              decoration: const InputDecoration(
                labelText: 'What did you eat? (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _text,
              enabled: !_busy,
              maxLength: 500,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'How were the food and the place?',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _editing
                  ? 'After you save, your review is checked again before it '
                      'is shown. Hateful or abusive language leads to a '
                      'warning, then temporary bans, and can end with your '
                      'account being disabled.'
                  : 'Reviews are checked before they are posted. Hateful or '
                      'abusive language leads to a warning, then temporary '
                      'bans, and can end with your account being disabled.',
              style: TextStyle(color: colors.muted, fontSize: 12, height: 1.4),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!,
                  style: TextStyle(
                      color: Colors.red.shade700,
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(_editing ? 'Save changes' : 'Submit review'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}