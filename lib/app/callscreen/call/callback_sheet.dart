import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/vibe_colors.dart';
import '../../../core/utils/scale.dart';
import '../../api/listingflow/listing_api.dart';
import '../../component/c_alert.dart';
import '../../component/c_image.dart';
import '../../component/c_text.dart';
import '../../component/pressable.dart';
import '../../listingflow/profile/host_profile_sheet.dart';
import '../helper/call_actions.dart';
import '../helper/call_alerts.dart';
import '../helper/call_controller.dart';
import 'call_avatar.dart';
import 'helper/call_format.dart';
import 'helper/callback_data.dart';

/// RN `CallbackModal` ("Expert Callback"): the host who nudged, then Voice /
/// Video call-back buttons with their per-minute rates. The whole layer
/// (backdrop included) slides up, as RN `animationType="slide"`. Solid card
/// (decision 3; RN's 4 % white was see-through). [data] may change while it
/// is open (a newer nudge).
Future<void> showCallbackSheet(
  BuildContext context,
  ValueListenable<CallbackData> data,
) => showGeneralDialog<void>(
  context: context,
  useRootNavigator: true,
  barrierDismissible: false,
  barrierColor: AppColors.transparent,
  transitionDuration: const Duration(milliseconds: 300),
  transitionBuilder: (_, anim, _, page) => SlideTransition(
    position: anim.drive(
      Tween(
        begin: const Offset(0, 1),
        end: Offset.zero,
      ).chain(CurveTween(curve: Curves.easeOut)),
    ),
    child: page,
  ),
  pageBuilder: (_, _, _) => _CallbackPage(data: data),
);

/// Profile opens this long after the sheet went (RN iOS: modals can't stack).
const _profileDelay = Duration(milliseconds: 350);

void _close(BuildContext context) {
  final route = ModalRoute.of(context);
  if (route == null || !route.isActive) return;
  route.isCurrent
      ? Navigator.of(context).pop()
      : Navigator.of(context).removeRoute(route);
}

class _CallbackPage extends StatelessWidget {
  const _CallbackPage({required this.data});
  final ValueListenable<CallbackData> data;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(
        child: GestureDetector(
          onTap: () => _close(context),
          child: ColoredBox(color: AppColors.blackA(0.55)),
        ),
      ),
      Align(
        alignment: Alignment.bottomCenter,
        child: ValueListenableBuilder<CallbackData>(
          valueListenable: data,
          builder: (_, d, _) => _CallbackSheet(data: d),
        ),
      ),
    ],
  );
}

class _CallbackSheet extends HookWidget {
  const _CallbackSheet({required this.data});
  final CallbackData data;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dark = c.isDark;
    final text = dark ? AppColors.white : LightColors.text;
    final subtle = dark ? AppColors.whiteA(0.5) : AppColors.blackA(0.5);
    final cardBg = dark ? AppColors.whiteA(0.05) : AppColors.blackA(0.03);
    final cardBorder = dark ? AppColors.whiteA(0.08) : AppColors.blackA(0.08);
    final initiating = useState(false);

    Future<void> call({required bool video}) async {
      if (initiating.value) return;
      final target = data.targetFor(video: video);
      if (target == null) {
        // RN "Unable to start call / Missing caller or expert details."
        await CAlert.show(
          context: context,
          title: CallFlowKeys.unableTitle,
          message: CallFlowKeys.missingExpert,
          variant: CAlertVariant.error,
        );
        return;
      }
      initiating.value = true;
      // The root context outlives this sheet (the call screen replaces the
      // page under it).
      final root = rootNavigatorKey.currentContext ?? context;
      await CallActions.placeCallTo(root, target: target, video: video);
      if (!context.mounted) return;
      initiating.value = false;
      if (CallController.instance.isOnCall) _close(context);
    }

    Future<void> openProfile() async {
      _close(context);
      try {
        final host = await ListingApi.findCallbackHost(
          expertDocumentId: data.expertDocId,
          userId: data.expertId,
        );
        if (host.userDocumentId == null &&
            host.documentId == null &&
            host.receiverId == null) {
          return;
        }
        await Future<void>.delayed(_profileDelay);
        final root = rootNavigatorKey.currentContext;
        if (root != null && root.mounted) await showHostProfile(root, host);
      } catch (_) {
        // RN only logged a failed lookup.
      }
    }

