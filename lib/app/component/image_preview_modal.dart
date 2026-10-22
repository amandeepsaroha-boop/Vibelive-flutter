import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/scale.dart';
import 'c_image.dart';
import 'c_text.dart';
import 'pressable.dart';

/// RN `ImagePreviewModal`: big photo card with name, handle and actions
/// (favorite, share, copy link, QR). Drag down to close.
///
/// Share / copy / QR run *after* the modal has closed (RN fix: presenting a
/// sheet on top of a closing modal froze iOS).
abstract final class ImagePreviewModal {
  static Future<void> show(
    BuildContext context, {
    required String? imageUrl,
    required String title,
    String handle = '',
    bool isFavorite = false,

    /// The real favourite state (RN `isFavorite` prop): the heart follows
    /// it, so a failed toggle reverts. Without it the heart flips locally.
    ValueListenable<bool>? favorite,
    VoidCallback? onToggleFavorite,
    VoidCallback? onShare,
    VoidCallback? onCopyLink,
    VoidCallback? onShowQR,
  }) async {
    VoidCallback? pending;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'preview',
      barrierColor: AppColors.blackA(0.6),
      transitionDuration: const Duration(milliseconds: 200),
      transitionBuilder: (_, anim, _, child) =>
          FadeTransition(opacity: anim, child: child),
      pageBuilder: (ctx, _, _) => _PreviewCard(
        imageUrl: imageUrl,
        title: title,
        handle: handle,
        isFavorite: isFavorite,
        favorite: favorite,
        onToggleFavorite: onToggleFavorite,
        onAfterClose: (action) {
          pending = action;
          Navigator.of(ctx).pop();
        },
        onShare: onShare,
        onCopyLink: onCopyLink,
        onShowQR: onShowQR,
      ),
    );
    final action = pending;
    if (action != null) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      action();
    }
  }
}

class _PreviewCard extends StatefulWidget {
  const _PreviewCard({
    required this.imageUrl,
    required this.title,
    required this.handle,
    required this.isFavorite,
    required this.favorite,
    required this.onToggleFavorite,
    required this.onAfterClose,
    required this.onShare,
    required this.onCopyLink,
    required this.onShowQR,
  });

  final String? imageUrl;
  final String title;
  final String handle;
  final bool isFavorite;
  final ValueListenable<bool>? favorite;
  final VoidCallback? onToggleFavorite;
  final void Function(VoidCallback? action) onAfterClose;
  final VoidCallback? onShare;
  final VoidCallback? onCopyLink;
  final VoidCallback? onShowQR;

  @override
  State<_PreviewCard> createState() => _PreviewCardState();
}

class _PreviewCardState extends State<_PreviewCard> {
  /// Drag offset: only the transform listens, the card isn't rebuilt.
  final _dragY = ValueNotifier<double>(0);
  late final _localFavorite = ValueNotifier(widget.isFavorite);

  ValueListenable<bool> get _favorite => widget.favorite ?? _localFavorite;

  void _toggleFavorite() {
    if (widget.favorite == null) {
      _localFavorite.value = !_localFavorite.value;
    }
    widget.onToggleFavorite!();
  }

