import 'package:flutter/widgets.dart';

/// RN `TouchableOpacity`: dims while pressed. Cheaper than InkWell (no
/// Material ink layer) and works on any background.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onPressed,
    this.activeOpacity = 0.7,
    this.semanticLabel,
    this.hitPadding = EdgeInsets.zero,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final double activeOpacity;
  final String? semanticLabel;

  /// Extra touch area around [child] (RN `hitSlop`).
  final EdgeInsets hitPadding;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _pressed = false;

  void _set(bool pressed) {
    if (_pressed != pressed && mounted) setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    Widget child = AnimatedOpacity(
      opacity: _pressed ? widget.activeOpacity : 1,
      duration: const Duration(milliseconds: 90),
      child: widget.child,
    );
    if (widget.hitPadding != EdgeInsets.zero) {
      child = Padding(padding: widget.hitPadding, child: child);
    }
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        onTapDown: enabled ? (_) => _set(true) : null,
        onTapUp: enabled ? (_) => _set(false) : null,
        onTapCancel: enabled ? () => _set(false) : null,
        child: child,
      ),
    );
  }
}
