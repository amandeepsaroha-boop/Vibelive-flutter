import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/vibe_colors.dart';
import '../../../../core/utils/scale.dart';
import '../../../api/client/client_models.dart';
import '../../../component/c_image.dart';
import '../../../component/c_text.dart';
import '../../../component/pressable.dart';
import '../../../component/skeleton.dart';
import '../helper/favourites_palette.dart';

/// One favourite host (RN FavouritesScreen row): photo, name + verified,
/// handle, remove.
class FavouriteTile extends StatelessWidget {
  const FavouriteTile({
    super.key,
    required this.favourite,
    required this.onOpen,
    required this.onRemove,
    this.removing = false,
    this.opening = false,
  });

  final FavoriteExpert favourite;
  final VoidCallback onOpen;
  final VoidCallback onRemove;
  final bool removing;
  final bool opening;

  static String _letter(String name) {
    final m = RegExp('[A-Za-z]').firstMatch(name.trim());
    return m?.group(0)?.toUpperCase() ?? 'P';
  }

  @override
  Widget build(BuildContext context) {
    final p = FavouritesPalette.of(context);
    final c = context.colors;
    final name =
        favourite.expertName ?? context.t('client:fallback.expert_name');
    final handle = favourite.expertHandle;
    final pic = favourite.profilePicUrl;
    return Padding(
      padding: EdgeInsets.only(bottom: 9.ms),
      child: Pressable(
        onPressed: opening ? null : onOpen,
        activeOpacity: 0.88,
        child: Container(
          padding: EdgeInsets.all(12.ms),
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(16.ms),
            border: Border.all(color: p.border),
          ),
          child: Row(
            children: [
              Container(
                width: 54.ms,
                height: 54.ms,
                alignment: Alignment.center,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: p.soft,
                  border: Border.all(color: c.accentA(0.4), width: 2),
                ),
                child: pic != null
                    ? CImage(url: pic, width: 54.ms, height: 54.ms)
                    : CText.raw(
                        _letter(name),
                        size: 18,
                        weight: FontWeight.w900,
                        color: p.text,
                      ),
              ),
              SizedBox(width: 11.ms),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: CText.raw(
                            name,
                            size: 15,
                            weight: FontWeight.w900,
                            color: p.text,
                            maxLines: 1,
                          ),
                        ),
                        if (favourite.expertVerified) ...[
                          SizedBox(width: 5.ms),
                          Icon(
                            Icons.check_circle,
                            size: 14.ms,
                            color: StatusColors.info,
                          ),
                        ],
                      ],
                    ),
                    SizedBox(height: 2.ms),
                    handle.isEmpty
                        ? CText(
                            'resources:favourites.professional',
                            size: 14,
                            weight: FontWeight.w700,
                            color: p.muted,
                            maxLines: 1,
                          )
                        : CText.raw(
                            '@$handle',
                            size: 14,
                            weight: FontWeight.w700,
                            color: p.muted,
                            maxLines: 1,
                          ),
                  ],
                ),
              ),
              Pressable(
                onPressed: removing || opening ? null : onRemove,
                semanticLabel: context.t('resources:favourites.remove'),
                activeOpacity: 0.9,
                child: Container(
                  width: 38.ms,
                  height: 38.ms,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: StatusColors.dangerA(0.12),
                    borderRadius: BorderRadius.circular(12.ms),
                    border: Border.all(color: StatusColors.dangerA(0.35)),
                  ),
                  child: removing
                      ? SizedBox.square(
                          dimension: 16.ms,
                          child: const CircularProgressIndicator(
                            strokeWidth: 2,
                            color: StatusColors.danger,
                          ),
                        )
                      : Icon(
                          LucideIcons.trash2,
                          size: 16.ms,
                          color: StatusColors.danger,
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// First load: rows shaped like [FavouriteTile].
class FavouritesSkeleton extends StatelessWidget {
  const FavouritesSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Shimmer(
    child: Column(
      children: [
        for (var i = 0; i < 7; i++)
          Padding(
            padding: EdgeInsets.only(bottom: 9.ms),
            child: SkeletonBox(height: 80.ms, radius: 16.ms),
          ),
      ],
    ),
  );
}

/// "No favourites yet".
class FavouritesEmpty extends StatelessWidget {
  const FavouritesEmpty({super.key});

  @override
  Widget build(BuildContext context) {
    final p = FavouritesPalette.of(context);
    return Padding(
      padding: EdgeInsets.only(top: 90.ms, left: 24.ms, right: 24.ms),
      child: Column(
        children: [
          Icon(LucideIcons.heart, size: 40.ms, color: p.muted),
          SizedBox(height: 12.ms),
          CText(
            'resources:favourites.empty_title',
            size: 17,
            weight: FontWeight.w900,
            color: p.text,
            align: TextAlign.center,
          ),
          SizedBox(height: 6.ms),
          CText(
            'resources:favourites.empty_message',
            size: 14,
            weight: FontWeight.w700,
            color: p.muted,
            align: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
