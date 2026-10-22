import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/scale.dart';
import '../../../component/c_image.dart';
import '../../../component/c_text.dart';
import '../../../component/pressable.dart';
import '../helper/personal_info_controller.dart';
import '../helper/personal_info_palette.dart';
import '../helper/personal_info_validation.dart';

/// Avatar band at the top: tap the photo to change it (RN avatar +
/// "Use this page…" hint). Rebuilds on upload state and, without a photo,
/// on the name (its letter).
class PhotoHeader extends StatelessWidget {
  const PhotoHeader({
    super.key,
    required this.form,
    required this.photoUrl,
    required this.onChangePhoto,
  });

  final PersonalInfoController form;
  final String? photoUrl;
  final VoidCallback onChangePhoto;

  static double get avatarSize => 124.ms;

  @override
  Widget build(BuildContext context) {
    final p = PersonalInfoPalette.of(context);
    final size = avatarSize;
    final hasPhoto = photoUrl != null && photoUrl!.isNotEmpty;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(20.ms, 24.ms, 20.ms, 20.ms),
      decoration: BoxDecoration(
        color: p.card,
        border: Border.symmetric(horizontal: BorderSide(color: p.border)),
      ),
      child: Column(
        children: [
          ValueListenableBuilder<bool>(
            valueListenable: form.uploading,
            builder: (_, uploading, _) => Pressable(
              key: const ValueKey('personal_info.photo'),
              activeOpacity: 0.8,
              semanticLabel: context.t('client:personal_info.change_photo'),
              onPressed: uploading ? null : onChangePhoto,
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: p.soft,
                  border: Border.all(color: p.accent, width: 3),
                ),
                child: ClipOval(
                  child: uploading
                      ? Center(
                          child: SizedBox.square(
                            dimension: 32.ms,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              color: p.accent,
                            ),
                          ),
                        )
                      : Stack(
                          fit: StackFit.expand,
                          children: [
                            if (hasPhoto)
                              CImage(
                                url: photoUrl,
                                width: size,
                                height: size,
                                placeholder: ColoredBox(color: p.soft),
                              )
                            else
                              Center(
                                child: ValueListenableBuilder<TextEditingValue>(
                                  valueListenable: form.name,
                                  builder: (_, name, _) => CText.raw(
                                    PersonalInfoValidation.initialOf(name.text),
                                    size: 32,
                                    weight: FontWeight.w900,
                                    color: p.text,
                                  ),
                                ),
                              ),
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              height: 30.ms,
                              child: ColoredBox(
                                color: AppColors.blackA(0.5),
                                child: Icon(
                                  LucideIcons.camera,
                                  size: 14.ms,
                                  color: AppColors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
          SizedBox(height: 10.ms),
          CText(
            'client:personal_info.photo_hint',
            size: 11,
            weight: FontWeight.w700,
            color: p.muted,
            align: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
