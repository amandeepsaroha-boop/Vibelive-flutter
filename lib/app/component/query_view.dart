import 'package:flutter/widgets.dart';

import '../../core/query/query_hooks.dart';
import 'c_loader.dart';
import 'c_state_view.dart';

/// Renders a query's loading / error / empty / data states in one place,
/// so every screen handles failures the same way.
///
/// ```dart
/// final hosts = useHosts(context);
/// return QueryView(
///   query: hosts,
///   isEmpty: (list) => list.isEmpty,
///   builder: (context, list) => HostList(list),
/// );
/// ```
class QueryView<T> extends StatelessWidget {
  const QueryView({
    super.key,
    required this.query,
    required this.builder,
    this.isEmpty,
    this.loading,
    this.empty,
    this.error,
  });

  final QueryResult<T, ApiException> query;
  final Widget Function(BuildContext context, T data) builder;
  final bool Function(T data)? isEmpty;
  final Widget? loading;
  final Widget? empty;

  /// Custom error UI; defaults to [CStateView.error] with Retry.
  final Widget Function(BuildContext context, ApiException error)? error;

  @override
  Widget build(BuildContext context) {
    final data = query.data;
    if (data != null) {
      // A failed background refetch keeps showing the last good data.
      if (isEmpty?.call(data) ?? false) {
        return empty ?? const CStateView.empty();
      }
      return builder(context, data);
    }
    final err = query.error;
    if (query.isError && err != null) {
      return error?.call(context, err) ??
          CStateView.error(context, err, onRetry: () => query.refetch());
    }
    return loading ?? const CLoader();
  }
}
