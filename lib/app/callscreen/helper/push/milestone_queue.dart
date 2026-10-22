import 'package:flutter/foundation.dart';

import '../../../../core/utils/log.dart';
import '../../../api/banner/banner_api.dart';
import '../../../api/banner/banner_models.dart';
import '../../../api/banner/banner_queries.dart';

/// RN `milestoneStore`: achievements to show one at a time. Fed by
/// `milestone_unlocked` pushes (foreground) and the post-login fetch of
/// unviewed ones; deduped on the unlocked row id. The achievement modal (UI)
/// listens to [queue], shows [current] and calls [closeCurrent].
abstract final class MilestoneQueue {
  static final _queue = ValueNotifier<List<UnlockedMilestone>>(const []);
  static final _seen = <String>{};

  static ValueListenable<List<UnlockedMilestone>> get queue => _queue;
  static UnlockedMilestone? get current => _queue.value.firstOrNull;

  static void add(UnlockedMilestone m) {
    final id = m.id;
    if (id == null || !_seen.add(id)) return;
    _queue.value = [..._queue.value, m];
  }

  /// A `milestone_unlocked` push (data values are strings).
  static void addFromPush(Map<String, dynamic> data) =>
      add(UnlockedMilestone.fromPush(data));

  /// After login / signed-in start: the ones unlocked while away.
  static Future<void> fetchMissed(String userDocumentId) async {
    try {
      for (final m in await ensureUnviewedMilestones(userDocumentId)) {
        add(m);
      }
    } catch (e) {
      Log.w('MilestoneQueue', 'fetch failed: $e');
    }
  }

  /// The modal closed: next one, and mark this one viewed (never blocks).
  static Future<void> closeCurrent() async {
    final shown = current;
    if (shown == null) return;
    _queue.value = _queue.value.skip(1).toList();
    final id = shown.unlockedMilestoneDocumentId;
    if (id == null) return;
    try {
      await MilestoneApi.markViewed(id);
    } catch (e) {
      Log.w('MilestoneQueue', 'markViewed failed: $e');
    }
  }

  static void clear() {
    _queue.value = const [];
    _seen.clear();
  }
}
