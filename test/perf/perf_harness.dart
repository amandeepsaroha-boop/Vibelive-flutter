import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Counts rebuilds per widget type while [body] runs.
Future<Map<String, int>> countRebuilds(Future<void> Function() body) async {
  final counts = <String, int>{};
  debugOnRebuildDirtyWidget = (e, _) {
    final n = e.widget.runtimeType.toString();
    counts[n] = (counts[n] ?? 0) + 1;
  };
  try {
    await body();
  } finally {
    debugOnRebuildDirtyWidget = null;
  }
  return counts;
}

/// Counts how often each text in [texts] is painted (re-recorded) while
/// [body] runs. A repaint boundary that is reused doesn't paint its
/// children again, so a cached layer counts 0.
Future<Map<String, int>> countTextPaints(
  Iterable<String> texts,
  Future<void> Function() body,
) async {
  final wanted = texts.toSet();
  final counts = {for (final t in wanted) t: 0};
  debugOnProfilePaint = (o) {
    if (o is! RenderParagraph) return;
    final text = o.text.toPlainText(includeSemanticsLabels: false);
    if (wanted.contains(text)) counts[text] = counts[text]! + 1;
  };
  try {
    await body();
  } finally {
    debugOnProfilePaint = null;
  }
  return counts;
}

/// [frames] frames of [ms] each.
Future<void> pumpFrames(WidgetTester tester, int frames, {int ms = 8}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(Duration(milliseconds: ms));
  }
}
