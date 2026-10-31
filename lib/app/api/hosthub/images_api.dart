import 'package:flutter/foundation.dart';

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

  /// Makes the server rows match [slots] (media id per slot, in order, the
  /// first is the primary; null = empty), matching rows by their PICTURE.
  ///
  /// The backend sends a photo back to review on any host edit (even a
  /// reorder) and refuses to delete an approved one, so only what really
  /// changed is written: a removed picture is deleted; unchanged pictures in
  /// an unchanged order are left alone (new ones are added after them); a
  /// reorder or a new primary updates only the rows whose place changed.
  /// [existing] must be the host's current rows.
  static Future<void> sync({
    required String expertId,
    required List<Object?> slots,
    List<HostProfileImage> existing = const [],
  }) async {
    // The pictures wanted, in order, once each.
    final want = <String>[];
    final refs = <String, Object>{};
    for (final s in slots) {
      if (s == null || (s is String && s.isEmpty)) continue;
      final k = '$s';
      if (refs.containsKey(k)) continue;
      want.add(k);
      refs[k] = s;
    }

    // One row per wanted picture (the first in display order); every other
    // row goes (a removed picture, or a duplicate row of a kept one).
    final rowOf = <String, HostProfileImage>{};
    final stale = <HostProfileImage>[];
    for (final row in HostProfileImage.sorted(existing)) {
      final img = row.imageId == null ? null : '${row.imageId}';
      if (img != null && refs.containsKey(img) && !rowOf.containsKey(img)) {
        rowOf[img] = row;
      } else {
        stale.add(row);
      }
    }
    for (final row in stale) {
      final key = row.key;
      if (key != null) await delete(key);
    }

    final kept = [
      for (final k in want)
        if (rowOf.containsKey(k)) k,
    ];
    final added = [
      for (final k in want)
        if (!rowOf.containsKey(k)) k,
    ];
    final shownNow = [
      for (final r in HostProfileImage.sorted(rowOf.values.toList()))
        '${r.imageId}',
    ];
    // The same pictures in the same order, new ones only after them: the
    // existing rows stay exactly as they are.
    final untouched =
        listEquals(shownNow, kept) &&
        listEquals(want.take(kept.length).toList(), kept);

    if (untouched) {
      var priority = rowOf.values.fold<int>(
        0,
        (m, r) => r.priority > m ? r.priority : m,
      );
      for (final k in added) {
        priority++;
        await create({
          'host_image': expertId,
          'image': refs[k],
          'priority': priority,
          'isprimary': kept.isEmpty && k == added.first,
        });
      }
      return;
    }

    // Reordered, or a new primary: slot i gets priority i + 1.
    for (var i = 0; i < want.length; i++) {
      final k = want[i];
      final priority = i + 1;
      final primary = i == 0;
      final row = rowOf[k];
      if (row == null) {
        await create({
          'host_image': expertId,
          'image': refs[k],
          'priority': priority,
          'isprimary': primary,
        });
      } else if (row.priority != priority || row.isPrimary != primary) {
        final key = row.key;
        if (key != null) {
          await update(key, {'priority': priority, 'isprimary': primary});
        }
      }
    }
  }
}
