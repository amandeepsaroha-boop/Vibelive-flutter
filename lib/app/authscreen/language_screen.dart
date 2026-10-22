import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/vibe_colors.dart';
import '../../core/utils/scale.dart';
import '../api/authscreen/interests_models.dart';
import '../api/authscreen/onboarding_queries.dart';
import '../component/c_button.dart';
import '../component/c_text.dart';
import '../component/pressable.dart';
import '../component/skeleton.dart';
import 'helper/onboarding_actions.dart';
import 'onboarding_widgets.dart';

/// "Which languages should your expert speak?", `/onboarding/language`
/// (RN `LanguagePreferenceScreen`). The choices are the Languages collection
/// (`/languages`); title, help, limits and "Skip for now" (only while the
/// question is optional) come from the admin interests form. The picks are
/// saved as language documentIds in the `expert_language` answer.
class LanguageScreen extends HookWidget {
  const LanguageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final query = useLanguageQuestion(context);
    final question = query.data?.question;
    final selected = useState<List<String>?>(null);
    final error = useState<(String, Map<String, dynamic>?)?>(null);
    final busy = useState(false);

    // The form stopped asking: the step is done.
    useEffect(() {
      if (query.data != null && question == null) {
        skipLanguageStep().then((_) {
          if (context.mounted) OnboardingActions.continueIntoApp(context);
        });
      }
      return null;
    }, [query.data]);

    final picks = selected.value ?? query.data?.selected ?? const [];
    final min = (question?.minSelect ?? 1).clamp(1, 99);
    final max = question?.maxSelect;

    void toggle(String value) {
      if (busy.value) return;
      error.value = null;
      if (picks.contains(value)) {
        selected.value = [...picks]..remove(value);
      } else if (question?.isMulti != true) {
        selected.value = [value];
      } else if (max != null && picks.length >= max) {
        error.value = (
          'auth:onboarding.language.errors.pick_max',
          {'max': max},
        );
      } else {
        selected.value = [...picks, value];
      }
    }

    Future<void> run(Future<void> Function() action) async {
      if (busy.value) return;
      busy.value = true;
      try {
        await action();
        if (context.mounted) await OnboardingActions.continueIntoApp(context);
      } on ApiException catch (e) {
        error.value = (e.i18nKey, null);
      } catch (_) {
        error.value = ('auth:onboarding.language.errors.save_failed', null);
      }
      if (context.mounted) busy.value = false;
    }

    void submit() {
      if (picks.length < min) {
        error.value = min > 1
            ? ('auth:onboarding.language.errors.pick_min', {'min': min})
            : ('auth:onboarding.language.errors.pick_one', null);
        return;
      }
      run(() => saveLanguageStep(picks));
    }

    final hasTitle = question?.title.isNotEmpty ?? false;
    final hasHelp = question?.helpText.isNotEmpty ?? false;
    final help = hasHelp
        ? question!.helpText
        : context.t('auth:onboarding.language.help');
    // RN appends " Pick up to N." to the help line once the form is loaded.
    final limit = question != null && max != null
        ? ' ${context.t('auth:onboarding.language.limit', variables: {'max': max})}'
        : '';
    final idle = !busy.value;
    return OnboardingPage(
      icon: LucideIcons.languages,
      titleRaw: hasTitle,
      title: hasTitle ? question!.title : 'auth:onboarding.language.title',
      bodyRaw: true,
      body: '$help$limit',
      children: [
        if (query.isLoading || (query.data != null && question == null))
          const _ChipsSkeleton()
        else if (query.isError && query.data == null) ...[
          const OnboardingNote(
            'auth:onboarding.language.load_error',
            error: true,
          ),
          SizedBox(height: 22.ms),
          CButton(
            title: 'auth:onboarding.language.try_again',
            showArrow: false,
            height: 54.ms,
            disabled: !idle,
            onPressed: () => query.refetch(),
          ),
          _TextAction(
            'auth:onboarding.language.continue_app',
            enabled: idle,
            onPressed: () => run(skipLanguageStep),
          ),
        ] else if (question != null) ...[
          Wrap(
            spacing: 10.ms,
            runSpacing: 10.ms,
            children: [
              for (final option in question.options)
                _Chip(
                  option,
                  on: picks.contains(option.value),
                  onTap: () => toggle(option.value),
                ),
            ],
          ),
          if (error.value != null)
            OnboardingNote(
              error.value!.$1,
              variables: error.value!.$2,
              error: true,
            ),
          SizedBox(height: 22.ms),
          CButton(
            title: 'actions.continue',
            showArrow: false,
            height: 54.ms,
            loading: busy.value,
            disabled: picks.length < min,
            onPressed: submit,
          ),
          if (!question.required)
            _TextAction(
              'auth:onboarding.language.skip',
              enabled: idle,
              onPressed: () => run(skipLanguageStep),
            ),
        ],
        SizedBox(height: 10.ms),
        SignOutLink(enabled: idle),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.option, {required this.on, required this.onTap});
  final InterestOption option;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Pressable(
      activeOpacity: 0.8,
      onPressed: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 44.ms,
        padding: EdgeInsets.symmetric(horizontal: 16.ms),
        decoration: BoxDecoration(
          color: on ? c.accentA(0.12) : c.surface,
          borderRadius: BorderRadius.circular(14.ms),
          border: Border.all(width: 1.5, color: on ? c.accent : c.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (on) ...[
              Icon(LucideIcons.check, size: 14.ms, color: c.accent),
              SizedBox(width: 6.ms),
            ],
            Flexible(
              child: CText.raw(
                option.label,
                size: 14,
                weight: on ? FontWeight.w800 : FontWeight.w600,
                color: c.text,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Loading: language chips of varied widths (same height and radius).
class _ChipsSkeleton extends StatelessWidget {
  const _ChipsSkeleton();

  static const _widths = [92.0, 118.0, 78.0, 104.0, 86.0, 124.0, 98.0];

  @override
  Widget build(BuildContext context) => Shimmer(
    child: Wrap(
      spacing: 10.ms,
      runSpacing: 10.ms,
      children: [
        for (final w in _widths)
          SkeletonBox(width: w.ms, height: 44.ms, radius: 14.ms),
      ],
    ),
  );
}

/// Muted text button; dimmed while the screen is busy (RN).
class _TextAction extends StatelessWidget {
  const _TextAction(this.label, {required this.onPressed, this.enabled = true});
  final String label;
  final VoidCallback onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Center(
    child: Pressable(
      onPressed: enabled ? onPressed : null,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 12.ms, horizontal: 16.ms),
        child: Opacity(
          opacity: enabled ? 1 : 0.5,
          child: CText(
            label,
            size: 12,
            weight: FontWeight.w800,
            color: context.colors.textMuted,
          ),
        ),
      ),
    ),
  );
}
