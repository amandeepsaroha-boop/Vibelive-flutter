import '../../../core/network/api_client.dart';
import '../../../core/network/strapi.dart';

/// Abuse reports, used from a profile, the call history and a live call.
abstract final class ReportApi {
  static Future<List<JsonMap>> fetchCategories() async =>
      Strapi.list(await ApiClient.get('/report-categories'));

  static Future<void> submit(ReportInput input) async {
    await ApiClient.post('/reports', data: {'data': input.toJson()});
  }
}

class ReportInput {
  const ReportInput({
    required this.reporterId,
    this.reportedUserId,
    this.categoryId,
    this.note = '',
  });

  /// documentId (or id) of the user reporting.
  final Object reporterId;

  /// documentId of the reported user. RN's call log posted the report even
  /// without one (the field is then left out).
  final Object? reportedUserId;
  final Object? categoryId;
  final String note;

  Map<String, dynamic> toJson() => {
    'reported_by_user': reporterId,
    'reported_to_user': ?reportedUserId,
    'report_category': ?categoryId,
    'note': note,
    'report_status': 'new',
  };
}
