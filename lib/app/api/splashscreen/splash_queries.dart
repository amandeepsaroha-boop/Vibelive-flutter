import 'package:flutter/widgets.dart';

import '../../../core/query/query_hooks.dart';
import 'splash_api.dart';
import 'splash_keys.dart';
import 'splash_models.dart';

/// App config, kept on disk so it is there instantly on the next launch.
QueryResult<AppConfig, ApiException> useAppConfig(BuildContext context) =>
    usePersistedQuery<AppConfig>(
      SplashKeys.appConfig,
      SplashApi.fetchAppConfig,
      context: context,
      staleDuration: StaleTime.long,
      toJson: (c) => c.toJson(),
      fromJson: AppConfig.fromJson,
    );

QueryResult<List<String>, ApiException> useHostTopics(BuildContext context) =>
    useApiQuery<List<String>>(
      SplashKeys.hostTopics,
      SplashApi.fetchHostTopics,
      context: context,
      staleDuration: StaleTime.long,
    );

/// Outside widgets (call setup needs the Agora app id, startup prefetch…).
Future<AppConfig> ensureAppConfig() => queryCache.fetchQuery<AppConfig>(
  SplashKeys.appConfig,
  SplashApi.fetchAppConfig,
  staleDuration: StaleTime.long,
);
