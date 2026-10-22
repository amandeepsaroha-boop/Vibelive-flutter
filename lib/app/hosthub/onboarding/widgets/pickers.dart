import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../../api/client/client_models.dart';
import '../../../api/client/client_queries.dart';
import '../../../api/hosthub/catalog_models.dart';
import '../../../api/hosthub/hosthub_queries.dart';
import 'option_list.dart';
import 'sheet_frame.dart';

/// State picker, or the districts of [state]. Resolves to the chosen row.
Future<GeoOption?> showGeoPicker(
  BuildContext context, {
  GeoOption? state,
  GeoOption? selected,
}) => showHostSheet<GeoOption>(
  context,
  title: state == null ? 'hostflow:basic.state' : 'hostflow:basic.district',
  child: _GeoList(state: state, selected: selected),
);

class _GeoList extends HookWidget {
  const _GeoList({this.state, this.selected});
  final GeoOption? state;
  final GeoOption? selected;

  @override
  Widget build(BuildContext context) {
    final search = useTextEditingController();
    final term = _useDebounced(search);
    final states = useStates(
      context,
      search: term,
      pageSize: 100,
      enabled: state == null,
    );
    final districts = useDistricts(
      context,
      state: state,
      search: term,
      pageSize: 100,
      enabled: state != null,
    );
    final q = state == null ? states : districts;
    return HostOptionList<GeoOption>(
      search: search,
      items: q.data ?? const [],
      loading: q.isLoading || q.isFetching,
      error: q.error,
      onRetry: q.refetch,
      labelOf: (o) => o.name,
      isSelected: (o) => _same(o, selected),
      onTap: (o) => Navigator.of(context).pop(o),
    );
  }

  static bool _same(GeoOption a, GeoOption? b) {
    if (b == null) return false;
    if (a.filterId != null && a.filterId == b.filterId) return true;
    return a.name.toLowerCase() == b.name.toLowerCase();
  }
}

/// Multi-select of the catalog languages; edits [selected] live.
Future<void> showLanguagePicker(
  BuildContext context,
  ValueNotifier<List<HostOption>> selected,
) => showHostSheet<void>(
  context,
  title: 'hostflow:basic.languages',
  child: _LanguageList(selected: selected),
);

class _LanguageList extends HookWidget {
  const _LanguageList({required this.selected});
  final ValueNotifier<List<HostOption>> selected;

  @override
  Widget build(BuildContext context) {
    final q = useHostLanguages(context);
    final chosen = useValueListenable(selected);
    return HostOptionList<HostOption>(
      multi: true,
      items: q.data ?? const [],
      loading: q.isLoading,
      error: q.error,
      onRetry: q.refetch,
      labelOf: (o) => o.label,
      isSelected: (o) => chosen.any((c) => c.value == o.value),
      onTap: (o) {
        final next = [...chosen];
        final i = next.indexWhere((c) => c.value == o.value);
        if (i >= 0) {
          next.removeAt(i);
        } else {
          next.add(o);
        }
        selected.value = next;
      },
    );
  }
}

/// The controller's text, 300 ms after the last keystroke.
String _useDebounced(TextEditingController c) {
  final value = useState('');
  useEffect(() {
    Timer? timer;
    void listener() {
      timer?.cancel();
      timer = Timer(const Duration(milliseconds: 300), () {
        value.value = c.text.trim();
      });
    }

    c.addListener(listener);
    return () {
      timer?.cancel();
      c.removeListener(listener);
    };
  }, [c]);
  return value.value;
}
