import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/vibe_colors.dart';
import '../../core/utils/scale.dart';
import 'pressable.dart';

/// RN `InputBox` types.
enum CInputType { mobile, email, password, name, referral, text }

/// App text field (RN `InputBox`): a pill whose border turns the accent
/// color while focused and red on error. Mobile shows the country prefix
/// instead of an icon. [placeholder] and [errorText] are i18n keys. Not
/// scaled by the OS font-size setting.
class CInput extends StatefulWidget {
  const CInput({
    super.key,
    this.type = CInputType.name,
    this.placeholder,
    this.controller,
    this.initialValue,
    this.onChanged,
    this.onSubmitted,
    this.errorText,
    this.errorVariables,
    this.translateError = true,
    this.trailing,
    this.focusNode,
    this.onFocus,
    this.textInputAction,
    this.enabled = true,
    this.autofocus = false,
    this.autofocusDelay = Duration.zero,
    this.maxLength,
    this.inputFormatters,
    this.countryCode = '+91',
    this.countryFlag = '🇮🇳',
    this.bottomSpacing = 16,
  });

  final CInputType type;
  final String? placeholder;
  final TextEditingController? controller;
  final String? initialValue;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// i18n key, or literal text when [translateError] is false.
  final String? errorText;
  final Map<String, dynamic>? errorVariables;
  final bool translateError;

  /// Replaces the password eye (spinner, check mark…).
  final Widget? trailing;
  final FocusNode? focusNode;

  /// Each time the field gains focus.
  final VoidCallback? onFocus;
  final TextInputAction? textInputAction;
  final bool enabled;
  final bool autofocus;

  /// With [autofocus]: wait this long before taking focus (and raising the
  /// keyboard), e.g. until the sheet the field sits in has slid in. Bringing
  /// the keyboard up blocks the main thread, which also runs Dart frames,
  /// and its insets re-lay out the screen on every frame: neither should
  /// overlap an entrance animation. A tap still focuses at once.
  final Duration autofocusDelay;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;
  final String countryCode;
  final String countryFlag;

  /// Unscaled gap below the field (RN `marginBottom: 16`).
  final double bottomSpacing;

  @override
  State<CInput> createState() => _CInputState();

  /// Lays out the country prefix once, off any animation: the flag emoji
  /// makes the engine resolve the system emoji font, a fallback lookup that
  /// otherwise lands on the first frame of the first mobile field shown.
  static void warmUp({String flag = '🇮🇳'}) {
    TextPainter(
        text: TextSpan(
          text: flag,
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16.ms),
        ),
        textDirection: TextDirection.ltr,
      )
      ..layout()
      ..dispose();
  }
}

/// Theme colors of the field (RN `InputBox` `PALETTE`).
class _Palette {
  const _Palette({
    required this.icon,
    required this.text,
    required this.placeholder,
    required this.border,
    required this.bg,
    required this.chipBg,
    required this.divider,
  });

  final Color icon, text, placeholder, border, bg, chipBg, divider;

  static const dark = _Palette(
    icon: Color(0xFFA27BFF),
    text: AppColors.white,
    placeholder: Color(0x59FFFFFF), // white 35%
    border: Color(0x1FFFFFFF), // white 12%
    bg: Color(0x0DFFFFFF), // white 5%
    chipBg: Color(0x24A27BFF), // 14%
    divider: Color(0x24FFFFFF), // white 14%
  );

  static const light = _Palette(
    icon: BrandColors.purple,
    text: Color(0xFF110D2E),
    placeholder: Color(0x52110D2E), // 32%
    border: Color(0x1F110D2E), // 12%
    bg: AppColors.white,
    chipBg: Color(0x125E17EB), // 7%
    divider: Color(0x1F110D2E), // 12%
  );

  /// The focus border and caret are the icon color.
  Color get focus => icon;
}

class _CInputState extends State<CInput> {
  TextEditingController? _ownController;
  FocusNode? _ownFocus;
  Timer? _autofocusTimer;

