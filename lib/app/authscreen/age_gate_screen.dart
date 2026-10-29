import 'package:flutter/cupertino.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/analytics/analytics.dart';
import '../../core/analytics/events/auth_events.dart';
import '../../core/analytics/screen_tracker.dart';
import '../../core/network/api_exception.dart';
import '../../core/session/session_store.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/vibe_colors.dart';
import '../../core/utils/scale.dart';
import '../api/authscreen/auth_models.dart';
import '../api/authscreen/onboarding_queries.dart';
import '../component/c_button.dart';
import '../component/c_text.dart';
import '../component/pressable.dart';
import 'helper/onboarding_actions.dart';
import 'onboarding_widgets.dart';

/// 18+ gate, `/onboarding/age` (RN `AgeVerificationScreen`). The verdict is
/// the server's: `required` shows the date wheel, `blocked` is terminal
/// (sign out only), `ok` continues.
class AgeGateScreen extends HookWidget {
  const AgeGateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final status = useValueListenable(SessionStore.instance).ageGateStatus;
    final dob = useState<DateTime?>(null);
    final error = useState<String?>(null); // i18n key or server text
    final errorRaw = useState(false);
    final busy = useState(false);

    // The terminal "under 18" state is its own screen.
    final isBlocked = status == AgeGateStatus.blocked;
    useEffect(() {
      if (isBlocked) {
        AuthEvents.ageGateBlockedShown();
        ScreenTracker.view('onboarding_age_blocked');
      }
      return null;
    }, [isBlocked]);

    Future<void> submit() async {
      if (busy.value) return;
      final picked = dob.value;
      final check = picked == null ? null : DateOfBirthCheck.fromDate(picked);
      if (check == null || !check.isValid) {
        AuthEvents.ageGateSubmitted(
          result: 'invalid',
          error: check?.errorKey ?? 'no_date',
        );
        error.value = check?.errorKey ?? 'auth:onboarding.age.select_error';
        errorRaw.value = false;
        return;
      }
      busy.value = true;
      error.value = null;
      try {
        final verdict = await saveDateOfBirth(check.isoDate!);
        AuthEvents.ageGateSubmitted(
          result: switch (verdict) {
            AgeGateStatus.ok => 'allowed',
            AgeGateStatus.blocked => 'blocked',
            AgeGateStatus.required => 'needs_date',
            AgeGateStatus.unknown => 'unknown',
          },
        );
        if (verdict == AgeGateStatus.ok && context.mounted) {
          await OnboardingActions.continueIntoApp(context, from: 'age_gate');
        }
      } catch (err) {
        final e = ApiException.from(err);
        AuthEvents.ageGateSubmitted(
          result: 'error',
          error: Analytics.errorCode(e),
        );
        error.value = e.serverMessage ?? e.i18nKey;
        errorRaw.value = e.serverMessage != null;
      }
      // Still here (navigation didn't happen): Continue can be retried.
      if (context.mounted) busy.value = false;
    }

    Future<void> proceed() async {
      if (busy.value) return;
      busy.value = true;
      try {
        await OnboardingActions.continueIntoApp(context, from: 'age_gate');
      } catch (err) {
        final e = ApiException.from(err);
        error.value = e.serverMessage ?? e.i18nKey;
        errorRaw.value = e.serverMessage != null;
      }
      if (context.mounted) busy.value = false;
    }

    final blocked = status == AgeGateStatus.blocked;
    return OnboardingPage(
      icon: blocked ? LucideIcons.shieldAlert : LucideIcons.calendarDays,
      danger: blocked,
      title: blocked
          ? 'auth:onboarding.age.title_blocked'
          : 'auth:onboarding.age.title',
      body: blocked
          ? 'auth:onboarding.age.body_blocked'
          : 'auth:onboarding.age.body',
      children: [
        if (!blocked && status != AgeGateStatus.ok) ...[
          _DateField(
            date: dob.value,
            hasError: error.value != null,
            enabled: !busy.value,
            onPicked: (d) {
              dob.value = d;
              error.value = null;
            },
          ),
          if (error.value != null)
            OnboardingNote(error.value!, error: true, raw: errorRaw.value),
          SizedBox(height: 22.ms),
          CButton(
            title: 'actions.continue',
            showArrow: false,
            height: 54.ms,
            loading: busy.value,
            onPressed: submit,
          ),
          const OnboardingNote('auth:onboarding.age.once_hint'),
        ],
        if (status == AgeGateStatus.ok) ...[
          CButton(
            title: 'actions.continue',
            showArrow: false,
            height: 54.ms,
            loading: busy.value,
            onPressed: proceed,
          ),
          if (error.value != null)
            OnboardingNote(error.value!, error: true, raw: errorRaw.value),
        ],
        SizedBox(height: 18.ms),
        SignOutLink(enabled: !busy.value, screen: 'age_gate'),
      ],
    );
  }
}

