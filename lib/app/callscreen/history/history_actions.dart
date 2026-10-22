import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../core/network/api_exception.dart';
import '../../api/listingflow/listing_models.dart';
import '../../api/listingflow/listing_queries.dart';
import '../../component/c_alert.dart';
import '../../listingflow/profile/host_profile_sheet.dart';
import 'helper/history_entry.dart';
import 'helper/history_errors.dart';
import 'history_menu.dart';
import 'report_sheet.dart';
import 'review_sheet.dart';

/// What a call-log row does: open the other person's host profile, and the
/// ⋮ menu with its review / report sheets.
class HistoryActions {
  /// One profile lookup at a time (RN `openingProfileId`).
  bool _opening = false;

  /// Any host (approved or pending; the viewer's own through the owner
  /// lookup) opens; a client row is inert (an expert viewer's client rows
  /// aren't tappable). A host that can't be found says
  /// "Unable to open profile". Calling happens only from the profile (its
  /// checks, then `CallActions.placeCall`).
  Future<void> openProfile(BuildContext context, HistoryEntry entry) async {
    final party = entry.item.counterpart;
    if (!entry.isExpert || party == null || _opening) return;
    if (party.documentId == null && party.id == null) return;
    _opening = true;
    final HostCard host;
    try {
      host = await ensureProfile(
        userDocumentId: party.documentId,
        userId: party.id?.toString(),
      );
    } on ApiException catch (e) {
      // A row whose other person is a client (a client viewer's rows all
      // try: a pending host's role may still say Client) stays inert.
      final client = (party.role ?? '').toLowerCase() == 'client';
      final missing =
          e.type == ApiErrorType.rejected || e.type == ApiErrorType.notFound;
      if (e.type != ApiErrorType.loggingOut && !(client && missing)) {
        unawaited(
          CAlert.error(
            HistoryErrors.relabel(e, 'call:history.profile_failed'),
            title: HistoryErrors.profileTitle,
          ),
        );
      }
      return;
    } finally {
      _opening = false;
    }
    if (context.mounted) await showHostProfile(context, host);
  }

  Future<void> openMenu(BuildContext context, HistoryEntry entry) async {
    final choice = await showHistoryMenu(context, entry);
    if (choice == null || !context.mounted) return;
    switch (choice) {
      case HistoryMenuChoice.rate:
        if (await showReviewSheet(context, entry)) {
          unawaited(
            CAlert.show(
              title: 'call:history.review.thanks_title',
              message: 'call:history.review.thanks',
              variant: CAlertVariant.success,
            ),
          );
        }
      case HistoryMenuChoice.profile:
        await openProfile(context, entry);
      case HistoryMenuChoice.report:
        if (await showReportSheet(context, entry)) {
          unawaited(
            CAlert.show(
              title: 'call:history.report.success_title',
              message: 'call:history.report.success',
              variant: CAlertVariant.success,
            ),
          );
        }
    }
  }
}
