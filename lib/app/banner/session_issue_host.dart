import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/network/network_status.dart';
import '../../core/session/session_health.dart';
import '../../core/session/session_store.dart';
import '../../core/theme/vibe_colors.dart';
import '../../core/utils/scale.dart';
import '../api/authscreen/auth_queries.dart';
import '../callscreen/helper/call_controller.dart';
import '../component/c_alert.dart';
import '../component/c_button.dart';
import '../component/c_text.dart';
import '../component/pressable.dart';

/// "Server unreachable" over the whole app (mounted at the root) while the
/// session can't be refreshed ([SessionHealth]). The user stays signed in:
/// Retry tries again (and so does the app, every few seconds and when the
/// connection comes back). Only when the server refused the session is
/// "Log in again" offered, and only the user taps it.
///
/// Never covers a call: it steps aside while one is on screen.
class SessionIssueHost extends StatelessWidget {
  const SessionIssueHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      child,
      ListenableBuilder(
        listenable: Listenable.merge([
          SessionHealth.instance,
          CallController.instance.session,
        ]),
        builder: (context, _) {
          final issue = SessionHealth.instance.value;
          final show =
              issue != null &&
              SessionStore.instance.value.isAuthenticated &&
              !CallController.instance.isOnCall;
          return show
              ? Positioned.fill(child: _IssuePanel(issue: issue))
              : const SizedBox.shrink();
        },
      ),
    ],
  );
}

class _IssuePanel extends StatefulWidget {
  const _IssuePanel({required this.issue});
  final SessionIssue issue;

  @override
  State<_IssuePanel> createState() => _IssuePanelState();
}

class _IssuePanelState extends State<_IssuePanel> {
  /// While the server is down, try again on its own this often.
  static const autoRetry = Duration(seconds: 20);

  bool _busy = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(autoRetry, (_) => _retry(quiet: true));
    NetworkStatus.instance.addListener(_onNetwork);
  }

  void _onNetwork() {
    if (NetworkStatus.instance.value) _retry(quiet: true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    NetworkStatus.instance.removeListener(_onNetwork);
    super.dispose();
  }

  Future<void> _retry({bool quiet = false}) async {
    // A refused session gets no automatic retries: only the user's.
    if (_busy || (quiet && widget.issue == SessionIssue.rejected)) return;
    if (!quiet) setState(() => _busy = true);
    await SessionHealth.instance.retry();
    if (mounted && !quiet) setState(() => _busy = false);
  }

  Future<void> _logInAgain() async {
    final ok = await CAlert.confirm(
      title: 'resources:logout.title',
      message: 'resources:logout.message',
      confirmLabel: 'resources:logout.confirm',
      variant: CAlertVariant.error,
    );
    if (ok) await logout();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final refused = widget.issue == SessionIssue.rejected;
    final prefix = refused ? 'rejected' : 'unreachable';
    return Material(
      color: c.modalBackdrop,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 24.ms),
            child: Container(
              padding: EdgeInsets.fromLTRB(22.ms, 26.ms, 22.ms, 18.ms),
              decoration: BoxDecoration(
                color: c.modalCard,
                borderRadius: BorderRadius.circular(24.ms),
                border: Border.all(color: c.modalBorder),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 60.ms,
                    height: 60.ms,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: c.accentA(0.14),
                    ),
                    child: Icon(
                      refused ? LucideIcons.shieldAlert : LucideIcons.cloudOff,
                      size: 28.ms,
                      color: c.accent,
                    ),
                  ),
                  SizedBox(height: 16.ms),
                  CText(
                    'session_issue.${prefix}_title',
                    size: 19,
                    weight: FontWeight.w800,
                    color: c.modalText,
                    align: TextAlign.center,
                  ),
                  SizedBox(height: 8.ms),
                  CText(
                    'session_issue.${prefix}_body',
                    size: 14,
                    height: 20,
                    weight: FontWeight.w500,
                    color: c.modalMuted,
                    align: TextAlign.center,
                  ),
                  SizedBox(height: 20.ms),
                  CButton(
                    title: 'session_issue.retry',
                    loading: _busy,
                    showArrow: false,
                    onPressed: _retry,
                  ),
                  if (refused) ...[
                    SizedBox(height: 6.ms),
                    Pressable(
                      onPressed: _logInAgain,
                      hitPadding: EdgeInsets.all(6.ms),
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 10.ms),
                        child: CText(
                          'session_issue.log_in_again',
                          size: 14,
                          weight: FontWeight.w700,
                          color: c.modalMuted,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
