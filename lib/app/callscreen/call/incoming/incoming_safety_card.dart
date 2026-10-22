import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/scale.dart';
import '../call_avatar.dart';
import '../call_safety_row.dart';

/// Which incoming safety action runs.
enum IncomingSafety { block, report }

/// RN incoming safety card: "Block this caller" / "Report this caller".
/// Each confirms, then declines the call and files the block / report.
class IncomingSafetyCard extends StatelessWidget {
  const IncomingSafetyCard({
    super.key,
    required this.busy,
    required this.onAction,
  });

  final IncomingSafety? busy;
  final void Function(IncomingSafety kind) onAction;

  @override
  Widget build(BuildContext context) {
    final SafetyRowSizes sizes = (
      disc: 30.sw,
      icon: 14.ms,
      gap: 11.sw,
      padV: 10.vs,
      label: 12.5,
      hint: 10,
      hintGap: 1,
    );
    return Container(
      margin: EdgeInsets.fromLTRB(24.sw, 0, 24.sw, 26.vs),
      padding: EdgeInsets.symmetric(horizontal: 14.sw, vertical: 4.vs),
      decoration: BoxDecoration(
        color: CallColors.safetyCard,
        borderRadius: BorderRadius.circular(20.sw),
        border: Border.all(color: AppColors.whiteA(0.10)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CallSafetyRow(
            sizes: sizes,
            icon: LucideIcons.userX,
            label: 'call:incoming.block_label',
            hint: 'call:incoming.block_hint',
            busy: busy == IncomingSafety.block,
            otherBusy: busy == IncomingSafety.report,
            onPressed: () => onAction(IncomingSafety.block),
          ),
          CallSafetyRow(
            sizes: sizes,
            icon: LucideIcons.flag,
            label: 'call:incoming.report_label',
            hint: 'call:incoming.report_hint',
            busy: busy == IncomingSafety.report,
            otherBusy: busy == IncomingSafety.block,
            onPressed: () => onAction(IncomingSafety.report),
            divider: true,
          ),
        ],
      ),
    );
  }
}
