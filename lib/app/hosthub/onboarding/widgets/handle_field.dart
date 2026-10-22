import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/utils/scale.dart';
import '../../../api/hosthub/hosthub_queries.dart';
import '../../../authscreen/helper/link_parser.dart';
import '../../../component/c_text.dart';
import '../helper/host_palette.dart';
import '../helper/validation.dart';
import 'host_field.dart';

/// Lower-case letters and `_` only, as the backend saves handles.
class HandleFormatter extends TextInputFormatter {
  const HandleFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final clean = newValue.text
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'[^a-z_]'), '');
    final capped = clean.length > 30 ? clean.substring(0, 30) : clean;
    if (capped == newValue.text) return newValue;
    return TextEditingValue(
      text: capped,
      selection: TextSelection.collapsed(offset: capped.length),
    );
  }
}

/// Display handle with a live "is it free" check (debounced) and the public
/// link preview. Only the status and the preview rebuild while typing.
class HostHandleField extends HookWidget {
  const HostHandleField({
    super.key,
    required this.controller,
    this.ownExpertId,
  });

  final TextEditingController controller;
  final String? ownExpertId;

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    final handle = _useSettled(controller);
    final valid = HostValidation.handlePattern.hasMatch(handle);
    final check = useHostHandleCheck(
      context,
      handle,
      ownExpertId: ownExpertId,
      enabled: valid,
    );
    final Widget? status;
    if (!valid) {
      status = null;
    } else if (check.isLoading) {
      status = SizedBox.square(
        dimension: 18.ms,
        child: CircularProgressIndicator(strokeWidth: 2, color: p.accent),
      );
    } else if (check.data == true) {
      status = Icon(
        LucideIcons.circleCheck,
        key: const ValueKey('handle-ok'),
        size: 22.ms,
        color: p.success,
      );
    } else if (check.data == false) {
      status = Icon(
        LucideIcons.circleX,
        key: const ValueKey('handle-taken'),
        size: 22.ms,
        color: p.danger,
      );
    } else {
      status = null;
    }

    final String? note = switch ((valid, check.data)) {
      (false, _) when handle.isNotEmpty => 'hostflow:basic.handle_rule',
      (true, false) => 'hostflow:errors.handle_taken',
      _ => null,
    };

    // While typing, the last result no longer applies: hide it.
    Widget settledOnly(Widget? child) => child == null
        ? const SizedBox.shrink()
        : ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (_, v, _) =>
                v.text == handle ? child : const SizedBox.shrink(),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HostField(
          controller: controller,
          hint: 'hostflow:basic.handle_hint',
          capitalization: TextCapitalization.none,
          inputFormatters: const [HandleFormatter()],
          textInputAction: TextInputAction.next,
          fieldKey: const ValueKey('hostflow-handle'),
          trailing: status == null ? null : settledOnly(status),
        ),
        SizedBox(height: 8.ms),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (_, v, _) => _LinkPreview(handle: v.text, palette: p),
        ),
        if (note != null)
          settledOnly(
            Padding(
              padding: EdgeInsets.only(top: 4.ms),
              child: CText(
                note,
                size: 13.5,
                weight: FontWeight.w500,
                color: note.contains('taken') ? p.danger : p.muted,
              ),
            ),
          ),
      ],
    );
  }
}

class _LinkPreview extends StatelessWidget {
  const _LinkPreview({required this.handle, required this.palette});
  final String handle;
  final HostPalette palette;

  @override
  Widget build(BuildContext context) {
    final base = LinkParser.shareLink(
      '',
    ).replaceFirst(RegExp('^https?://'), '');
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$base/',
            style: TextStyle(color: palette.muted),
          ),
          TextSpan(
            text: handle,
            style: TextStyle(
              color: palette.accent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      style: TextStyle(fontSize: 13.ms, fontWeight: FontWeight.w500),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textScaler: TextScaler.noScaling,
    );
  }
}

/// The controller's text once typing paused for 450 ms.
String _useSettled(TextEditingController c) {
  final settled = useState(c.text);
  useEffect(() {
    Timer? timer;
    void listener() {
      timer?.cancel();
      timer = Timer(const Duration(milliseconds: 450), () {
        settled.value = c.text;
      });
    }

    c.addListener(listener);
    return () {
      timer?.cancel();
      c.removeListener(listener);
    };
  }, [c]);
  return settled.value;
}
