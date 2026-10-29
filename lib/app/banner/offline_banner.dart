import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/analytics/events/discover_events.dart';
import '../../core/network/network_status.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/scale.dart';
import '../component/c_text.dart';

/// Slim "No internet" strip; collapses to nothing when online.
class OfflineBanner extends StatefulWidget {
  const OfflineBanner({super.key});

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

/// Logs the strip appearing / going (with how long it was offline).
class _OfflineBannerState extends State<OfflineBanner> {
  DateTime? _offlineSince;

  void _onNetwork() {
    final online = NetworkStatus.instance.value;
    if (!online && _offlineSince == null) {
      _offlineSince = DateTime.now();
      DiscoverEvents.offlineBanner(shown: true);
    } else if (online && _offlineSince != null) {
      final seconds = DateTime.now().difference(_offlineSince!).inSeconds;
      _offlineSince = null;
      DiscoverEvents.offlineBanner(shown: false, seconds: seconds);
    }
  }

  @override
  void initState() {
    super.initState();
    NetworkStatus.instance.addListener(_onNetwork);
    _onNetwork();
  }

  @override
  void dispose() {
    NetworkStatus.instance.removeListener(_onNetwork);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: NetworkStatus.instance,
      builder: (context, online, _) => AnimatedSize(
        duration: const Duration(milliseconds: 200),
        child: online
            ? const SizedBox(width: double.infinity)
            : Container(
                width: double.infinity,
                color: StatusColors.dangerRed,
                padding: EdgeInsets.symmetric(
                  vertical: 6.ms,
                  horizontal: 12.ms,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      LucideIcons.wifiOff,
                      size: 14.ms,
                      color: AppColors.white,
                    ),
                    SizedBox(width: 6.ms),
                    const CText(
                      'banner:offline',
                      size: 12,
                      weight: FontWeight.w800,
                      color: AppColors.white,
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
