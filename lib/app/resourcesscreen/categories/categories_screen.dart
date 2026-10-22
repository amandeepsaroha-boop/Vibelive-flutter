import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/vibe_colors.dart';
import '../../../core/utils/scale.dart';
import '../../api/client/client_keys.dart';
import '../../api/hosthub/hosthub_queries.dart';
import '../../api/resourcesscreen/resources_keys.dart';
import '../../api/resourcesscreen/resources_queries.dart';
import '../../component/c_alert.dart';
import '../../component/c_button.dart';
import '../../component/c_state_view.dart';
import '../../component/c_text.dart';
import '../../component/skeleton.dart';
import '../../component/status_bar_style.dart';
import '../../component/vibe_background.dart';
import '../helper/categories_controller.dart';
import '../helper/resource_palette.dart';
import '../widgets/sub_page_header.dart';
import 'categories_widgets.dart';

/// `/me/categories` (RN `CategoriesScreen`): a host picks up to 10
/// categories for their expertise, then moves on to the next missing
/// profile step.
class CategoriesScreen extends HookWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final setup = useHostCategoriesSetup(context);
    final first = useHostCategoriesPage(
      context,
      platform: setup.data?.platform,
      enabled: setup.data != null,
    );
    final ctrl = useMemoized(CategoriesController.new);
    useEffect(() => ctrl.dispose, [ctrl]);
    useListenable(ctrl);
    final setupData = setup.data;
    final firstPage = first.data;
    useEffect(() {
      if (setupData != null && firstPage != null) {
        ctrl.seed(setupData, firstPage);
      }
      return null;
    }, [setupData, firstPage]);

    final saving = useState(false);
    final update = useUpdateHostProfile(
      alsoInvalidate: const [
        ResourcesKeys.hostCategoriesAll,
        ClientKeys.profiles,
      ],
    );

    Future<void> save() async {
      final expertId = setupData?.expertId;
      if (expertId == null || saving.value) return;
      if (ctrl.selectedCount == 0) {
        await CAlert.show(
          title: 'resources:categories.title',
          message: 'resources:errors.pick_one',
        );
        return;
      }
      saving.value = true;
      try {
        final saved = await update.mutateAsync((
          expertId: expertId,
          patch: ctrl.patch,
        ));
        if (!context.mounted) return;
        saving.value = false;
        await CAlert.show(
          title: 'resources:categories.saved_title',
          message: 'resources:categories.saved_message',
          primaryLabel: 'resources:categories.continue',
          variant: CAlertVariant.success,
          dismissible: false,
        );
        if (context.mounted) {
          await context.push<void>(CategoriesController.nextRoute(saved));
        }
      } on ApiException catch (e) {
        await CAlert.error(e);
      } finally {
        if (context.mounted) saving.value = false;
      }
    }

    final error = setup.error ?? first.error;
    final Widget body;
    if (!ctrl.seeded && (setup.isError || first.isError) && error != null) {
      body = CStateView.error(
        context,
        error,
        onRetry: () {
          if (setup.isError) setup.refetch();
          if (first.isError) first.refetch();
        },
      );
    } else if (!ctrl.seeded) {
      body = Padding(
        padding: EdgeInsets.fromLTRB(20.ms, 8.ms, 20.ms, 0),
        child: const CategoriesSkeleton(),
      );
    } else {
      body = _Picker(ctrl: ctrl, saving: saving.value, onSave: save);
    }

    return ThemedStatusBar(
      child: Scaffold(
        backgroundColor: context.colors.bg,
        body: Stack(
          children: [
            const VibeBackground(),
            SafeArea(
              child: Column(
                children: [
                  const SubPageHeader(title: 'resources:categories.title'),
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

class _Picker extends StatelessWidget {
  const _Picker({
    required this.ctrl,
    required this.saving,
    required this.onSave,
  });

  final CategoriesController ctrl;
  final bool saving;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final p = ResourcePalette.of(context);
    final items = ctrl.visible;
    final count = ctrl.selectedCount;
    return Padding(
      padding: EdgeInsets.fromLTRB(20.ms, 8.ms, 20.ms, 18.ms),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CText(
            'resources:categories.hint',
            size: 12,
            weight: FontWeight.w700,
            color: p.muted,
          ),
          SizedBox(height: 8.ms),
          CategorySearch(onChanged: ctrl.setQuery),
          SizedBox(height: 10.ms),
          if (count > 0)
            Padding(
              padding: EdgeInsets.fromLTRB(12.ms, 0, 12.ms, 10.ms),
              child: CText(
                'resources:categories.selected',
                variables: {'n': count},
                size: 11,
                weight: FontWeight.w900,
                letterSpacing: 1.2,
                color: p.muted,
              ),
            ),
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n.metrics.extentAfter < 300) ctrl.loadMore();
                return false;
              },
              child: items.isEmpty && !ctrl.busy
                  ? Padding(
                      padding: EdgeInsets.symmetric(vertical: 24.ms),
                      child: CText(
                        'resources:categories.empty',
                        size: 14,
                        weight: FontWeight.w700,
                        color: p.muted,
                        align: TextAlign.center,
                      ),
                    )
                  : ListView.builder(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      itemCount: items.length + (ctrl.busy ? 1 : 0),
                      itemBuilder: (context, i) {
                        if (i == items.length) {
                          return Shimmer(
                            child: SkeletonBox(height: 46.ms, radius: 14.ms),
                          );
                        }
                        final o = items[i];
                        return CategoryTile(
                          key: ValueKey(o.value),
                          option: o,
                          active: ctrl.isSelected(o),
                          onTap: () => ctrl.toggle(o),
                        );
                      },
                    ),
            ),
          ),
          SizedBox(height: 10.ms),
          CButton(
            title: saving
                ? 'resources:categories.saving'
                : 'resources:categories.save',
            titleVariables: {'n': count},
            onPressed: onSave,
            loading: saving,
            disabled: count == 0,
          ),
        ],
      ),
    );
  }
}
