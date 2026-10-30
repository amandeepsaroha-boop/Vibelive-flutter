import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/analytics/events/host_events.dart';
import '../../../../core/config/runtime_config.dart';
import '../../../../core/utils/scale.dart';
import '../../../api/paymentscreen/billing_models.dart';
import '../../../api/paymentscreen/payment_queries.dart';
import '../../../api/paymentscreen/runtime_config_queries.dart';
import '../../../component/c_text.dart';
import '../../../component/pressable.dart';
import '../helper/draft_controller.dart';
import '../helper/host_palette.dart';
import '../helper/host_payout.dart';
import '../helper/validation.dart';
import '../widgets/continue_bar.dart';
import '../widgets/host_switch.dart';
import '../widgets/rate_stepper.dart';
import '../widgets/sheet_frame.dart';
import '../widgets/step_body.dart';

/// Rates: audio and/or video, each with its per-minute rate (the pricing
/// config sets the floor) and, live under it, what the host earns at that
/// rate: from app callers and from callers who joined with their invite
/// link (RN CallRatesScreen "Estimated earnings payout"), worked out the way
/// the backend bills a call ([HostPayoutTerms]).
class RatesStep extends HookWidget {
  const RatesStep({super.key, required this.draft});
  final HostDraftController draft;

  @override
  Widget build(BuildContext context) {
    final pricing = usePricingConfig(context).data ?? PricingConfig.empty;
    final runtime = useRuntimeConfig(context);
    final voicePayout = HostRatePayout.from(runtime, pricing, video: false);
    final videoPayout = HostRatePayout.from(runtime, pricing, video: true);
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
          payout: voicePayout,
        ),
        SizedBox(height: 12.ms),
        RateFormatCard(
          icon: LucideIcons.video,
          title: 'hostflow:rates.video',
          on: draft.videoOn,
          rate: draft.videoRate,
          min: videoMin,
          payout: videoPayout,
        ),
        SizedBox(height: 12.ms),
        // The full breakdown (call lengths, fees, invite link, payouts).
        Pressable(
          onPressed: () {
            HostEvents.earningsViewed(
              audioRate: draft.audioOn.value ? draft.audioRate.value : null,
              videoRate: draft.videoOn.value ? draft.videoRate.value : null,
            );
            _showEarnings(
              context,
              draft,
              voice: voicePayout,
              video: videoPayout,
              runtime: runtime,
            );
          },
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 10.ms),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(LucideIcons.info, size: 17.ms, color: p.accent),
                SizedBox(width: 6.ms),
                Flexible(
                  child: CText(
                    'hostflow:rates.earnings_link',
                    size: 14.5,
                    weight: FontWeight.w700,
                    color: p.accent,
                  ),
                ),
                SizedBox(width: 4.ms),
                Icon(LucideIcons.arrowRight, size: 14.ms, color: p.accent),
              ],
            ),
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
    this.payout,
  });

  final IconData icon;

  /// i18n key.
  final String title;
  final ValueNotifier<bool> on;
  final ValueNotifier<int> rate;
  final int min;

  /// What the host earns at [rate]; shown under the stepper.
  final HostRatePayout? payout;

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
                  child: CText(
                    title,
                    size: 18,
                    weight: FontWeight.w700,
                    color: p.text,
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
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Under the title, as in the design.
                        Padding(
                          padding: EdgeInsets.only(top: 12.ms, left: 64.ms),
                          child: HostRateStepper(
                            rate: rate,
                            min: min,
                            max: HostValidation.rateCeiling,
                            step: HostValidation.rateStep,
                          ),
                        ),
                        if (payout case final payout?)
                          _EarningsPanel(rate: rate, payout: payout),
                      ],
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }
}

