import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/analytics/events/payment_events.dart';
import '../../../../core/i18n/i18n.dart';
import '../../../../core/utils/scale.dart';
import '../../../api/paymentscreen/billing_models.dart';
import '../../../api/resourcesscreen/resources_models.dart';
import '../../../api/splashscreen/splash_queries.dart';
import '../../../component/c_alert.dart';
import '../../../component/c_text.dart';
import '../../../component/pressable.dart';
import '../helper/bank_form.dart';
import '../helper/wallet_palette.dart';

/// A saved payout account: its review state, the account (masked), and the
/// way to change it — which is support, never an in-app edit.
class BankStatusView extends HookWidget {
  const BankStatusView({super.key, required this.detail});

  final BankDetail detail;

  @override
  Widget build(BuildContext context) {
    final p = WalletPalette.of(context);
    final config = useAppConfig(context).data;
    final email = config == null
        ? SupportContact.defaultEmail
        : SupportContact.fromAppConfig(config).emailOrDefault;
    final verified = detail.isVerified;
    final tone = verified ? WalletPalette.success : WalletPalette.pending;
    useEffect(() {
      PaymentEvents.bankStatusViewed(
        status: verified ? 'verified' : 'pending',
        hasUpi: (detail.upiAddress ?? '').isNotEmpty,
      );
      return null;
    }, const []);

    Future<void> contactSupport() async {
      final subject = Uri.encodeComponent(
        context.t('payment:bank.mail_subject'),
      );
      var opened = false;
      try {
        opened = await launchUrl(
          Uri(scheme: 'mailto', path: email, query: 'subject=$subject'),
        );
      } catch (_) {
        // No mail app: say where to write instead.
      }
      PaymentEvents.bankSupportTapped(mailOpened: opened);
      if (!opened) {
        unawaited(
          CAlert.show(
            title: 'payment:bank.contact_title',
            message: 'payment:bank.contact_email',
            variables: {'email': email},
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Panel(
          color: tone.withValues(alpha: 0.12),
          border: tone.withValues(alpha: 0.35),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                verified ? LucideIcons.circleCheck : LucideIcons.clock,
                size: 20.ms,
                color: tone,
              ),
              SizedBox(width: 10.ms),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CText(
                      verified
                          ? 'payment:bank.verified_title'
                          : 'payment:bank.pending_title',
                      size: 13,
                      weight: FontWeight.w900,
                      letterSpacing: 0.5,
                      color: tone,
                    ),
                    SizedBox(height: 3.ms),
                    CText(
                      verified
                          ? 'payment:bank.verified_hint'
                          : 'payment:bank.pending_hint',
                      size: 11,
                      weight: FontWeight.w700,
                      height: 16,
                      color: p.text,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 12.ms),
        _Panel(
          color: p.cardBg,
          border: p.cardBorder,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 44.ms,
                    height: 44.ms,
                    decoration: BoxDecoration(
                      color: tone.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12.ms),
                    ),
                    child: Icon(LucideIcons.landmark, size: 22.ms, color: tone),
                  ),
                  SizedBox(width: 12.ms),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CText.raw(
                          detail.bankName ?? '',
                          size: 15,
                          weight: FontWeight.w900,
                          color: p.text,
                          maxLines: 1,
                        ),
                        SizedBox(height: 2.ms),
                        CText.raw(
                          BankForm.masked(detail.accountNumber),
                          size: 12,
                          weight: FontWeight.w800,
                          color: p.muted,
                          maxLines: 1,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Padding(
                padding: EdgeInsets.symmetric(vertical: 12.ms),
                child: Divider(height: 1, color: p.cardBorder),
              ),
              _DetailRow(
                label: 'payment:bank.holder_label',
                value: detail.accountName,
              ),
              _DetailRow(label: 'payment:bank.ifsc_label', value: detail.ifsc),
              if ((detail.upiAddress ?? '').isNotEmpty)
                _DetailRow(
                  label: 'payment:bank.upi_label',
                  value: detail.upiAddress,
                ),
            ],
          ),
        ),
        SizedBox(height: 12.ms),
        Pressable(
          onPressed: () => unawaited(contactSupport()),
          semanticLabel: context.t('payment:bank.change_title'),
          child: _Panel(
            color: p.cardBg,
            border: p.cardBorder,
            child: Row(
              children: [
                Icon(LucideIcons.mail, size: 18.ms, color: p.accent),
                SizedBox(width: 10.ms),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CText(
                        'payment:bank.change_title',
                        size: 13,
                        weight: FontWeight.w900,
                        color: p.text,
                      ),
                      SizedBox(height: 2.ms),
                      CText(
                        'payment:bank.change_hint',
                        variables: {'email': email},
                        size: 11,
                        weight: FontWeight.w700,
                        height: 16,
                        color: p.muted,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.color,
    required this.border,
    required this.child,
  });

  final Color color;
  final Color border;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.all(16.ms),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(18.ms),
      border: Border.all(color: border),
    ),
    child: child,
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final p = WalletPalette.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.ms),
      child: Row(
        children: [
          CText(label, size: 12, weight: FontWeight.w800, color: p.muted),
          SizedBox(width: 12.ms),
          Expanded(
            child: CText.raw(
              value == null || value!.isEmpty ? '—' : value!,
              size: 13,
              weight: FontWeight.w900,
              color: p.text,
              align: TextAlign.end,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}
