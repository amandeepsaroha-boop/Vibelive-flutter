import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/network/network_status.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/scale.dart';
import '../component/c_text.dart';

/// Slim "No internet" strip; collapses to nothing when online.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

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
