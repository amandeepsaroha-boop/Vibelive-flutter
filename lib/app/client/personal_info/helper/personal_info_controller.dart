import 'package:flutter/widgets.dart';

import '../../../api/client/client_models.dart';
import '../../../api/client/profile_api.dart';
import 'personal_info_validation.dart';

/// Form state of Personal Info. One notifier per field, so typing in a
/// field (or picking a state) rebuilds only that field.
class PersonalInfoController {
  final name = TextEditingController();
  final email = TextEditingController();
  final mobile = TextEditingController();
  final state = ValueNotifier<GeoOption?>(null);
  final district = ValueNotifier<GeoOption?>(null);

  /// Save / photo upload in flight (header button, avatar, mobile field).
  final saving = ValueNotifier<bool>(false);
  final uploading = ValueNotifier<bool>(false);

  UserWithExpert? _profile;
  _Snapshot? _seeded;

  /// The profile being edited (latest one loaded).
  UserWithExpert? get profile => _profile;

  /// The user changed something since the last [seed].
  bool get isDirty {
    final s = _seeded;
    return s != null && s != _snapshot();
  }

  /// Fills the form from [p]. A background refetch never overwrites what
  /// the user is typing: unless [force], edited fields are kept.
  void seed(UserWithExpert p, {bool force = false}) {
    final keep = isDirty && !force;
    _profile = p;
    if (keep) return;
    name.text = p.name ?? '';
    email.text = p.email ?? '';
    mobile.text = p.mobile ?? '';
    state.value = p.state;
    district.value = p.district;
    _seeded = _snapshot();
  }

  /// A new state clears the district (RN `handleSelectState`).
  void selectState(GeoOption option) {
    if (_same(option, state.value)) return;
    state.value = option;
    district.value = null;
  }

  void selectDistrict(GeoOption option) => district.value = option;

  PersonalInfoIssue? validate() => PersonalInfoValidation.validate(
    name: name.text,
    email: email.text,
    mobile: mobile.text,
    state: state.value,
    district: district.value,
  );

  /// Call after [validate] passed and [profile] is loaded.
  PersonalInfoInput input() => PersonalInfoInput(
    current: _profile!,
    name: name.text,
    email: email.text,
    mobile: mobile.text,
    state: state.value!,
    district: district.value,
  );

  _Snapshot _snapshot() => _Snapshot(
    name.text,
    email.text,
    mobile.text,
    _key(state.value),
    _key(district.value),
  );

  static String _key(GeoOption? o) =>
      o == null ? '' : '${o.filterId ?? ''}|${o.name}';

  static bool _same(GeoOption? a, GeoOption? b) => _key(a) == _key(b);

  void dispose() {
    name.dispose();
    email.dispose();
    mobile.dispose();
    state.dispose();
    district.dispose();
    saving.dispose();
    uploading.dispose();
  }
}

@immutable
class _Snapshot {
  const _Snapshot(
    this.name,
    this.email,
    this.mobile,
    this.state,
    this.district,
  );

  final String name, email, mobile, state, district;

  @override
  bool operator ==(Object other) =>
      other is _Snapshot &&
      other.name == name &&
      other.email == email &&
      other.mobile == mobile &&
      other.state == state &&
      other.district == district;

  @override
  int get hashCode => Object.hash(name, email, mobile, state, district);
}
