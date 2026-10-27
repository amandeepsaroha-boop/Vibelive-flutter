import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/router/app_router.dart';
import '../../../api/hosthub/profile_models.dart';
import '../widgets/me_segmented.dart';
import 'host_availability_controller.dart';
import 'me_actions.dart';
import 'me_data.dart';

/// The three modes, in order, with their icon and label.
const availabilitySegments = [
  MeSegment(
    HostAvailability.available,
    LucideIcons.phoneCall,
    'client:me.availability.available',
  ),
  MeSegment(
    HostAvailability.vacation,
    LucideIcons.plane,
    'client:me.availability.vacation',
  ),
  MeSegment(
    HostAvailability.custom,
    LucideIcons.settings2,
    'client:me.availability.custom',
  ),
];

/// Availability shown and how to change it: [mode] is the tapped one while it
/// saves ([saving]); [change] does nothing while a save runs.
typedef AvailabilityChange = ({
  HostAvailability mode,
  bool saving,
  Future<void> Function(HostAvailability next) change,
});

/// Available / vacation / custom (RN `handleMeAvailabilityModeChange`), for
/// every selector of it, through [HostAvailabilityController] (shared with
/// the dock's sheet): the tapped mode shows at once while it saves; custom
/// without a saved slot opens the schedule, which sets the mode with the
/// hours.
AvailabilityChange useAvailabilityChange(BuildContext context, MeData data) {
  final pending = useValueListenable(HostAvailabilityController.pending);

  Future<void> change(HostAvailability next) async {
    if (pending != null) return;
    if (next == HostAvailability.custom && !data.hasScheduleSlots) {
      await MeActions.open(context, AppRoutes.schedule);
      return;
    }
    if (next == data.availability) return;
    await HostAvailabilityController.set(next);
  }

  return (
    mode: pending ?? data.availability,
    saving: pending != null,
    change: change,
  );
}
