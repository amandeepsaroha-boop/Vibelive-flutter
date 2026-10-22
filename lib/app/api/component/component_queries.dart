import 'package:flutter/widgets.dart';

import '../../../core/network/strapi.dart';
import '../../../core/query/query_hooks.dart';
import 'component_keys.dart';
import 'report_api.dart';
import 'upload_api.dart';

/// Report categories rarely change: fetched once per session.
QueryResult<List<JsonMap>, ApiException> useReportCategories(
  BuildContext context, {
  bool enabled = true,
}) => useApiQuery<List<JsonMap>>(
  ComponentKeys.reportCategories,
  ReportApi.fetchCategories,
  context: context,
  enabled: enabled,
  staleDuration: StaleTime.long,
);

MutationResult<void, ApiException, ReportInput> useSubmitReport({
  void Function()? onSuccess,
  void Function(ApiException error)? onError,
}) => useApiMutation<void, ReportInput>(
  ReportApi.submit,
  onSuccess: (_, _) => onSuccess?.call(),
  onError: (e, _) => onError?.call(e),
);

/// Upload a local file; [invalidates] = the queries that show it.
MutationResult<JsonMap, ApiException, String> useUploadFile({
  List<RawQueryKey> invalidates = const [],
  void Function(JsonMap file)? onSuccess,
  void Function(ApiException error)? onError,
}) => useApiMutation<JsonMap, String>(
  UploadApi.uploadFile,
  invalidates: invalidates,
  onSuccess: (file, _) => onSuccess?.call(file),
  onError: (e, _) => onError?.call(e),
);
