import 'package:flutter/widgets.dart';

/// Lifts [child] above the soft keyboard (RN `KeyboardAvoidingView`
/// `padding`). Only this widget reads the keyboard height, so while the
/// keyboard animates it alone rebuilds and [child] is reused as is.
///
/// Wrap the sheet where it is created (`builder: (_) => KeyboardInset(child:
/// _Sheet())`) and open bottom sheets with `useSafeArea: true`: without it the
/// route rebuilds its whole page on every keyboard frame.
class KeyboardInset extends StatelessWidget {
  const KeyboardInset({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: child,
  );
}
