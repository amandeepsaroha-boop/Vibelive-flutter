import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/strapi.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/scale.dart';
import '../../api/client/client_queries.dart';
import '../../component/c_alert.dart';
import '../../component/c_button.dart';
import '../../component/c_state_view.dart';
import '../../component/c_text.dart';
import '../../component/status_bar_style.dart';
import '../../component/vibe_background.dart';
import '../../resourcesscreen/widgets/sub_page_header.dart';
import '../personal_info/widgets/geo_picker_sheet.dart';
import 'helper/gst_form.dart';
import 'helper/gst_palette.dart';
import 'widgets/gst_fields.dart';

/// `/me/gst-details` (RN `GstDetailsScreen`): GST registration details, or
/// the non-registration declaration. Read-only once submitted until the
/// pencil is tapped.
class GstDetailsScreen extends HookWidget {
  const GstDetailsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final details = useGstDetails(context);
    final save = useSaveGstDetails();
    final form = useMemoized(GstForm.new);
    useEffect(() => form.dispose, [form]);
    useListenable(form);
    final data = details.data;
    useEffect(() {
      if (data != null) form.seed(data);
      return null;
    }, [data]);
    final saving = useState(false);
    final p = GstPalette.of(context);
    final bottom = MediaQuery.paddingOf(context).bottom;

    Future<void> pickImage(void Function(String) set) async {
      final path = await GstImageSource.instance.pick();
      if (path != null) set(path);
    }

    Future<void> onSave() async {
      if (saving.value || !form.editable) return;
      FocusScope.of(context).unfocus();
      if (!form.validate()) return;
      saving.value = true;
      try {
        final saved = await save.mutateAsync(
          form.input(context.t('resources:gst.declaration_statement')),
        );
        form.markSaved(J.str(saved?['documentId']) ?? J.str(saved?['id']));
        if (!context.mounted) return;
        saving.value = false;
        await CAlert.show(
          title: 'resources:gst.title',
          message: 'resources:gst.saved_message',
          primaryLabel: 'resources:gst.continue',
          variant: CAlertVariant.success,
        );
      } on ApiException catch (e) {
        await CAlert.error(e);
      } finally {
        if (context.mounted) saving.value = false;
      }
    }

