import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../../../core/analytics/events/host_events.dart';
import '../../../../core/utils/scale.dart';
import '../../../api/authscreen/interests_queries.dart';
import '../../../component/c_state_view.dart';
import '../../../component/c_text.dart';
import '../../../component/pressable.dart';
import '../../../component/skeleton.dart';
import '../helper/draft_controller.dart';
import '../helper/draft_models.dart';
import '../helper/host_palette.dart';
import '../helper/topic_catalog.dart';
import '../widgets/host_chip.dart';
import '../widgets/search_box.dart';
import '../widgets/step_body.dart';

/// 3 of 11: the topics the host likes to talk about (the interests form's
/// topic question, saved as service areas).
class InterestsStep extends HookWidget {
  const InterestsStep({super.key, required this.draft});
  final HostDraftController draft;

  @override
  Widget build(BuildContext context) {
    final form = useInterestForm(context);
    final question = useMemoized(() => HostTopicCatalog.question(form.data), [
      form.data,
    ]);
    final all = useMemoized(() => HostTopicCatalog.topics(question), [
      question,
    ]);
    final search = useTextEditingController();
    final max = HostTopicCatalog.maxSelect(question);

    final Widget grid;
    if (all.isEmpty && form.isLoading) {
      grid = const _GridSkeleton();
    } else if (all.isEmpty && form.error != null) {
      grid = CStateView.error(context, form.error!, onRetry: form.refetch);
    } else {
      grid = _FilteredGrid(
        search: search,
        all: all,
        selected: draft.topics,
        max: max,
        onLimit: () => draft.notice.value = (
          key: 'hostflow:interests.max',
          variables: {'max': max},
        ),
      );
    }

    return HostStepBody(
      title: 'hostflow:interests.title',
      subtitle: 'hostflow:interests.subtitle',
      children: [
        HostSearchBox(
          controller: search,
          hint: 'hostflow:interests.search',
          fieldKey: const ValueKey('hostflow-topic-search'),
        ),
        SizedBox(height: 16.ms),
        grid,
        SizedBox(height: 16.ms),
        _Footer(selected: draft.topics),
      ],
    );
  }
}

/// Filters while typing in the search box; only this part rebuilds.
class _FilteredGrid extends HookWidget {
  const _FilteredGrid({
    required this.search,
    required this.all,
    required this.selected,
    required this.max,
    required this.onLimit,
  });

  final TextEditingController search;
  final List<HostTopic> all;
  final ValueNotifier<List<HostTopic>> selected;
  final int max;
  final VoidCallback onLimit;

  @override
  Widget build(BuildContext context) {
    final term = useValueListenable(search).text.trim().toLowerCase();
    final shown = useMemoized(
      () => term.isEmpty
          ? all
          : [
              for (final t in all)
                if (t.label.toLowerCase().contains(term)) t,
            ],
      [all, term],
    );
    return _TopicGrid(
      topics: shown,
      selected: selected,
      max: max,
      onLimit: onLimit,
    );
  }
}

class _TopicGrid extends StatelessWidget {
  const _TopicGrid({
    required this.topics,
    required this.selected,
    required this.max,
    required this.onLimit,
  });

  final List<HostTopic> topics;
  final ValueNotifier<List<HostTopic>> selected;
  final int max;

  /// A topic past [max] was tapped.
  final VoidCallback onLimit;

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    if (topics.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 24.ms),
        child: CText(
          'hostflow:interests.empty',
          size: 15.5,
          color: p.muted,
          align: TextAlign.center,
        ),
      );
    }
    return ValueListenableBuilder<List<HostTopic>>(
      valueListenable: selected,
      // Two columns, as in the design.
      builder: (_, chosen, _) => LayoutBuilder(
        builder: (_, box) {
          final w = (box.maxWidth - 10.ms) / 2;
          return Wrap(
            spacing: 10.ms,
            runSpacing: 10.ms,
            children: [
              for (final t in topics)
                SizedBox(
                  width: w,
                  child: HostChip(
                    key: ValueKey('topic-${t.value}'),
                    label: t.label,
                    translate: false,
                    center: false,
                    fontSize: 14.5,
                    selected: chosen.contains(t),
                    leading: t.emoji.isEmpty
                        ? null
                        : Text(
                            t.emoji,
                            style: TextStyle(fontSize: 15.ms),
                            textScaler: TextScaler.noScaling,
                          ),
                    onTap: () {
                      if (!chosen.contains(t) && chosen.length >= max) {
                        onLimit();
                        return;
                      }
                      final next = [...chosen];
                      final added = !next.remove(t);
                      if (added) next.add(t);
                      selected.value = next;
                      HostEvents.topicToggled(
                        topic: t.value,
                        selected: added,
                        count: next.length,
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.selected});
  final ValueNotifier<List<HostTopic>> selected;

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    return ValueListenableBuilder<List<HostTopic>>(
      valueListenable: selected,
      builder: (_, chosen, _) => Row(
        children: [
          Expanded(
            child: CText(
              'hostflow:interests.selected',
              variables: {'count': chosen.length},
              size: 15.5,
              weight: FontWeight.w700,
              color: p.accent,
            ),
          ),
          Pressable(
            onPressed: () {
              HostEvents.topicsCleared(count: selected.value.length);
              selected.value = const [];
            },
            hitPadding: EdgeInsets.all(6.ms),
            child: CText(
              'hostflow:interests.clear',
              size: 15.5,
              weight: FontWeight.w700,
              color: p.accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _GridSkeleton extends StatelessWidget {
  const _GridSkeleton();

  @override
  Widget build(BuildContext context) => Shimmer(
    child: Wrap(
      spacing: 10.ms,
      runSpacing: 10.ms,
      children: [
        for (final w in const [150.0, 120.0, 170.0, 100.0, 140.0, 130.0])
          SkeletonBox(width: w.ms, height: 46.ms, radius: 14),
      ],
    ),
  );
}
