import 'package:flutter/widgets.dart';

import '../../../api/listingflow/listing_models.dart';
import '../../../callscreen/helper/call_actions.dart';

/// Hand-off from the host profile to the call layer. The profile has already
/// run every RN pre-call check (own profile, session, profile completeness,
/// company account, cash balance vs. rate) and the user confirmed the safety
/// notice; the profile sheet is closed. [host] is the receiver, [video]
/// the call type, [context] a context that outlives the sheet.
///
/// The call layer does the rest (RN DiscoveryScreen `handleInitiateCall`):
/// mic (and camera for [video]) permissions, `/initiateCall` with the busy /
/// failure alerts, then the outgoing call screen.
Future<void> startOutgoingCall(
  BuildContext context, {
  required HostCard host,
  required bool video,
}) => CallActions.placeCall(context, host: host, video: video);
