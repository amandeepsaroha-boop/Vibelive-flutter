import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../query/query_client.dart';
import '../utils/log.dart';

/// Online/offline flag for UI (offline banner) plus TanStack-style
/// "refetch on reconnect": when the connection comes back, every query is
/// marked stale and mounted ones refetch.
class NetworkStatus extends ValueNotifier<bool> {
  NetworkStatus._() : super(true);
  static final NetworkStatus instance = NetworkStatus._();

  StreamSubscription<List<ConnectivityResult>>? _sub;

  Future<void> init() async {
    if (_sub != null) return;
    try {
      final connectivity = Connectivity();
      _apply(await connectivity.checkConnectivity(), initial: true);
      _sub = connectivity.onConnectivityChanged.listen(_apply);
    } catch (e, st) {
      Log.e('NetworkStatus', e, st);
    }
  }

  void _apply(List<ConnectivityResult> results, {bool initial = false}) {
    final online = results.any((r) => r != ConnectivityResult.none);
    final wasOffline = !value;
    value = online;
    if (!initial && online && wasOffline) {
      Log.d('NetworkStatus', 'back online → refetching');
      queryCache.invalidateQueries(const []);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