  /// Decided once: a later [CInput.autofocusDelay] must not refocus.
  late final bool _delayedFocus =
      widget.autofocus && widget.autofocusDelay > Duration.zero;
  bool _obscured = true;

  TextEditingController get _controller =>
      widget.controller ??
      (_ownController ??= TextEditingController(text: widget.initialValue));

  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
    if (_delayedFocus) {
      _autofocusTimer = Timer(widget.autofocusDelay, () {
        // Same rule as `autofocus`: only when nothing else took focus.
        if (mounted) FocusScope.of(context).autofocus(_focus);
      });
    }
  }

  @override
  void didUpdateWidget(CInput old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      (old.focusNode ?? _ownFocus)?.removeListener(_onFocusChange);
      _focus.addListener(_onFocusChange);
    }
  }

  void _onFocusChange() {
    if (_focus.hasFocus) widget.onFocus?.call();
  }

  @override
  void dispose() {
    _autofocusTimer?.cancel();
    _focus.removeListener(_onFocusChange);
    _ownController?.dispose();
    _ownFocus?.dispose();
    super.dispose();
  }

  IconData get _icon => switch (widget.type) {
    CInputType.mobile => LucideIcons.phone,
    CInputType.email => LucideIcons.mail,
    CInputType.password => LucideIcons.lock,
    CInputType.referral => LucideIcons.ticket,
    CInputType.name || CInputType.text => LucideIcons.user,
  };

  @override
  Widget build(BuildContext context) {
    final p = context.colors.isDark ? _Palette.dark : _Palette.light;
    final type = widget.type;
    final isPassword = type == CInputType.password;
    final isMobile = type == CInputType.mobile;
    final isEmail = type == CInputType.email;
    final hasError = widget.errorText != null && widget.errorText!.isNotEmpty;

    final field = TextField(
      controller: _controller,
      focusNode: _focus,
      enabled: widget.enabled,
      autofocus: widget.autofocus && !_delayedFocus,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      textInputAction: widget.textInputAction,
      obscureText: isPassword && _obscured,
      autocorrect: false,
      enableSuggestions: !isPassword && !isEmail,
      keyboardType: switch (type) {
        CInputType.mobile => TextInputType.number,
        CInputType.email => TextInputType.emailAddress,
        CInputType.password => TextInputType.visiblePassword,
        CInputType.name => TextInputType.name,
        _ => TextInputType.text,
      },
      textCapitalization: switch (type) {
        CInputType.name => TextCapitalization.words,
        CInputType.referral => TextCapitalization.characters,
        _ => TextCapitalization.none,
      },
      autofillHints: switch (type) {
        CInputType.mobile => const [AutofillHints.telephoneNumber],
        CInputType.email => const [AutofillHints.email],
        CInputType.password => const [AutofillHints.password],
        CInputType.name => const [AutofillHints.name],
        _ => null,
      },
      maxLength: widget.maxLength,
      inputFormatters: [
        if (isMobile)
          widget.countryCode == '+91'
              ? const IndianMobileFormatter()
              : FilteringTextInputFormatter.digitsOnly,
        if (isEmail) _LowerCaseFormatter(),
        ...?widget.inputFormatters,
      ],
      cursorColor: p.focus,
      style: TextStyle(
        color: p.text,
        fontWeight: isMobile ? FontWeight.w700 : FontWeight.w600,
        fontSize: (isMobile ? 18.5 : 16.5).ms,
        letterSpacing: isMobile ? 1.5.ms : (isEmail ? 0.2.ms : 0),
      ),
      decoration: InputDecoration(
        // No label: never "float" one. Otherwise focusing (and typing the
        // first character) runs a 167 ms label animation that re-lays out
        // the field and the form around it on each of its frames.
        floatingLabelBehavior: FloatingLabelBehavior.never,
        isCollapsed: true,
        border: InputBorder.none,
        counterText: '',
        hintText: widget.placeholder == null
            ? null
            : context.t(widget.placeholder!),
        hintStyle: TextStyle(color: p.placeholder),
      ),
    );

    final errorStyle = TextStyle(
      color: AppColors.red,
      fontWeight: FontWeight.w600,
      fontSize: 13.ms,
    );

    return MediaQuery.withNoTextScaling(
      child: Padding(
        padding: EdgeInsets.only(bottom: moderateScale(widget.bottomSpacing)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Only the outline repaints on focus; the field is reused. The
            // pill is its own layer: focus, typing and the caret repaint it
            // alone, not the form around it.
            RepaintBoundary(
              child: ListenableBuilder(
                listenable: _focus,
                builder: (_, row) => Container(
                  height: 58.ms,
                  padding: EdgeInsets.only(left: 10.ms, right: 14.ms),
                  decoration: BoxDecoration(
                    color: p.bg,
                    borderRadius: BorderRadius.circular(29.ms),
                    border: Border.all(
                      width: 1.5,
                      color: hasError
                          ? AppColors.red
                          : (_focus.hasFocus ? p.focus : p.border),
                    ),
                  ),
                  child: row,
                ),
                child: Row(
                  children: [
                    if (isMobile)
                      _CountryPrefix(
                        flag: widget.countryFlag,
                        code: widget.countryCode,
                        palette: p,
                      )
                    else
                      Container(
                        width: 38.ms,
                        height: 38.ms,
                        margin: EdgeInsets.only(right: 10.ms),
                        decoration: BoxDecoration(
                          color: p.chipBg,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(_icon, size: 19.ms, color: p.icon),
                      ),
                    Expanded(child: field),
                    if (widget.trailing != null)
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8.ms),
                        child: widget.trailing,
                      )
                    else if (isPassword)
                      Pressable(
                        onPressed: () => setState(() => _obscured = !_obscured),
                        semanticLabel: context.t(
                          _obscured
                              ? 'input.show_password'
                              : 'input.hide_password',
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(8.ms),
                          child: Icon(
                            _obscured ? LucideIcons.eye : LucideIcons.eyeOff,
                            size: 20,
                            color: p.icon,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (hasError)
              Padding(
                padding: EdgeInsets.only(top: 10.ms),
                child: Text(
                  widget.translateError
                      ? context.t(
                          widget.errorText!,
                          variables: widget.errorVariables,
                        )
                      : widget.errorText!,
                  textAlign: TextAlign.center,
                  style: errorStyle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// "🇮🇳  +91" and a hairline, in place of the type icon: a phone icon AND
/// a "+91" chip side by side read as two extra buttons (RN).
class _CountryPrefix extends StatelessWidget {
  const _CountryPrefix({
    required this.flag,
    required this.code,
    required this.palette,
  });

  final String flag;
  final String code;
  final _Palette palette;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: palette.text,
      fontWeight: FontWeight.w700,
      fontSize: 16.ms,
    );
    return Padding(
      padding: EdgeInsets.only(left: 10.ms, right: 12.ms),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(child: Text(flag, style: style)),
          SizedBox(width: 8.ms),
          Text(code, style: style),
          Container(
            width: 1,
            height: 28.ms,
            margin: EdgeInsets.only(left: 12.ms),
            color: palette.divider,
          ),
        ],
      ),
    );
  }
}

class _LowerCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => newValue.copyWith(text: newValue.text.toLowerCase());
}

/// Digits only; a paste or autofill like "+91 98765 43210", "09876543210" or
/// "919876543210" becomes "9876543210" (RN `normalizeIndianMobile`). Typing
/// digit by digit is never rewritten.
class IndianMobileFormatter extends TextInputFormatter {
  const IndianMobileFormatter();

  static String normalize(String value) {
    var digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 10 && digits.startsWith('91')) {
      digits = digits.substring(2);
    }
    if (digits.length > 10 && digits.startsWith('0')) {
      digits = digits.replaceFirst(RegExp('^0+'), '');
    }
    return digits.length > 10 ? digits.substring(0, 10) : digits;
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.length - oldValue.text.length <= 1) {
      return FilteringTextInputFormatter.digitsOnly.formatEditUpdate(
        oldValue,
        newValue,
      );
    }
    final text = normalize(newValue.text);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
