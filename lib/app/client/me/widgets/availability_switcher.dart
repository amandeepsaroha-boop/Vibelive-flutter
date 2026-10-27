import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../core/session/session_store.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/vibe_colors.dart';
import '../../../../core/utils/scale.dart';
import '../../../component/pressable.dart';
import '../helper/availability_change.dart';
import '../helper/me_data.dart';

/// Compact, icon-only available / vacation / custom selector. Drop it in
/// anywhere: it reads the signed-in host from the session, saves like the
/// Profile card ([useAvailabilityChange]) and draws nothing for a client.
class AvailabilitySwitcher extends StatelessWidget {
  const AvailabilitySwitcher({super.key, this.height = 38});

  /// Outer height; each mode is a square cell inside it.
  final double height;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<SessionState>(
    valueListenable: SessionStore.instance,
    builder: (_, s, _) {
      final data = MeData.of(s);
      return data.isExpert
          ? _Switcher(data: data, height: height)
          : const SizedBox.shrink();
    },
  );
}

class _Switcher extends HookWidget {
  const _Switcher({required this.data, required this.height});
  final MeData data;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final availability = useAvailabilityChange(context, data);
    final pad = 3.ms;
    final cell = height.ms - pad * 2;
    return Opacity(
      opacity: availability.saving ? 0.6 : 1,
      child: Container(
        height: height.ms,
        padding: EdgeInsets.all(pad),
        decoration: BoxDecoration(
          color: c.isDark ? AppColors.whiteA(0.05) : AppColors.blackA(0.04),
          borderRadius: BorderRadius.circular(12.ms),
          border: Border.all(
            color: c.isDark ? AppColors.whiteA(0.12) : AppColors.blackA(0.09),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final s in availabilitySegments)
              Pressable(
                activeOpacity: 0.8,
                semanticLabel: context.t(s.label),
                onPressed: availability.saving
                    ? null
                    : () => availability.change(s.value),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: cell,
                  height: cell,
                  decoration: BoxDecoration(
                    color: s.value == availability.mode
                        ? c.accent
                        : AppColors.transparent,
                    borderRadius: BorderRadius.circular(9.ms),
                  ),
                  child: Icon(
                    s.icon,
                    size: 15.ms,
                    color: s.value == availability.mode
                        ? c.onAccent
                        : c.text.withValues(alpha: 0.6),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
