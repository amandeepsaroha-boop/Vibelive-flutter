import 'package:flutter/material.dart';

import '../../../../core/utils/scale.dart';
import '../../../api/client/client_models.dart';
import '../../../component/c_input.dart' show IndianMobileFormatter;
import '../../../component/c_text.dart';
import '../helper/personal_info_controller.dart';
import '../helper/personal_info_palette.dart';
import 'gender_chips.dart';
import 'info_fields.dart';
import 'use_location_button.dart';

/// "BASIC INFO": name, email, mobile, state, district (RN form card). Fills
/// the rest of the screen; [bottomPadding] clears the home indicator.
class BasicInfoSection extends StatelessWidget {
  const BasicInfoSection({
    super.key,
    required this.form,
    required this.onPickState,
    required this.onPickDistrict,
    required this.onUseLocation,
    required this.bottomPadding,
  });

  final PersonalInfoController form;
  final VoidCallback onPickState;
  final VoidCallback onPickDistrict;
  final VoidCallback onUseLocation;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    final p = PersonalInfoPalette.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 1),
      padding: EdgeInsets.fromLTRB(20.ms, 28.ms, 20.ms, bottomPadding),
      decoration: BoxDecoration(
        color: p.card,
        border: Border(top: BorderSide(color: p.border)),
      ),
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.only(bottom: 10.ms),
              child: CText(
                'client:personal_info.basic_info',
                size: 10,
                weight: FontWeight.w900,
                letterSpacing: 1.5,
                color: p.muted,
              ),
            ),
            InfoField(
              label: 'client:personal_info.fields.name',
              child: InfoTextField(
                key: const ValueKey('personal_info.name'),
                controller: form.name,
                placeholder: 'client:personal_info.placeholders.name',
                keyboardType: TextInputType.name,
                autofillHints: const [AutofillHints.name],
              ),
            ),
            InfoField(
              label: 'client:personal_info.fields.email',
              child: InfoTextField(
                key: const ValueKey('personal_info.email'),
                controller: form.email,
                placeholder: 'client:personal_info.placeholders.email',
                keyboardType: TextInputType.emailAddress,
                capitalization: TextCapitalization.none,
                autofillHints: const [AutofillHints.email],
              ),
            ),
            InfoField(
              label: 'client:personal_info.fields.mobile',
              // RN: read-only while saving.
              child: ValueListenableBuilder<bool>(
                valueListenable: form.saving,
                builder: (_, saving, _) => InfoTextField(
                  key: const ValueKey('personal_info.mobile'),
                  controller: form.mobile,
                  placeholder: 'client:personal_info.placeholders.mobile',
                  keyboardType: TextInputType.phone,
                  capitalization: TextCapitalization.none,
                  enabled: !saving,
                  maxLength: 10,
                  inputFormatters: const [IndianMobileFormatter()],
                  autofillHints: const [AutofillHints.telephoneNumberNational],
                  textInputAction: TextInputAction.done,
                ),
              ),
            ),
            InfoField(
              label: 'client:personal_info.fields.gender',
              child: GenderChips(gender: form.gender),
            ),
            Padding(
              padding: EdgeInsets.only(bottom: 12.ms),
              child: UseLocationButton(
                locating: form.locating,
                onPressed: onUseLocation,
              ),
            ),
            InfoField(
              label: 'client:personal_info.fields.state',
              child: InfoSelectField(
                key: const ValueKey('personal_info.state'),
                value: form.state,
                placeholder: 'client:personal_info.placeholders.state',
                onPressed: onPickState,
              ),
            ),
            InfoField(
              label: 'client:personal_info.fields.district',
              child: ValueListenableBuilder<GeoOption?>(
                valueListenable: form.state,
                builder: (_, state, _) => InfoSelectField(
                  key: const ValueKey('personal_info.district'),
                  value: form.district,
                  placeholder: 'client:personal_info.placeholders.district',
                  enabled: state != null,
                  onPressed: onPickDistrict,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
