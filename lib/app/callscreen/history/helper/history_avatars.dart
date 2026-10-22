import 'package:clock/clock.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/query/query_client.dart';
import '../../../api/authscreen/auth_queries.dart';
import 'history_entry.dart';

/// RN explore `fetchAvatar`: a call-log user whose populated row carries no
/// photo is looked up once (`/public-users/:id?populate[profilePic]`), and
/// the photo is reused for every row of that user. One request per user at
/// a time; a user without a photo (or a failed lookup) is retried only after
/// [StaleTime.medium], not on every scroll.
///
/// Plain futures, no query observer per row: a row's photo arriving must
/// not rebuild the list.
abstract final class HistoryAvatars {
  static final _found = <String, String>{};
  static final _inFlight = <String, Future<String?>>{};
  static final _missedAt = <String, DateTime>{};

  /// The photo already found for [userId].
  static String? cached(String userId) => _found[userId];

  /// The photo of [userId], or null. Never throws.
  static Future<String?> lookup(String userId) {
    final hit = _found[userId];
    if (hit != null) return Future.value(hit);
    final missed = _missedAt[userId];
    if (missed != null && clock.now().difference(missed) < StaleTime.medium) {
      return Future.value();
    }
    return _inFlight[userId] ??= _fetch(userId);
  }

  static Future<String?> _fetch(String userId) async {
    try {
      final url = HistoryEntry.avatarOfUser(
        await ensureUserByDocumentId(userId),
      );
      if (url != null) return _found[userId] = url;
    } on ApiException {
      // Kept as "no photo": the row shows the letter.
    } finally {
      _inFlight.remove(userId)?.ignore();
    }
    _missedAt[userId] = clock.now();
    return null;
  }

  /// Forget everything (sign-out, tests).
  static void clear() {
    _found.clear();
    _inFlight.clear();
    _missedAt.clear();
  }
}
