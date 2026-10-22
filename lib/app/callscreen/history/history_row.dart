import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/vibe_colors.dart';
import '../../../core/utils/scale.dart';
import '../../api/callscreen/call_errors.dart';
import '../../api/callscreen/call_models.dart';
import '../../api/callscreen/call_queries.dart';
import '../../component/c_alert.dart';
import '../../component/c_image.dart';
import '../../component/c_text.dart';
import '../../component/pressable.dart';
import 'helper/history_avatars.dart';
import 'helper/history_entry.dart';
import 'helper/history_errors.dart';
import 'helper/history_layout.dart';

/// One call-log card (RN explore `renderItem`): avatar with a status badge,
/// name + call type + duration / MISSED / DECLINED, outcome + time, and the
/// NUDGE pill. Its height is [HistoryLayout.extent].
class HistoryRow extends StatelessWidget {
  const HistoryRow({
    super.key,
    required this.entry,
    required this.onOpen,
    required this.onMenu,
  });

  final HistoryEntry entry;
  final ValueChanged<HistoryEntry> onOpen;
  final ValueChanged<HistoryEntry> onMenu;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final e = entry;
    final meta = c.isDark ? AppColors.whiteA(0.56) : AppColors.blackA(0.56);
    final name = e.name ?? context.t('call:history.unknown');
    final typeColor = switch (e.tone) {
      HistoryTone.missed => StatusColors.dangerRed,
      HistoryTone.warning => StatusColors.warningOrange,
      HistoryTone.ok => meta,
    };

    final lines = <Widget>[
      SizedBox(
        height: HistoryLayout.nameLine.ms,
        child: Row(
          children: [
            Expanded(
              child: CText.raw(
                name,
                size: 15,
                weight: FontWeight.w900,
                height: HistoryLayout.nameLine,
                maxLines: 1,
                color: c.text,
              ),
            ),
            SizedBox(width: 5.ms),
            Icon(
              e.isVideo ? LucideIcons.video : LucideIcons.phone,
              size: 15.ms,
              color: typeColor,
            ),
            SizedBox(width: 5.ms),
            _Label(entry: e),
          ],
        ),
      ),
      SizedBox(height: 3.ms),
      // Outcome left, time right (RN space-between); both bounded so a long
      // date or label truncates instead of overflowing.
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            flex: 2,
            child: CText(
              _outcomeKey(e.outcome),
              size: 10,
              weight: FontWeight.w700,
              letterSpacing: 0.8,
              height: HistoryLayout.metaLine,
              uppercase: true,
              maxLines: 1,
              color: meta,
            ),
          ),
          SizedBox(width: 8.ms),
          Flexible(
            flex: 3,
            // RN without a date: "N/A • NO DATE".
            child: CText.raw(
              e.when ??
                  '${context.t('call:history.no_time')} • '
                      '${context.t('call:history.no_date').toUpperCase()}',
              size: 10,
              weight: FontWeight.w600,
              height: HistoryLayout.metaLine,
              maxLines: 1,
              color: meta,
            ),
          ),
        ],
      ),
      if (e.showPing) ...[SizedBox(height: 8.ms), _NudgePill(entry: e)],
    ];

    return Padding(
      padding: EdgeInsets.only(bottom: HistoryLayout.gap),
      child: Pressable(
        activeOpacity: 0.86,
        onPressed: e.isExpert ? () => onOpen(e) : null,
        child: Container(
          padding: EdgeInsets.fromLTRB(
            HistoryLayout.padH,
            HistoryLayout.padV,
            0,
            HistoryLayout.padV,
          ),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(HistoryLayout.radius),
            border: Border.all(
              color: c.isDark ? AppColors.whiteA(0.08) : AppColors.blackA(0.09),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: _StatusAvatar(entry: e, name: name),
              ),
              SizedBox(width: 10.ms),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: lines,
                ),
              ),
              _MenuStrip(
                ping: e.showPing,
                color: meta,
                onPressed: () => onMenu(e),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _outcomeKey(CallOutcome outcome) => switch (outcome) {
    CallOutcome.missed => 'call:history.outcome.missed',
    CallOutcome.declined => 'call:history.outcome.declined',
    CallOutcome.videoCall => 'call:history.outcome.video',
    CallOutcome.voiceCall => 'call:history.outcome.voice',
  };
}

/// MISSED / DECLINED, else the talk time.
class _Label extends StatelessWidget {
  const _Label({required this.entry});
  final HistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    const line = HistoryLayout.nameLine;
    Widget status(String key, Color color) => CText(
      key,
      size: 11,
      weight: FontWeight.w800,
      letterSpacing: 0.5,
      height: line,
      color: color,
    );
    return switch (e.direction) {
      CallDirection.missed => status(
        'call:history.missed',
        StatusColors.dangerRed,
      ),
      CallDirection.declined => status(
        'call:history.declined',
        StatusColors.warningOrange,
      ),
      _ when e.clock != null => CText.raw(
        e.clock!,
        size: 13,
        weight: FontWeight.w800,
        height: line,
        color: context.colors.text,
      ),
      _ when e.minutes != null => CText(
        'call:history.minutes',
        variables: {'minutes': e.minutes},
        size: 13,
        weight: FontWeight.w800,
        height: line,
        color: context.colors.text,
      ),
      _ => const SizedBox.shrink(),
    };
  }
}

