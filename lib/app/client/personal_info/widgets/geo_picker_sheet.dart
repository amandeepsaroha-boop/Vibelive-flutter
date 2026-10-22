import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/scale.dart';
import '../../../api/client/client_models.dart';
import '../../../api/client/client_queries.dart';
import '../../../component/c_button.dart';
import '../../../component/c_text.dart';
import '../../../component/keyboard_inset.dart';
import '../../../component/pressable.dart';
import '../helper/personal_info_palette.dart';

enum GeoPickerKind { state, district }

/// Opens the searchable State / District sheet (RN `PickerSheet`); resolves
/// to the picked row, or null when closed.
Future<GeoOption?> showGeoPicker(
  BuildContext context, {
  required GeoPickerKind kind,
  GeoOption? state,
}) => showModalBottomSheet<GeoOption>(
  context: context,
  useRootNavigator: true,
  useSafeArea: true,
  isScrollControlled: true,
  backgroundColor: AppColors.transparent,
  barrierColor: AppColors.blackA(0.65),
  builder: (_) => KeyboardInset(
    child: GeoPickerSheet(kind: kind, state: state),
  ),
);

class GeoPickerSheet extends HookWidget {
  const GeoPickerSheet({super.key, required this.kind, this.state});

  final GeoPickerKind kind;

  /// Parent of the districts (district picker only).
  final GeoOption? state;

  static const _debounce = Duration(milliseconds: 300);

  @override
  Widget build(BuildContext context) {
    final p = PersonalInfoPalette.of(context);
    final search = useTextEditingController();
    final term = useState('');

    // RN: search 300 ms after the last keystroke.
    useEffect(() {
      Timer? timer;
      void onChange() {
        final next = search.text.trim();
        timer?.cancel();
        if (next == term.value) return;
        timer = Timer(_debounce, () => term.value = next);
      }

      search.addListener(onChange);
      return () {
        timer?.cancel();
        search.removeListener(onChange);
      };
    }, [search]);

    final isState = kind == GeoPickerKind.state;
    final states = useStates(context, search: term.value, enabled: isState);
    final districts = useDistricts(
      context,
      state: state,
      search: term.value,
      enabled: !isState,
    );
    final query = isState ? states : districts;
    final title = context.t(
      isState
          ? 'client:personal_info.fields.state'
          : 'client:personal_info.fields.district',
    );
    final rows = query.data;

    final Widget body;
    if (rows == null && query.isError) {
      body = _Message(
        text: query.error!.localizedMessage(context),
        onRetry: query.refetch,
      );
    } else if (rows == null) {
      body = Padding(
        padding: EdgeInsets.symmetric(vertical: 48.ms),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 20.ms,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: p.accent,
              ),
            ),
            SizedBox(height: 12.ms),
            CText(
              'client:personal_info.picker.loading',
              variables: {'title': title},
              size: 12,
              weight: FontWeight.w700,
              color: p.muted,
            ),
          ],
        ),
      );
    } else if (rows.isEmpty) {
      body = _Message(
        text: context.t(
          isState
              ? 'client:personal_info.picker.no_states'
              : (state == null
                    ? 'client:personal_info.picker.select_state_first'
                    : 'client:personal_info.picker.no_districts'),
        ),
      );
    } else {
      body = ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.35,
        ),
        child: ListView.builder(
          shrinkWrap: true,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.only(top: 16.ms, bottom: 8.ms),
          itemExtent: 66.ms,
          itemCount: rows.length,
          itemBuilder: (context, i) => _OptionRow(option: rows[i]),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.sheet,
        borderRadius: BorderRadius.vertical(top: Radius.circular(40.ms)),
        border: Border.all(color: p.border),
      ),
      child: SafeArea(
        top: false,
        minimum: EdgeInsets.only(bottom: 20.ms),
        child: Padding(
          padding: EdgeInsets.fromLTRB(24.ms, 12.ms, 24.ms, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40.ms,
                  height: 4.ms,
                  margin: EdgeInsets.only(bottom: 16.ms),
                  decoration: BoxDecoration(
                    color: p.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: CText.raw(
                      title.toUpperCase(),
                      size: 20,
                      weight: FontWeight.w900,
                      letterSpacing: 0.5,
                      color: p.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Pressable(
                    semanticLabel: context.t('actions.close'),
                    onPressed: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 36.ms,
                      height: 36.ms,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: p.soft,
                        borderRadius: BorderRadius.circular(12.ms),
                        border: Border.all(color: p.border),
                      ),
                      child: Icon(LucideIcons.x, size: 18.ms, color: p.text),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16.ms),
              _SearchBar(controller: search, title: title),
              Flexible(child: body),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.controller, required this.title});

  final TextEditingController controller;
  final String title;

  @override
  Widget build(BuildContext context) {
    final p = PersonalInfoPalette.of(context);
    return MediaQuery.withNoTextScaling(
      child: Container(
        height: 50.ms,
        padding: EdgeInsets.symmetric(horizontal: 14.ms),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(18.ms),
          border: Border.all(color: p.border, width: 1.5),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.search, size: 18.ms, color: p.muted),
            SizedBox(width: 10.ms),
            Expanded(
              child: TextField(
                key: const ValueKey('personal_info.picker.search'),
                controller: controller,
                autocorrect: false,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.search,
                cursorColor: p.accent,
                style: TextStyle(
                  color: p.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 15.ms,
                ),
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: context.t(
                    'client:personal_info.picker.search',
                    variables: {'title': title},
                  ),
                  hintStyle: TextStyle(color: p.muted),
                ),
              ),
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (_, value, _) => value.text.isEmpty
                  ? const SizedBox.shrink()
                  : Pressable(
                      semanticLabel: context.t('actions.close'),
                      onPressed: controller.clear,
                      hitPadding: const EdgeInsets.all(4),
                      child: Icon(LucideIcons.x, size: 16.ms, color: p.muted),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({required this.option});

  final GeoOption option;

  @override
  Widget build(BuildContext context) {
    final p = PersonalInfoPalette.of(context);
    final name = option.name;
    return Padding(
      padding: EdgeInsets.only(bottom: 10.ms),
      child: Pressable(
        onPressed: () => Navigator.of(context).pop(option),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 18.ms),
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(16.ms),
            border: Border.all(color: p.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: name.isEmpty
                    ? CText(
                        'client:personal_info.picker.unnamed',
                        size: 15,
                        weight: FontWeight.w800,
                        color: p.text,
                      )
                    : CText.raw(
                        name,
                        size: 15,
                        weight: FontWeight.w800,
                        color: p.text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
              ),
              Container(
                width: 8.ms,
                height: 8.ms,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: p.muted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Empty / error line in the list area (error with Retry).
class _Message extends StatelessWidget {
  const _Message({required this.text, this.onRetry});

  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final p = PersonalInfoPalette.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 36.ms),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CText.raw(
            text,
            size: 14,
            weight: FontWeight.w700,
            color: p.muted,
            align: TextAlign.center,
          ),
          if (onRetry != null) ...[
            SizedBox(height: 8.ms),
            CButton(
              title: 'actions.retry',
              variant: CButtonVariant.ghost,
              showArrow: false,
              onPressed: onRetry,
            ),
          ],
        ],
      ),
    );
  }
}