    return Material(
      type: MaterialType.transparency,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(20.ms, 12.ms, 20.ms, 34.ms),
        decoration: BoxDecoration(
          color: c.modalCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28.ms)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40.ms,
              height: 5.ms,
              margin: EdgeInsets.only(bottom: 14.ms),
              decoration: BoxDecoration(
                color: dark ? AppColors.whiteA(0.18) : AppColors.blackA(0.15),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            _Header(text: text, subtle: subtle, cardBg: cardBg),
            Pressable(
              onPressed: openProfile,
              activeOpacity: 0.8,
              child: Container(
                margin: EdgeInsets.only(bottom: 16.ms),
                padding: EdgeInsets.all(12.ms),
                decoration: BoxDecoration(
                  color: cardBg,
                  border: Border.all(color: cardBorder),
                  borderRadius: BorderRadius.circular(16.ms),
                ),
                child: _Expert(data: data, text: text, subtle: subtle),
              ),
            ),
            CText(
              'call:callback.prompt',
              color: subtle,
              size: 14,
              weight: FontWeight.w600,
              align: TextAlign.center,
            ),
            SizedBox(height: 14.ms),
            Opacity(
              opacity: initiating.value ? 0.6 : 1,
              child: Row(
                children: [
                  Expanded(
                    child: _CallButton(
                      color: CallColors.callbackVoice,
                      icon: LucideIcons.phone,
                      iconSize: 20.ms,
                      price: data.voicePrice,
                      onPressed: initiating.value
                          ? null
                          : () => call(video: false),
                    ),
                  ),
                  SizedBox(width: 10.ms),
                  Expanded(
                    child: _CallButton(
                      color: c.accent,
                      icon: LucideIcons.video,
                      iconSize: 22.ms,
                      price: data.videoPrice,
                      onPressed: initiating.value
                          ? null
                          : () => call(video: true),
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
}

class _Header extends StatelessWidget {
  const _Header({
    required this.text,
    required this.subtle,
    required this.cardBg,
  });

  final Color text;
  final Color subtle;
  final Color cardBg;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: 14.ms),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              CText(
                'call:callback.title',
                color: text,
                size: 20,
                weight: FontWeight.w900,
                maxLines: 1,
              ),
              const SizedBox(height: 2),
              CText(
                'call:callback.subtitle',
                color: context.colors.accent,
                size: 11,
                weight: FontWeight.w800,
                letterSpacing: 1,
                uppercase: true,
                maxLines: 1,
              ),
            ],
          ),
        ),
        Pressable(
          onPressed: () => _close(context),
          semanticLabel: context.t('actions.close'),
          child: Container(
            width: 34.ms,
            height: 34.ms,
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(14.ms),
            ),
            child: Icon(LucideIcons.x, size: 18.ms, color: subtle),
          ),
        ),
      ],
    ),
  );
}

class _Expert extends StatelessWidget {
  const _Expert({required this.data, required this.text, required this.subtle});

  final CallbackData data;
  final Color text;
  final Color subtle;

  @override
  Widget build(BuildContext context) {
    final d = 54.ms;
    final glyph = Center(
      child: Icon(LucideIcons.user, size: 28.ms, color: AppColors.white),
    );
    final category = nonEmpty(data.category);
    return Row(
      children: [
        Container(
          width: d,
          height: d,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: context.colors.accent,
            shape: BoxShape.circle,
          ),
          child: (data.avatarUrl ?? '').isEmpty
              ? glyph
              : CImage(
                  url: data.avatarUrl,
                  width: d,
                  height: d,
                  placeholder: glyph,
                  errorWidget: glyph,
                ),
        ),
        SizedBox(width: 12.ms),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: data.name == null
                        ? CText(
                            'call:callback.fallback_name',
                            color: text,
                            size: 17,
                            weight: FontWeight.w800,
                            maxLines: 1,
                          )
                        : CText.raw(
                            data.name!,
                            color: text,
                            size: 17,
                            weight: FontWeight.w800,
                            maxLines: 1,
                          ),
                  ),
                  Icon(LucideIcons.chevronRight, size: 20.ms, color: subtle),
                ],
              ),
              if (category != null) ...[
                const SizedBox(height: 2),
                CText.raw(
                  category,
                  color: subtle,
                  size: 12,
                  weight: FontWeight.w500,
                  maxLines: 1,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _CallButton extends StatelessWidget {
  const _CallButton({
    required this.color,
    required this.icon,
    required this.iconSize,
    required this.price,
    required this.onPressed,
  });

  final Color color;
  final IconData icon;
  final double iconSize;
  final num price;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Pressable(
    onPressed: onPressed,
    activeOpacity: 0.2,
    child: Container(
      height: 58.ms,
      padding: EdgeInsets.symmetric(horizontal: 8.ms),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(29.ms),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: iconSize, color: AppColors.white),
          SizedBox(width: 8.ms),
          Flexible(
            child: CText(
              'call:callback.price',
              variables: {'price': formatRate(price)},
              color: AppColors.white,
              size: 13,
              weight: FontWeight.w900,
              maxLines: 1,
            ),
          ),
        ],
      ),
    ),
  );
}
