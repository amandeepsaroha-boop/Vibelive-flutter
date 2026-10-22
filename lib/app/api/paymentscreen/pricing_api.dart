import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/strapi.dart';
import 'billing_models.dart';

/// Pricing and tax configuration (single types).
abstract final class PricingApi {
  /// `GET /pricing-config`; deployments that expose it as a collection
  /// answer 404 there, so read the newest `/pricing-configs` row instead.
  /// Both missing (404) means "not configured": every value reads 0, as in
  /// RN. Other errors propagate.
  static Future<PricingConfig> fetchPricingConfig() async {
    try {
      final body = await ApiClient.get('/pricing-config');
      return PricingConfig(Strapi.map(Strapi.body(body)) ?? const {});
    } on ApiException catch (e) {
      if (e.statusCode != 404) rethrow;
    }
    try {
      final body = await ApiClient.get(
        '/pricing-configs',
        query: {
          'pagination[page]': 1,
          'pagination[pageSize]': 1,
          'sort': 'createdAt:desc',
        },
      );
      final first = Strapi.list(body).firstOrNull;
      return first == null ? PricingConfig.empty : PricingConfig(first);
    } on ApiException catch (e) {
      if (e.statusCode != 404) rethrow;
      return PricingConfig.empty;
    }
  }

  /// `GET /gst`. On failure the UI keeps [GstConfig.defaultIgstRate].
  static Future<GstConfig> fetchGstConfig() async =>
      GstConfig.fromResponse(await ApiClient.get('/gst'));
}
