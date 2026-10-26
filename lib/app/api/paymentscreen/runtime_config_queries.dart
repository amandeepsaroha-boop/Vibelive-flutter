import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../../core/config/runtime_config.dart';
import '../../../core/query/query_hooks.dart';
import '../../../core/query/query_persist.dart';
import '../../../core/utils/log.dart';
import '../splashscreen/splash_api.dart';
import '../splashscreen/splash_keys.dart';
import '../splashscreen/splash_models.dart';
import '../splashscreen/splash_queries.dart';
import 'billing_models.dart';
import 'payment_keys.dart';
import 'payment_queries.dart';

/// Runtime pricing / bonus config, fed by `/app-config` (RN's source) and
/// `/pricing-config`. Every read resolves with the shipped fallbacks, so a
/// failed or offline fetch never surfaces 0 or NaN.
RuntimeConfig useRuntimeConfig(BuildContext context) {
  final app = useAppConfig(context);
  final pricing = usePricingConfig(context);
  return useMemoized(
    () => RuntimeConfig.resolve(app.data?.raw, pricing.data?.raw),
    [app.data, pricing.data],
  );
}

/// [useRuntimeConfig] outside widgets: what is cached now (memory, else
/// the disk copy of app-config), never a request.
RuntimeConfig currentRuntimeConfig() {
  final app =
      queryCache.entry<AppConfig>(SplashKeys.appConfig)?.data ??
      QueryPersist.read<AppConfig>(SplashKeys.appConfig, AppConfig.fromJson);
  final pricing = queryCache
      .entry<PricingConfig>(PaymentKeys.pricingConfig)
      ?.data;
  return RuntimeConfig.resolve(app?.raw, pricing?.raw);
}

/// Re-reads app-config once it is older than the server TTL, keeping the
/// disk copy current. RN degraded here on purpose: offline or a 401 keeps
/// serving the cached block, so this never throws.
Future<RuntimeConfig> ensureFreshRuntimeConfig() async {
  final ttl = currentRuntimeConfig().ttl;
  try {
    await Future.wait([
      queryCache.fetchQuery<AppConfig>(SplashKeys.appConfig, () async {
        final config = await SplashApi.fetchAppConfig();
        QueryPersist.write(SplashKeys.appConfig, config.toJson());
        return config;
      }, staleDuration: ttl),
      ensurePricingConfig(),
    ]);
  } on ApiException catch (e) {
    Log.w('RuntimeConfig', 'refresh failed, keeping cached config: $e');
  }
  return currentRuntimeConfig();
}

/// RN re-checks config on every foreground transition, so an admin change
/// reaches users who are already logged in. Started once at startup.
abstract final class RuntimeConfigRefresher {
  static AppLifecycleListener? _listener;

  static void start() {
    _listener ??= AppLifecycleListener(
      onResume: () => unawaited(ensureFreshRuntimeConfig()),
    );
  }
}
