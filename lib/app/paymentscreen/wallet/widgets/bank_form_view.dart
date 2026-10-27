import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/session/session_store.dart';
import '../../../../core/utils/scale.dart';
import '../../../api/paymentscreen/billing_models.dart';
import '../../../api/paymentscreen/payment_queries.dart';
import '../../../component/c_alert.dart';
import '../../../component/c_button.dart';
import '../../../component/c_input.dart';
import '../../../component/c_text.dart';
import '../helper/bank_form.dart';
import '../helper/wallet_palette.dart';

/// The payout-account form (RN WithdrawalModal, add state). Submitted once:
/// the saved account then shows as pending, and changes go through support.
class BankFormView extends HookWidget {
  const BankFormView({super.key});

  @override
  Widget build(BuildContext context) {
    final p = WalletPalette.of(context);
    final holder = useTextEditingController();
    final bank = useTextEditingController();
    final number = useTextEditingController();
    final confirm = useTextEditingController();
    final ifsc = useTextEditingController();
    final upi = useTextEditingController();
    final errors = useState<Map<BankField, String>>(const {});
    final save = useSaveBankDetail();
    // fquery's isPending lags a frame: a second tap must not resend. After a
    // success the sheet swaps to the account's status once the refetch lands;
    // until then the button stays busy.
    final busy = useState(false);

    void clear(BankField field) {
      if (!errors.value.containsKey(field)) return;
      errors.value = {...errors.value}..remove(field);
    }

    Future<void> submit() async {
      if (busy.value) return;
      FocusScope.of(context).unfocus();
      final next = BankForm.validate(
        holder: holder.text,
        bank: bank.text,
        number: number.text,
        confirm: confirm.text,
        ifsc: ifsc.text,
        upi: upi.text,
      );
      errors.value = next;
      if (next.isNotEmpty) return;
      busy.value = true;
      try {
        await save.mutateAsync(
          BankDetailInput(
            userDocumentId: SessionStore.instance.value.userDocumentId ?? '',
            accountName: holder.text,
            accountNumber: number.text,
            ifsc: ifsc.text,
            bankName: bank.text,
            upiAddress: upi.text,
          ),
        );
      } on ApiException catch (e) {
        busy.value = false;
        unawaited(CAlert.error(e, title: 'payment:bank.save_failed_title'));
        return;
      }
      unawaited(
        CAlert.show(
          title: 'payment:bank.saved_title',
          message: 'payment:bank.saved_message',
          variant: CAlertVariant.success,
        ),
      );
    }

    final digits = [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(18),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CText(
          'payment:bank.intro',
          size: 12,
          weight: FontWeight.w700,
          height: 18,
          color: p.muted,
        ),
        SizedBox(height: 8.ms),
        const CText(
          'payment:bank.lock_warning',
          size: 12,
          weight: FontWeight.w800,
          height: 18,
          color: WalletPalette.pending,
        ),
        SizedBox(height: 18.ms),
        const _Label('payment:bank.holder'),
        CInput(
          controller: holder,
          placeholder: 'payment:bank.holder_hint',
          errorText: errors.value[BankField.holder],
          onChanged: (_) => clear(BankField.holder),
          textInputAction: TextInputAction.next,
        ),
        const _Label('payment:bank.bank_name'),
        CInput(
          type: CInputType.text,
          icon: LucideIcons.building2,
          controller: bank,
          placeholder: 'payment:bank.bank_name_hint',
          errorText: errors.value[BankField.bank],
          onChanged: (_) => clear(BankField.bank),
          textInputAction: TextInputAction.next,
        ),
        const _Label('payment:bank.number'),
        CInput(
          type: CInputType.text,
          icon: LucideIcons.creditCard,
          keyboardType: TextInputType.number,
          controller: number,
          placeholder: 'payment:bank.number_hint',
          errorText: errors.value[BankField.number],
          onChanged: (_) => clear(BankField.number),
          inputFormatters: digits,
          textInputAction: TextInputAction.next,
        ),
        const _Label('payment:bank.confirm'),
        CInput(
          type: CInputType.text,
          icon: LucideIcons.creditCard,
          keyboardType: TextInputType.number,
          controller: confirm,
          placeholder: 'payment:bank.confirm_hint',
          errorText: errors.value[BankField.confirm],
          onChanged: (_) => clear(BankField.confirm),
          inputFormatters: digits,
          textInputAction: TextInputAction.next,
        ),
        const _Label('payment:bank.ifsc'),
        CInput(
          // `referral` capitalises as you type, which an IFSC needs.
          type: CInputType.referral,
          icon: LucideIcons.landmark,
          controller: ifsc,
          placeholder: 'payment:bank.ifsc_hint',
          errorText: errors.value[BankField.ifsc],
          onChanged: (_) => clear(BankField.ifsc),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9]')),
            LengthLimitingTextInputFormatter(11),
          ],
          textInputAction: TextInputAction.next,
        ),
        const _Label('payment:bank.upi'),
        CInput(
          type: CInputType.text,
          icon: LucideIcons.atSign,
          keyboardType: TextInputType.emailAddress,
          controller: upi,
          placeholder: 'payment:bank.upi_hint',
          errorText: errors.value[BankField.upi],
          onChanged: (_) => clear(BankField.upi),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => unawaited(submit()),
        ),
        SizedBox(height: 6.ms),
        CButton(
          title: 'payment:bank.submit',
          loading: busy.value || save.isPending,
          disabled: busy.value || save.isPending,
          onPressed: () => unawaited(submit()),
        ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(left: 4.ms, bottom: 6.ms),
    child: CText(
      text,
      size: 10,
      weight: FontWeight.w900,
      letterSpacing: 1,
      uppercase: true,
      color: WalletPalette.of(context).muted,
    ),
  );
}
