import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/strapi.dart';
import 'client_models.dart';

/// `/user-blocks`: block / unblock someone and list who the user blocked.
abstract final class BlockApi {
  static Future<List<BlockedUser>> fetchBlockedUsers({
    int limit = 50,
    int offset = 0,
  }) async {
    final body = await ApiClient.get(
      '/user-blocks',
      query: {'limit': limit, 'offset': offset},
    );
    return [for (final row in Strapi.list(body)) BlockedUser(row)];
  }

  static Future<void> blockUser(BlockUserInput input) async {
    final target = input.targetUserId.trim();
    if (target.isEmpty) throw _missingTarget;
    final reason = input.reason?.trim() ?? '';
    await ApiClient.post(
      '/user-blocks',
      data: {'targetUserId': target, if (reason.isNotEmpty) 'reason': reason},
    );
  }

  /// [targetUserId]: documentId (or id) of the blocked user.
  static Future<void> unblockUser(String targetUserId) async {
    final target = targetUserId.trim();
    if (target.isEmpty) throw _missingTarget;
    try {
      await ApiClient.post(
        '/user-blocks/unblock',
        data: {'targetUserId': target},
      );
    } on ApiException catch (e, st) {
      // Older backends only expose `DELETE /user-blocks/:targetUserId`; if
      // that fails too, report the original error.
      try {
        await ApiClient.delete('/user-blocks/${Uri.encodeComponent(target)}');
      } on ApiException {
        Error.throwWithStackTrace(e, st);
      }
    }
  }

  static const _missingTarget = ApiException(
    ApiErrorType.rejected,
    messageKey: 'client:errors.missing_user',
  );
}

class BlockUserInput {
  const BlockUserInput(this.targetUserId, {this.reason});

  /// documentId (or numeric id) of the user to block.
  final String targetUserId;

  /// Optional note for moderators ("Blocked during a live call.").
  final String? reason;
}
