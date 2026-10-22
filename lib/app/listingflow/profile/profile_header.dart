import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/vibe_colors.dart';
import '../../../core/utils/scale.dart';
import '../../api/listingflow/listing_models.dart';
import '../../component/c_text.dart';
import '../../component/verification_badge.dart';

/// Name, badge, company pill, city and rating (top of the RN profile card).
class ProfileHeader extends StatelessWidget {
  const ProfileHeader({
    super.key,
    required this.host,
    required this.showCompany,
    required this.onInfluencer,
  });

  final HostCard host;

  /// "Company's Profile" pill (own profile of a company account).
  final bool showCompany;

  /// Influencer badge tapped.
  final VoidCallback onInfluencer;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dark = c.isDark;
    final influencer =
        host.instaVerified || host.facebookVerified || host.snapchatVerified;
    // RN shows the influencer crown pill on Android only.
    final crown =
        influencer && Theme.of(context).platform != TargetPlatform.iOS;
    final name = host.name.isEmpty
        ? context.t(HostCard.unknownNameKey)
        : host.name;
    final city = host.city.isEmpty
        ? context.t(HostCard.defaultCityKey)
        : host.city;

    return Padding(
      padding: EdgeInsets.only(bottom: 12.ms),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (crown)
            Padding(
              padding: EdgeInsets.only(bottom: 6.ms),
              child: InfluencerBadge(size: 13.ms, onPressed: onInfluencer),
            ),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          // RN `adjustsFontSizeToFit`: long names shrink.
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: CText.raw(
                              name,
                              size: 26,
                              weight: FontWeight.w900,
                              maxLines: 1,
                            ),
                          ),
                        ),
                        if (!influencer) ...[
                          SizedBox(width: 4.ms),
                          Padding(
                            padding: EdgeInsets.only(top: 2.ms),
                            child: VerificationBadge(
                              expert: host.badgeFlags,
                              size: 20.ms,
                              onProfilePage: true,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (showCompany)
                      Padding(
                        padding: EdgeInsets.only(top: 4.ms),
                        child: const CompanyPill(
                          label: 'host:header.company_profile',
                        ),
                      ),
                    SizedBox(height: 2.ms),
                    Row(
                      children: [
                        Icon(LucideIcons.globe, size: 11.ms, color: c.accent),
                        SizedBox(width: 5.ms),
                        Flexible(
                          child: CText.raw(
                            city,
                            size: 10,
                            weight: FontWeight.w900,
                            letterSpacing: 2,
                            maxLines: 1,
                            color: dark
                                ? AppColors.whiteA(0.42)
                                : AppColors.blackA(0.48),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (host.rating > 0) ...[
                SizedBox(width: 10.ms),
                _RatingBox(rating: host.ratingLabel),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _RatingBox extends StatelessWidget {
  const _RatingBox({required this.rating});
  final String rating;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dark = c.isDark;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.ms, vertical: 5.ms),
      decoration: BoxDecoration(
        color: dark ? AppColors.whiteA(0.05) : AppColors.blackA(0.03),
        borderRadius: BorderRadius.circular(12.ms),
        border: Border.all(
          color: dark ? AppColors.whiteA(0.08) : AppColors.blackA(0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CText.raw(
                rating,
                size: 15,
                weight: FontWeight.w900,
                color: c.accent,
              ),
              SizedBox(width: 4.ms),
              Icon(Icons.star_rounded, size: 15.ms, color: c.accent),
            ],
          ),
          CText(
            'host:header.rating',
            size: 8,
            weight: FontWeight.w900,
            letterSpacing: 1.2,
            color: dark ? AppColors.whiteA(0.34) : AppColors.blackA(0.34),
          ),
        ],
      ),
    );
  }
}

/// Blue "company" pill (RN `#E3F2FD` / `#1565C0`).
class CompanyPill extends StatelessWidget {
  const CompanyPill({super.key, required this.label, this.large = false});

  /// i18n key.
  final String label;
  final bool large;

  static const _bg = Color(0xFFE3F2FD);
  static const _border = Color(0xFF90CAF9);
  static const _fg = Color(0xFF1565C0);

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(
      horizontal: (large ? 12 : 8).ms,
      vertical: (large ? 4 : 3).ms,
    ),
    decoration: BoxDecoration(
      color: _bg,
      border: Border.all(color: _border),
      borderRadius: BorderRadius.circular((large ? 16 : 10).ms),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.business, size: (large ? 14 : 13).ms, color: _fg),
        SizedBox(width: 4.ms),
        Flexible(
          child: CText(
            label,
            size: large ? 12 : 11,
            weight: FontWeight.w700,
            color: _fg,
            maxLines: 1,
          ),
        ),
      ],
    ),
  );
}