/// 62 pt avatar (photo or letter) with the direction / outcome badge. A
/// row whose populated user carries no photo looks it up once (RN
/// `fetchAvatar`: `/public-users/:id?populate[profilePic]`).
class _StatusAvatar extends HookWidget {
  const _StatusAvatar({required this.entry, required this.name});
  final HistoryEntry entry;
  final String name;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final lookup = e.avatarUrl == null ? e.counterpartId : null;
    final found = useState<String?>(null);
    useEffect(() {
      if (lookup == null || HistoryAvatars.cached(lookup) != null) return null;
      var live = true;
      HistoryAvatars.lookup(lookup).then((url) {
        if (live && url != null) found.value = url;
      });
      return () => live = false;
    }, [lookup]);
    final url =
        e.avatarUrl ??
        (lookup == null ? null : HistoryAvatars.cached(lookup) ?? found.value);
    final (bg, fg) = switch (e.tone) {
      HistoryTone.missed => (StatusColors.dangerRed, AppColors.white),
      HistoryTone.warning => (StatusColors.warningOrange, AppColors.white),
      HistoryTone.ok => (BrandColors.lime, AppColors.black),
    };
    final icon = switch (e.direction) {
      CallDirection.missed => LucideIcons.phoneMissed,
      CallDirection.declined => LucideIcons.phoneOff,
      _ => e.isOutgoing ? LucideIcons.arrowUpRight : LucideIcons.arrowDownLeft,
    };
    final size = HistoryLayout.avatar;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        children: [
          CAvatar(url: url, name: name, size: size),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: HistoryLayout.badge,
              height: HistoryLayout.badge,
              decoration: BoxDecoration(
                color: bg,
                shape: BoxShape.circle,
                border: Border.all(color: context.colors.surface, width: 1.5),
              ),
              child: Icon(icon, size: 10.ms, color: fg),
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-height ⋮ target at the card's right edge; the icon sits on the
/// name line like RN's inline button.
class _MenuStrip extends StatelessWidget {
  const _MenuStrip({
    required this.ping,
    required this.color,
    required this.onPressed,
  });

  final bool ping;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final line = HistoryLayout.nameLine.ms;
    return Pressable(
      onPressed: onPressed,
      semanticLabel: context.t('call:history.options'),
      child: Padding(
        padding: EdgeInsets.only(left: 5.ms, right: HistoryLayout.padH),
        child: SizedBox(
          width: 24.ms,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                height: line,
                child: Icon(
                  LucideIcons.ellipsisVertical,
                  size: 18.ms,
                  color: color,
                ),
              ),
              SizedBox(height: HistoryLayout.content(ping: ping) - line),
            ],
          ),
        ),
      ),
    );
  }
}

/// RN NUDGE: asks a client who missed / declined the call to call back.
class _NudgePill extends HookWidget {
  const _NudgePill({required this.entry});
  final HistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final ping = usePingClient();
    final busy = ping.isPending;
    final name = entry.name ?? context.t('call:history.unknown');

    Future<void> send() async {
      final clientId = entry.counterpartId;
      if (clientId == null || busy) return;
      try {
        await ping.mutateAsync(clientId);
        unawaited(
          CAlert.show(
            title: 'call:history.ping_sent_title',
            message: 'call:history.ping_sent',
            variables: {'name': name},
            variant: CAlertVariant.success,
          ),
        );
      } on ApiException catch (e) {
        unawaited(
          CAlert.error(
            HistoryErrors.ping(e, CallErrorKeys.pingFailed),
            title: HistoryErrors.title,
          ),
        );
      }
    }

    return Pressable(
      onPressed: busy ? null : send,
      child: Container(
        height: HistoryLayout.pill,
        padding: EdgeInsets.symmetric(horizontal: 10.ms),
        decoration: BoxDecoration(
          color: AppColors.slate900,
          borderRadius: BorderRadius.circular(6.ms),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              SizedBox.square(
                dimension: 12.ms,
                child: const RepaintBoundary(
                  child: CircularProgressIndicator(
                    strokeWidth: 1.6,
                    color: AppColors.white,
                  ),
                ),
              )
            else
              Icon(LucideIcons.bellRing, size: 12.ms, color: AppColors.white),
            SizedBox(width: 4.ms),
            const CText(
              'call:history.nudge',
              size: 10,
              weight: FontWeight.w800,
              letterSpacing: 0.5,
              height: HistoryLayout.metaLine,
              color: AppColors.white,
            ),
          ],
        ),
      ),
    );
  }
}
