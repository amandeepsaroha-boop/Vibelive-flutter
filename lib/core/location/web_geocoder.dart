import 'package:dio/dio.dart';

import '../utils/log.dart';
import 'current_place.dart';

/// Free, keyless reverse geocoders for when the device's own geocoder has
/// no answer (no Play Services, no geocoder, or a placemark without a
/// state / district). Tried in order; null when none could name the place.
///
/// - BigDataCloud "reverse-geocode-client": free for a device's own live
///   location (exactly this use), no key.
/// - OpenStreetMap Nominatim: free, no key; its policy asks for an
///   identifying User-Agent and at most one request a second, which a
///   one-shot fallback stays well under.
abstract final class WebGeocoder {
  static final _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 6),
      receiveTimeout: const Duration(seconds: 8),
      headers: {'User-Agent': 'VibeLive-App/1.0 (mobile; reverse geocode)'},
    ),
  );

  static Future<DetectedPlace?> lookup(double lat, double lng) async {
    for (final source in [_bigDataCloud, _nominatim]) {
      try {
        final place = await source(lat, lng);
        if (place?.state != null) return place;
      } catch (e) {
        Log.w('WebGeocoder', 'reverse geocode failed: $e');
      }
    }
    return null;
  }

  static Future<DetectedPlace?> _bigDataCloud(double lat, double lng) async {
    final res = await _dio.get<Map<String, dynamic>>(
      'https://api-bdc.io/data/reverse-geocode-client',
      queryParameters: {
        'latitude': lat,
        'longitude': lng,
        'localityLanguage': 'en',
      },
    );
    final d = res.data;
    if (d == null) return null;
    // India on OSM boundaries: level 4 = state, level 5 = district. Rows go
    // largest first, so the last of a level is the most specific ("Mumbai"
    // then "Mumbai Suburban district").
    String? level(int n) {
      final admin = (d['localityInfo'] as Map?)?['administrative'];
      if (admin is! List) return null;
      String? found;
      for (final a in admin) {
        if (a is Map && a['adminLevel'] == n) {
          found = _clean(a['name']) ?? found;
        }
      }
      return found;
    }

    return DetectedPlace(
      state: _clean(d['principalSubdivision']) ?? level(4),
      district: level(5),
      city: _clean(d['city']) ?? _clean(d['locality']),
      countryCode: _clean(d['countryCode']),
    );
  }

  static Future<DetectedPlace?> _nominatim(double lat, double lng) async {
    final res = await _dio.get<Map<String, dynamic>>(
      'https://nominatim.openstreetmap.org/reverse',
      queryParameters: {
        'format': 'jsonv2',
        'lat': lat,
        'lon': lng,
        'zoom': 10,
        'addressdetails': 1,
        'accept-language': 'en',
      },
    );
    final a = res.data?['address'];
    if (a is! Map) return null;
    return DetectedPlace(
      state: _clean(a['state']),
      district: _clean(a['state_district']) ?? _clean(a['county']),
      city: _clean(a['city']) ?? _clean(a['town']) ?? _clean(a['village']),
      countryCode: _clean(a['country_code'])?.toUpperCase(),
    );
  }

  static String? _clean(dynamic s) {
    final t = (s is String ? s : '').trim();
    return t.isEmpty ? null : t;
  }
}
