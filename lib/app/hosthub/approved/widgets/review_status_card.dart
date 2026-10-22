import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/utils/scale.dart';
import '../../../api/hosthub/approval_models.dart';
import '../../../component/c_text.dart';
import '../../onboarding/helper/host_palette.dart';
import '../../onboarding/widgets/continue_bar.dart';

/// A host not approved yet: under review, rejected (edit and resubmit), or
/// never submitted (finish the setup).
class HostReviewStatusCard extends StatelessWidget {
  const HostReviewStatusCard({
    super.key,
    required this.status,
    required this.onOpenFlow,
  });

  /// Null: no approval request yet.
  final ApprovalStatus? status;
  final VoidCallback onOpenFlow;

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    final (icon, color, bg, prefix, cta) = switch (status) {
      ApprovalStatus.pending => (
        LucideIcons.clock,
        p.accent,
        p.tint,
        'pending',
        null,
      ),
      ApprovalStatus.rejected => (
        LucideIcons.circleAlert,
        p.danger,
        p.dangerTint,
        'rejected',
        'hostflow:status.rejected_cta',
      ),
      _ => (
        LucideIcons.sparkles,
        p.accent,
        p.tint,
        'draft',
        'hostflow:status.draft_cta',
      ),
    };
    return Container(
      padding: EdgeInsets.all(14.ms),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18.ms),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 22.ms, color: color),
              SizedBox(width: 12.ms),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CText(
                      'hostflow:status.${prefix}_title',
                      size: 15,
                      weight: FontWeight.w800,
                      color: p.text,
                    ),
                    SizedBox(height: 4.ms),
                    CText(
                      'hostflow:status.${prefix}_body',
                      size: 13,
                      height: 18,
                      weight: FontWeight.w500,
                      color: p.muted,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (cta != null) ...[
            SizedBox(height: 12.ms),
            HostButton(label: cta, height: 46, onPressed: onOpenFlow),
          ],
        ],
      ),
    );
  }
}
