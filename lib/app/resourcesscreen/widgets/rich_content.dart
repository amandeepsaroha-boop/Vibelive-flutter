import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../helper/content_blocks.dart';
import '../helper/resource_links.dart';
import '../helper/resource_palette.dart';

/// Draws a CMS page's [ContentBlock]s (RN `renderBlocks` / `RenderHTML`
/// tag styles). Links open through [ResourceLinks].
class RichContent extends StatefulWidget {
  const RichContent({super.key, required this.blocks});
  final List<ContentBlock> blocks;

  @override
  State<RichContent> createState() => _RichContentState();
}

class _RichContentState extends State<RichContent> {
  final _recognizers = <TapGestureRecognizer>[];

  static const _headingSizes = [26.0, 22.0, 18.0, 16.0, 14.0, 12.0];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    // Rebuilt spans get fresh recognizers; drop the previous ones.
    _disposeRecognizers();
    final p = ResourcePalette.of(context);
    final blocks = widget.blocks;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < blocks.length; i++)
          _block(
            blocks[i],
            p,
            endsList: i == blocks.length - 1 || blocks[i + 1] is! ListItemBlock,
          ),
      ],
    );
  }

  Widget _block(ContentBlock b, ResourcePalette p, {required bool endsList}) {
    switch (b) {
      case HeadingBlock(:final level):
        final size = _headingSizes[level - 1];
        return Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 8),
          child: Semantics(
            header: true,
            child: _text(
              b,
              p,
              TextStyle(
                fontSize: size,
                fontWeight: FontWeight.w900,
                color: p.text,
                height: 1.25,
              ),
            ),
          ),
        );
      case ParagraphBlock():
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _text(b, p, _body(p, 21)),
        );
      case ListItemBlock(:final marker, :final depth):
        return Padding(
          padding: EdgeInsets.only(
            left: 6 + depth * 18.0,
            bottom: endsList ? 10 : 6,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 24,
                child: Text(
                  marker,
                  style: TextStyle(
                    fontSize: 14,
                    height: 20 / 14,
                    fontWeight: FontWeight.w700,
                    color: p.muted,
                  ),
                ),
              ),
              Expanded(child: _text(b, p, _body(p, 20))),
            ],
          ),
        );
    }
  }

  static TextStyle _body(ResourcePalette p, double lineHeight) => TextStyle(
    fontSize: 14,
    height: lineHeight / 14,
    color: p.text,
    fontWeight: FontWeight.w400,
  );

  Widget _text(ContentBlock b, ResourcePalette p, TextStyle base) => Text.rich(
    TextSpan(style: base, children: [for (final run in b.runs) _span(run, p)]),
  );

  InlineSpan _span(InlineRun run, ResourcePalette p) {
    final decorations = [
      if (run.underline || run.href != null) TextDecoration.underline,
      if (run.strike) TextDecoration.lineThrough,
    ];
    TapGestureRecognizer? recognizer;
    final href = run.href;
    if (href != null && href.isNotEmpty) {
      recognizer = TapGestureRecognizer()
        ..onTap = () => ResourceLinks.open(href);
      _recognizers.add(recognizer);
    }
    return TextSpan(
      text: run.text,
      recognizer: recognizer,
      style: TextStyle(
        fontWeight: run.bold ? FontWeight.w700 : null,
        fontStyle: run.italic ? FontStyle.italic : null,
        decoration: decorations.isEmpty
            ? null
            : TextDecoration.combine(decorations),
        decorationColor: href != null ? ResourcePalette.link : null,
        color: href != null ? ResourcePalette.link : null,
        fontFamily: run.code
            ? (defaultTargetPlatform == TargetPlatform.iOS
                  ? 'Menlo'
                  : 'monospace')
            : null,
        backgroundColor: run.code ? p.soft : null,
      ),
    );
  }
}
