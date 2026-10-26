import 'package:flutter/foundation.dart' show immutable;

import '../../../core/network/strapi.dart';

/// Whether a host can take a call right now (RN `mapExpert` presence).
///
/// Read from `user_status`, not `isActive`: the server's schedule sync writes
/// `isActive` to mean "their schedule says available", which for a host set
/// to "available any time" is true forever. `busy` counts as available: that
/// host is reachable, just mid-call.
@immutable
class HostPresence {
  const HostPresence({this.status, this.busySince, this.busyKind});

  static const unknown = HostPresence();

  /// [e] is the expert-profile node. The server sends the call's START time
  /// (`busy_since`), not a duration, so a label built from it stays right
  /// while the screen sits open.
  factory HostPresence.fromExpert(JsonMap e) => HostPresence(
    status: J.str(e['user_status'])?.trim().toLowerCase(),
    busySince: J.date(e['busy_since']),
    busyKind: J.str(e['busy_kind']),
  );

  /// Lower-cased `user_status` (`online`, `busy`, `offline`…).
  final String? status;
  final DateTime? busySince;

  /// `on_call` or `ringing` while [isBusy].
  final String? busyKind;

  bool get isAvailable => status == 'online' || status == 'busy';
  bool get isBusy => status == 'busy';
  bool get isRinging => busyKind == 'ringing';
}
