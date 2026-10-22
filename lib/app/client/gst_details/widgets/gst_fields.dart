import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/scale.dart';
import '../../../component/c_image.dart';
import '../../../component/c_text.dart';
import '../../../component/pressable.dart';
import '../../../component/skeleton.dart';
import '../helper/gst_palette.dart';

/// Small caps label above a field or tile.
class GstLabel extends StatelessWidget {
  const GstLabel(this.label, {super.key, this.bottom = 6});
  final String label;
  final double bottom;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: bottom.ms),
    child: CText(
      label,
      size: 10,
      weight: FontWeight.w900,
      letterSpacing: 1.8,
      uppercase: true,
      color: GstPalette.of(context).muted,
    ),
  );
}

/// Label, field, error (RN `Field`).
class GstField extends StatelessWidget {
  const GstField({
    super.key,
    required this.label,
    required this.child,
    this.error,
  });

  final String label;
  final Widget child;

  /// i18n key.
  final String? error;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: 16.ms),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GstLabel(label),
        child,
        if (error != null) ...[
          SizedBox(height: 6.ms),
          CText(
            error!,
            size: 12,
            weight: FontWeight.w700,
            color: StatusColors.danger,
          ),
        ],
      ],
    ),
  );
}

/// RN `Input`: 52 tall (100 multiline), card fill, soft when read-only.
class GstInput extends StatelessWidget {
  const GstInput({
    super.key,
    required this.controller,
    required this.placeholder,
    required this.editable,
    this.onChanged,
    this.multiline = false,
    this.maxLength,
    this.keyboardType,
    this.formatters = const [],
  });

  final TextEditingController controller;

  /// i18n key.
  final String placeholder;
  final bool editable;
  final ValueChanged<String>? onChanged;
  final bool multiline;
  final int? maxLength;
  final TextInputType? keyboardType;
  final List<TextInputFormatter> formatters;

  @override
  Widget build(BuildContext context) {
    final p = GstPalette.of(context);
    final style = TextStyle(
      color: p.text,
      fontSize: 15.ms,
      fontWeight: FontWeight.w700,
    );
    return Container(
      constraints: BoxConstraints(minHeight: (multiline ? 100 : 52).ms),
      padding: EdgeInsets.symmetric(
        horizontal: 16.ms,
        vertical: multiline ? 12.ms : 0,
      ),
      alignment: multiline ? Alignment.topLeft : Alignment.centerLeft,
      decoration: BoxDecoration(
        color: editable ? p.card : p.soft,
        borderRadius: BorderRadius.circular(16.ms),
        border: Border.all(color: p.border),
      ),
      child: TextField(
        controller: controller,
        enabled: editable,
        onChanged: onChanged,
        maxLines: multiline ? null : 1,
        minLines: multiline ? 3 : 1,
        keyboardType: multiline ? TextInputType.multiline : keyboardType,
        inputFormatters: [
          if (maxLength != null) LengthLimitingTextInputFormatter(maxLength),
          ...formatters,
        ],
        style: style,
        cursorColor: p.text,
        decoration: InputDecoration(
          isCollapsed: true,
          border: InputBorder.none,
          hintText: context.t(placeholder),
          hintStyle: style.copyWith(color: p.muted),
        ),
      ),
    );
  }
}

/// State / district picker row with a chevron.
class GstSelect extends StatelessWidget {
  const GstSelect({
    super.key,
    required this.value,
    required this.placeholder,
    required this.enabled,
    required this.onTap,
  });

  /// Picked name (server text), or null.
  final String? value;

  /// i18n key.
  final String placeholder;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = GstPalette.of(context);
    final v = value;
    return Pressable(
      onPressed: enabled ? onTap : null,
      child: Container(
        constraints: BoxConstraints(minHeight: 52.ms),
        padding: EdgeInsets.symmetric(horizontal: 16.ms),
        decoration: BoxDecoration(
          color: enabled ? p.card : p.soft,
          borderRadius: BorderRadius.circular(16.ms),
          border: Border.all(color: p.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: v != null && v.isNotEmpty
                  ? CText.raw(
                      v,
                      size: 14,
                      weight: FontWeight.w700,
                      color: p.text,
                      maxLines: 1,
                    )
                  : CText(
                      placeholder,
                      size: 14,
                      weight: FontWeight.w700,
                      color: p.muted,
                      maxLines: 1,
                    ),
            ),
            Icon(LucideIcons.chevronDown, size: 18.ms, color: p.muted),
          ],
        ),
      ),
    );
  }
}

