import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../api/listingflow/filter_models.dart';
import '../../../api/listingflow/listing_models.dart';
import '../../../api/listingflow/listing_queries.dart';
import '../../../api/listingflow/search_models.dart';
import '../../../component/c_alert.dart';

/// Search screen state as small notifiers, so each part rebuilds alone: the
/// field owns [text]; the results listen to [query], [typing] and [filter];
/// each row listens to [opening].
class SearchScreenController {
  SearchScreenController({String initialQuery = ''})
    : text = TextEditingController(text: initialQuery),
      query = ValueNotifier(initialQuery.trim()),
      typing = ValueNotifier(initialQuery.trim().isNotEmpty);

  /// RN `SEARCH_DEBOUNCE_MS`.
  static const debounce = Duration(milliseconds: 350);

  final TextEditingController text;

  /// What is searched: the trimmed text after [debounce]. Clearing the
  /// field clears it at once.
  final ValueNotifier<String> query;

  /// The field has text (the results show a skeleton until [query] catches
  /// up on the first search).
  final ValueNotifier<bool> typing;

  /// Language / topic filter, applied client-side over the hits.
  final filter = ValueNotifier(HostFilter.none);

  /// [hitKey] of the hit whose full profile is loading.
  final opening = ValueNotifier<String?>(null);

  /// Latest unfiltered hits: the filter sheet offers their languages and
  /// topics (RN `availableLanguages` / `availableTopics`).
  List<SearchHost> hits = const [];

  Timer? _timer;
  bool _disposed = false;

  static String? hitKey(SearchHost hit) => hit.documentId ?? hit.userDocumentId;

  void onChanged(String value) {
    _timer?.cancel();
    final q = value.trim();
    typing.value = q.isNotEmpty;
    if (q.isEmpty) {
      query.value = '';
      return;
    }
    _timer = Timer(debounce, () {
      if (!_disposed) query.value = q;
    });
  }

  /// Keyboard "search": runs now instead of after the debounce.
  void submit() {
    if (_disposed) return;
    _timer?.cancel();
    final q = text.text.trim();
    typing.value = q.isNotEmpty;
    query.value = q;
  }

  /// A category row (no category screen exists) or a deep-link `q`: fill
  /// the field and search at once.
  void searchFor(String value) {
    if (_disposed) return;
    text.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    submit();
  }

  void clear() {
    text.clear();
    onChanged('');
  }

  /// A hit is a summary; the profile needs the full host (expert-profile
  /// documentId, then user documentId, then handler, as RN did). One at a
  /// time; the row spins until the host is resolved.
  Future<void> open(
    SearchHost hit,
    Future<void> Function(HostCard host) show,
  ) async {
    final key = hitKey(hit);
    if (key == null || opening.value != null) return;
    FocusManager.instance.primaryFocus?.unfocus();
    opening.value = key;
    final HostCard host;
    try {
      host = await ensureHostDetail(
        expertDocumentId: hit.documentId,
        userDocumentId: hit.userDocumentId,
        handler: hit.handler,
      );
    } catch (e) {
      if (_disposed) return;
      opening.value = null;
      await CAlert.error(e, title: 'search:results.profile_title');
      return;
    }
    if (_disposed) return;
    opening.value = null;
    await show(host);
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    text.dispose();
    query.dispose();
    typing.dispose();
    filter.dispose();
    opening.dispose();
  }
}
