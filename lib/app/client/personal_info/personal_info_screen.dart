import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../api/authscreen/interests_queries.dart';
import '../../api/client/client_queries.dart';
import '../../component/c_alert.dart';
import '../../component/c_state_view.dart';
import '../../component/keyboard_inset.dart';
import '../../component/status_bar_style.dart';
import '../../component/vibe_background.dart';
import 'helper/gender_answer.dart';
import 'helper/location_autofill.dart';
import 'helper/personal_info_actions.dart';
import 'helper/personal_info_controller.dart';
import 'helper/personal_info_palette.dart';
import 'widgets/basic_info_section.dart';
import 'widgets/geo_picker_sheet.dart';
import 'widgets/personal_info_skeleton.dart';
import 'widgets/personal_info_top_bar.dart';
import 'widgets/photo_header.dart';

/// `/me/personal-info` (RN `PersonalInfoScreen`): photo, name, email,
/// mobile, state and district. Calls, wallet top-up and "Become a Host"
/// send users here when name / email / mobile are missing; Save returns
/// them to where they came from.
class PersonalInfoScreen extends HookWidget {
  const PersonalInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = PersonalInfoPalette.of(context);
    final form = useMemoized(PersonalInfoController.new);
    useEffect(() => form.dispose, [form]);

    final profileQuery = useMyProfile(context);
    final profile = profileQuery.data;
    // First data: fill before the form is built (no empty frame). Later
    // refetches go through the effect and never overwrite edits.
    if (profile != null && form.profile == null) form.seed(profile);
    useEffect(() {
      if (profile != null && !identical(profile, form.profile)) {
        form.seed(profile);
      }
      return null;
    }, [profile]);

    // Gender is the public-user `gender` (seeded with the profile); an
    // older interests answer only fills it when the user field is empty.
    final answers = useMyInterests(context);
    useEffect(() {
      final sel = answers.data?.selections;
      if (sel != null && form.gender.value == null) {
        form.seedGender(GenderAnswer.fromAnswers(sel));
      }
      return null;
    }, [answers.data]);

    final actions = usePersonalInfoActions(context, form);

    // No saved location yet: fill state / district from where the device is,
    // once per visit. A saved address is never replaced automatically; the
    // "Use current location" link does that on request.
    final autoLocated = useRef(false);
    useEffect(() {
      if (profile == null || autoLocated.value) return null;
      autoLocated.value = true;
      if (form.state.value == null && form.district.value == null) {
        LocationAutofill.run(
          locating: form.locating,
          apply: form.applyLocation,
          alive: () => context.mounted,
          silent: true,
        );
      }
      return null;
    }, [profile]);

    void useCurrentLocation() => LocationAutofill.run(
      locating: form.locating,
      apply: form.applyLocation,
      alive: () => context.mounted,
    );

    Future<void> pickState() async {
      final picked = await showGeoPicker(context, kind: GeoPickerKind.state);
      if (picked != null) form.selectState(picked);
    }

    Future<void> pickDistrict() async {
      final state = form.state.value;
      if (state == null) {
        await CAlert.show(
          title: 'client:personal_info.title',
          message: 'client:personal_info.picker.select_state_first',
        );
        return;
      }
      final picked = await showGeoPicker(
        context,
        kind: GeoPickerKind.district,
        state: state,
      );
      if (picked != null) form.selectDistrict(picked);
    }

    final Widget body;
    if (profile == null) {
      body = profileQuery.isError
          ? CStateView.error(
              context,
              profileQuery.error!,
              onRetry: profileQuery.refetch,
            )
          : const PersonalInfoSkeleton();
    } else {
      final bottomSafe = MediaQuery.viewPaddingOf(context).bottom;
      body = CustomScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
        slivers: [
          SliverToBoxAdapter(
            child: PhotoHeader(
              form: form,
              photoUrl: profile.profilePicUrl,
              onChangePhoto: actions.changePhoto,
            ),
          ),
          SliverFillRemaining(
            hasScrollBody: false,
            child: BasicInfoSection(
              form: form,
              onPickState: pickState,
              onPickDistrict: pickDistrict,
              onUseLocation: useCurrentLocation,
              bottomPadding: 60 + bottomSafe,
            ),
          ),
        ],
      );
    }

    return ThemedStatusBar(
      child: Scaffold(
        backgroundColor: p.bg,
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            const VibeBackground(),
            KeyboardInset(
              child: Column(
                children: [
                  SafeArea(
                    bottom: false,
                    child: PersonalInfoTopBar(
                      saving: form.saving,
                      loading: profile == null,
                      onBack: actions.leave,
                      onSave: actions.save,
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      // Tap outside a field closes the keyboard.
                      onTap: () =>
                          FocusManager.instance.primaryFocus?.unfocus(),
                      behavior: HitTestBehavior.translucent,
                      child: body,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
