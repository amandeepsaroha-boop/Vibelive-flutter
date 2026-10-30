import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/vibe_colors.dart';
import '../../../core/utils/scale.dart';
import '../../api/listingflow/host_index.dart';
import '../../api/listingflow/search_models.dart';
import '../../component/c_image.dart';
import '../../component/c_text.dart';
import '../../component/pressable.dart';
import '../../component/skeleton.dart';
import '../../component/verification_badge.dart';
import 'helper/search_controller.dart';
import 'helper/search_format.dart';

/// An expert hit (RN search row): avatar, highlighted name / specialization
/// / tagline, languages, call button with the voice rate, and a trust footer
/// (rating, calls handled) only when there is something to show. Spins while
/// its profile loads; the other rows dim and ignore taps meanwhile.
class SearchHostRow extends StatelessWidget {
  const SearchHostRow({
    super.key,
    required this.hit,
    required this.highlight,
    required this.opening,
    required this.onOpen,
  });

  final SearchHost hit;

  /// Matcher of the searched text (null = no highlight).
  final RegExp? highlight;
  final ValueNotifier<String?> opening;
  final ValueChanged<SearchHost> onOpen;

  @override
  Widget build(BuildContext context) {
    final key = SearchScreenController.hitKey(hit);
    return ValueListenableBuilder<String?>(
      valueListenable: opening,
      builder: (_, openingKey, _) {
        final busy = openingKey != null && openingKey == key;
        final dimmed = openingKey != null && !busy;
        return AnimatedOpacity(
          opacity: dimmed ? 0.5 : 1,
          duration: const Duration(milliseconds: 150),
          child: Pressable(
            activeOpacity: 0.85,
            onPressed: openingKey == null ? () => onOpen(hit) : null,
            child: _Card(hit: hit, highlight: highlight, busy: busy),
          ),
        );
      },
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.hit, required this.highlight, required this.busy});

  final SearchHost hit;
  final RegExp? highlight;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dark = c.isDark;
    final h = hit;
    final tagline = formatTagline(h.tagline);
    final showFooter = h.rating > 0 || h.callMinutes > 0;
    Color a(double darkA, double lightA) =>
        dark ? AppColors.whiteA(darkA) : AppColors.blackA(lightA);

    return Container(
      margin: EdgeInsets.only(bottom: 10.ms),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: dark ? AppColors.whiteA(0.04) : AppColors.white,
        borderRadius: BorderRadius.circular(16.ms),
        border: Border.all(color: a(0.08, 0.07)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.all(12.ms),
            child: Row(
              children: [
                // The host's card photo (primary) once their card loaded.
                CAvatar(
                  url:
                      HostIndex.photoOf(
                        expertDocumentId: h.documentId,
                        userDocumentId: h.userDocumentId,
                      ) ??
                      h.profilePic,
                  name: h.name,
                  size: 58.ms,
                ),
                SizedBox(width: 12.ms),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: _Highlighted(
                              h.name.isEmpty
                                  ? context.t(SearchHost.defaultNameKey)
                                  : h.name,
                              highlight,
                              size: 20.5,
                              weight: FontWeight.w900,
                              color: c.text,
                            ),
                          ),
                          SizedBox(width: 5.ms),
                          VerificationBadge(expert: h.badgeFlags, size: 20.ms),
                        ],
                      ),
                      if (h.specialization.isNotEmpty)
                        Padding(
                          padding: EdgeInsets.only(top: 2.ms),
                          child: _Highlighted(
                            h.specialization,
                            highlight,
                            size: 12,
                            weight: FontWeight.w700,
                            color: a(0.7, 0.6),
                          ),
                        ),
                      if (tagline.isNotEmpty)
                        Padding(
                          padding: EdgeInsets.only(top: 3.ms),
                          child: _Highlighted(
                            tagline,
                            highlight,
                            size: 11,
                            weight: FontWeight.w400,
                            highlightWeight: FontWeight.w800,
                            color: a(0.45, 0.42),
                          ),
                        ),
                      // Only when the payload has them: inventing "English"
                      // would be wrong on every profile that never set one.
                      if (h.languages.isNotEmpty)
                        Padding(
                          padding: EdgeInsets.only(top: 5.ms),
                          child: Row(
                            children: [
                              Icon(
                                LucideIcons.globe,
                                size: 11.ms,
                                color: a(0.35, 0.3),
                              ),
                              SizedBox(width: 4.ms),
                              Expanded(
                                child: CText.raw(
                                  h.languages.join(' • ').toUpperCase(),
                                  size: 9.5,
                                  weight: FontWeight.w900,
                                  letterSpacing: 0.8,
                                  color: a(0.4, 0.35),
                                  maxLines: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(width: 12.ms),
                _CallColumn(rate: h.voiceRate, busy: busy),
              ],
            ),
          ),
          if (showFooter) _TrustFooter(hit: h),
        ],
      ),
    );
  }
}