    final editable = form.editable;
    final Widget body;
    if (!form.seeded && details.isError && details.error != null) {
      body = CStateView.error(
        context,
        details.error!,
        onRetry: () => details.refetch(),
      );
    } else if (!form.seeded) {
      body = Padding(
        padding: EdgeInsets.fromLTRB(20.ms, 16.ms, 20.ms, 0),
        child: const GstSkeleton(),
      );
    } else {
      body = SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(20.ms, 16.ms, 20.ms, 40.ms + bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const GstLabel('resources:gst.section', bottom: 12),
            if (form.submitted && !form.editMode)
              Container(
                margin: EdgeInsets.only(bottom: 16.ms),
                padding: EdgeInsets.symmetric(
                  horizontal: 14.ms,
                  vertical: 12.ms,
                ),
                decoration: BoxDecoration(
                  color: BrandColors.limeA(0.12),
                  borderRadius: BorderRadius.circular(14.ms),
                  border: Border.all(color: BrandColors.limeA(0.35)),
                ),
                child: const CText(
                  'resources:gst.submitted_banner',
                  size: 12,
                  weight: FontWeight.w800,
                  color: BrandColors.lime,
                  height: 18,
                ),
              ),
            GstRegistrationToggle(
              value: form.hasRegistration,
              enabled: editable,
              onChanged: form.setRegistration,
            ),
            if (form.hasRegistration)
              ..._registeredFields(context, form, editable, pickImage)
            else
              GstDeclaration(
                checked: form.declarationConfirmed,
                enabled: editable,
                error: form.errors['declaration'],
                onTap: form.toggleDeclaration,
              ),
            SizedBox(height: 10.ms),
            CButton(
              title: form.submitted && !form.editMode
                  ? 'resources:gst.submitted'
                  : 'resources:gst.save',
              onPressed: onSave,
              loading: saving.value,
              disabled: !editable,
              showArrow: false,
            ),
          ],
        ),
      );
    }

    return ThemedStatusBar(
      child: Scaffold(
        backgroundColor: p.bg,
        body: Stack(
          children: [
            const VibeBackground(),
            SafeArea(
              bottom: false,
              child: Column(
                children: [
                  SubPageHeader(
                    title: 'resources:gst.title',
                    trailing: form.submitted
                        ? SubPageButton(
                            icon: LucideIcons.pencil,
                            iconSize: 15,
                            label: 'resources:gst.edit',
                            onPressed: form.toggleEdit,
                          )
                        : null,
                  ),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () => FocusScope.of(context).unfocus(),
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

  static List<Widget> _registeredFields(
    BuildContext context,
    GstForm form,
    bool editable,
    Future<void> Function(void Function(String)) pickImage,
  ) => [
    GstField(
      label: 'resources:gst.number',
      error: form.errors['number'],
      child: GstInput(
        controller: form.number,
        placeholder: 'resources:gst.number_placeholder',
        editable: editable,
        maxLength: 15,
        formatters: [_UpperCase()],
        onChanged: (_) => form.clearError('number'),
      ),
    ),
    GstField(
      label: 'resources:gst.business',
      error: form.errors['business'],
      child: GstInput(
        controller: form.business,
        placeholder: 'resources:gst.business_placeholder',
        editable: editable,
        maxLength: 100,
        onChanged: (_) => form.clearError('business'),
      ),
    ),
    GstField(
      label: 'resources:gst.address',
      error: form.errors['address'],
      child: GstInput(
        controller: form.address,
        placeholder: 'resources:gst.address_placeholder',
        editable: editable,
        multiline: true,
        maxLength: 400,
        onChanged: (_) => form.clearError('address'),
      ),
    ),
    GstField(
      label: 'resources:gst.zipcode',
      child: GstInput(
        controller: form.zipcode,
        placeholder: 'resources:gst.zipcode_placeholder',
        editable: editable,
        maxLength: 6,
        keyboardType: TextInputType.number,
        formatters: [FilteringTextInputFormatter.digitsOnly],
      ),
    ),
    GstField(
      label: 'resources:gst.state',
      child: GstSelect(
        value: form.state?.name,
        placeholder: 'resources:gst.state_placeholder',
        enabled: editable,
        onTap: () async {
          final picked = await showGeoPicker(
            context,
            kind: GeoPickerKind.state,
          );
          if (picked != null) form.setState(picked);
        },
      ),
    ),
    GstField(
      label: 'resources:gst.district',
      child: GstSelect(
        value: form.district?.name,
        placeholder: form.state == null
            ? 'resources:gst.district_needs_state'
            : 'resources:gst.district_placeholder',
        enabled: editable && form.state != null,
        onTap: () async {
          final picked = await showGeoPicker(
            context,
            kind: GeoPickerKind.district,
            state: form.state,
          );
          if (picked != null) form.setDistrict(picked);
        },
      ),
    ),
    Padding(
      padding: EdgeInsets.only(bottom: 16.ms),
      child: Row(
        children: [
          Expanded(
            child: GstUploadTile(
              label: 'resources:gst.certificate',
              emptyLabel: 'resources:gst.upload_file',
              icon: LucideIcons.fileText,
              enabled: editable,
              path: form.gstFilePath,
              url: form.gstFileUrl,
              onTap: () => pickImage(form.setGstFile),
            ),
          ),
          SizedBox(width: 12.ms),
          Expanded(
            child: GstUploadTile(
              label: 'resources:gst.logo',
              emptyLabel: 'resources:gst.upload_logo',
              icon: LucideIcons.image,
              enabled: editable,
              path: form.logoPath,
              url: form.logoUrl,
              onTap: () => pickImage(form.setLogo),
            ),
          ),
        ],
      ),
    ),
  ];
}

/// GST numbers are upper case (RN `v.toUpperCase()`).
class _UpperCase extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => newValue.copyWith(text: newValue.text.toUpperCase());
}