/// What the host gets per minute at the rate being set, big, with the
/// fee under it; one line for invite-link callers when they pay more. The
/// full breakdown is in "How earnings work". Follows the stepper.
class _EarningsPanel extends StatelessWidget {
  const _EarningsPanel({required this.rate, required this.payout});
  final ValueListenable<int> rate;
  final HostRatePayout payout;

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    return ValueListenableBuilder<int>(
      valueListenable: rate,
      builder: (_, r, _) => Container(
        margin: EdgeInsets.only(top: 10.ms),
        padding: EdgeInsets.fromLTRB(12.ms, 9.ms, 12.ms, 9.ms),
        decoration: BoxDecoration(
          color: p.successTint,
          borderRadius: BorderRadius.circular(12.ms),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CText(
                        'hostflow:rates.you_get',
                        size: 13.5,
                        weight: FontWeight.w700,
                        color: p.text,
                      ),
                      CText(
                        'hostflow:rates.after_fee',
                        variables: {'percent': rupees(payout.standard.percent)},
                        size: 11.5,
                        weight: FontWeight.w500,
                        color: p.muted,
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 8.ms),
                // The number a host decides on: the boldest thing here.
                // Shrinks rather than overflow on a narrow phone.
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        CText(
                          'hostflow:rates.amount_plain',
                          variables: {
                            'amount': rupees(payout.standard.perMinute(r)),
                          },
                          size: 22,
                          weight: FontWeight.w900,
                          color: p.success,
                          maxLines: 1,
                        ),
                        SizedBox(width: 2.ms),
                        CText(
                          'hostflow:rates.per_min_short',
                          size: 12.5,
                          weight: FontWeight.w700,
                          color: p.success,
                          maxLines: 1,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (payout.inviteIsBetter) ...[
              SizedBox(height: 6.ms),
              Row(
                children: [
                  Icon(LucideIcons.link, size: 13.ms, color: p.success),
                  SizedBox(width: 5.ms),
                  Expanded(
                    child: CText(
                      'hostflow:rates.invite_line',
                      variables: {'amount': rupees(payout.invite.perMinute(r))},
                      size: 12,
                      weight: FontWeight.w600,
                      color: p.success,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "How earnings work": for each format on offer, what a 1, 5, 10 and 30
/// minute call pays, the fee rules, invite-link callers, and where the money
/// goes.
Future<void> _showEarnings(
  BuildContext context,
  HostDraftController draft, {
  required HostRatePayout voice,
  required HostRatePayout video,
  required RuntimeConfig runtime,
}) {
  return showHostSheet<void>(
    context,
    title: 'hostflow:rates.earn_title',
    name: 'host_earnings_sheet',
    child: Builder(
      builder: (sheet) {
        final p = HostPalette.of(sheet);
        Widget line(String key, [Map<String, dynamic>? vars]) => Padding(
          padding: EdgeInsets.only(bottom: 10.ms),
          child: CText(
            key,
            variables: vars,
            size: 14.5,
            height: 21,
            weight: FontWeight.w500,
            color: p.text,
          ),
        );
        final formats = [
          if (draft.audioOn.value)
            ('hostflow:rates.earn_audio', draft.audioRate.value, voice),
          if (draft.videoOn.value)
            ('hostflow:rates.earn_video', draft.videoRate.value, video),
        ];
        final invite = formats.any((f) => f.$3.inviteIsBetter);
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20.ms, 0, 20.ms, 8.ms),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              line('hostflow:rates.earn_body'),
              for (final (title, rate, payout) in formats) ...[
                _CallTable(title: title, rate: rate, payout: payout),
                SizedBox(height: 14.ms),
              ],
              if (invite) line('hostflow:rates.earn_invite'),
              line('hostflow:rates.earn_short'),
              if (!runtime.bonus.bonusCreditHostPayoutEnabled)
                line('hostflow:rates.earn_bonus'),
              line('hostflow:rates.earn_note', {
                'min': rupees(runtime.pricing.minAmountToWithdrawal),
              }),
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

/// One format in the sheet: its fee rule and a call-length table.
class _CallTable extends StatelessWidget {
  const _CallTable({
    required this.title,
    required this.rate,
    required this.payout,
  });

  /// i18n key ("Audio at ₹{{rate}}/min").
  final String title;
  final int rate;
  final HostRatePayout payout;

  static const lengths = [1, 5, 10, 30];

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    final std = payout.standard;
    Widget cell(
      String key,
      Map<String, dynamic>? vars, {
      bool head = false,
      bool strong = false,
      TextAlign align = TextAlign.start,
    }) => Expanded(
      child: CText(
        key,
        variables: vars,
        size: head ? 11.5 : 13.5,
        weight: head
            ? FontWeight.w800
            : (strong ? FontWeight.w800 : FontWeight.w600),
        color: head ? p.muted : (strong ? p.accent : p.text),
        align: align,
      ),
    );
    return Container(
      padding: EdgeInsets.all(12.ms),
      decoration: BoxDecoration(
        color: p.soft,
        borderRadius: BorderRadius.circular(14.ms),
        border: Border.all(color: p.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CText(
            title,
            variables: {'rate': rate},
            size: 15,
            weight: FontWeight.w800,
            color: p.text,
          ),
          SizedBox(height: 4.ms),
          CText(
            'hostflow:rates.fee_rule',
            variables: {
              'percent': rupees(std.percent),
              'min': rupees(std.minimumPerCall),
            },
            size: 12.5,
            height: 18,
            weight: FontWeight.w500,
            color: p.muted,
          ),
          SizedBox(height: 10.ms),
          Row(
            children: [
              cell('hostflow:rates.col_call', null, head: true),
              cell(
                'hostflow:rates.col_pays',
                null,
                head: true,
                align: TextAlign.end,
              ),
              cell(
                'hostflow:rates.col_gets',
                null,
                head: true,
                align: TextAlign.end,
              ),
            ],
          ),
          for (final m in lengths)
            Padding(
              padding: EdgeInsets.only(top: 6.ms),
              child: Row(
                children: [
                  cell('hostflow:rates.minutes', {'minutes': m}),
                  cell('hostflow:rates.amount_plain', {
                    'amount': rupees((rate * m).toDouble()),
                  }, align: TextAlign.end),
                  cell(
                    'hostflow:rates.amount_plain',
                    {'amount': rupees(std.forCall(rate, m))},
                    strong: true,
                    align: TextAlign.end,
                  ),
                ],
              ),
            ),
          if (payout.inviteIsBetter) ...[
            SizedBox(height: 10.ms),
            CText(
              'hostflow:rates.invite_rule',
              variables: {
                'percent': rupees(payout.invite.percent),
                'min': rupees(payout.invite.minimumPerCall),
                'amount': rupees(payout.invite.perMinute(rate)),
              },
              size: 12.5,
              height: 18,
              weight: FontWeight.w600,
              color: p.success,
            ),
          ],
        ],
      ),
    );
  }
}
