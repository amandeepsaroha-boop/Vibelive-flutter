import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../../core/query/query_hooks.dart';
import '../../../core/session/session_store.dart';
import 'banner_api.dart';
import 'banner_keys.dart';
import 'banner_models.dart';

/// Milestones unlocked while the user was away; the modal queues them (and
/// dedupes against pushes by [UnlockedMilestone.id]).
QueryResult<List<UnlockedMilestone>, ApiException> useUnviewedMilestones(
  BuildContext context, {
  String? userDocumentId,
  bool enabled = true,
}) {
  final session = useValueListenable(SessionStore.instance);
  final id = userDocumentId ?? session.userDocumentId ?? '';
  return useApiQuery<List<UnlockedMilestone>>(
    BannerKeys.unviewedMilestones(id),
    () => MilestoneApi.fetchUnviewed(id),
    context: context,
    enabled: enabled && id.isNotEmpty,
    staleDuration: StaleTime.short,
  );
}

/// Outside widgets: the post-login bootstrap (RN fetched these once the push
/// setup ran).
Future<List<UnlockedMilestone>> ensureUnviewedMilestones(
  String userDocumentId,
) => queryCache.fetchQuery<List<UnlockedMilestone>>(
  BannerKeys.unviewedMilestones(userDocumentId),
  () => MilestoneApi.fetchUnviewed(userDocumentId),
  staleDuration: StaleTime.short,
);

/// Variables: [UnlockedMilestone.unlockedMilestoneDocumentId]. Close the modal
/// without waiting: RN never let a failed update keep it open.
MutationResult<void, ApiException, String> useMarkMilestoneViewed({
  void Function()? onSettled,
}) => useApiMutation<void, String>(
  MilestoneApi.markViewed,
  invalidates: const [BannerKeys.milestones],
  onSettled: onSettled,
);
