import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/analytics/screen_tracker.dart';
import '../../../../core/i18n/i18n.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/scale.dart';
import '../../../component/c_text.dart';
import '../helper/wallet_palette.dart';
import 'wallet_header.dart';

/// Slide-up sheet shared by the balance gate, first-top-up and exit-intent
/// offers (RN AuthSheet pattern: grabber, close X, safe-area padding).
/// [name]: the analytics screen name of the sheet.
Future<T?> showOfferSheet<T>(
  BuildContext context,
  WidgetBuilder builder, {
  String? name,
}) => showModalBottomSheet<T>(
      context: context,
      routeSettings: name == null ? null : ScreenTracker.sheet(name),
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      backgroundColor: AppColors.transparent,
      barrierColor: AppColors.blackA(0.5),
      builder: builder,
    );

/// The sheet body: solid themed background, rounded top, no shadow.
class OfferSheetFrame extends StatelessWidget {
  const OfferSheetFrame({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = WalletPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        color: p.bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.ms)),
        border: Border(top: BorderSide(color: p.cardBorder)),
      ),
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          20.ms,
          0,
          20.ms,
          20.ms + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                SizedBox(width: 36.ms),
                Expanded(
                  child: Center(
                    child: Container(
                      width: 40.ms,
                      height: 4.ms,
                      decoration: BoxDecoration(
                        color: p.dark
                            ? AppColors.whiteA(0.12)
                            : AppColors.blackA(0.12),
                        borderRadius: BorderRadius.circular(2.ms),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.only(top: 12.ms),
                  child: WalletIconButton(
                    icon: LucideIcons.x,
                    size: 36,
                    radius: 12,
                    iconSize: 18,
                    semanticLabel: context.t('actions.close'),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ],
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// Round tinted badge with an icon, above an offer's title.
class OfferBadge extends StatelessWidget {
  const OfferBadge(this.icon, {super.key});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final p = WalletPalette.of(context);
    return Center(
      child: Container(
        width: 48.ms,
        height: 48.ms,
        margin: EdgeInsets.only(bottom: 12.ms),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: p.accent.withValues(alpha: 0.12),
        ),
        child: Icon(icon, size: 22.ms, color: p.accent),
      ),
    );
  }
}

/// Centred title and subtitle of an offer.
class OfferHeading extends StatelessWidget {
  const OfferHeading({
    super.key,
    required this.title,
    required this.subtitle,
    this.variables,
  });

  final String title;
  final String subtitle;
  final Map<String, dynamic>? variables;

  @override
  Widget build(BuildContext context) {
    final p = WalletPalette.of(context);
    return Column(
      children: [
        CText(
          title,
          variables: variables,
          size: 19,
          weight: FontWeight.w800,
          color: p.text,
          align: TextAlign.center,
        ),
        SizedBox(height: 6.ms),
        CText(
          subtitle,
          variables: variables,
          size: 13.5,
          height: 19,
          color: p.muted,
          align: TextAlign.center,
        ),
      ],
    );
  }
}
