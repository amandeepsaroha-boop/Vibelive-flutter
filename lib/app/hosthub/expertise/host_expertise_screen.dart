import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/strapi.dart';
import '../../../core/utils/scale.dart';
import '../../api/authscreen/interests_models.dart';
import '../../api/authscreen/interests_queries.dart';
import '../../api/hosthub/expertise_models.dart';
import '../../api/hosthub/hosthub_queries.dart';
import '../../component/c_alert.dart';
import '../../component/c_state_view.dart';
import '../../component/c_text.dart';
import '../../component/c_toast.dart';
import '../common/host_page.dart';
import '../onboarding/helper/host_palette.dart';
import '../onboarding/widgets/continue_bar.dart';
import '../onboarding/widgets/host_chip.dart';

/// Specialization (RN ExpertiseScreen): every interests-form question a
/// host answers (gender and call mode are not asked: their saved / default
/// answers are kept), with RN's min / max / required rules.
class HostExpertiseScreen extends HookWidget {
  const HostExpertiseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final form = useInterestForm(context);
    final mine = useMyExpertise(context);
    final save = useSaveMyExpertise();
    final all = useMemoized<List<JsonMap>>(
      () => [
        for (final q in form.data?.questions ?? const <InterestQuestion>[])
          q.toJson(),
      ],
      [form.data],
    );
    final selections = useState<ExpertiseAnswers?>(null);
    final error = useState<String?>(null);
    final saving = useState(false);
    useEffect(() {
      final saved = mine.data?.selections;
      if (selections.value == null && form.data != null && saved != null) {
        selections.value = ExpertiseQuestions.draft(all, saved);
      }
      return null;
    }, [form.data, mine.data]);

    final questions = [
      for (final q in form.data?.questions ?? const <InterestQuestion>[])
        if (!q.isDeprecated && !ExpertiseQuestions.isHiddenForHosts(q.toJson()))
          q,
    ];
    final current = selections.value;

    Future<void> submit() async {
      final s = current;
      if (s == null) return;
      final issue = _check(questions, all, s);
      error.value = issue;
      if (issue != null) return;
      saving.value = true;
      try {
        await save.mutateAsync((selections: s, source: 'settings'));
        CToast.show('hosthub:expertise.saved', variant: CToastVariant.success);
        if (context.mounted) HostPage.leave(context);
      } on ApiException catch (e) {
        await CAlert.error(e, title: 'hostflow:hub.expertise');
      } finally {
        if (context.mounted) saving.value = false;
      }
    }

    final Widget body;
    if (current == null && (form.isError || mine.isError)) {
      body = CStateView.error(
        context,
        (form.error ?? mine.error)!,
        onRetry: () {
          form.refetch();
          mine.refetch();
        },
      );
    } else if (current == null) {
      body = const HostPageSkeleton();
    } else {
      body = ListView.builder(
        padding: EdgeInsets.fromLTRB(20.ms, 8.ms, 20.ms, 24.ms),
        itemCount: questions.length,
        itemBuilder: (_, i) => _Question(
          question: questions[i],
          selected: current[questions[i].key] ?? const [],
          onChanged: (values) {
            error.value = null;
            selections.value = {...current, questions[i].key: values};
          },
        ),
      );
    }

    return HostPage(
      title: 'hostflow:hub.expertise',
      body: body,
      bottom: current == null
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (error.value != null)
                  Padding(
                    padding: EdgeInsets.only(bottom: 10.ms),
                    child: CText(
                      error.value!,
                      size: 13,
                      weight: FontWeight.w600,
                      color: HostPalette.of(context).danger,
                      align: TextAlign.center,
                    ),
                  ),
                HostButton(
                  label: 'hostflow:hub.save',
                  arrow: false,
                  loading: saving.value,
                  onPressed: submit,
                ),
              ],
            ),
    );
  }

  /// RN: required / minSelect, maxSelect, then the shared rules.
  static String? _check(
    List<InterestQuestion> visible,
    List<JsonMap> all,
    ExpertiseAnswers s,
  ) {
    for (final q in visible) {
      final n = (s[q.key] ?? const []).length;
      final min = q.minSelect > 0 ? q.minSelect : (q.required ? 1 : 0);
      if (n < min) return 'hosthub:expertise.errors.required';
      if (q.maxSelect != null && n > q.maxSelect!) {
        return 'hosthub:expertise.errors.single_only';
      }
    }
    final errors = ExpertiseQuestions.validate(all, s);
    return errors.isEmpty ? null : errors.values.first;
  }
}

class _Question extends StatelessWidget {
  const _Question({
    required this.question,
    required this.selected,
    required this.onChanged,
  });

  final InterestQuestion question;
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    final q = question;
    final limits = [if (q.minSelect > 0) 'min', if (q.maxSelect != null) 'max'];
    return Padding(
      padding: EdgeInsets.only(bottom: 22.ms),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CText.raw(q.title, size: 17, weight: FontWeight.w700, color: p.text),
          if (q.helpText.isNotEmpty) ...[
            SizedBox(height: 4.ms),
            CText.raw(q.helpText, size: 13.5, color: p.muted),
          ],
          if (limits.isNotEmpty) ...[
            SizedBox(height: 4.ms),
            CText(
              'hostflow:hub.limits_${limits.join('_')}',
              variables: {'min': q.minSelect, 'max': q.maxSelect},
              size: 12,
              weight: FontWeight.w600,
              color: p.accent,
            ),
          ],
          SizedBox(height: 12.ms),
          Wrap(
            spacing: 8.ms,
            runSpacing: 8.ms,
            children: [
              for (final o in q.options)
                if (!o.isDeprecated)
                  HostChip(
                    label: o.label,
                    translate: false,
                    height: 44,
                    fontSize: 14,
                    selected: selected.contains(o.value),
                    leading: '${o.metadata['emoji'] ?? ''}'.isEmpty
                        ? null
                        : Text(
                            '${o.metadata['emoji']}',
                            style: TextStyle(fontSize: 14.ms),
                            textScaler: TextScaler.noScaling,
                          ),
                    onTap: () => onChanged(_toggle(o.value)),
                  ),
            ],
          ),
        ],
      ),
    );
  }

  List<String> _toggle(String value) {
    if (!question.isMulti) return selected.contains(value) ? [] : [value];
    final next = [...selected];
    if (!next.remove(value)) {
      final max = question.maxSelect;
      if (max != null && next.length >= max) return selected;
      next.add(value);
    }
    return next;
  }
}