  @override
  void dispose() {
    _dragY.dispose();
    _localFavorite.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final handle = widget.handle.isEmpty
        ? ''
        : (widget.handle.startsWith('@') ? widget.handle : '@${widget.handle}');

    Widget action(
      IconData icon,
      String label,
      VoidCallback onTap, {
      Color color = AppColors.slate500,
      double size = 22,
    }) => Pressable(
      onPressed: onTap,
      semanticLabel: context.t(label),
      child: Container(
        width: 50.ms,
        height: 50.ms,
        decoration: const BoxDecoration(
          color: AppColors.slate50,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: size.ms, color: color),
      ),
    );

    return SafeArea(
      child: Center(
        child: GestureDetector(
          onVerticalDragUpdate: (d) =>
              _dragY.value = (_dragY.value + d.delta.dy).clamp(0, 600),
          onVerticalDragEnd: (_) {
            if (_dragY.value > 150) {
              widget.onAfterClose(null);
            } else {
              _dragY.value = 0;
            }
          },
          child: ValueListenableBuilder<double>(
            valueListenable: _dragY,
            builder: (_, dy, card) => AnimatedContainer(
              duration: Duration(milliseconds: dy == 0 ? 220 : 0),
              curve: Curves.easeOut,
              transform: Matrix4.translationValues(0, dy, 0),
              width: Scale.screenWidth * 0.94,
              child: card,
            ),
            // Dragging moves the cached card: the photo, shadow and clip
            // aren't repainted on every pointer move.
            child: RepaintBoundary(
              child: Material(
                color: AppColors.white,
                elevation: 25,
                borderRadius: BorderRadius.circular(32.ms),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 460.vs,
                      width: double.infinity,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (widget.imageUrl?.isNotEmpty ?? false)
                            CImage(
                              url: widget.imageUrl,
                              width: Scale.screenWidth * 0.94,
                            )
                          else
                            Container(
                              color: BrandColors.tealDark,
                              alignment: Alignment.center,
                              child: CText.raw(
                                widget.title.isEmpty
                                    ? 'E'
                                    : widget.title[0].toUpperCase(),
                                size: 120,
                                weight: FontWeight.w900,
                                color: AppColors.whiteA(0.9),
                              ),
                            ),
                          Positioned(
                            top: 20.ms,
                            right: 20.ms,
                            child: Pressable(
                              onPressed: () => widget.onAfterClose(null),
                              semanticLabel: context.t('actions.close'),
                              hitPadding: const EdgeInsets.all(15),
                              child: Container(
                                width: 34.ms,
                                height: 34.ms,
                                decoration: BoxDecoration(
                                  color: AppColors.blackA(0.3),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  LucideIcons.x,
                                  size: 18.ms,
                                  color: AppColors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(20.ms, 18.ms, 20.ms, 16.ms),
                      child: Column(
                        children: [
                          CText.raw(
                            widget.title,
                            size: 20,
                            weight: FontWeight.w700,
                            color: AppColors.slate900,
                            maxLines: 1,
                          ),
                          if (handle.isNotEmpty)
                            Padding(
                              padding: EdgeInsets.only(top: 2.ms),
                              child: CText.raw(
                                handle,
                                size: 14,
                                color: AppColors.slate500,
                                maxLines: 1,
                              ),
                            ),
                          Container(
                            width: Scale.screenWidth * 0.94 * 0.25,
                            height: 1,
                            margin: EdgeInsets.symmetric(vertical: 10.ms),
                            color: AppColors.slate100,
                          ),
                          Wrap(
                            spacing: 24.sw,
                            children: [
                              if (widget.onToggleFavorite != null)
                                ValueListenableBuilder<bool>(
                                  valueListenable: _favorite,
                                  builder: (_, on, _) => action(
                                    on ? Icons.favorite : LucideIcons.heart,
                                    'image_preview.favorite',
                                    _toggleFavorite,
                                    color: on
                                        ? const Color(0xFFFF5D7D)
                                        : AppColors.slate500,
                                  ),
                                ),
                              if (widget.onShare != null)
                                action(
                                  LucideIcons.send,
                                  'image_preview.share',
                                  () => widget.onAfterClose(widget.onShare),
                                ),
                              if (widget.onCopyLink != null)
                                action(
                                  LucideIcons.link,
                                  'image_preview.copy_link',
                                  () => widget.onAfterClose(widget.onCopyLink),
                                  size: 24,
                                ),
                              if (widget.onShowQR != null)
                                action(
                                  LucideIcons.scanQrCode,
                                  'image_preview.qr',
                                  () => widget.onAfterClose(widget.onShowQR),
                                  size: 20,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
