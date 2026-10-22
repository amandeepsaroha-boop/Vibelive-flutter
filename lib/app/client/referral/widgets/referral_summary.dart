import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/vibe_colors.dart';
import '../../../../core/utils/scale.dart';
import '../../../component/c_button.dart';
import '../../../component/c_text.dart';
import '../helper/referral_format.dart';
import '../helper/referral_palette.dart';

/// List header of the referral screen (RN `ListHeaderComponent`): the code
/// card with its share button, the two counters and the section label.
class ReferralSummary extends StatelessWidget {
  const ReferralSummary({
    super.key,
    required this.code,
    required this.totalClicks,
    required this.joinedUserCount,
    required this.sharing,
    required this.onShare,
  });

  final String code;
  final int totalClicks;
  final int joinedUserCount;

  /// Only the share button listens to it.
  final ValueListenable<bool> sharing;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final p = ReferralPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          margin: EdgeInsets.only(bottom: 12.ms),
          padding: EdgeInsets.all(16.ms),
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(22.ms),
            border: Border.all(color: p.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CText(
                'client:referral.your_code',
                size: 10,
                weight: FontWeight.w900,
                letterSpacing: 1.4,
                color: p.muted,
                maxLines: 1,
              ),
              SizedBox(height: 6.ms),
              code.isEmpty
                  ? CText(
                      ReferralFormat.noCodeKey,
                      size: 26,
                      weight: FontWeight.w900,
                      color: p.text,
                      maxLines: 1,
                    )
                  : CText.raw(
                      code,
                      size: 26,
                      weight: FontWeight.w900,
                      color: p.text,
                      maxLines: 1,
                    ),
              SizedBox(height: 6.ms),
              CText.raw(
                ReferralFormat.link(code),
                size: 12,
                weight: FontWeight.w700,
                color: p.muted,
                maxLines: 2,
              ),
              SizedBox(height: 16.ms),
              ValueListenableBuilder<bool>(
                valueListenable: sharing,
                builder: (context, busy, _) => CButton(
                  title: 'client:referral.share',
                  onPressed: onShare,
                  loading: busy,
                  showArrow: false,
                  icon: Icon(
                    LucideIcons.share2,
                    size: 18.ms,
                    // The label color of a primary CButton.
                    color: context.colors.onAccent,
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.only(bottom: 16.ms),
          child: Row(
            children: [
              Expanded(
                child: _Stat(
                  label: 'client:referral.total_clicks',
                  value: ReferralFormat.count(totalClicks),
                ),
              ),
              SizedBox(width: 12.ms),
              Expanded(
                child: _Stat(
                  label: 'client:referral.joined_users',
                  value: ReferralFormat.count(joinedUserCount),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.only(bottom: 10.ms),
          child: CText(
            'client:referral.referred_users',
            size: 13,
            weight: FontWeight.w900,
            letterSpacing: 1.1,
            color: p.text,
            maxLines: 1,
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final p = ReferralPalette.of(context);
    return Container(
      padding: EdgeInsets.all(14.ms),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(16.ms),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CText(
            label,
            size: 11,
            weight: FontWeight.w700,
            color: p.muted,
            maxLines: 1,
          ),
          SizedBox(height: 4.ms),
          CText.raw(
            value,
            size: 22,
            weight: FontWeight.w900,
            color: p.text,
            maxLines: 1,
          ),
        ],
      ),
    );
  }
}
