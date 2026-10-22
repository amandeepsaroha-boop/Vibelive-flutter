import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../../core/session/session_store.dart';
import '../../../core/theme/vibe_colors.dart';
import '../../../core/utils/scale.dart';
import '../../api/resourcesscreen/resources_queries.dart';
import '../../component/c_back_button.dart';
import '../../component/c_text.dart';
import '../../component/pressable.dart';
import '../../component/status_bar_style.dart';
import '../../component/vibe_background.dart';
import '../helper/menu_actions.dart';
import '../helper/resource_menu.dart';
import '../helper/resource_palette.dart';
import '../widgets/resource_row.dart';

/// `/me/category-menu?id=resources|identity|hub` (RN `CategoryMenuScreen`):
/// the ME tab's RESOURCES card opens it.
class CategoryMenuScreen extends HookWidget {
  const CategoryMenuScreen({super.key, this.id});
  final String? id;

  @override
  Widget build(BuildContext context) {
    final session = useValueListenable(SessionStore.instance);
    final isExpert = session.isExpert;
    final isResources = id == ResourceMenu.resourcesId;
    // Disk-cached: the CMS rows are there instantly after the first launch.
    // A failed read leaves the fixed rows (RN ignored the error).
    final pages = useMenuPages(context);
    final pageList = pages.data;
    final category = useMemoized(
      () => ResourceMenu.category(
        id,
        isExpert: isExpert,
        pages: pageList ?? const [],
      ),
      [id, isExpert, pageList],
    );
    final expanded = useState<String?>(null);
    final p = ResourcePalette.of(context);

    if (category == null) return const _NotFound();

    final color = category.color ?? context.colors.accent;
    final loadingPages = isResources && pageList == null && pages.isLoading;
    final rows = <Widget>[];
    for (final item in category.items) {
      if (loadingPages && item.action == ResourceAction.logout) {
        for (var i = 0; i < 2; i++) {
          rows.add(_gap(const ResourceRowSkeleton()));
        }
      }
      final isDropdown = item.action == ResourceAction.dropdown;
      final open = isDropdown && expanded.value == item.id;
      rows.add(
        _gap(
          ResourceRow(
            key: ValueKey(item.id),
            item: item,
            color: color,
            open: open,
            onTap: () {
              if (isDropdown) {
                expanded.value = open ? null : item.id;
              } else {
                ResourceMenuActions.run(context, item);
              }
            },
          ),
        ),
      );
      if (open) {
        rows.add(
          Padding(
            padding: EdgeInsets.only(left: 40.ms, bottom: 4.ms),
            child: Column(
              children: [
                for (final c in item.children)
                  Padding(
                    padding: EdgeInsets.only(bottom: 8.ms),
                    child: ResourceRow(
                      key: ValueKey(c.id),
                      item: c,
                      color: color,
                      child: true,
                      onTap: () => ResourceMenuActions.run(context, c),
                    ),
                  ),
              ],
            ),
          ),
        );
      }
    }

    final bottom = MediaQuery.paddingOf(context).bottom;
    return ThemedStatusBar(
      child: Scaffold(
        backgroundColor: context.colors.bg,
        body: Stack(
          children: [
            const VibeBackground(),
            SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 20.ms,
                      vertical: 16.ms,
                    ),
                    child: Row(
                      children: [
                        CBackButton(color: p.text),
                        SizedBox(width: 16.ms),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CText(
                                category.label,
                                size: 20,
                                weight: FontWeight.w900,
                                letterSpacing: 1,
                                color: p.text,
                                maxLines: 1,
                              ),
                              CText(
                                'resources:menu.subtitle',
                                size: 10,
                                weight: FontWeight.w700,
                                letterSpacing: 2,
                                color: p.menuMuted,
                                maxLines: 1,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(
                        20.ms,
                        10.ms,
                        20.ms,
                        40.ms + bottom,
                      ),
                      children: rows,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _gap(Widget child) => Padding(
    padding: EdgeInsets.only(bottom: 12.ms),
    child: child,
  );
}

/// RN "Category not found" + "Go Back".
class _NotFound extends StatelessWidget {
  const _NotFound();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ThemedStatusBar(
      child: Scaffold(
        backgroundColor: c.bg,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CText('resources:menu.not_found', size: 16, color: c.text),
              SizedBox(height: 20.ms),
              Pressable(
                onPressed: () => Navigator.of(context).maybePop(),
                hitPadding: const EdgeInsets.all(8),
                child: CText(
                  'resources:menu.go_back',
                  size: 16,
                  color: c.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
