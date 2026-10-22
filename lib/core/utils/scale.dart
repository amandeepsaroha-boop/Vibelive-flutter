import 'dart:ui';

/// Responsive sizing, same formulas as the RN app
/// (`src/shared/utils/responsive.js`). Base design: iPhone X, 375 x 812.
///
/// ```dart
/// padding: EdgeInsets.all(16.ms)      // moderateScale(16)
/// fontSize: moderateScale(14)
/// ```
abstract final class Scale {
  static const double baseWidth = 375;
  static const double baseHeight = 812;

  static Size _size = _readWindowSize();

  static Size _readWindowSize() {
    final views = PlatformDispatcher.instance.views;
    if (views.isEmpty) return const Size(baseWidth, baseHeight);
    final view = views.first;
    final size = view.physicalSize / view.devicePixelRatio;
    if (size.isEmpty) return const Size(baseWidth, baseHeight);
    // Portrait app: width = short side, height = long side.
    return Size(size.shortestSide, size.longestSide);
  }

  /// Called by the app root whenever the window size changes.
  static void update(Size size) {
    if (size.isEmpty) return;
    _size = Size(size.shortestSide, size.longestSide);
  }

  static double get screenWidth => _size.width;
  static double get screenHeight => _size.height;

  /// Linear scale on width.
  static double scale(num size) => _size.width / baseWidth * size;

  /// Linear scale on height.
  static double verticalScale(num size) => _size.height / baseHeight * size;

  /// Half-way between the raw size and [scale], so tablets don't blow up.
  static double moderateScale(num size, [double factor = 0.5]) =>
      size + (scale(size) - size) * factor;
}

double scale(num size) => Scale.scale(size);
double verticalScale(num size) => Scale.verticalScale(size);
double moderateScale(num size, [double factor = 0.5]) =>
    Scale.moderateScale(size, factor);

extension ScaleNum on num {
  /// `moderateScale(this)`
  double get ms => Scale.moderateScale(this);

  /// `scale(this)`
  double get sw => Scale.scale(this);

  /// `verticalScale(this)`
  double get vs => Scale.verticalScale(this);
}
