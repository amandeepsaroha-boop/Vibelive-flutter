import 'package:flutter/material.dart';
import 'package:fquery_core/fquery_core.dart' show InfiniteQueryResult;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/strapi.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/vibe_colors.dart';
import '../../../core/utils/scale.dart';
import '../../api/callscreen/call_models.dart';
import '../../component/c_text.dart';
import '../../component/pressable.dart';
import 'helper/host_profile_rules.dart';
import 'profile_skeleton.dart';

typedef ReviewsQuery = InfiniteQueryResult<ReviewPage, ApiException, int>;

/// "REVIEWS (n)": a horizontal, lazily built row of review cards with a
/// "SEE MORE" tile that loads the next page (RN).
class ProfileReviews extends StatelessWidget {
  const ProfileReviews({super.key, required this.query, this.waiting = false});

  final ReviewsQuery query;

  /// The host's full profile is still loading (no expert id yet).
  final bool waiting;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dark = c.isDark;
    final pages = query.data?.pages ?? const <ReviewPage>[];
    final reviews = [for (final p in pages) ...p.reviews];
    final total = pages.firstOrNull?.total ?? reviews.length;
    final height = 136.ms;
    final muted = dark ? AppColors.whiteA(0.4) : AppColors.blackA(0.4);

    final Widget content;
    if (waiting || (reviews.isEmpty && (query.isLoading || query.isFetching))) {
      content = ReviewsSkeleton(height: height);
    } else if (reviews.isEmpty && query.isError) {
      content = _Failed(onRetry: query.refetch);
    } else if (reviews.isEmpty) {
      content = Padding(
        padding: EdgeInsets.symmetric(vertical: 8.ms),
        child: Center(
          child: CText(
            'host:reviews.empty',
            size: 11,
            italic: true,
            color: muted,
          ),
        ),
      );
    } else {
      final more = query.hasNextPage;
      // The next page loads in place of the tile: a card-shaped skeleton.
      final loadingMore = more && query.isFetchingNextPage;
      content = SizedBox(
        height: height,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: 16.ms),
          itemCount: reviews.length + (more ? 1 : 0),
          itemExtentBuilder: (i, _) => i < reviews.length
              ? 272.ms
              : (i == reviews.length && more
                    ? (loadingMore ? 272.ms : 120.ms)
                    : null),
          itemBuilder: (_, i) => i < reviews.length
              ? Padding(
                  padding: EdgeInsets.only(right: 12.ms),
                  child: _ReviewCard(reviews[i]),
                )
              : loadingMore
              ? Padding(
                  padding: EdgeInsets.only(right: 12.ms),
                  child: const ReviewCardSkeleton(),
                )
              : _SeeMore(
                  failed: query.isFetchNextPageError,
                  onTap: query.fetchNextPage,
                ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          margin: EdgeInsets.fromLTRB(20.ms, 16.ms, 20.ms, 10.ms),
          padding: EdgeInsets.only(top: 16.ms),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: dark ? AppColors.whiteA(0.06) : AppColors.blackA(0.06),
              ),
            ),
          ),
          child: CText(
            'host:reviews.title',
            variables: {'count': total},
            size: 12,
            weight: FontWeight.w900,
            letterSpacing: 1.8,
          ),
        ),
        // The row bleeds into the card padding (RN margin -16).
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 4.ms),
          child: content,
        ),
      ],
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard(this.review);
  final Review review;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dark = c.isDark;
    final author = review.author;
    final name = author?.name ?? J.str(author?.raw['username']);
    final at = review.createdAt;
    final rating = review.rating;
    final initial = (name == null || name.isEmpty)
        ? 'U'
        : name.substring(0, 1).toUpperCase();
    return Container(
      padding: EdgeInsets.all(14.ms),
      decoration: BoxDecoration(
        color: dark ? AppColors.whiteA(0.03) : AppColors.white,
        borderRadius: BorderRadius.circular(20.ms),
        border: Border.all(
          color: dark ? AppColors.whiteA(0.08) : AppColors.blackA(0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34.ms,
                height: 34.ms,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.accent,
                  shape: BoxShape.circle,
                ),
                child: CText.raw(
                  initial,
                  size: 14,
                  weight: FontWeight.w900,
                  color: c.onAccent,
                ),
              ),
              SizedBox(width: 8.ms),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    name == null
                        ? const CText(
                            'host:reviews.user',
                            size: 13,
                            weight: FontWeight.w800,
                            maxLines: 1,
                          )
                        : CText.raw(
                            name,
                            size: 13,
                            weight: FontWeight.w800,
                            maxLines: 1,
                          ),
                    if (at != null)
                      Padding(
                        padding: EdgeInsets.only(top: 1.ms),
                        child: CText.raw(
                          HostProfileRules.reviewDate(
                            at,
                            Localizations.localeOf(context).toLanguageTag(),
                          ),
                          size: 9.5,
                          weight: FontWeight.w600,
                          color: dark
                              ? AppColors.whiteA(0.4)
                              : AppColors.blackA(0.4),
                        ),
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  CText.raw(
                    rating.toStringAsFixed(1),
                    size: 14,
                    weight: FontWeight.w900,
                    color: c.accent,
                  ),
                  SizedBox(height: 2.ms),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var star = 1; star <= 5; star++)
                        Icon(
                          star <= rating
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          size: 10.ms,
                          color: c.accent,
                        ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          SizedBox(height: 12.ms),
          if (review.comments.isNotEmpty)
            CText.raw(
              '"${review.comments}"',
              size: 12,
              height: 17,
              weight: FontWeight.w400,
              color: dark ? AppColors.whiteA(0.8) : AppColors.blackA(0.7),
              maxLines: 3,
            )
          else
            CText(
              'host:reviews.no_comment',
              size: 12,
              weight: FontWeight.w400,
              italic: true,
              color: dark ? AppColors.whiteA(0.3) : AppColors.blackA(0.3),
            ),
        ],
      ),
    );
  }
}

class _SeeMore extends StatelessWidget {
  const _SeeMore({required this.failed, required this.onTap});

  final bool failed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Pressable(
        onPressed: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 12.ms, horizontal: 16.ms),
          decoration: BoxDecoration(
            color: c.accentA(c.isDark ? 0.1 : 0.05),
            borderRadius: BorderRadius.circular(16.ms),
            border: Border.all(color: c.accentA(c.isDark ? 0.3 : 0.2)),
          ),
          child: CText(
            failed ? 'actions.retry' : 'host:reviews.see_more',
            size: 11,
            weight: FontWeight.w900,
            letterSpacing: 1,
            uppercase: true,
            color: c.accent,
            align: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8.ms),
      child: Center(
        child: Pressable(
          onPressed: onRetry,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CText(
                'host:reviews.failed',
                size: 11,
                color: c.isDark ? AppColors.whiteA(0.4) : AppColors.blackA(0.4),
              ),
              SizedBox(width: 8.ms),
              Icon(LucideIcons.refreshCcw, size: 12.ms, color: c.accent),
              SizedBox(width: 4.ms),
              CText(
                'actions.retry',
                size: 11,
                weight: FontWeight.w800,
                color: c.accent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
