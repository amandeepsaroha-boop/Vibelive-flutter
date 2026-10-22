import '../../../core/network/api_client.dart';
import '../../../core/network/strapi.dart';
import 'client_models.dart';

/// Countries, states and districts for the address pickers (Personal Info,
/// GST). Reference data: cache with `StaleTime.static`.
abstract final class GeoApi {
  static const defaultCountry = 'India';

  static Future<List<GeoOption>> fetchCountries({
    String search = '',
    int page = 1,
    int pageSize = 25,
  }) async => _options(
    await ApiClient.get(
      '/countries',
      query: {
        'pagination[page]': page,
        'pagination[pageSize]': pageSize,
        'sort': 'name:asc',
        if (search.isNotEmpty) r'filters[name][$containsi]': search,
      },
    ),
  );

  /// Case-insensitive exact match, or null.
  static Future<GeoOption?> findCountryByName(String name) async {
    final rows = _options(
      await ApiClient.get(
        '/countries',
        query: {
          r'filters[name][$eqi]': name,
          'pagination[page]': 1,
          'pagination[pageSize]': 1,
        },
      ),
    );
    return rows.isEmpty ? null : rows.first;
  }

  static Future<List<GeoOption>> fetchStates({
    String search = '',
    String? countryName = defaultCountry,
    int page = 1,
    int pageSize = 45,
  }) async {
    final query = <String, dynamic>{
      'pagination[page]': page,
      'pagination[pageSize]': pageSize,
      'sort': 'name:asc',
      if (search.isNotEmpty) r'filters[name][$containsi]': search,
    };
    if (countryName != null && countryName.isNotEmpty) {
      final rows = _options(
        await ApiClient.get(
          '/states',
          query: {...query, r'filters[country][name][$eqi]': countryName},
        ),
      );
      // Some datasets have no country relation on states: retry unfiltered.
      if (rows.isNotEmpty) return rows;
    }
    return _options(await ApiClient.get('/states', query: query));
  }

  static Future<List<GeoOption>> fetchDistricts({
    required String stateId,
    GeoIdField field = GeoIdField.documentId,
    String search = '',
    int page = 1,
    int pageSize = 45,
  }) async {
    if (stateId.isEmpty) return const [];
    final query = <String, dynamic>{
      'pagination[page]': page,
      'pagination[pageSize]': pageSize,
      'sort': 'name:asc',
      if (search.isNotEmpty) r'filters[name][$containsi]': search,
    };
    final rows = _options(
      await ApiClient.get(
        '/districts',
        query: {...query, _stateKey(field): stateId},
      ),
    );
    if (rows.isNotEmpty) return rows;

    // No match: retry with the other state key (backends differ). Never send
    // a non-numeric documentId to `[id]`: Postgres fails the integer cast.
    final other = field == GeoIdField.id
        ? GeoIdField.documentId
        : GeoIdField.id;
    if (other == GeoIdField.id && int.tryParse(stateId) == null) return rows;
    return _options(
      await ApiClient.get(
        '/districts',
        query: {...query, _stateKey(other): stateId},
      ),
    );
  }

  static String _stateKey(GeoIdField field) =>
      'filters[state][${field.name}][\$eq]';

  static List<GeoOption> _options(dynamic body) => [
    for (final row in Strapi.list(body)) GeoOption(row),
  ];
}