/// Text with every match of the query tinted in the accent.
class _Highlighted extends StatelessWidget {
  const _Highlighted(
    this.text,
    this.highlight, {
    required this.size,
    required this.weight,
    required this.color,
    this.highlightWeight = FontWeight.w900,
  });

  final String text;
  final RegExp? highlight;
  final double size;
  final FontWeight weight;
  final FontWeight highlightWeight;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final accent = context.colors.accent;
    return Text.rich(
      TextSpan(
        children: highlightSpans(
          text,
          highlight,
          TextStyle(color: accent, fontWeight: highlightWeight),
        ),
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textScaler: TextScaler.noScaling,
      style: TextStyle(
        fontSize: moderateScale(size),
        fontWeight: weight,
        color: color,
      ),
    );
  }
}

/// Call button + voice rate. The button opens the profile: the call itself
/// starts there, behind the balance and permission checks.
class _CallColumn extends StatelessWidget {
  const _CallColumn({required this.rate, required this.busy});

  final double rate;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final muted = c.isDark ? AppColors.whiteA(0.45) : AppColors.blackA(0.4);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 42.ms,
          height: 42.ms,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
          child: busy
              ? RepaintBoundary(
                  child: SizedBox.square(
                    dimension: 18.ms,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: c.onAccent,
                    ),
                  ),
                )
              : Icon(LucideIcons.phone, size: 18.ms, color: c.onAccent),
        ),
        SizedBox(height: 6.ms),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: context.t('search:results.currency'),
                style: TextStyle(color: muted, fontSize: 10.ms),
              ),
              TextSpan(
                text: formatRate(rate),
                style: TextStyle(color: c.text, fontSize: 15.ms),
              ),
              TextSpan(
                text: context.t('search:results.per_min'),
                style: TextStyle(color: muted, fontSize: 8.5.ms),
              ),
            ],
          ),
          maxLines: 1,
          textScaler: TextScaler.noScaling,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ],
    );
  }
}

/// Rating stars + "4.5 (12)" on the left, minutes of calls on the right.
class _TrustFooter extends StatelessWidget {
  const _TrustFooter({required this.hit});
  final SearchHost hit;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dark = c.isDark;
    final h = hit;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.ms, vertical: 9.ms),
      decoration: BoxDecoration(
        color: dark ? AppColors.whiteA(0.02) : AppColors.blackA(0.02),
        border: Border(
          top: BorderSide(
            color: dark ? AppColors.whiteA(0.06) : AppColors.blackA(0.06),
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (h.rating > 0)
            Flexible(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Stars(rating: h.rating, color: c.accent),
                  Container(
                    width: 1,
                    height: 11.ms,
                    margin: EdgeInsets.symmetric(horizontal: 8.ms),
                    color: dark
                        ? AppColors.whiteA(0.15)
                        : AppColors.blackA(0.12),
                  ),
                  Flexible(
                    child: CText.raw(
                      '${h.rating.toStringAsFixed(1)} (${h.reviewCount})',
                      size: 11,
                      weight: FontWeight.w900,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
            )
          else
            const SizedBox.shrink(),
          if (h.callMinutes > 0)
            Flexible(
              child: Padding(
                padding: EdgeInsets.only(left: 8.ms),
                child: CText(
                  'search:results.calls_handled',
                  variables: {'minutes': formatCallMinutes(h.callMinutes)},
                  size: 9.5,
                  weight: FontWeight.w900,
                  letterSpacing: 0.6,
                  color: c.accent,
                  maxLines: 1,
                  align: TextAlign.end,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Stars extends StatelessWidget {
  const _Stars({required this.rating, required this.color});
  final double rating;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final full = rating.round();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var star = 1; star <= 5; star++)
          Padding(
            padding: EdgeInsets.only(right: star < 5 ? 2.ms : 0),
            child: Icon(
              star <= full ? Icons.star_rounded : Icons.star_border_rounded,
              size: 12.ms,
              color: color,
            ),
          ),
      ],
    );
  }
}

/// Skeleton of an expert hit (same layout, no footer). Put under a
/// `Shimmer`.
class SearchHostRowSkeleton extends StatelessWidget {
  const SearchHostRowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(12.ms, 12.ms, 12.ms, 22.ms),
      child: Row(
        children: [
          SkeletonBox(width: 58.ms, height: 58.ms, circle: true),
          SizedBox(width: 12.ms),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FractionallySizedBox(
                  widthFactor: 0.6,
                  child: SkeletonBox(height: 18.ms, radius: 6),
                ),
                SizedBox(height: 8.ms),
                FractionallySizedBox(
                  widthFactor: 0.4,
                  child: SkeletonBox(height: 11.ms, radius: 5),
                ),
                SizedBox(height: 7.ms),
                FractionallySizedBox(
                  widthFactor: 0.8,
                  child: SkeletonBox(height: 10.ms, radius: 5),
                ),
              ],
            ),
          ),
          SizedBox(width: 12.ms),
          SkeletonBox(width: 42.ms, height: 42.ms, circle: true),
        ],
      ),
    );
  }
}
