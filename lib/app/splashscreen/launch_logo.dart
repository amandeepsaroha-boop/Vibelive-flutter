import 'package:flutter/material.dart';

import '../component/app_logo.dart';

/// The launch hand-off: when the splash ends, its logo flies up into the
/// logo of the first screen (a [LaunchLogoAnchor]: Discover's top bar, the
/// onboarding slides) instead of vanishing with the splash. [LaunchLogoLayer]
/// draws the flight above the router.
abstract final class LaunchLogo {
  /// True from the hand-off until the logo lands: the splash's logo and the
  /// anchors stay hidden meanwhile (never two logos).
  static final flying = ValueNotifier<bool>(false);

  static final List<GlobalKey> _anchors = [];
  static _LaunchLogoLayerState? _layer;

  /// Starts the flight from [from], the splash logo's box on screen. False
  /// (nothing happens) without a layer or while a flight runs.
  static bool handOff(Rect from) {
    final layer = _layer;
    if (layer == null || flying.value || from.isEmpty) return false;
    flying.value = true;
    layer._start(from);
    return true;
  }

  /// [handOff] from the box of the widget [key] is on.
  static bool handOffFrom(GlobalKey key) {
    final rect = _rectOf(key);
    return rect != null && handOff(rect);
  }

  /// The newest anchor laid out on screen.
  static Rect? _target() {
    for (final key in _anchors.reversed) {
      final rect = _rectOf(key);
      if (rect != null) return rect;
    }
    return null;
  }

  /// The artwork's box inside [key]'s widget, on screen: corners through
  /// `localToGlobal`, so a parent's scale (FittedBox) counts, then the
  /// wordmark as `BoxFit.contain` places it (a square [AppLogo] centres it).
  static Rect? _rectOf(GlobalKey key) {
    final box = key.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    final rect = Rect.fromPoints(
      box.localToGlobal(Offset.zero),
      box.localToGlobal(box.size.bottomRight(Offset.zero)),
    );
    if (rect.width <= 0 || rect.height <= 0) return null;
    final w = rect.width * AppLogo.aspect <= rect.height
        ? rect.width
        : rect.height / AppLogo.aspect;
    return Rect.fromCenter(
      center: rect.center,
      width: w,
      height: w * AppLogo.aspect,
    );
  }
}

/// Marks an [AppLogo] as a landing spot for the launch logo; hidden while
/// it flies in.
class LaunchLogoAnchor extends StatefulWidget {
  const LaunchLogoAnchor({super.key, required this.child});

  final Widget child;

  @override
  State<LaunchLogoAnchor> createState() => _LaunchLogoAnchorState();
}

class _LaunchLogoAnchorState extends State<LaunchLogoAnchor> {
  final _key = GlobalKey(debugLabel: 'launch-logo-anchor');

  @override
  void initState() {
    super.initState();
    LaunchLogo._anchors.add(_key);
  }

  @override
  void dispose() {
    LaunchLogo._anchors.remove(_key);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LaunchLogoHidden(
    child: KeyedSubtree(key: _key, child: widget.child),
  );
}

/// [child], not painted while the launch logo flies (Opacity 0 skips the
/// paint; layout stays, so the anchor can still be measured).
class LaunchLogoHidden extends StatelessWidget {
  const LaunchLogoHidden({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: LaunchLogo.flying,
    child: child,
    builder: (_, flying, child) =>
        Opacity(opacity: flying ? 0 : 1, child: child),
  );
}

/// Draws the flight above the app ([MaterialApp.builder]). After the
/// hand-off the next screen needs a frame or two to lay out: it looks for an
/// anchor for up to ~12 frames, then glides into it (translate + scale only:
/// composited, smooth while that screen builds), or, with no anchor there,
/// fades out in place.
class LaunchLogoLayer extends StatefulWidget {
  const LaunchLogoLayer({super.key, required this.child});

  final Widget child;

  @override
  State<LaunchLogoLayer> createState() => _LaunchLogoLayerState();
}

class _LaunchLogoLayerState extends State<LaunchLogoLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flight;

  /// Where it starts; null when nothing flies.
  Rect? _from;

  /// Where it lands; null while looking, or when it fades out instead.
  Rect? _to;
  bool _moving = false;
  int _frames = 0;

  @override
  void initState() {
    super.initState();
    _flight = AnimationController(vsync: this);
    LaunchLogo._layer = this;
  }

  @override
  void dispose() {
    if (LaunchLogo._layer == this) LaunchLogo._layer = null;
    // After the tree is gone: hidden logos must not be told mid-teardown.
    if (LaunchLogo.flying.value) {
      Future.microtask(() => LaunchLogo.flying.value = false);
    }
    _flight.dispose();
    super.dispose();
  }

  void _start(Rect from) {
    setState(() {
      _from = from;
      _to = null;
      _moving = false;
      _frames = 0;
    });
    _seek();
  }

  void _seek() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _from == null || _moving) return;
      final to = LaunchLogo._target();
      if (to != null || ++_frames >= 12) return _go(to);
      WidgetsBinding.instance.scheduleFrame();
      _seek();
    });
  }

  void _go(Rect? to) {
    final still = MediaQuery.disableAnimationsOf(context);
    setState(() {
      _to = to;
      _moving = true;
    });
    _flight
      ..duration = Duration(
        milliseconds: still ? 150 : (to == null ? 380 : 820),
      )
      ..forward(from: 0).whenCompleteOrCancel(_land);
  }

  void _land() {
    LaunchLogo.flying.value = false;
    if (mounted) setState(() => _from = null);
  }

  @override
  Widget build(BuildContext context) {
    final from = _from;
    return Stack(
      fit: StackFit.passthrough,
      textDirection: TextDirection.ltr,
      children: [
        widget.child,
        if (from != null)
          Positioned.fill(
            child: IgnorePointer(
              child: _Flight(
                from: from,
                to: _to,
                moving: _moving,
                progress: _flight,
              ),
            ),
          ),
      ],
    );
  }
}

class _Flight extends StatelessWidget {
  const _Flight({
    required this.from,
    required this.to,
    required this.moving,
    required this.progress,
  });

  final Rect from;
  final Rect? to;
  final bool moving;
  final Animation<double> progress;

  @override
  Widget build(BuildContext context) {
    // Decoded at its starting (largest) size: sharp all the way down.
    final logo = RepaintBoundary(
      child: AppLogo(size: from.width, height: from.height),
    );
    final end = to;
    return Stack(
      children: [
        Positioned.fromRect(
          rect: from,
          child: AnimatedBuilder(
            animation: progress,
            child: logo,
            builder: (_, child) {
              if (!moving) return child!;
              if (end == null) {
                final t = Curves.easeOut.transform(progress.value);
                return Opacity(
                  opacity: 1 - t,
                  child: Transform.scale(scale: 1 + 0.08 * t, child: child),
                );
              }
              // A long, soft landing: quick lift-off, slow settle.
              final t = Curves.easeInOutCubicEmphasized.transform(
                progress.value,
              );
              final rect = Rect.lerp(from, end, t)!;
              final scale = rect.width / from.width;
              return Transform(
                transform: Matrix4.identity()
                  ..translateByDouble(
                    rect.left - from.left,
                    rect.top - from.top,
                    0,
                    1,
                  )
                  ..scaleByDouble(scale, scale, 1, 1),
                child: child,
              );
            },
          ),
        ),
      ],
    );
  }
}
