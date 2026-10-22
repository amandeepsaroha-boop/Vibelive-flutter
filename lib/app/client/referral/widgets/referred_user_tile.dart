import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/utils/scale.dart';
import '../../../api/client/client_models.dart';
import '../../../component/c_image.dart';
import '../../../component/c_text.dart';
import '../helper/referral_format.dart';
import '../helper/referral_palette.dart';

/// One referred user (RN `renderUser`): avatar, name, "Referred user".
class ReferredUserTile extends StatelessWidget {
  const ReferredUserTile({super.key, required this.user});

  final JoinedUser user;

  /// Row height plus its bottom gap (unscaled): a fixed list extent.
  static const extent = 80.0;

  @override
  Widget build(BuildContext context) {
    final p = ReferralPalette.of(context);
    final name = user.name;
    final url = user.profilePicUrl;
    final avatar = 44.ms;
    return Padding(
      padding: EdgeInsets.only(bottom: 10.ms),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14.ms),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(16.ms),
          border: Border.all(color: p.border),
        ),
        child: Row(
          children: [
            Container(
              width: avatar,
              height: avatar,
              alignment: Alignment.center,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: p.soft,
                shape: BoxShape.circle,
                border: Border.all(color: p.border),
              ),
              child: url == null || url.isEmpty
                  ? CText.raw(
                      ReferralFormat.avatarLetter(name),
                      size: 16,
                      weight: FontWeight.w900,
                      color: p.text,
                    )
                  : CImage(url: url, width: avatar, height: avatar),
            ),
            SizedBox(width: 12.ms),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  name == null
                      ? CText(
                          ReferralFormat.unnamedKey,
                          size: 14,
                          weight: FontWeight.w800,
                          color: p.text,
                          maxLines: 1,
                        )
                      : CText.raw(
                          name,
                          size: 14,
                          weight: FontWeight.w800,
                          color: p.text,
                          maxLines: 1,
                        ),
                  SizedBox(height: 2.ms),
                  CText(
                    'client:referral.referred_user',
                    size: 12,
                    weight: FontWeight.w700,
                    color: p.muted,
                    maxLines: 1,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// RN `ListEmptyComponent`: users icon and "No referred users yet".
class ReferralEmpty extends StatelessWidget {
  const ReferralEmpty({super.key});

  @override
  Widget build(BuildContext context) {
    final p = ReferralPalette.of(context);
    return Padding(
      padding: EdgeInsets.only(top: 40.ms),
      child: Column(
        children: [
          Icon(LucideIcons.users, size: 38.ms, color: p.muted),
          SizedBox(height: 12.ms),
          CText(
            'client:referral.empty',
            size: 14,
            weight: FontWeight.w900,
            color: p.text,
            align: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
