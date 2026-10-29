import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../core/utils/scale.dart';
import '../../../api/client/client_models.dart';
import '../../../api/client/client_queries.dart';
import '../../../api/hosthub/catalog_models.dart';
import '../../../api/hosthub/hosthub_queries.dart';
import '../../../client/personal_info/helper/location_autofill.dart';
import '../../../client/personal_info/widgets/use_location_button.dart';
import '../../common/host_review.dart';
import '../helper/draft_controller.dart';
import '../helper/host_steps.dart';
import '../helper/prefill.dart';
import '../widgets/fix_notice.dart';
import '../widgets/handle_field.dart';
import '../widgets/host_chip.dart';
import '../widgets/host_field.dart';
import '../widgets/pickers.dart';
import '../widgets/select_field.dart';
import '../widgets/step_body.dart';

/// 2 of 11: name, handle, gender, languages and location, pre-filled from
/// Personal Info.
class BasicProfileStep extends StatelessWidget {
  const BasicProfileStep({super.key, required this.draft});
  final HostDraftController draft;

  @override
  Widget build(BuildContext context) {
    final d = draft;
    final review = HostReviewScope.of(context);
    return HostStepBody(
      title: 'hostflow:basic.title',
      subtitle: 'hostflow:basic.subtitle',
      children: [
        const HostFixNotice(step: HostStep.basic),
        const HostLabel('hostflow:basic.name', top: 0),
        HostField(
          controller: d.name,
          hint: 'hostflow:basic.name_hint',
          capitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.name],
          fieldKey: const ValueKey('hostflow-name'),
          flagged: review.flagged('name'),
        ),
        const HostLabel('hostflow:basic.handle'),
        HostHandleField(
          controller: d.handle,
          ownExpertId: d.expertId,
          flagged: review.flagged('handler'),
        ),
        const HostLabel('hostflow:basic.gender'),
        _GenderRow(gender: d.gender),
        const HostLabel('hostflow:basic.languages'),
        _Languages(draft: d),
        const HostLabel('hostflow:basic.location'),
        _Location(state: d.state, district: d.district),
      ],
    );
  }
}

class _GenderRow extends StatelessWidget {
  const _GenderRow({required this.gender});
  final ValueNotifier<String?> gender;

  static const _options = [
    ('Female', 'hostflow:basic.female', LucideIcons.venus),
    ('Male', 'hostflow:basic.male', LucideIcons.mars),
    ('Others', 'hostflow:basic.other', LucideIcons.venusAndMars),
  ];

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String?>(
    valueListenable: gender,
    builder: (_, value, _) => Row(
      children: [
        for (final (i, (v, label, icon)) in _options.indexed) ...[
          if (i > 0) SizedBox(width: 10.ms),
          Expanded(
            child: HostChip(
              label: label,
              icon: icon,
              selected: value == v,
              onTap: () => gender.value = v,
            ),
          ),
        ],
      ],
    ),
  );
}

class _Languages extends HookWidget {
  const _Languages({required this.draft});
  final HostDraftController draft;

  @override
  Widget build(BuildContext context) {
    final catalog = useHostLanguages(context);
    final locale = Localizations.localeOf(context);
    useEffect(() {
      final data = catalog.data;
      if (data != null) HostPrefill.seedLanguages(draft, data, locale);
      return null;
    }, [catalog.data]);
    final chosen = useValueListenable(draft.languages);
    void open() => showLanguagePicker(context, draft.languages);
    return Wrap(
      spacing: 10.ms,
      runSpacing: 10.ms,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final HostOption l in chosen)
          HostChip(
            label: l.label,
            translate: false,
            tone: HostChipTone.tint,
            onTap: open,
          ),
        HostRoundChip(
          icon: LucideIcons.plus,
          onTap: open,
          semanticLabel: context.t('hostflow:basic.add_language'),
        ),
      ],
    );
  }
}

class _Location extends HookWidget {
  const _Location({required this.state, required this.district});
  final ValueNotifier<GeoOption?> state;
  final ValueNotifier<GeoOption?> district;

  @override
  Widget build(BuildContext context) {
    final s = useValueListenable(state);
    final dist = useValueListenable(district);
    final locating = useValueNotifier(false);

    // Tracked by LocationAutofill (`location_autofill`, this source).
    void locate({bool silent = false}) => LocationAutofill.run(
      locating: locating,
      alive: () => context.mounted,
      silent: silent,
      stillEmpty: () => state.value == null,
      analyticsSource: 'host_onboarding',
      apply: (fill) {
        state.value = fill.state;
        district.value = fill.district;
      },
    );

    // An empty location fills itself from where the device is, once; a
    // location already chosen (or restored with the draft) is kept.
    useEffect(() {
      if (state.value == null) locate(silent: true);
      return null;
    }, const []);
    // A state known only by name (Personal Info's address copy) is looked up
    // once, so its districts can load.
    final lookup = s != null && s.filterId == null ? s.name : '';
    final found = useStates(context, search: lookup, enabled: lookup != '');
    useEffect(() {
      final match = found.data?.where(
        (o) => o.name.toLowerCase() == lookup.toLowerCase(),
      );
      if (match != null && match.isNotEmpty) state.value = match.first;
      return null;
    }, [found.data]);

    Future<void> pickState() async {
      final picked = await showGeoPicker(context, selected: s);
      if (picked == null) return;
      if (picked.filterId != s?.filterId || picked.name != s?.name) {
        district.value = null;
      }
      state.value = picked;
    }

    Future<void> pickDistrict() async {
      final picked = await showGeoPicker(context, state: s, selected: dist);
      if (picked != null) district.value = picked;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: 10.ms),
          child: UseLocationButton(locating: locating, onPressed: locate),
        ),
        Row(
          children: [
            Expanded(
              child: HostSelectField(
                key: const ValueKey('hostflow-state'),
                value: s?.name,
                hint: 'hostflow:basic.state',
                onTap: pickState,
              ),
            ),
            SizedBox(width: 10.ms),
            Expanded(
              child: HostSelectField(
                key: const ValueKey('hostflow-district'),
                value: dist?.name,
                hint: 'hostflow:basic.district',
                enabled: s?.filterId != null,
                onTap: pickDistrict,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
