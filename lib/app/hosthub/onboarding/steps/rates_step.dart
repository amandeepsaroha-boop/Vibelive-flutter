import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/analytics/events/host_events.dart';
import '../../../../core/utils/scale.dart';
import '../../../api/paymentscreen/billing_models.dart';
import '../../../api/paymentscreen/payment_queries.dart';
import '../../../component/c_text.dart';
import '../../../component/pressable.dart';
import '../helper/draft_controller.dart';
import '../helper/host_palette.dart';
import '../helper/validation.dart';
import '../widgets/continue_bar.dart';
import '../widgets/host_switch.dart';
import '../widgets/rate_stepper.dart';
import '../widgets/sheet_frame.dart';
import '../widgets/step_body.dart';

/// 7 of 11: audio and/or video, each with its per-minute rate (the
/// pricing config sets the floor).
class RatesStep extends HookWidget {
  const RatesStep({super.key, required this.draft});
  final HostDraftController draft;

  @override
  Widget build(BuildContext context) {
    final pricing = usePricingConfig(context).data ?? PricingConfig.empty;
    final voiceMin = HostValidation.minRate(pricing.minimumVoiceRate);
    final videoMin = HostValidation.minRate(pricing.minimumVideoRate);
    // A floor above the default lifts the rate once the config is known.
    useEffect(() {
      if (draft.audioRate.value < voiceMin) draft.audioRate.value = voiceMin;
      if (draft.videoRate.value < videoMin) draft.videoRate.value = videoMin;
      return null;
    }, [voiceMin, videoMin]);
    final p = HostPalette.of(context);

    return HostStepBody(
      title: 'hostflow:rates.title',
      subtitle: 'hostflow:rates.subtitle',
      children: [
        RateFormatCard(
          icon: LucideIcons.headphones,
          title: 'hostflow:rates.audio',
          on: draft.audioOn,
          rate: draft.audioRate,
          min: voiceMin,
        ),
        SizedBox(height: 12.ms),
        RateFormatCard(
          icon: LucideIcons.video,
          title: 'hostflow:rates.video',
          on: draft.videoOn,
          rate: draft.videoRate,
          min: videoMin,
        ),
        SizedBox(height: 12.ms),
        HostCard(
          color: p.tint,
          borderColor: p.tint,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(LucideIcons.info, size: 22.ms, color: p.accent),
              SizedBox(width: 12.ms),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CText(
                      'hostflow:rates.info',
                      size: 14.5,
                      height: 21.5,
                      weight: FontWeight.w500,
                      color: p.text,
                    ),
                    SizedBox(height: 6.ms),
                    Pressable(
                      onPressed: () {
                        HostEvents.earningsViewed(
                          audioRate: draft.audioOn.value
                              ? draft.audioRate.value
                              : null,
                          videoRate: draft.videoOn.value
                              ? draft.videoRate.value
                              : null,
                        );
                        _showEarnings(context, draft, pricing);
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: CText(
                              'hostflow:rates.earnings_link',
                              size: 14.5,
                              weight: FontWeight.w700,
                              color: p.accent,
                            ),
                          ),
                          SizedBox(width: 4.ms),
                          Icon(
                            LucideIcons.arrowRight,
                            size: 14.ms,
                            color: p.accent,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One call format: icon, title, switch and its rate stepper.
class RateFormatCard extends StatelessWidget {
  const RateFormatCard({
    super.key,
    required this.icon,
    required this.title,
    required this.on,
    required this.rate,
    required this.min,
  });

  final IconData icon;

  /// i18n key.
  final String title;
  final ValueNotifier<bool> on;
  final ValueNotifier<int> rate;
  final int min;

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    return HostCard(
      child: ValueListenableBuilder<bool>(
        valueListenable: on,
        builder: (_, enabled, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 52.ms,
                  height: 52.ms,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: p.buttonGradient,
                    borderRadius: BorderRadius.circular(12.ms),
                  ),
                  child: Icon(icon, size: 26.ms, color: p.onAccent),
                ),
                SizedBox(width: 12.ms),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CText(
                        title,
                        size: 18,
                        weight: FontWeight.w700,
                        color: p.text,
                      ),
                      SizedBox(height: 2.ms),
                      CText(
                        'hostflow:rates.rate_hint',
                        size: 14.5,
                        weight: FontWeight.w500,
                        color: p.muted,
                      ),
                    ],
                  ),
                ),
                HostSwitch(
                  key: ValueKey('hostflow-switch-$title'),
                  value: enabled,
                  onChanged: (v) {
                    on.value = v;
                    HostEvents.callTypeToggled(
                      callType: title.contains('video') ? 'video' : 'audio',
                      enabled: v,
                    );
                  },
                ),
              ],
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: enabled
                  // Under the title, as in the design.
                  ? Padding(
                      padding: EdgeInsets.only(top: 12.ms, left: 64.ms),
                      child: HostRateStepper(
                        rate: rate,
                        min: min,
                        max: HostValidation.rateCeiling,
                        step: HostValidation.rateStep,
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }
}

/// RN CallRatesScreen `calculateEarnings`: the platform keeps the larger of
/// its percentage and its fixed minimum, never more than the rate.
double hostEarnings(double rate, double percent, double minimumFixed) {
  final commission = math.min(
    math.max(rate * percent / 100, minimumFixed),
    rate,
  );
  final net = rate - commission;
  return net < 0 ? 0 : net;
}

Future<void> _showEarnings(
  BuildContext context,
  HostDraftController draft,
  PricingConfig pricing,
) {
  String money(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
  final audio = hostEarnings(
    draft.audioRate.value.toDouble(),
    pricing.voiceCommissionPercent,
    pricing.minimumVoiceCommissionFixed,
  );
  final video = hostEarnings(
    draft.videoRate.value.toDouble(),
    pricing.videoCommissionPercent,
    pricing.minimumVideoCommissionFixed,
  );
  return showHostSheet<void>(
    context,
    title: 'hostflow:rates.earn_title',
    name: 'host_earnings_sheet',
    child: Builder(
      builder: (sheet) {
        final p = HostPalette.of(sheet);
        Widget line(String key, Map<String, dynamic>? vars) => Padding(
          padding: EdgeInsets.only(bottom: 10.ms),
          child: CText(
            key,
            variables: vars,
            size: 15.5,
            height: 22.5,
            weight: FontWeight.w500,
            color: p.text,
          ),
        );
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20.ms, 0, 20.ms, 8.ms),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              line('hostflow:rates.earn_body', null),
              if (draft.audioOn.value)
                line('hostflow:rates.earn_audio', {
                  'rate': draft.audioRate.value,
                  'amount': money(audio),
                }),
              if (draft.videoOn.value)
                line('hostflow:rates.earn_video', {
                  'rate': draft.videoRate.value,
                  'amount': money(video),
                }),
              line('hostflow:rates.earn_note', null),
              SizedBox(height: 8.ms),
              HostButton(
                label: 'hostflow:rates.got_it',
                arrow: false,
                onPressed: () => Navigator.of(sheet).pop(),
              ),
            ],
          ),
        );
      },
    ),
  );
}
