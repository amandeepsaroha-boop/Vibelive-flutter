import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

/// Why the device could not tell where it is (or [notFound]: it could, but
/// the place is not one the app offers).
enum LocationFailure {
  serviceOff,
  denied,
  deniedForever,
  unavailable,
  notFound,
}

class LocationException implements Exception {
  const LocationException(this.reason);
  final LocationFailure reason;

  @override
  String toString() => 'LocationException(${reason.name})';
}

/// The device's current place as the OS geocoder names it (English).
@immutable
class DetectedPlace {
  const DetectedPlace({this.state, this.district, this.city, this.countryCode});

  /// administrativeArea: "Haryana".
  final String? state;

  /// subAdministrativeArea: "Faridabad" (sometimes "… Division").
  final String? district;

  /// locality: "Faridabad", "Gurugram".
  final String? city;

  /// ISO code: "IN".
  final String? countryCode;
}

/// One-shot current location → place names, for filling address pickers.
///
/// Asks for "while in use" permission when it has not been decided yet.
/// Throws [LocationException] for anything the user can act on (location off,
/// permission refused) or when no fix / address could be found.
abstract final class CurrentPlace {
  static Future<DetectedPlace> detect() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationException(LocationFailure.serviceOff);
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationException(LocationFailure.deniedForever);
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.unableToDetermine) {
      throw const LocationException(LocationFailure.denied);
    }

    // State and district only need city-level accuracy; a slow first fix
    // falls back to the last known position rather than failing.
    Position? position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 15),
        ),
      );
    } on TimeoutException {
      position = await Geolocator.getLastKnownPosition();
    } on LocationServiceDisabledException {
      throw const LocationException(LocationFailure.serviceOff);
    } on PermissionDeniedException {
      throw const LocationException(LocationFailure.denied);
    }
    if (position == null) {
      throw const LocationException(LocationFailure.unavailable);
    }

    final List<Placemark> marks;
    try {
      // English names: the backend's states/districts are English, whatever
      // the app language is.
      marks = await Geocoding().placemarkFromCoordinates(
        position.latitude,
        position.longitude,
        locale: const Locale('en', 'IN'),
      );
    } catch (_) {
      // No geocoder on the device, or no network for it.
      throw const LocationException(LocationFailure.unavailable);
    }
    final mark = marks.isEmpty ? null : marks.first;
    if (mark == null || (_clean(mark.administrativeArea) == null)) {
      throw const LocationException(LocationFailure.unavailable);
    }
    return DetectedPlace(
      state: _clean(mark.administrativeArea),
      district: _clean(mark.subAdministrativeArea),
      city: _clean(mark.locality),
      countryCode: _clean(mark.isoCountryCode),
    );
  }

  static String? _clean(String? s) {
    final t = (s ?? '').trim();
    return t.isEmpty ? null : t;
  }
}
