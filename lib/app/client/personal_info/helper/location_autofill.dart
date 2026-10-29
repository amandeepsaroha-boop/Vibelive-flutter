import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../../../../core/analytics/events/me_events.dart';
import '../../../../core/location/current_place.dart';
import '../../../../core/network/api_exception.dart';
import '../../../api/client/client_models.dart';
import '../../../api/client/client_queries.dart';
import '../../../api/client/geo_match.dart';
import '../../../component/c_toast.dart';

/// The backend rows for the device's current place. [district] is null when
/// only the state could be matched.
@immutable
class LocationFill {
  const LocationFill(this.state, this.district);
  final GeoOption state;
  final GeoOption? district;
}

/// Fills the state / district pickers from the device's current location
/// (Personal Info and the host onboarding "Location" step).
abstract final class LocationAutofill {
  /// Current place → backend state and district. Throws [LocationException]
  /// or [ApiException].
  static Future<LocationFill> detect() async {
    final place = await CurrentPlace.detect();
    final country = (place.countryCode ?? '').toUpperCase();
    if (country.isNotEmpty && country != 'IN') {
      throw const LocationException(LocationFailure.notFound);
    }
    final state = GeoMatch.best(await ensureAllStates(), [place.state]);
    if (state == null) throw const LocationException(LocationFailure.notFound);
    final district = GeoMatch.best(await ensureAllDistricts(state), [
      place.district,
      place.city,
    ]);
    return LocationFill(state, district);
  }

  /// Runs [detect] and hands the result to [apply]. While it runs
  /// [locating] is true, and a second call is ignored.
  ///
  /// [silent] (the automatic attempt on opening a screen) says nothing when
  /// it fails: the pickers are still there. A tap on "Use current location"
  /// explains the failure and, where the fix is in Settings, opens it.
  /// [alive] is checked after the wait: a screen left meanwhile has disposed
  /// the notifiers. [stillEmpty] (silent runs) is checked too: a saved
  /// location that loaded meanwhile is never replaced. [analyticsSource]:
  /// the screen, for the `location_autofill` event.
  static Future<void> run({
    required ValueNotifier<bool> locating,
    required void Function(LocationFill fill) apply,
    required bool Function() alive,
    bool silent = false,
    bool Function()? stillEmpty,
    String? analyticsSource,
  }) async {
    if (locating.value) return;
    locating.value = true;
    void track(String result, [String? reason]) =>
        PersonalInfoEvents.locationAutofill(
          trigger: silent ? 'auto' : 'tap',
          result: result,
          reason: reason,
          source: analyticsSource,
        );
    try {
      final fill = await detect();
      if (!alive()) return;
      if (silent && stillEmpty != null && !stillEmpty()) return;
      apply(fill);
      final district = fill.district;
      track(district == null ? 'state_only' : 'filled');
      if (district == null) {
        CToast.show(
          'client:location.state_only',
          variables: {'state': fill.state.name},
        );
      } else {
        CToast.show(
          'client:location.filled',
          variables: {'place': '${district.name}, ${fill.state.name}'},
          variant: CToastVariant.success,
        );
      }
    } on LocationException catch (e) {
      track('failed', e.reason.name);
      if (silent || !alive()) return;
      switch (e.reason) {
        case LocationFailure.serviceOff:
          CToast.show(
            'client:location.service_off',
            variant: CToastVariant.error,
          );
          await Geolocator.openLocationSettings();
        case LocationFailure.deniedForever:
          CToast.show(
            'client:location.denied_forever',
            variant: CToastVariant.error,
          );
          await Geolocator.openAppSettings();
        case LocationFailure.denied:
          CToast.show('client:location.denied', variant: CToastVariant.error);
        case LocationFailure.unavailable:
          CToast.show(
            'client:location.unavailable',
            variant: CToastVariant.error,
          );
        case LocationFailure.notFound:
          CToast.show(
            'client:location.not_found',
            variant: CToastVariant.error,
          );
      }
    } on ApiException catch (e) {
      track('failed', 'api');
      if (!silent && alive()) CToast.error(e);
    } finally {
      if (alive()) locating.value = false;
    }
  }
}
