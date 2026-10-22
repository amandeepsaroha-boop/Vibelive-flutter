import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/vibe_colors.dart';
import '../../../core/utils/scale.dart';
import '../../api/client/client_models.dart';
import '../../api/client/client_queries.dart';
import '../../api/listingflow/listing_queries.dart';
import '../../component/c_alert.dart';
import '../../component/c_state_view.dart';
import '../../component/status_bar_style.dart';
import '../../component/vibe_background.dart';
import '../../resourcesscreen/widgets/sub_page_header.dart';
import 'helper/favourites_actions.dart';
import 'widgets/favourite_tile.dart';

/// `/me/favourites` (RN `FavouritesScreen`): the user's favourite hosts
/// (newest first, up to 100: RN did not page). Tap opens the host's
/// profile sheet; the trash removes the favourite.
class FavouritesScreen extends HookWidget {
  const FavouritesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final favourites = useFavorites(context);
    // Every favourite's full card in one read: a tap opens it at once.
    useWarmHostIndex(
      context,
      expertDocumentIds: [
        for (final f in favourites.data ?? const []) ?f.expertId,
      ],
    );
    final remove = useRemoveFavorite();
    final removingId = useState<String?>(null);
    final openingId = useState<String?>(null);
    final removed = useState(const <String>{});
    final bottom = MediaQuery.paddingOf(context).bottom;

    String keyOf(FavoriteExpert f) => f.documentId ?? f.id ?? '';

    Future<void> onRemove(FavoriteExpert f) async {
      if (removingId.value != null) return;
      removingId.value = keyOf(f);
      try {
        await remove.mutateAsync(f);
        removed.value = {...removed.value, keyOf(f)};
      } on ApiException catch (e) {
        await CAlert.error(e);
      } finally {
        if (context.mounted) removingId.value = null;
      }
    }

    Future<void> onOpen(FavoriteExpert f) async {
      if (openingId.value != null) return;
      openingId.value = f.expertId;
      try {
        await FavouritesActions.openProfile(context, f);
      } finally {
        if (context.mounted) openingId.value = null;
      }
    }

    final data = favourites.data;
    final Widget body;
    if (data == null && favourites.isError && favourites.error != null) {
      body = CStateView.error(
        context,
        favourites.error!,
        onRetry: () => favourites.refetch(),
      );
    } else if (data == null) {
      body = Padding(
        padding: EdgeInsets.fromLTRB(20.ms, 10.ms, 20.ms, 0),
        child: const FavouritesSkeleton(),
      );
    } else {
      final list = [
        for (final f in data)
          if (!removed.value.contains(keyOf(f))) f,
      ];
      body = RefreshIndicator(
        color: context.colors.accent,
        onRefresh: () async => favourites.refetch(),
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(20.ms, 10.ms, 20.ms, 24.ms + bottom),
          itemCount: list.isEmpty ? 1 : list.length,
          itemBuilder: (context, i) {
            if (list.isEmpty) return const FavouritesEmpty();
            final f = list[i];
            return FavouriteTile(
              key: ValueKey(keyOf(f)),
              favourite: f,
              removing: removingId.value == keyOf(f),
              opening: openingId.value != null && openingId.value == f.expertId,
              onOpen: () => onOpen(f),
              onRemove: () => onRemove(f),
            );
          },
        ),
      );
    }

    return ThemedStatusBar(
      child: Scaffold(
        backgroundColor: context.colors.bg,
        body: Stack(
          children: [
            const VibeBackground(),
            SafeArea(
              bottom: false,
              child: Column(
                children: [
                  SubPageHeader(
                    title: 'resources:favourites.title',
                    trailing: SubPageButton(
                      icon: LucideIcons.heart,
                      label: 'resources:favourites.refresh',
                      color: context.colors.accent,
                      busy: favourites.isFetching,
                      onPressed: () => favourites.refetch(),
                    ),
                  ),
                  Expanded(child: body),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
