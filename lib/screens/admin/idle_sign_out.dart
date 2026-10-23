import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/admin_service.dart';

/// Signs the admin out after [timeout] with no pointer activity
/// (tap, click, drag or mouse-wheel scroll). AdminGate listens to the auth
/// state, so signing out here sends the admin back to the login page.
class IdleSignOut extends StatefulWidget {
  final Widget child;
  final Duration timeout;
  const IdleSignOut({
    super.key,
    required this.child,
    this.timeout = const Duration(minutes: 15),
  });

  @override
  State<IdleSignOut> createState() => _IdleSignOutState();
}

class _IdleSignOutState extends State<IdleSignOut> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _reset();
  }

  void _reset() {
    _timer?.cancel();
    _timer = Timer(widget.timeout, () => AdminService.signOut());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _reset(),
      onPointerMove: (_) => _reset(),
      onPointerSignal: (_) => _reset(), // mouse wheel / scrolling
      child: widget.child,
    );
  }
}