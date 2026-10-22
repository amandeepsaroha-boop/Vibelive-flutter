import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/log.dart';
import '../../../../core/utils/scale.dart';
import '../../../component/app_share.dart';
import '../../../component/c_text.dart';
import '../../../component/c_toast.dart';
import '../../../component/pressable.dart';
import '../../onboarding/helper/host_palette.dart';
import '../../onboarding/widgets/step_body.dart';
import 'brand_icons.dart';

/// "Share your profile with friends and followers": the link with Copy,
/// then WhatsApp / Instagram / Facebook / the OS share sheet.
class HostShareProfileCard extends StatelessWidget {
  const HostShareProfileCard({super.key, required this.link});

  /// Full public link (`https://…/handle`).
  final String link;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: link));
    CToast.show('hostflow:approved.copied', variant: CToastVariant.success);
  }

  Future<bool> _launch(String url) async {
    try {
      return await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      Log.w('HostShare', 'launch failed: $e');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    final message = context.t(
      'hostflow:approved.share_message',
      variables: {'link': link},
    );
    final shown = link.replaceFirst(RegExp('^https?://'), '');

    Future<void> whatsApp() async {
      final text = Uri.encodeComponent(message);
      if (await _launch('whatsapp://send?text=$text')) return;
      if (await _launch('https://wa.me/?text=$text')) return;
      await AppShare.text(message);
    }

    // Instagram takes no shared text: copy the link, then open the app.
    Future<void> instagram() async {
      await Clipboard.setData(ClipboardData(text: link));
      CToast.show('hostflow:approved.instagram_hint');
      if (!await _launch('instagram://app')) {
        await _launch('https://www.instagram.com/');
      }
    }

    Future<void> facebook() async {
      final u = Uri.encodeComponent(link);
      if (!await _launch('https://www.facebook.com/sharer/sharer.php?u=$u')) {
        await AppShare.text(message);
      }
    }

    Widget social({
      required String label,
      required Widget icon,
      required VoidCallback onTap,
      Color? color,
      Gradient? gradient,
      bool outlined = false,
      bool caption = false,
    }) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Pressable(
          onPressed: onTap,
          semanticLabel: context.t(label),
          child: Container(
            width: 46.ms,
            height: 46.ms,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color,
              gradient: gradient,
              borderRadius: BorderRadius.circular(14.ms),
              border: outlined ? Border.all(color: p.cardBorder) : null,
            ),
            child: icon,
          ),
        ),
        if (caption) ...[
          SizedBox(height: 6.ms),
          CText(label, size: 12, weight: FontWeight.w500, color: p.muted),
        ],
      ],
    );

    return HostCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CText(
            'hostflow:approved.share_title',
            size: 16,
            height: 22,
            weight: FontWeight.w800,
            color: p.text,
          ),
          SizedBox(height: 6.ms),
          CText(
            'hostflow:approved.share_body',
            size: 13,
            height: 18,
            weight: FontWeight.w500,
            color: p.muted,
          ),
          SizedBox(height: 14.ms),
          Container(
            height: 44.ms,
            decoration: BoxDecoration(
              color: p.field,
              borderRadius: BorderRadius.circular(12.ms),
              border: Border.all(color: p.fieldBorder),
            ),
            child: Row(
              children: [
                SizedBox(width: 12.ms),
                Expanded(
                  child: CText.raw(
                    shown,
                    size: 13,
                    weight: FontWeight.w500,
                    color: p.text,
                    maxLines: 1,
                  ),
                ),
                Pressable(
                  onPressed: _copy,
                  child: Container(
                    height: 44.ms,
                    padding: EdgeInsets.symmetric(horizontal: 14.ms),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: p.buttonGradient,
                      borderRadius: BorderRadius.circular(12.ms),
                    ),
                    child: CText(
                      'hostflow:approved.copy',
                      size: 13,
                      weight: FontWeight.w700,
                      color: p.onAccent,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 16.ms),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              social(
                label: 'hostflow:approved.whatsapp',
                color: BrandTints.whatsapp,
                icon: WhatsAppGlyph(size: 24.ms),
                onTap: whatsApp,
              ),
              social(
                label: 'hostflow:approved.instagram',
                gradient: const LinearGradient(
                  colors: BrandTints.instagram,
                  begin: Alignment.bottomLeft,
                  end: Alignment.topRight,
                ),
                icon: InstagramGlyph(size: 22.ms),
                onTap: instagram,
              ),
              social(
                label: 'hostflow:approved.facebook',
                color: BrandTints.facebook,
                icon: Icon(Icons.facebook, size: 28.ms, color: AppColors.white),
                onTap: facebook,
              ),
              social(
                label: 'hostflow:approved.more',
                outlined: true,
                caption: true,
                icon: Icon(LucideIcons.ellipsis, size: 20.ms, color: p.text),
                onTap: () => AppShare.text(message),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
