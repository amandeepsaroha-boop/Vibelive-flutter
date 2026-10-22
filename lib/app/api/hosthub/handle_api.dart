import '../../../core/network/api_client.dart';
import '../../../core/network/strapi.dart';
import '../../../core/session/session_store.dart';
import 'strapi_lookup.dart';

/// Profile handle (`expert-profiles.handler`) lookups for the onboarding
/// flow. The backend has no dedicated "is it free" route: a case-insensitive
/// filter on the list endpoint answers it.
abstract final class HostHandleApi {
  /// True when no other host uses [handle]. [ownExpertId] (a host editing
  /// their own profile) is not counted as a clash.
  static Future<bool> isAvailable(String handle, {String? ownExpertId}) async {
    final rows = StrapiLookup.rowsOf(
      await ApiClient.get(
        '/expert-profiles',
        query: {
          'filters[handler][\$eqi]': handle.trim(),
          'fields[0]': 'handler',
          'pagination[page]': 1,
          'pagination[pageSize]': 2,
        },
      ),
    );
    final wanted = handle.trim().toLowerCase();
    final own = {
      (ownExpertId ?? '').trim(),
      SessionStore.instance.value.expertDocumentId ?? '',
      SessionStore.instance.value.expertId ?? '',
    }..remove('');
    // Taken = another host whose handle really equals [handle]. Rows that
    // don't match (an ignored filter returns the viewer's own or any
    // profile) and the viewer's own profile never count.
    return !rows.any(
      (row) =>
          (J.str(row['handler']) ?? '').toLowerCase() == wanted &&
          !own.contains(J.str(row['documentId'])) &&
          !own.contains(J.str(row['id'])),
    );
  }
}