/// Tap → native date wheel (nothing is typed).
class _DateField extends StatelessWidget {
  const _DateField({
    required this.date,
    required this.hasError,
    required this.enabled,
    required this.onPicked,
  });

  final DateTime? date;
  final bool hasError;
  final bool enabled;
  final ValueChanged<DateTime> onPicked;

  Future<void> _open(BuildContext context) async {
    var value = date ?? DateTime(2000);
    final now = DateTime.now();
    final confirmed = await showCupertinoModalPopup<bool>(
      context: context,
      routeSettings: ScreenTracker.sheet('age_date_picker_sheet'),
      builder: (sheet) {
        final c = sheet.colors;
        return Container(
          // The wheel keeps its height above the home indicator.
          height: 300.ms + MediaQuery.viewPaddingOf(sheet).bottom,
          color: c.modalCard,
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    CupertinoButton(
                      onPressed: () => Navigator.pop(sheet, false),
                      child: CText(
                        'actions.cancel',
                        size: 14,
                        color: c.textMuted,
                      ),
                    ),
                    Flexible(
                      child: CText(
                        'auth:onboarding.age.picker_title',
                        size: 14,
                        weight: FontWeight.w800,
                        color: c.text,
                        maxLines: 1,
                      ),
                    ),
                    CupertinoButton(
                      onPressed: () => Navigator.pop(sheet, true),
                      child: CText(
                        'actions.confirm',
                        size: 14,
                        weight: FontWeight.w800,
                        color: c.accent,
                      ),
                    ),
                  ],
                ),
                Expanded(
                  child: CupertinoTheme(
                    data: CupertinoThemeData(
                      brightness: c.isDark ? Brightness.dark : Brightness.light,
                    ),
                    child: CupertinoDatePicker(
                      mode: CupertinoDatePickerMode.date,
                      initialDateTime: value,
                      minimumDate: DateTime(1900),
                      maximumDate: now,
                      onDateTimeChanged: (d) => value = d,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    AuthEvents.ageDatePicked(confirmed: confirmed == true);
    if (confirmed == true) onPicked(value);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final muted = c.isDark ? AppColors.whiteA(0.6) : AppColors.blackA(0.58);
    final placeholder = c.isDark
        ? AppColors.whiteA(0.4)
        : AppColors.blackA(0.38);
    final picked = date;
    // RN: "17 November 2003".
    final label = picked == null
        ? null
        : DateFormat(
            'd MMMM y',
            Localizations.localeOf(context).toLanguageTag(),
          ).format(picked);
    return Pressable(
      activeOpacity: 0.8,
      onPressed: enabled ? () => _open(context) : null,
      child: Container(
        height: 56.ms,
        padding: EdgeInsets.symmetric(horizontal: 16.ms),
        decoration: BoxDecoration(
          color: c.isDark ? AppColors.whiteA(0.04) : AppColors.blackA(0.025),
          borderRadius: BorderRadius.circular(16.ms),
          border: Border.all(
            width: 1.5,
            color: hasError
                ? StatusColors.dangerRed
                : picked != null
                ? c.accent
                : (c.isDark ? AppColors.whiteA(0.12) : AppColors.blackA(0.1)),
          ),
        ),
        child: Row(
          children: [
            Icon(
              LucideIcons.calendarDays,
              size: 18.ms,
              color: picked != null ? c.accent : muted,
            ),
            SizedBox(width: 10.ms),
            Expanded(
              child: label == null
                  ? CText(
                      'auth:onboarding.age.select',
                      size: 16,
                      weight: FontWeight.w600,
                      color: placeholder,
                      maxLines: 1,
                    )
                  : CText.raw(
                      label,
                      size: 16,
                      weight: FontWeight.w800,
                      color: c.text,
                      maxLines: 1,
                    ),
            ),
            Icon(LucideIcons.chevronDown, size: 18.ms, color: muted),
          ],
        ),
      ),
    );
  }
}
