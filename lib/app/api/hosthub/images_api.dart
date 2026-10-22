import '../../../core/network/api_client.dart';
import '../../../core/network/strapi.dart';
import 'profile_models.dart';
import 'strapi_lookup.dart';

/// The host's profile photos (`/profile-images`, 3 slots, slot 1 primary).
abstract final class HostImagesApi {
  /// Every row of a host, primary first then priority.
  static Future<List<HostProfileImage>> fetchAll(String expertId) async {
    final by = StrapiLookup.isNumericId(expertId) ? 'id' : 'documentId';
    final rows = StrapiLookup.rowsOf(
      await ApiClient.get(
        '/profile-images',
        query: {
          'filters[host_image][$by][\$eq]': expertId,
          'populate[image]': 'true',
          'pagination[pageSize]': 50,
          'sort[0]': 'priority:asc',
        },
      ),
    );
    return HostProfileImage.sorted([
      for (var i = 0; i < rows.length; i++)
        HostProfileImage.fromRow(rows[i], i),
    ]);
  }

  static Future<void> create(JsonMap payload) async {
    await ApiClient.post(
      '/profile-images',
      data: {'data': payload, 'status': 'published'},
    );
  }

  static Future<void> update(String imageKey, JsonMap payload) async {
    await ApiClient.put(
      '/profile-images/${Uri.encodeComponent(imageKey)}',
      data: {'data': payload, 'status': 'published'},
    );
  }

  static Future<void> delete(String imageKey) async {
    await ApiClient.delete('/profile-images/${Uri.encodeComponent(imageKey)}');
  }

  /// Makes the server rows match [slots] (media id per slot, null = empty):
  /// updates the row already at a priority instead of adding a duplicate,
  /// deletes emptied slots and rows outside 1–3. [existing] must be the
  /// host's current rows, or every save adds duplicates.
  static Future<void> sync({
    required String expertId,
    required List<Object?> slots,
    List<HostProfileImage> existing = const [],
  }) async {
    final byPriority = <int, HostProfileImage>{};
    for (final row in existing) {
      byPriority.putIfAbsent(row.priority, () => row);
    }

    final touched = <String>{};
    for (var i = 0; i < 3; i++) {
      final priority = i + 1;
      final ref = i < slots.length ? slots[i] : null;
      final current = byPriority[priority];
      final currentKey = current?.key;
      if (currentKey != null) touched.add(current!.identity);

      if (ref == null || (ref is String && ref.isEmpty)) {
        if (currentKey != null) await delete(currentKey);
        continue;
      }
      // No moderation state is sent: the backend forces `pending` on every
      // non-admin write, and a new photo shows only once a human clears it.
      final payload = {
        'host_image': expertId,
        'image': ref,
        'priority': priority,
        'isprimary': priority == 1,
      };
      if (currentKey != null) {
        await update(currentKey, payload);
      } else {
        await create(payload);
      }
    }

    for (final row in existing) {
      if (row.priority >= 1 && row.priority <= 3) continue;
      if (touched.contains(row.identity)) continue;
      final key = row.key;
      if (key != null) await delete(key);
    }
  }
}