/// GST certificate / business logo picker (100 tall).
class GstUploadTile extends StatelessWidget {
  const GstUploadTile({
    super.key,
    required this.label,
    required this.emptyLabel,
    required this.icon,
    required this.enabled,
    required this.onTap,
    this.path,
    this.url,
  });

  final String label;
  final String emptyLabel;
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  /// Picked on this device; wins over [url].
  final String? path;
  final String? url;

  @override
  Widget build(BuildContext context) {
    final p = GstPalette.of(context);
    final Widget content;
    if (path != null) {
      content = Image.file(
        File(path!),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    } else if (url != null) {
      content = CImage(url: url!, width: 160.ms, height: 100.ms);
    } else {
      content = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 24.ms, color: p.muted),
          SizedBox(height: 4.ms),
          CText(emptyLabel, size: 10, weight: FontWeight.w700, color: p.muted),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GstLabel(label, bottom: 8),
        Pressable(
          onPressed: enabled ? onTap : null,
          child: Container(
            height: 100.ms,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: p.card,
              borderRadius: BorderRadius.circular(18.ms),
              border: Border.all(color: p.border),
            ),
            child: content,
          ),
        ),
      ],
    );
  }
}

/// "Do you have GST registration?" with its switch.
class GstRegistrationToggle extends StatelessWidget {
  const GstRegistrationToggle({
    super.key,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = GstPalette.of(context);
    return Container(
      margin: EdgeInsets.only(bottom: 20.ms),
      padding: EdgeInsets.all(16.ms),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(18.ms),
        border: Border.all(color: p.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CText(
                  'resources:gst.toggle_title',
                  size: 14,
                  weight: FontWeight.w800,
                  color: p.text,
                ),
                SizedBox(height: 4.ms),
                CText(
                  'resources:gst.toggle_hint',
                  size: 12,
                  weight: FontWeight.w700,
                  color: p.muted,
                ),
              ],
            ),
          ),
          SizedBox(width: 12.ms),
          Switch.adaptive(
            value: value,
            onChanged: enabled ? onChanged : null,
            activeTrackColor: BrandColors.lime,
            activeThumbColor: AppColors.white,
            inactiveTrackColor: p.soft,
          ),
        ],
      ),
    );
  }
}

/// Not registered: the declaration checkbox (warning box).
class GstDeclaration extends StatelessWidget {
  const GstDeclaration({
    super.key,
    required this.checked,
    required this.enabled,
    required this.onTap,
    this.error,
  });

  final bool checked;
  final bool enabled;
  final VoidCallback onTap;

  /// i18n key.
  final String? error;

  @override
  Widget build(BuildContext context) {
    final p = GstPalette.of(context);
    return Container(
      margin: EdgeInsets.only(bottom: 20.ms),
      padding: EdgeInsets.all(14.ms),
      decoration: BoxDecoration(
        color: StatusColors.warningA(0.10),
        borderRadius: BorderRadius.circular(18.ms),
        border: Border.all(color: StatusColors.warningA(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Pressable(
            onPressed: enabled ? onTap : null,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 20.ms,
                  height: 20.ms,
                  margin: EdgeInsets.only(top: 1.ms, right: 10.ms),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: checked
                        ? StatusColors.warning
                        : AppColors.transparent,
                    borderRadius: BorderRadius.circular(6.ms),
                    border: Border.all(color: StatusColors.warning, width: 1.5),
                  ),
                  child: checked
                      ? Icon(
                          LucideIcons.check,
                          size: 14.ms,
                          color: AppColors.black,
                        )
                      : null,
                ),
                Expanded(
                  child: CText(
                    'resources:gst.declaration',
                    size: 13,
                    weight: FontWeight.w700,
                    color: p.text,
                    height: 18,
                  ),
                ),
              ],
            ),
          ),
          if (error != null) ...[
            SizedBox(height: 8.ms),
            CText(
              error!,
              size: 12,
              weight: FontWeight.w700,
              color: StatusColors.danger,
            ),
          ],
        ],
      ),
    );
  }
}

/// First load: toggle card and fields.
class GstSkeleton extends StatelessWidget {
  const GstSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Shimmer(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SkeletonBox(width: 130.ms, height: 10.ms, radius: 5),
        SizedBox(height: 12.ms),
        SkeletonBox(height: 76.ms, radius: 18.ms),
        SizedBox(height: 20.ms),
        for (var i = 0; i < 5; i++) ...[
          SkeletonBox(width: 90.ms, height: 10.ms, radius: 5),
          SizedBox(height: 6.ms),
          SkeletonBox(height: 52.ms, radius: 16.ms),
          SizedBox(height: 16.ms),
        ],
      ],
    ),
  );
}
