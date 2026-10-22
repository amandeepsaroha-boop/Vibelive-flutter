import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/utils/scale.dart';
import '../../../api/client/client_keys.dart';
import '../../../api/hosthub/hosthub_queries.dart';
import '../../../api/hosthub/profile_patch.dart';
import '../../../component/c_alert.dart';
import '../../../component/c_text.dart';
import '../../onboarding/helper/host_palette.dart';
import '../../onboarding/widgets/host_switch.dart';

/// "You're approved!" with the Go online switch (`isActive`; turning it on
/// is RN's "Go live", which also tells the admins). The switch shows the
/// new state at once while it saves.
class HostGoOnlineCard extends HookWidget {
  const HostGoOnlineCard({
    super.key,
    required this.expertId,
    required this.active,
    this.name,
    this.email,
  });

  final String expertId;

  /// Saved `isActive`.
  final bool active;
  final String? name;
  final String? email;

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    final goLive = useGoLive(alsoInvalidate: const [ClientKeys.profiles]);
    final update = useUpdateHostProfile(
      alsoInvalidate: const [ClientKeys.profiles],
    );
    final pending = useState<bool?>(null);
    final on = pending.value ?? active;

    Future<void> toggle(bool next) async {
      if (pending.value != null) return;
      pending.value = next;
      try {
        if (next) {
          await goLive.mutateAsync((
            expertId: expertId,
            name: name,
            email: email,
          ));
        } else {
          await update.mutateAsync((
            expertId: expertId,
            patch: const HostProfilePatch({'isActive': false}),
          ));
        }
      } on ApiException catch (e) {
        await CAlert.error(e, title: 'hostflow:approved.error_title');
      } finally {
        if (context.mounted) pending.value = null;
      }
    }

    return Container(
      padding: EdgeInsets.all(14.ms),
      decoration: BoxDecoration(
        color: p.successTint,
        borderRadius: BorderRadius.circular(18.ms),
        border: Border.all(color: p.success.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40.ms,
                height: 40.ms,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: p.success.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  LucideIcons.shieldCheck,
                  size: 22.ms,
                  color: p.success,
                ),
              ),
              SizedBox(width: 12.ms),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CText(
                      on
                          ? 'hostflow:approved.live_title'
                          : 'hostflow:approved.title',
                      size: 17,
                      weight: FontWeight.w800,
                      color: p.text,
                    ),
                    SizedBox(height: 4.ms),
                    CText(
                      on
                          ? 'hostflow:approved.live_body'
                          : 'hostflow:approved.body',
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
          SizedBox(height: 14.ms),
          Container(
            height: 52.ms,
            padding: EdgeInsets.only(left: 18.ms, right: 10.ms),
            decoration: BoxDecoration(
              gradient: p.buttonGradient,
              borderRadius: BorderRadius.circular(14.ms),
            ),
            child: Row(
              children: [
                Expanded(
                  child: CText(
                    on
                        ? 'hostflow:approved.online'
                        : 'hostflow:approved.go_online',
                    size: 16,
                    weight: FontWeight.w700,
                    color: p.onAccent,
                    align: TextAlign.center,
                    maxLines: 1,
                  ),
                ),
                HostSwitch(
                  key: const ValueKey('host-go-online'),
                  value: on,
                  onDark: true,
                  onChanged: pending.value == null ? toggle : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
