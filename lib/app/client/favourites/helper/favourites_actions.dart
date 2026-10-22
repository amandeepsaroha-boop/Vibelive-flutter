import 'package:flutter/widgets.dart';

import '../../../../core/network/api_exception.dart';
import '../../../api/client/client_models.dart';
import '../../../api/listingflow/listing_queries.dart';
import '../../../component/c_alert.dart';
import '../../../listingflow/profile/host_profile_sheet.dart';

/// Taps on a favourite (RN `handleOpenProfile`).
abstract final class FavouritesActions {
  /// The host's profile sheet (calls, favourite toggle…), like a tap on a
  /// Discover card.
  static Future<void> openProfile(
    BuildContext context,
    FavoriteExpert favourite,
  ) async {
    final id = favourite.expertId?.trim() ?? '';
    if (id.isEmpty) return;
    try {
      final host = await ensureHostByLink(id);
      if (context.mounted) await showHostProfile(context, host);
    } on ApiException catch (e) {
      await CAlert.error(e);
    }
  }
}
