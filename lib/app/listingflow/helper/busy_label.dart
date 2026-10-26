import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart' show immutable;

import '../../api/listingflow/host_presence.dart';

/// "On a call, about 6 min" for a busy host (RN `busyLabel`): a client can
/// decide whether to wait. Deliberately vague ("about"): the start time can
/// be a few seconds out.
@immutable
class BusyLabel {
  const BusyLabel(this.key, [this.variables = const {}]);

  /// i18n key (`listing:busy.*`).
  final String key;
  final Map<String, Object> variables;

  /// Null when the host is not busy. Computed per build, so the minutes
  /// advance whenever the card or sheet rebuilds.
  static BusyLabel? of(HostPresence p, {DateTime? now}) {
    if (!p.isBusy) return null;
    // An unanswered ring is not "on a call".
    if (p.isRinging) return const BusyLabel('listing:busy.ringing');
    final since = p.busySince;
    // A busy host with no call row is real; the server omits the start.
    if (since == null) return const BusyLabel('listing:busy.on_call');
    final mins = (now ?? clock.now()).difference(since).inSeconds ~/ 60;
    // Clock skew must never print a negative duration.
    if (mins < 0) return const BusyLabel('listing:busy.on_call');
    if (mins < 1) return const BusyLabel('listing:busy.just_started');
    if (mins == 1) return const BusyLabel('listing:busy.minute');
    if (mins < 60) return BusyLabel('listing:busy.minutes', {'n': mins});
    final hours = mins ~/ 60;
    return hours == 1
        ? const BusyLabel('listing:busy.hour')
        : BusyLabel('listing:busy.hours', {'n': hours});
  }
}
