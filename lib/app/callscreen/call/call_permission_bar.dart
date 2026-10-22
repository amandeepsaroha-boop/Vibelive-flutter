import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/scale.dart';
import '../../component/c_text.dart';
import '../../component/pressable.dart';
import 'helper/call_permission_state.dart';

/// RN `CallPermissionWarning` (dark): a self-gating bar, visible ONLY when
/// the mic (or, with [needsCamera], the camera) is denied or blocked. While
/// checking, when granted and when unknown it draws nothing, so it can never
/// flash or lie. Re-reads on app resume (twice: iOS can report the old
/// status for a moment after Settings).
class CallPermissionBar extends StatefulWidget {
  const CallPermissionBar({
    super.key,
    required this.needsCamera,
    this.floating = false,
  });

  final bool needsCamera;

  /// Absolutely positioned by the screen (no side margins).
  final bool floating;

  /// RN `SETTLE_RECHECK_MS` / `UNDETERMINED_GRACE_MS`.
  static const settleRecheck = Duration(milliseconds: 600);
  static const undeterminedGrace = Duration(milliseconds: 2500);

  @override
  State<CallPermissionBar> createState() => _CallPermissionBarState();
}

class _CallPermissionBarState extends State<CallPermissionBar> {
  /// Null while the first read is pending.
  CallPermissionState? _state;
  bool _firstRead = true;
  Timer? _settle;
  Timer? _grace;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _checkWithSettle);
    _check();
  }

  @override
  void didUpdateWidget(CallPermissionBar old) {
    super.didUpdateWidget(old);
    if (old.needsCamera != widget.needsCamera) _check();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _settle?.cancel();
    _grace?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    final read = await checkCallPermissions(needsCamera: widget.needsCamera);
    if (!mounted) return;
    // A never-asked permission: the app prompts for it right after login,
    // so the first read waits for that prompt instead of flashing a bar.
    if (read.undetermined && _firstRead) {
      _firstRead = false;
      _grace?.cancel();
      _grace = Timer(CallPermissionBar.undeterminedGrace, _check);
      return;
    }
    _firstRead = false;
    _set(read.state);
  }

  void _checkWithSettle() {
    _check();
    _settle?.cancel();
    _settle = Timer(CallPermissionBar.settleRecheck, _check);
  }

  void _set(CallPermissionState s) {
    if (mounted && s != _state) setState(() => _state = s);
  }

  Future<void> _onTap() async {
    if (_state == CallPermissionState.blocked) {
      await openCallSettings();
      return;
    }
    final read = await requestCallPermissions(needsCamera: widget.needsCamera);
    _set(read.state);
    // A prompt that came back blocked would leave a dead bar: Settings now.
    if (read.state == CallPermissionState.blocked) await openCallSettings();
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    if (state != CallPermissionState.denied &&
        state != CallPermissionState.blocked) {
      return const SizedBox.shrink();
    }
    final blocked = state == CallPermissionState.blocked;
    // Fixed accents (RN: the brand accent turns purple in light mode).
    final accent = blocked ? AppColors.red : StatusColors.warning;
    final what = context.t(
      widget.needsCamera ? 'call:permission.mic_camera' : 'call:permission.mic',
    );
    return Pressable(
      onPressed: _onTap,
      activeOpacity: 0.9,
      child: Container(
        margin: EdgeInsets.fromLTRB(
          widget.floating ? 0 : 16.ms,
          8.ms,
          widget.floating ? 0 : 16.ms,
          4.ms,
        ),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.darkWarningBg,
          borderRadius: BorderRadius.circular(16.ms),
          border: Border.all(color: accent.withValues(alpha: 0x40 / 255)),
          boxShadow: [
            BoxShadow(
              color: AppColors.blackA(0.1),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            Padding(
              padding: EdgeInsets.all(12.ms),
              child: Row(
                children: [
                  Container(
                    width: 32.ms,
                    height: 32.ms,
                    margin: EdgeInsets.only(right: 10.ms),
                    decoration: BoxDecoration(
                      color: AppColors.whiteA(0.05),
                      borderRadius: BorderRadius.circular(10.ms),
                    ),
                    child: Icon(
                      widget.needsCamera
                          ? LucideIcons.videoOff
                          : LucideIcons.micOff,
                      size: 18.ms,
                      color: accent,
                    ),
                  ),
                  Expanded(
                    child: CText(
                      'call:permission.bar',
                      variables: {'what': what},
                      size: 12,
                      height: 16,
                      letterSpacing: 0.3,
                      weight: FontWeight.w800,
                      color: AppColors.white,
                      maxLines: 2,
                    ),
                  ),
                  Container(
                    margin: EdgeInsets.only(left: 8.ms),
                    padding: EdgeInsets.symmetric(
                      horizontal: 12.ms,
                      vertical: 6.ms,
                    ),
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(10.ms),
                    ),
                    child: CText(
                      blocked
                          ? 'call:permission.settings'
                          : 'call:permission.allow',
                      size: 11,
                      letterSpacing: 0.5,
                      weight: FontWeight.w900,
                      color: blocked ? AppColors.white : AppColors.black,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 4,
              child: ColoredBox(color: accent),
            ),
          ],
        ),
      ),
    );
  }
}
