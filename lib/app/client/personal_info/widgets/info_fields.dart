import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../core/utils/scale.dart';
import '../../../api/client/client_models.dart';
import '../../../component/c_text.dart';
import '../../../component/pressable.dart';
import '../helper/personal_info_palette.dart';

/// Uppercase-tracked label above a field (RN `Field`). [label] is an i18n
/// key.
class InfoField extends StatelessWidget {
  const InfoField({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = PersonalInfoPalette.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: 18.ms),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.only(bottom: 10.ms),
            child: CText(
              label,
              size: 13,
              weight: FontWeight.w900,
              letterSpacing: 1.2,
              color: p.muted,
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// Rounded box shared by the text and select fields (RN `TextField` /
/// `SelectField` container).
class _FieldBox extends StatelessWidget {
  const _FieldBox({required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = PersonalInfoPalette.of(context);
    return Container(
      constraints: BoxConstraints(minHeight: 56.ms),
      padding: EdgeInsets.symmetric(horizontal: 16.ms),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: enabled ? p.card : p.soft,
        borderRadius: BorderRadius.circular(16.ms),
        border: Border.all(color: p.border),
      ),
      child: child,
    );
  }
}

/// Plain text input in a rounded box (RN `TextField`). The controller is
/// its own notifier: typing rebuilds this field only. [placeholder] is an
/// i18n key.
class InfoTextField extends StatelessWidget {
  const InfoTextField({
    super.key,
    required this.controller,
    required this.placeholder,
    this.keyboardType = TextInputType.text,
    this.capitalization = TextCapitalization.words,
    this.enabled = true,
    this.maxLength,
    this.inputFormatters,
    this.autofillHints,
    this.textInputAction = TextInputAction.next,
  });

  final TextEditingController controller;
  final String placeholder;
  final TextInputType keyboardType;
  final TextCapitalization capitalization;
  final bool enabled;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;
  final Iterable<String>? autofillHints;
  final TextInputAction textInputAction;

  @override
  Widget build(BuildContext context) {
    final p = PersonalInfoPalette.of(context);
    return MediaQuery.withNoTextScaling(
      child: _FieldBox(
        enabled: enabled,
        child: TextField(
          controller: controller,
          enabled: enabled,
          keyboardType: keyboardType,
          textCapitalization: capitalization,
          textInputAction: textInputAction,
          autocorrect: false,
          maxLength: maxLength,
          inputFormatters: inputFormatters,
          autofillHints: autofillHints,
          cursorColor: p.accent,
          // Keeps the field clear of the keyboard with room to spare.
          scrollPadding: EdgeInsets.all(40.ms),
          style: TextStyle(
            color: p.text,
            fontWeight: FontWeight.w700,
            fontSize: 16.ms,
          ),
          decoration: InputDecoration(
            isCollapsed: true,
            border: InputBorder.none,
            counterText: '',
            contentPadding: EdgeInsets.symmetric(vertical: 16.ms),
            hintText: context.t(placeholder),
            hintStyle: TextStyle(
              color: p.muted,
              fontWeight: FontWeight.w700,
              fontSize: 16.ms,
            ),
          ),
        ),
      ),
    );
  }
}

/// Tappable box showing the picked option, else the placeholder, with a
/// chevron (RN `SelectField`). Rebuilds only when [value] changes.
class InfoSelectField extends StatelessWidget {
  const InfoSelectField({
    super.key,
    required this.value,
    required this.placeholder,
    required this.onPressed,
    this.enabled = true,
  });

  final ValueListenable<GeoOption?> value;

  /// i18n key.
  final String placeholder;
  final VoidCallback onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final p = PersonalInfoPalette.of(context);
    return Opacity(
      opacity: enabled ? 1 : 0.6,
      child: Pressable(
        activeOpacity: 0.86,
        onPressed: enabled ? onPressed : null,
        child: _FieldBox(
          enabled: enabled,
          child: Row(
            children: [
              Expanded(
                child: ValueListenableBuilder<GeoOption?>(
                  valueListenable: value,
                  builder: (_, option, _) {
                    final name = option?.name ?? '';
                    final style = (
                      size: 16.0,
                      weight: FontWeight.w900,
                      color: name.isEmpty ? p.muted : p.text,
                    );
                    return name.isEmpty
                        ? CText(
                            placeholder,
                            size: style.size,
                            weight: style.weight,
                            color: style.color,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )
                        : CText.raw(
                            name,
                            size: style.size,
                            weight: style.weight,
                            color: style.color,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          );
                  },
                ),
              ),
              SizedBox(width: 8.ms),
              Icon(LucideIcons.chevronDown, size: 18.ms, color: p.muted),
            ],
          ),
        ),
      ),
    );
  }
}
