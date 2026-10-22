import 'package:flutter/foundation.dart';

import '../../../../core/network/strapi.dart';
import '../../../../core/session/session_store.dart';
import '../../../../core/utils/log.dart';
import '../../../api/listingflow/listing_api.dart';
import '../../helper/call_actions.dart';
import '../../helper/call_signals.dart';
import 'call_format.dart';

/// What the callback sheet shows (RN `CallbackModalListener` `data`).
@immutable
class CallbackData {
  const CallbackData({
    required this.expertId,
    this.expertDocId,
    this.expertUserDocId,
    this.name,
    this.avatarUrl,
    this.category,
    this.voicePrice = 0,
    this.videoPrice = 0,
  });

  /// Numeric public-user id of the host (the call receiver).
  final String? expertId;

  /// Expert-profile documentId (profile lookup).
  final String? expertDocId;

  /// The host's user documentId (`receiverDocID`), from the lookup.
  final String? expertUserDocId;
  final String? name;
  final String? avatarUrl;
  final String? category;
  final num voicePrice;
  final num videoPrice;

  /// What the Voice / Video button places: the rate shown on that button
  /// travels with it (A11: the max-duration cap needs it; 0 = unknown, the
  /// logic looks it up).
  CallTarget? targetFor({required bool video}) {
    final id = expertId;
    if (id == null) return null;
    final rate = video ? videoPrice : voicePrice;
    return CallTarget(
      receiverId: id,
      receiverDocId: expertUserDocId,
      name: name,
      avatarUrl: avatarUrl,
      ratePerMin: rate > 0 ? rate : null,
    );
  }
}

/// Turns a PING_CLIENT nudge into sheet data: null when it must not show
/// (sent by this very user, E-73). The push carries no prices, so they come
/// from the host's profile (list + filter lookup); a failed lookup falls back
/// to whatever the push carried, else 0.
Future<CallbackData?> resolveCallback(CallbackRequest request) async {
  final d = request.data;
  String? s(String key) => nonEmpty(J.str(d[key]));

  final expertId = s('expertId');
  final me = SessionStore.instance.value.userId;
  if (me != null && expertId == '$me') return null;

  num? voice = J.number(d['voiceCallPrice']);
  num? video = J.number(d['videoCallPrice']);
  String? userDocId;
  String? hostPic;
  try {
    final host = await ListingApi.findCallbackHost(
      expertDocumentId: s('expertDocId'),
      userId: expertId,
    );
    voice ??= host.aPrice;
    video ??= host.vPrice;
    userDocId = host.userDocumentId;
    hostPic = host.images.firstOrNull;
  } catch (e) {
    Log.w('Callback', 'host lookup failed: $e');
  }

  return CallbackData(
    expertId: expertId,
    expertDocId: s('expertDocId'),
    expertUserDocId: userDocId,
    name: s('expertName') ?? s('name'),
    avatarUrl:
        Strapi.mediaUrl(s('expertPic') ?? s('ProfilePic') ?? s('profilePic')) ??
        hostPic,
    category: s('categoryName'),
    voicePrice: voice ?? 0,
    videoPrice: video ?? 0,
  );
}
