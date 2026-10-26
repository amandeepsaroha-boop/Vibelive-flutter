import '../../../core/network/strapi.dart';
import 'profile_models.dart';

enum ApprovalStatus { pending, approved, rejected }

/// An `/expert-profile-approvals` row (the host's request to go live).
class ApprovalRecord {
  const ApprovalRecord(this.raw);

  final JsonMap raw;

  static ApprovalRecord? from(dynamic row) {
    final m = Strapi.map(row);
    return m == null ? null : ApprovalRecord(m);
  }

  /// RN `deriveApprovalStatus`: explicit approval or rejection, anything else
  /// is still pending.
  ApprovalStatus get status {
    final s = (J.str(raw['status']) ?? '').toLowerCase();
    if (raw['is_approved'] == true || raw['approved'] == true) {
      return ApprovalStatus.approved;
    }
    if (s == 'approved') return ApprovalStatus.approved;
    if (raw['rejected'] == true || s == 'rejected') {
      return ApprovalStatus.rejected;
    }
    return ApprovalStatus.pending;
  }

  /// Last change (`updatedAt`, else `createdAt`) in ms; 0 when unknown.
  int get changedAt =>
      DateTime.tryParse(
        J.str(raw['updatedAt']) ?? J.str(raw['createdAt']) ?? '',
      )?.millisecondsSinceEpoch ??
      0;

  /// ApprovalScreen rule: an approved profile wins over the latest request;
  /// null means no request yet.
  static ApprovalStatus? effective(
    HostProfile? expert,
    ApprovalRecord? latest,
  ) => (expert?.isApproved ?? false)
      ? ApprovalStatus.approved
      : (latest ?? embedded(expert))?.status;

  /// Newest request populated on the profile (`expert_profile_approvals`):
  /// the server's approval list can come back empty for the owner, while the
  /// profile read (ME / Host Hub) carries them.
  static ApprovalRecord? embedded(HostProfile? expert) {
    final rows = Strapi.list(expert?.raw['expert_profile_approvals']);
    ApprovalRecord? newest;
    for (final row in rows) {
      final r = ApprovalRecord.from(row);
      if (r != null && (newest == null || r.changedAt >= newest.changedAt)) {
        newest = r;
      }
    }
    return newest;
  }
}
