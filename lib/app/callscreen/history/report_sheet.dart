import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/network/strapi.dart';
import '../../../core/query/query_hooks.dart';
import '../../../core/session/session_store.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/vibe_colors.dart';
import '../../../core/utils/scale.dart';
import '../../api/component/component_queries.dart';
import '../../api/component/report_api.dart';
import '../../component/c_alert.dart';
import '../../component/c_button.dart';
import '../../component/c_text.dart';
import '../../component/pressable.dart';
import '../../component/skeleton.dart';
import '../../component/keyboard_inset.dart';
import 'helper/history_entry.dart';
import 'helper/history_errors.dart';
import 'history_note_field.dart';

/// "Report Profile" (RN explore report modal): a category, an optional note.
/// True when the report was sent. Centered above the keyboard; the title and
/// the submit button stay put while the categories and the note scroll.
Future<bool> showReportSheet(BuildContext context, HistoryEntry entry) async =>
    await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierLabel: context.t('actions.close'),
      barrierColor: AppColors.blackA(0.6),
      transitionDuration: const Duration(milliseconds: 180),
      transitionBuilder: (_, anim, _, child) =>
          FadeTransition(opacity: anim, child: child),
      pageBuilder: (_, _, _) =>
          KeyboardInset(child: _ReportDialog(entry: entry)),
    ) ??
    false;

class _ReportDialog extends HookWidget {
  const _ReportDialog({required this.entry});
  final HistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final categories = useReportCategories(context);
    final selected = useState<Object?>(null);
    final note = useTextEditingController();
    final submit = useSubmitReport();

    Future<void> send() async {
      final me = SessionStore.instance.value.userDocumentId;
      final category = selected.value;
      // RN checks the reporter and the category only; a row without the
      // other person still posts (without `reported_to_user`).
      if (me == null || category == null) {
        unawaited(
          CAlert.show(
            title: 'call:history.report.missing_title',
            message: 'call:history.report.missing',
            variant: CAlertVariant.warning,
          ),
        );
        return;
      }
      try {
        await submit.mutateAsync(
          ReportInput(
            reporterId: me,
            reportedUserId: entry.counterpartId,
            categoryId: category,
            note: note.text,
          ),
        );
        if (context.mounted) Navigator.of(context).pop(true);
      } on ApiException catch (e) {
        unawaited(
          CAlert.error(
            HistoryErrors.relabel(e, 'call:history.report.failed'),
            title: HistoryErrors.title,
          ),
        );
      }
    }

    return SafeArea(
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(16.ms),
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 480),
              padding: EdgeInsets.all(16.ms),
              decoration: BoxDecoration(
                color: c.modalCard,
                borderRadius: BorderRadius.circular(18.ms),
                border: Border.all(color: c.modalBorder),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: CText(
                          'call:history.report.title',
                          size: 18,
                          weight: FontWeight.w900,
                          color: c.modalText,
                          maxLines: 1,
                        ),
                      ),
                      Pressable(
                        onPressed: () => Navigator.of(context).pop(false),
                        semanticLabel: context.t('actions.close'),
                        hitPadding: EdgeInsets.all(4.ms),
                        child: Icon(
                          LucideIcons.x,
                          size: 18.ms,
                          color: c.modalText,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12.ms),
                  Flexible(
                    child: SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _Categories(
                            query: categories,
                            selected: selected.value,
                            onSelect: (id) => selected.value = id,
                          ),
                          SizedBox(height: 12.ms),
                          HistoryNoteField(
                            controller: note,
                            placeholder: 'call:history.report.placeholder',
                            minLines: 3,
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: 12.ms),
                  CButton(
                    title: 'call:history.report.submit',
                    showArrow: false,
                    height: 44.ms,
                    titleSize: 13,
                    loading: submit.isPending,
                    onPressed: send,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Category chips; a shimmer while they load, a retry when they failed.
class _Categories extends StatelessWidget {
  const _Categories({
    required this.query,
    required this.selected,
    required this.onSelect,
  });

  final QueryResult<List<JsonMap>, ApiException> query;
  final Object? selected;
  final ValueChanged<Object> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final spacing = 8.ms;
    final list = query.data;
    if (list != null) {
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [
          for (final row in list)
            if (_idOf(row) case final id?)
              _Chip(
                label: J.str(row['category']) ?? J.str(row['name']),
                active: selected == id,
                onPressed: () => onSelect(id),
              ),
        ],
      );
    }
    if (query.isError && !query.isFetching) {
      return Row(
        children: [
          Expanded(
            child: CText(
              'call:history.report.categories_failed',
              size: 12,
              weight: FontWeight.w700,
              color: c.modalMuted,
            ),
          ),
          Pressable(
            onPressed: () => query.refetch(),
            hitPadding: EdgeInsets.all(6.ms),
            child: CText(
              'actions.retry',
              size: 12,
              weight: FontWeight.w800,
              color: c.accent,
            ),
          ),
        ],
      );
    }
    return Shimmer(
      child: Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [
          for (final w in const [72.0, 96.0, 64.0, 110.0, 80.0])
            SkeletonBox(width: w.ms, height: 32.ms, radius: 10),
        ],
      ),
    );
  }

  /// RN: `documentId || id`.
  static Object? _idOf(JsonMap row) => J.str(row['documentId']) ?? row['id'];
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.active,
    required this.onPressed,
  });

  final String? label;
  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = active ? c.accent : c.modalText;
    final idle = c.isDark ? AppColors.whiteA(0.12) : AppColors.blackA(0.12);
    return Pressable(
      onPressed: onPressed,
      child: Container(
        height: 32.ms,
        padding: EdgeInsets.symmetric(horizontal: 10.ms),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? c.accentA(0.15) : AppColors.transparent,
          borderRadius: BorderRadius.circular(10.ms),
          border: Border.all(color: active ? c.accent : idle),
        ),
        child: label == null
            ? CText(
                'call:history.report.category',
                size: 11,
                weight: FontWeight.w800,
                color: color,
              )
            : CText.raw(
                label!,
                size: 11,
                weight: FontWeight.w800,
                color: color,
                maxLines: 1,
              ),
      ),
    );
  }
}
