import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/utils/scale.dart';
import '../../../component/c_text.dart';
import '../../../component/pressable.dart';
import '../helper/host_palette.dart';

/// Dropdown-looking box ("Assam ⌄") that opens a picker.
class HostSelectField extends StatelessWidget {
  const HostSelectField({
    super.key,
    required this.value,
    required this.hint,
    required this.onTap,
    this.enabled = true,
  });

  /// Shown as is (server data); null shows [hint].
  final String? value;

  /// i18n key.
  final String hint;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    final v = value;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Pressable(
        onPressed: enabled ? onTap : null,
        child: Container(
          height: 48.ms,
          padding: EdgeInsets.symmetric(horizontal: 14.ms),
          decoration: BoxDecoration(
            color: p.field,
            borderRadius: BorderRadius.circular(12.ms),
            border: Border.all(color: p.fieldBorder),
          ),
          child: Row(
            children: [
              Expanded(
                child: v == null || v.isEmpty
                    ? CText(hint, size: 17, color: p.faint, maxLines: 1)
                    : CText.raw(
                        v,
                        size: 17,
                        weight: FontWeight.w500,
                        color: p.text,
                        maxLines: 1,
                      ),
              ),
              Icon(LucideIcons.chevronDown, size: 18.ms, color: p.text),
            ],
          ),
        ),
      ),
    );
  }
}
