import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/vibe_colors.dart';
import '../../../core/utils/scale.dart';
import '../../api/listingflow/filter_models.dart';
import '../../api/listingflow/listing_models.dart';
import '../../component/c_text.dart';
import '../../component/pressable.dart';
import 'filter_section.dart';
import 'helper/filter_options.dart';

/// Language / topic filter sheet (RN `FilterSheetModal`) for Discover: the
/// options include what the loaded feed carries. Returns the applied filter,
/// [HostFilter.none] when cleared, null when dismissed.
Future<HostFilter?> showFilterSheet(
  BuildContext context, {
  required HostFilter current,
}) => showHostFilterSheet(context, current: current, hosts: cachedFeedHosts());

/// [showFilterSheet] over any [hosts] (search passes its hits and
/// [includeCategories], as RN search did).
///
/// The selection is staged until "Apply". "Clear All" clears at once and
/// keeps the sheet open (RN), so a dismiss after it yields [HostFilter.none].
Future<HostFilter?> showHostFilterSheet(
  BuildContext context, {
  required HostFilter current,
  List<HostTraits> hosts = const [],
  bool includeCategories = false,
}) async {
  FocusManager.instance.primaryFocus?.unfocus();
  var cleared = false;
  final applied = await showModalBottomSheet<HostFilter>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.transparent,
    barrierColor: AppColors.blackA(0.55),
    elevation: 0,
    builder: (_) => FilterSheet(
      current: current,
      hosts: hosts,
      includeCategories: includeCategories,
      onCleared: () => cleared = true,
    ),
  );
  return applied ?? (cleared ? HostFilter.none : null);
}

/// The sheet's content. Selection lives in two notifiers, so a tap rebuilds
/// only its section and the buttons.
class FilterSheet extends HookWidget {
  const FilterSheet({
    super.key,
    required this.current,
    required this.hosts,
    required this.includeCategories,
    required this.onCleared,
  });

  final HostFilter current;
  final List<HostTraits> hosts;
  final bool includeCategories;
  final VoidCallback onCleared;

  @override
  Widget build(BuildContext context) {
    final languages = useValueNotifier<List<String>>(current.languages);
    final topic = useValueNotifier<String?>(
      current.hasTopic ? current.topic : null,
    );
    final opts = useFilterSheetOptions(
      context,
      hosts: hosts,
      includeCategories: includeCategories,
      current: current,
    );
    final topics = opts.options.topics;

    final c = context.colors;
    final dark = c.isDark;
    final bottom = math.max(
      40.ms,
      MediaQuery.paddingOf(context).bottom + 16.ms,
    );

    void toggleLanguage(String lang) {
      final list = languages.value;
      languages.value = list.any((l) => sameText(l, lang))
          ? [
              for (final l in list)
                if (!sameText(l, lang)) l,
            ]
          : [...list, lang];
    }

    return Container(
      decoration: BoxDecoration(
        color: c.modalCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28.ms)),
        border: Border(
          top: BorderSide(
            color: dark ? AppColors.whiteA(0.08) : AppColors.blackA(0.07),
          ),
        ),
      ),
      padding: EdgeInsets.fromLTRB(20.ms, 16.ms, 20.ms, bottom),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40.ms,
                height: 4.ms,
                margin: EdgeInsets.only(bottom: 16.ms),
                decoration: BoxDecoration(
                  color: dark ? AppColors.whiteA(0.2) : AppColors.blackA(0.15),
                  borderRadius: BorderRadius.circular(2.ms),
                ),
              ),
            ),
            const _Header(),
            ValueListenableBuilder<List<String>>(
              valueListenable: languages,
              builder: (_, selected, _) => FilterSection(
                titleKey: 'search:filter.language',
                allKey: 'search:filter.all_languages',
                options: opts.options.languages,
                selected: selected,
                multi: true,
                loading: opts.languagesLoading,
                emptyKey: opts.languagesError != null
                    ? 'search:filter.languages_failed'
                    : 'search:filter.no_languages',
                onRetry: opts.languagesError != null
                    ? opts.retryLanguages
                    : null,
                onToggle: toggleLanguage,
                onReset: () => languages.value = const [],
              ),
            ),
            if (topics.isNotEmpty || opts.topicsLoading) ...[
              SizedBox(height: 20.ms),
              ValueListenableBuilder<String?>(
                valueListenable: topic,
                builder: (_, selected, _) => FilterSection(
                  titleKey: 'search:filter.topic',
                  allKey: 'search:filter.all_topics',
                  options: topics,
                  selected: [?selected],
                  loading: opts.topicsLoading,
                  onToggle: (t) =>
                      topic.value = sameText(selected, t) ? null : t,
                  onReset: () => topic.value = null,
                ),
              ),
            ],
            SizedBox(height: 28.ms),
            ListenableBuilder(
              listenable: Listenable.merge([languages, topic]),
              builder: (context, _) {
                final hasFilter =
                    languages.value.isNotEmpty || topic.value != null;
                return Row(
                  children: [
                    if (hasFilter) ...[
                      Expanded(
                        child: _SheetButton(
                          label: 'search:filter.clear_all',
                          onPressed: () {
                            languages.value = const [];
                            topic.value = null;
                            onCleared();
                          },
                        ),
                      ),
                      SizedBox(width: 12.ms),
                    ],
                    Expanded(
                      flex: hasFilter ? 2 : 1,
                      child: _SheetButton(
                        label: 'search:filter.apply',
                        filled: true,
                        onPressed: () => Navigator.of(context).pop(
                          HostFilter(
                            languages: languages.value,
                            topic: topic.value,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.only(bottom: 20.ms),
      child: Row(
        children: [
          const Expanded(
            child: CText(
              'search:filter.title',
              size: 20,
              weight: FontWeight.w900,
              maxLines: 1,
            ),
          ),
          Pressable(
            onPressed: () => Navigator.of(context).pop(),
            semanticLabel: context.t('search:filter.close'),
            child: Container(
              width: 36.ms,
              height: 36.ms,
              decoration: BoxDecoration(
                color: c.isDark
                    ? AppColors.whiteA(0.07)
                    : AppColors.blackA(0.05),
                borderRadius: BorderRadius.circular(10.ms),
              ),
              child: Icon(LucideIcons.x, size: 16.ms, color: c.text),
            ),
          ),
        ],
      ),
    );
  }
}

/// RN sheet buttons: Title Case, no letter-spacing, so "Clear All" fits the
/// one-third button at 320 px.
class _SheetButton extends StatelessWidget {
  const _SheetButton({
    required this.label,
    required this.onPressed,
    this.filled = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final radius = BorderRadius.circular(16.ms);
    return Pressable(
      onPressed: onPressed,
      activeOpacity: 0.85,
      child: Container(
        height: 50.ms,
        alignment: Alignment.center,
        padding: EdgeInsets.symmetric(horizontal: 8.ms),
        decoration: filled
            ? BoxDecoration(color: c.accent, borderRadius: radius)
            : BoxDecoration(
                borderRadius: radius,
                border: Border.all(
                  color: c.isDark
                      ? AppColors.whiteA(0.15)
                      : AppColors.blackA(0.12),
                ),
              ),
        child: CText(
          label,
          size: filled ? 15 : 14,
          weight: filled ? FontWeight.w900 : FontWeight.w800,
          color: filled ? c.onAccent : c.text,
          maxLines: 1,
        ),
      ),
    );
  }
}
