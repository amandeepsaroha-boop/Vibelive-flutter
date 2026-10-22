import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';

import '../../core/query/query_client.dart';
import '../../core/session/session_store.dart';
import '../../core/utils/scale.dart';
import '../authscreen/helper/auth_navigation.dart';
import '../authscreen/login_screen.dart';
import '../api/splashscreen/splash_api.dart';
import '../api/splashscreen/splash_keys.dart';
import '../component/app_logo.dart';
import '../component/c_text.dart';
import '../component/exit_on_double_back.dart';
import 'onboarding_view.dart';
import 'splash_palette.dart';
import '../callscreen/helper/call_controller.dart';

/// First screen (RN `app/index.jsx`): logo + load bar for at least 2.5 s.
/// Signed-in users then go straight to their route; everyone else sees the
/// onboarding slides first.
class SplashScreen extends HookWidget {
  const SplashScreen({super.key});

  static const minDuration = Duration(milliseconds: 2500);

  static bool _firstFrameHeld = false;

  /// Called from `main`: keeps the native splash up until the logo is
  /// decoded, so the hand-over shows a complete screen (no logo pop-in).
  static void holdFirstFrame() {
    WidgetsBinding.instance.deferFirstFrame();
    _firstFrameHeld = true;
    Timer(const Duration(seconds: 2), _releaseFirstFrame); // never stuck
  }

  static void _releaseFirstFrame() {
    if (!_firstFrameHeld) return;
    _firstFrameHeld = false;
    WidgetsBinding.instance.allowFirstFrame();
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = useMemoized(
      () => SessionStore.instance.value.isAuthenticated,
    );
    final route = useState<String?>(null);
    final minElapsed = useState(false);
    final left = useRef(false);
    final logoSize = 302.ms;

    useEffect(() {
      var alive = true;
      // After the (held) first layout: hooks can't read inherited widgets here.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return _releaseFirstFrame();
        precacheImage(
          AppLogo.provider(context, logoSize),
          context,
        ).whenComplete(_releaseFirstFrame);
        precacheImage(AppLogo.provider(context, 120.ms), context);
        // The login wordmark: decoded before its fade-in, not during it.
        if (!signedIn) {
          precacheImage(
            AppLogo.provider(context, LoginScreen.logoWidth),
            context,
          );
        }
      });
      // Shown on the first slide; the fallback covers a slow or offline start.
      queryCache.prefetchQuery<List<String>>(
        SplashKeys.hostTopics,
        SplashApi.fetchHostTopics,
        staleDuration: StaleTime.long,
      );
      nextAuthRoute(confirmAgeGate: true).then((r) {
        if (alive) route.value = r;
      });
      final timer = Timer(minDuration, () {
        if (alive) minElapsed.value = true;
      });
      return () {
        alive = false;
        timer.cancel();
      };
    }, const []);

    // Replaces the whole stack: nothing to go back to. Never while a call
    // routed in over the splash (cold-start accept / ring, RN E-62): the
    // call screens leave for Home themselves when it ends.
    void leave() {
      final target = route.value;
      if (target == null || left.value || !context.mounted) return;
      if (CallController.instance.isOnCall) return;
      left.value = true;
      context.go(target);
    }

    // A call that ended without leaving the splash: go on from here.
    final onCall = useValueListenable(CallController.instance.onCall);
    useEffect(() {
      if (signedIn && !onCall && minElapsed.value && route.value != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => leave());
      }
      return null;
    }, [minElapsed.value, route.value, onCall]);

    // Follows the app theme (RN light splash palette).
    final palette = SplashPalette.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: palette.overlay,
      child: ExitOnDoubleBack(
        child: Material(
          color: palette.bg,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: minElapsed.value && !signedIn
                ? OnboardingView(ready: route.value != null, onFinish: leave)
                : _SplashView(logoSize: logoSize),
          ),
        ),
      ),
    );
  }
}

class _SplashView extends StatelessWidget {
  const _SplashView({required this.logoSize});

  final double logoSize;

  @override
  Widget build(BuildContext context) {
    final palette = SplashPalette.of(context);
    final bottom = math.max(
      98.ms,
      MediaQuery.paddingOf(context).bottom + 20.ms,
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 24.ms),
            child: AppLogo(size: logoSize),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: bottom,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Grows on every frame for 2.5 s: repaints only itself.
              RepaintBoundary(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: SizedBox(
                    width: 170.ms,
                    height: 2.ms,
                    child: ColoredBox(
                      color: palette.track,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: SplashScreen.minDuration,
                        curve: Curves.easeOutCubic,
                        builder: (_, v, fill) => FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: v,
                          child: fill,
                        ),
                        child: ColoredBox(color: palette.accent),
                      ),
                    ),
                  ),
                ),
              ),
              CText(
                'splash:establishing_sync',
                variant: CTextVariant.caption,
                color: palette.text,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
