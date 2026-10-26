import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../core/utils/scale.dart';
import '../../../component/c_text.dart';
import '../helper/host_palette.dart';

/// The design's text box: a rounded rectangle without an icon (`CInput` is
/// the auth pill with a leading icon). Multi-line fields grow up to
/// [maxLines]; with [maxLength] a live "n/max" counter sits under it and is
/// the only thing that rebuilds while typing.
class HostField extends StatefulWidget {
  const HostField({
    super.key,
    required this.controller,
    this.hint,
    this.maxLength,
    this.minLines = 1,
    this.maxLines = 1,
    this.trailing,
    this.inputFormatters,
    this.capitalization = TextCapitalization.sentences,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.fieldKey,
    this.readOnly = false,
    this.counterLeading,
  });

  final TextEditingController controller;

  /// i18n key.
  final String? hint;
  final int? maxLength;
  final int minLines;
  final int maxLines;
  final Widget? trailing;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization capitalization;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;

  /// Key of the inner `TextField` (tests).
  final Key? fieldKey;

  /// Text can't change (e.g. while it is being enhanced).
  final bool readOnly;

  /// Sits on the counter's row, before "n/max" (e.g. "Enhance with AI").
  final Widget? counterLeading;

  @override
  State<HostField> createState() => _HostFieldState();
}

class _HostFieldState extends State<HostField> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    final multi = widget.maxLines > 1;
    final field = TextField(
      key: widget.fieldKey,
      controller: widget.controller,
      focusNode: _focus,
      readOnly: widget.readOnly,
      minLines: widget.minLines,
      maxLines: widget.maxLines,
      maxLength: widget.maxLength,
      maxLengthEnforcement: MaxLengthEnforcement.enforced,
      inputFormatters: widget.inputFormatters,
      textCapitalization: widget.capitalization,
      keyboardType:
          widget.keyboardType ??
          (multi ? TextInputType.multiline : TextInputType.text),
      textInputAction: widget.textInputAction,
      autofillHints: widget.autofillHints,
      cursorColor: p.accent,
      style: TextStyle(
        color: p.text,
        fontSize: 15.5.ms,
        fontWeight: FontWeight.w500,
        height: 1.4,
      ),
      decoration: InputDecoration(
        isCollapsed: true,
        border: InputBorder.none,
        counterText: '',
        hintText: widget.hint == null ? null : context.t(widget.hint!),
        hintStyle: TextStyle(color: p.faint, fontWeight: FontWeight.w500),
      ),
    );

    return MediaQuery.withNoTextScaling(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Only the outline repaints on focus; the field is reused.
          ListenableBuilder(
            listenable: _focus,
            builder: (_, child) => Container(
              constraints: BoxConstraints(minHeight: 48.ms),
              padding: EdgeInsets.symmetric(
                horizontal: 14.ms,
                vertical: multi ? 14.ms : 0,
              ),
              alignment: multi ? Alignment.topLeft : Alignment.centerLeft,
              decoration: BoxDecoration(
                color: p.field,
                borderRadius: BorderRadius.circular(12.ms),
                border: Border.all(
                  width: _focus.hasFocus ? 1.4 : 1,
                  color: _focus.hasFocus ? p.accent : p.fieldBorder,
                ),
              ),
              child: child,
            ),
            child: Row(
              crossAxisAlignment: multi
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.center,
              children: [
                Expanded(child: field),
                if (widget.trailing != null) ...[
                  SizedBox(width: 8.ms),
                  widget.trailing!,
                ],
              ],
            ),
          ),
          if (widget.maxLength != null)
            Padding(
              padding: EdgeInsets.only(
                top: widget.counterLeading == null ? 6.ms : 8.ms,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: widget.counterLeading ?? const SizedBox.shrink(),
                    ),
                  ),
                  SizedBox(width: 8.ms),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: widget.controller,
                    builder: (_, v, _) => CText(
                      'hostflow:counter',
                      variables: {
                        'count': v.text.characters.length,
                        'max': widget.maxLength,
                      },
                      size: 13.5,
                      weight: FontWeight.w500,
                      color: p.muted,
                      align: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
