import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/vibe_colors.dart';
import 'c_text.dart';

/// Network image with disk cache, decoded at display size (big Strapi
/// originals would otherwise eat memory in lists), placeholder and error box.
class CImage extends StatelessWidget {
  const CImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.radius = 0,
    this.placeholder,
    this.errorWidget,
    this.placeholderUrl,
  });

  final String? url;

  /// A smaller rendition already in the cache (e.g. Discover's card image),
  /// shown at once while [url] loads, then cross-faded.
  final String? placeholderUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final double radius;
  final Widget? placeholder;
  final Widget? errorWidget;

  /// Loads [url] decoded exactly as a `CImage(url: url, width: width)` asks
  /// for it — the provider CachedNetworkImage builds, resized to [width] ×
  /// device pixel ratio — so that image paints on its first frame instead of
  /// fading in from an empty box. Failures are silent: the widget retries.
  static Future<void> precache(
    BuildContext context,
    String? url,
    double width,
  ) {
    if (url == null || url.isEmpty) return Future.value();
    final memWidth = (width * MediaQuery.devicePixelRatioOf(context)).round();
    return precacheImage(
      ResizeImage.resizeIfNeeded(
        memWidth,
        null,
        CachedNetworkImageProvider(url),
      ),
      context,
      onError: (_, _) {},
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final memWidth = width == null ? null : (width! * dpr).round();
    final fill = Container(
      width: width,
      height: height,
      color: c.surfaceVariant,
    );
    final low = placeholderUrl;
    final hasLow = low != null && low.isNotEmpty && low != url;
    final box =
        placeholder ??
        (!hasLow
            ? fill
            : CachedNetworkImage(
                imageUrl: low,
                width: width,
                height: height,
                fit: fit,
                memCacheWidth: memWidth,
                fadeInDuration: Duration.zero,
                placeholder: (_, _) => fill,
                errorWidget: (_, _, _) => fill,
              ));
    final broken =
        errorWidget ??
        Container(
          width: width,
          height: height,
          color: c.surfaceVariant,
          alignment: Alignment.center,
          child: Icon(LucideIcons.imageOff, size: 20, color: c.textMuted),
        );

    final src = url;
    final Widget image = (src == null || src.isEmpty)
        ? broken
        : CachedNetworkImage(
            imageUrl: src,
            width: width,
            height: height,
            fit: fit,
            memCacheWidth: memWidth,
            fadeInDuration: const Duration(milliseconds: 150),
            placeholder: (_, _) => box,
            // The smaller rendition is still a good picture.
            errorWidget: (_, _, _) => hasLow ? box : broken,
          );

    if (radius <= 0) return image;
    return ClipRRect(borderRadius: BorderRadius.circular(radius), child: image);
  }
}

/// Round avatar: photo, or the first letter on a per-letter color
/// (RN `avatarLetter` / `avatarColor`).
class CAvatar extends StatelessWidget {
  const CAvatar({super.key, this.url, this.name, this.size = 48});

  final String? url;
  final String? name;
  final double size;

  static const _palette = [
    Color(0xFF007BFF),
    Color(0xFF00F0FF),
    Color(0xFF00FFA3),
    Color(0xFFB4FF00),
    Color(0xFFFFE600),
    Color(0xFFFF6A00),
    Color(0xFFFF3D5A),
    Color(0xFFFF00A8),
    Color(0xFFFF2EC4),
    Color(0xFFE600FF),
    Color(0xFF7A00FF),
    Color(0xFF3A0BFF),
    Color(0xFF005BFF),
    Color(0xFF00D9FF),
    Color(0xFF39FF14),
    Color(0xFFFF1E1E),
    Color(0xFFFF0044),
    Color(0xFFFF8C00),
    Color(0xFFFFC400),
    Color(0xFFFF8A7A),
    Color(0xFF00FFC6),
    Color(0xFF0099FF),
    Color(0xFFC084FF),
    Color(0xFFFF0099),
    Color(0xFFA855F7),
    Color(0xFF334155),
  ];

  static String letterFor(String? name) {
    final m = RegExp('[A-Z]').firstMatch((name ?? '').toUpperCase());
    return m?.group(0) ?? '?';
  }

  static Color colorFor(String? name) {
    final letter = letterFor(name);
    if (letter == '?') return _palette.first;
    return _palette[(letter.codeUnitAt(0) - 65).clamp(0, 25)];
  }

  @override
  Widget build(BuildContext context) {
    final letter = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      color: colorFor(name),
      child: CText.raw(
        letterFor(name),
        size: size * 0.42,
        weight: FontWeight.w900,
        color: AppColors.white,
      ),
    );
    return ClipOval(
      child: (url == null || url!.isEmpty)
          ? letter
          : CImage(
              url: url,
              width: size,
              height: size,
              placeholder: letter,
              errorWidget: letter,
            ),
    );
  }
}
