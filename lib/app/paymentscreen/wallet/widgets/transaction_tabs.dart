import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/scale.dart';
import '../../../api/paymentscreen/wallet_models.dart';
import '../../../component/c_text.dart';
import '../../../component/pressable.dart';
import '../helper/wallet_palette.dart';

/// ALL · CASH · EARNINGS chips (RN `TABS`).
class TransactionTabs extends StatelessWidget {
  const TransactionTabs({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  final ValueListenable<TransactionFilter> selected;
  final ValueChanged<TransactionFilter> onSelect;

  @override
  Widget build(BuildContext context) {
    final p = WalletPalette.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(16.ms, 8.ms, 16.ms, 12.ms),
      child: ValueListenableBuilder<TransactionFilter>(
        valueListenable: selected,
        // One row: ALL · CASH · EARNINGS share the width equally.
        builder: (_, active, _) => Row(
          children: [
            for (final tab in TransactionFilter.values) ...[
              if (tab != TransactionFilter.values.first) SizedBox(width: 8.ms),
              Expanded(
                child: Pressable(
                  onPressed: () => onSelect(tab),
                  child: Container(
                    height: 34.ms,
                    padding: EdgeInsets.symmetric(horizontal: 8.ms),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: tab == active ? p.accent : p.soft,
                      borderRadius: BorderRadius.circular(12.ms),
                      border: Border.all(
                        color: tab == active
                            ? AppColors.transparent
                            : p.cardBorder,
                      ),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Opacity(
                        opacity: tab == active ? 1 : 0.8,
                        child: CText(
                          'payment:wallet.tabs.${tab.name}',
                          size: 10,
                          weight: FontWeight.w900,
                          letterSpacing: 1.8,
                          // RN: white on the active chip in both themes.
                          color: tab == active || p.dark
                              ? AppColors.white
                              : p.text,
                          maxLines: 1,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
