import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/scale.dart';
import '../../../component/c_text.dart';
import '../call_avatar.dart';
import '../call_motion_widgets.dart';
import '../call_pulse.dart';
import '../helper/call_format.dart';
import '../helper/call_select.dart';

/// Caller block of the incoming screen (RN intro MotiView): pulse + ringed
/// photo, name, "App Official" chip, blinking "INCOMING CALL...", call type.
/// Pops in once (scale .5 → 1 spring, fade 300 ms).
class IncomingIntro extends HookWidget {
  const IncomingIntro({super.key});

  @override
  Widget build(BuildContext context) {
    final (name, url, company, video) = useCallSelect(
      (s) => (
        nonEmpty(s.remote.name),
        s.remote.avatarUrl,
        s.remote.isCompany,
        s.isVideo,
      ),
    );
    final ring = company ? CallColors.company : BrandColors.vibeLime;
    final size = 128.sw;
    return EntryIn(
      fromScale: 0.5,
      child: Padding(
        padding: EdgeInsets.only(top: 16.vs, bottom: 32.vs),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: size,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  CallPulse(size: size, color: ring),
                  CallAvatarRing(
                    size: size,
                    color: ring,
                    url: url,
                    companyRing: company,
                  ),
                ],
              ),
            ),
            SizedBox(height: 32.vs),
            _Name(name: name),
            if (company) const _OfficialChip(),
            Padding(
              padding: EdgeInsets.only(top: 16.vs),
              child: const HoldBlink(
                leg: Duration(milliseconds: 1500),
                low: 0.4,
                high: 1,
                child: CText(
                  'call:incoming.title',
                  color: BrandColors.lime,
                  weight: FontWeight.w900,
                  size: 10.5,
                  height: 14,
                  uppercase: true,
                  letterSpacing: 5.25,
                  align: TextAlign.center,
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.only(top: 16.vs),
              child: CText(
                callTypeKey(video: video),
                color: AppColors.whiteA(0.85),
                weight: FontWeight.w800,
                size: 20,
                align: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Name extends StatelessWidget {
  const _Name({required this.name});
  final String? name;

  @override
  Widget build(BuildContext context) {
    const color = AppColors.white;
    // RN wraps without a limit; two lines keep a very long name off the
    // safety card on a small phone.
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.sw),
      child: name == null
          ? const CText(
              'call:incoming.fallback_name',
              color: color,
              weight: FontWeight.w900,
              size: 36,
              letterSpacing: -0.35,
              align: TextAlign.center,
              maxLines: 2,
            )
          : CText.raw(
              name!,
              color: color,
              weight: FontWeight.w900,
              size: 36,
              letterSpacing: -0.35,
              align: TextAlign.center,
              maxLines: 2,
            ),
    );
  }
}

/// "✓ App Official" under the name (company caller).
class _OfficialChip extends StatelessWidget {
  const _OfficialChip();

  @override
  Widget build(BuildContext context) => Container(
    margin: EdgeInsets.only(top: 8.vs),
    padding: EdgeInsets.symmetric(horizontal: 10.sw, vertical: 3.vs),
    decoration: BoxDecoration(
      color: AppColors.whiteA(0.15),
      borderRadius: BorderRadius.circular(12.sw),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.verified, size: 13.ms, color: CallColors.verifiedGreen),
        const SizedBox(width: 4),
        const CText(
          'call:badge.official',
          color: AppColors.white,
          size: 11,
          weight: FontWeight.w700,
        ),
      ],
    ),
  );
}

/// White "App Official ✓" pill at the top of the incoming screen (company
/// caller); slides down and fades in once (400 ms timing).
class IncomingOfficialPill extends StatelessWidget {
  const IncomingOfficialPill({super.key});

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: EntryIn(
      fromDy: -20,
      timing: const Duration(milliseconds: 400),
      child: Container(
        margin: EdgeInsets.only(top: 12.vs),
        padding: EdgeInsets.symmetric(horizontal: 14.sw, vertical: 5.vs),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(20.sw),
          boxShadow: [BoxShadow(color: AppColors.blackA(0.2), blurRadius: 8)],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CText(
              'call:badge.official',
              color: AppColors.black,
              size: 12,
              weight: FontWeight.w800,
            ),
            SizedBox(width: 5.sw),
            Icon(Icons.verified, size: 15.ms, color: AppColors.black),
          ],
        ),
      ),
    ),
  );
}
