import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/utils/scale.dart';
import '../../../api/hosthub/hosthub_queries.dart';
import '../../../component/c_text.dart';
import '../../../component/c_toast.dart';
import '../../../component/pressable.dart';
import '../helper/host_palette.dart';
import 'host_field.dart';

/// [HostField] with "✨ Enhance with AI" on its counter row (tagline and bio steps,
/// onboarding and Host Hub edit alike). While it runs the field is
/// read-only; the result replaces the text through the controller (the
/// draft, counter and validation follow) and "Undo" brings the old text
/// back for [undoFor].
class HostEnhanceField extends HookWidget {
  const HostEnhanceField({
    super.key,
    required this.controller,
    required this.kind,
    required this.maxLength,
    required this.hint,
    required this.minLines,
    required this.maxLines,
    this.textInputAction,
    this.fieldKey,
  });

  final TextEditingController controller;

  /// `tagline` or `bio` (the API's `type`).
  final String kind;
  final int maxLength;

  /// i18n key.
  final String hint;
  final int minLines;
  final int maxLines;
  final TextInputAction? textInputAction;
  final Key? fieldKey;

  /// Shortest text worth enhancing.
  static const minChars = 3;
  static const undoFor = Duration(seconds: 6);

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    final enhance = useEnhanceHostText();
    final busy = useState(false);
    // The text before the last enhance, while "Undo" is offered.
    final undo = useState<String?>(null);
    final timer = useRef<Timer?>(null);
    useEffect(
      () =>
          () => timer.value?.cancel(),
      const [],
    );

    // Typing over the enhanced text drops the offer.
    final enhanced = useRef<String?>(null);
    useEffect(() {
      void watch() {
        if (undo.value != null && controller.text != enhanced.value) {
          timer.value?.cancel();
          undo.value = null;
        }
      }

      controller.addListener(watch);
      return () => controller.removeListener(watch);
    }, [controller]);

    Future<void> run() async {
      final before = controller.text;
      FocusManager.instance.primaryFocus?.unfocus();
      busy.value = true;
      try {
        final next = await enhance.mutateAsync((
          text: before,
          kind: kind,
          maxLength: maxLength,
        ));
        if (!context.mounted || next == null) return;
        timer.value?.cancel();
        undo.value = null;
        enhanced.value = next;
        controller.value = TextEditingValue(
          text: next,
          selection: TextSelection.collapsed(offset: next.length),
        );
        undo.value = before;
        timer.value = Timer(undoFor, () {
          if (context.mounted) undo.value = null;
        });
      } on ApiException catch (e) {
        CToast.error(e);
      } catch (e) {
        CToast.error(e);
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    void restore() {
      final old = undo.value;
      if (old == null) return;
      timer.value?.cancel();
      undo.value = null;
      controller.value = TextEditingValue(
        text: old,
        selection: TextSelection.collapsed(offset: old.length),
      );
    }

    return HostField(
      controller: controller,
      hint: hint,
      maxLength: maxLength,
      minLines: minLines,
      maxLines: maxLines,
      textInputAction: textInputAction,
      fieldKey: fieldKey,
      readOnly: busy.value,
      // Same row as "n/max", before it.
      counterLeading: RepaintBoundary(
        // Side by side when they fit, else Undo wraps under the button.
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8.ms,
          runSpacing: 8.ms,
          children: [
            // Only the button follows the text (enabled from 3 chars).
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (_, v, _) => _EnhanceButton(
                busy: busy.value,
                onPressed:
                    busy.value || v.text.trim().characters.length < minChars
                    ? null
                    : run,
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: undo.value == null
                  ? const SizedBox.shrink()
                  : Pressable(
                      key: ValueKey('hostflow-enhance-undo-$kind'),
                      onPressed: restore,
                      hitPadding: EdgeInsets.all(8.ms),
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 12.ms,
                          vertical: 6.ms,
                        ),
                        decoration: BoxDecoration(
                          color: p.soft,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.undo2, size: 14.ms, color: p.text),
                            SizedBox(width: 6.ms),
                            CText(
                              'hostflow:enhance.undo',
                              size: 13.5,
                              weight: FontWeight.w700,
                              color: p.text,
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "✨ Enhance with AI": accent outline, spinner while it runs, faded when
/// there is nothing to enhance.
class _EnhanceButton extends StatelessWidget {
  const _EnhanceButton({required this.busy, required this.onPressed});
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    final enabled = onPressed != null || busy;
    return AnimatedOpacity(
      opacity: enabled ? 1 : 0.45,
      duration: const Duration(milliseconds: 150),
      child: Pressable(
        onPressed: onPressed,
        semanticLabel: context.t('hostflow:enhance.button'),
        child: Container(
          height: 34.ms,
          padding: EdgeInsets.symmetric(horizontal: 12.ms),
          decoration: BoxDecoration(
            color: p.tint,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: p.tintBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox.square(
                dimension: 16.ms,
                child: busy
                    ? CircularProgressIndicator(strokeWidth: 2, color: p.accent)
                    : Icon(LucideIcons.sparkles, size: 16.ms, color: p.accent),
              ),
              SizedBox(width: 8.ms),
              Flexible(
                child: CText(
                  busy ? 'hostflow:enhance.busy' : 'hostflow:enhance.button',
                  size: 13.5,
                  weight: FontWeight.w700,
                  color: p.accent,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
