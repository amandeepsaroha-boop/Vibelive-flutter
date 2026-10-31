import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/analytics/screen_tracker.dart';
import '../../../../core/i18n/i18n.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/scale.dart';
import '../../../component/c_image.dart';
import '../../../component/c_text.dart';
import '../../../component/pressable.dart';
import '../helper/bank_doc.dart';
import '../helper/wallet_palette.dart';

/// "Choose from gallery / Take a photo" for a document; null when dismissed.
Future<BankDocOrigin?> showBankDocSourceSheet(BuildContext context) =>
    showModalBottomSheet<BankDocOrigin>(
      context: context,
      routeSettings: ScreenTracker.sheet('bank_doc_source_sheet'),
      useRootNavigator: true,
      useSafeArea: true,
      backgroundColor: AppColors.transparent,
      builder: (ctx) {
        final p = WalletPalette.of(ctx);
        Widget row(BankDocOrigin origin, IconData icon, String label) =>
            Pressable(
              onPressed: () => Navigator.of(ctx).pop(origin),
              child: Container(
                height: 56.ms,
                margin: EdgeInsets.only(bottom: 10.ms),
                padding: EdgeInsets.symmetric(horizontal: 16.ms),
                decoration: BoxDecoration(
                  color: p.cardBg,
                  borderRadius: BorderRadius.circular(14.ms),
                  border: Border.all(color: p.cardBorder),
                ),
                child: Row(
                  children: [
                    Icon(icon, size: 22.ms, color: p.accent),
                    SizedBox(width: 12.ms),
                    Expanded(
                      child: CText(
                        label,
                        size: 16,
                        weight: FontWeight.w700,
                        color: p.text,
                      ),
                    ),
                  ],
                ),
              ),
            );
        return Container(
          padding: EdgeInsets.fromLTRB(20.ms, 16.ms, 20.ms, 20.ms),
          decoration: BoxDecoration(
            color: p.bg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28.ms)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CText(
                'payment:bank.docs.source_title',
                size: 17,
                weight: FontWeight.w900,
                color: p.text,
              ),
              SizedBox(height: 14.ms),
              row(
                BankDocOrigin.gallery,
                LucideIcons.images,
                'payment:bank.docs.gallery',
              ),
              row(
                BankDocOrigin.camera,
                LucideIcons.camera,
                'payment:bank.docs.camera',
              ),
            ],
          ),
        );
      },
    );

/// One proof photo: tap to add, shows the picture once picked, a spinner
/// while it uploads, "tap to retry" when that failed, and the validation
/// error under it.
class BankDocTile extends StatelessWidget {
  const BankDocTile({
    super.key,
    required this.kind,
    required this.doc,
    required this.onTap,
    this.hint,
    this.error,
    this.height = 110,
  });

  final BankDocKind kind;
  final ValueListenable<BankDoc?> doc;
  final VoidCallback onTap;

  /// i18n key shown under the label when nothing is picked yet.
  final String? hint;

  /// i18n key of the validation error (red border and text).
  final String? error;

  /// Unscaled height of the picture area.
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = WalletPalette.of(context);
    return ValueListenableBuilder<BankDoc?>(
      valueListenable: doc,
      builder: (_, d, _) {
        final failed = d?.failed == true;
        final border = error != null || failed
            ? WalletPalette.error
            : d?.uploaded == true
            ? WalletPalette.success.withValues(alpha: 0.6)
            : p.cardBorder;
        final String? status = failed
            ? 'payment:bank.docs.retry'
            : d?.uploading == true
            ? 'payment:bank.docs.uploading'
            : d?.uploaded == true
            ? 'payment:bank.docs.change'
            : null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              button: true,
              label: context.t(kind.labelKey),
              child: Pressable(
                onPressed: onTap,
                child: Container(
                  height: height.ms,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: p.inputBg,
                    borderRadius: BorderRadius.circular(16.ms),
                    border: Border.all(color: border, width: 1.2),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (d?.localPath != null)
                        Image.file(
                          File(d!.localPath!),
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const SizedBox.shrink(),
                        )
                      else if (d?.url != null)
                        CImage(url: d!.url, fit: BoxFit.cover)
                      else
                        _Empty(kind: kind, hint: hint),
                      if (d?.uploaded == true && !failed)
                        Positioned(
                          top: 8.ms,
                          right: 8.ms,
                          child: Container(
                            padding: EdgeInsets.all(4.ms),
                            decoration: const BoxDecoration(
                              color: WalletPalette.success,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              LucideIcons.check,
                              size: 12.ms,
                              color: AppColors.white,
                            ),
                          ),
                        ),
                      if (d?.uploading == true || failed)
                        Container(
                          color: AppColors.blackA(0.45),
                          alignment: Alignment.center,
                          child: failed
                              ? Icon(
                                  LucideIcons.refreshCw,
                                  size: 26.ms,
                                  color: AppColors.white,
                                )
                              : SizedBox.square(
                                  dimension: 24.ms,
                                  child: const CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    color: AppColors.white,
                                  ),
                                ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (d != null) ...[
              SizedBox(height: 6.ms),
              CText(
                kind.labelKey,
                size: 11,
                weight: FontWeight.w800,
                color: p.text,
                maxLines: 1,
              ),
            ],
            if (status != null)
              CText(
                status,
                size: 10,
                weight: FontWeight.w700,
                color: failed ? WalletPalette.error : p.muted,
                maxLines: 1,
              ),
            if (error != null) ...[
              SizedBox(height: 4.ms),
              CText(
                error!,
                size: 11,
                weight: FontWeight.w700,
                height: 15,
                color: WalletPalette.error,
              ),
            ],
          ],
        );
      },
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.kind, this.hint});

  final BankDocKind kind;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final p = WalletPalette.of(context);
    // Scales down rather than overflow on a narrow phone or in Hindi.
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 10.ms, vertical: 8.ms),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36.ms,
              height: 36.ms,
              decoration: BoxDecoration(
                color: p.soft,
                borderRadius: BorderRadius.circular(12.ms),
              ),
              child: Icon(
                kind == BankDocKind.bankProof
                    ? LucideIcons.bookOpen
                    : LucideIcons.idCard,
                size: 18.ms,
                color: p.accent,
              ),
            ),
            SizedBox(height: 6.ms),
            SizedBox(
              width: 150.ms,
              child: CText(
                kind.labelKey,
                size: 11.5,
                weight: FontWeight.w800,
                color: p.text,
                align: TextAlign.center,
                maxLines: 2,
              ),
            ),
            if (hint != null) ...[
              SizedBox(height: 2.ms),
              SizedBox(
                width: 200.ms,
                child: CText(
                  hint!,
                  size: 9.5,
                  weight: FontWeight.w600,
                  color: p.muted,
                  align: TextAlign.center,
                  maxLines: 2,
                ),
              ),
            ],
            SizedBox(height: 4.ms),
            CText(
              'payment:bank.docs.add',
              size: 10,
              weight: FontWeight.w900,
              letterSpacing: 0.5,
              uppercase: true,
              color: p.accent,
            ),
          ],
        ),
      ),
    );
  }
}
