import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../core/network/api_exception.dart';
import '../../api/listingflow/listing_models.dart';
import '../../api/callscreen/call_errors.dart';
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

  /// Approved hosts only. A client, or a host that isn't approved (or can't
  /// be found), opens nothing: the tap is a no-op like RN. Calling happens
  /// only from the profile (its checks, then `CallActions.placeCall`).
  Future<void> openProfile(BuildContext context, HistoryEntry entry) async {
    final id = entry.counterpartId;
    if (!entry.isExpert || id == null || _opening) return;
    _opening = true;
    final HostCard host;
    try {
      host = await ensureHostByLink(id);
    } on ApiException catch (e) {
      if (e.type != ApiErrorType.rejected && e.type != ApiErrorType.notFound) {
        unawaited(
          CAlert.error(
            e.withFallbackKey('call:history.profile_failed'),
            title: HistoryErrors.profileTitle,
          ),
        );
      }
      return;
    } finally {
      _opening = false;
    }
    // A link to the viewer's own profile skips the approval check; RN's log
    // never did (a self-call row with an unapproved profile opens nothing).
    if (!host.isApprovedHost) return;
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
