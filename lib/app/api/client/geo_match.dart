import 'client_models.dart';

/// Matches a geocoder's place name ("NCT of Delhi", "Gurugram",
/// "Faridabad Division") to a backend state / district row.
abstract final class GeoMatch {
  /// The option whose name best matches any of [candidates] (tried in
  /// order), or null. Exact match after normalizing wins; otherwise one name
  /// containing the other, preferring the longest overlap.
  static GeoOption? best(List<GeoOption> options, List<String?> candidates) {
    for (final candidate in candidates) {
      final wanted = _variants(candidate);
      if (wanted.isEmpty) continue;
      for (final o in options) {
        if (_variants(o.name).any(wanted.contains)) return o;
      }
    }
    for (final candidate in candidates) {
      final wanted = _variants(candidate);
      if (wanted.isEmpty) continue;
      GeoOption? found;
      var foundLength = 0;
      for (final o in options) {
        for (final have in _variants(o.name)) {
          for (final want in wanted) {
            final shorter = have.length < want.length ? have : want;
            if (shorter.length < 4) continue;
            if ((have.contains(want) || want.contains(have)) &&
                shorter.length > foundLength) {
              found = o;
              foundLength = shorter.length;
            }
          }
        }
      }
      if (found != null) return found;
    }
    return null;
  }

  static Set<String> _variants(String? name) {
    final n = normalize(name);
    if (n.isEmpty) return const {};
    return {n, ?_aliases[n]};
  }

  /// Lowercase letters and single spaces, without "district" / "division" /
  /// "NCT of" noise; "&" reads as "and".
  static String normalize(String? name) {
    var s = (name ?? '').toLowerCase().replaceAll('&', ' and ');
    s = s.replaceAll(RegExp('[^a-z ]'), ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    for (final noise in _prefixes) {
      if (s.startsWith(noise)) s = s.substring(noise.length).trim();
    }
    for (final noise in _suffixes) {
      if (s.endsWith(noise)) s = s.substring(0, s.length - noise.length).trim();
    }
    return s;
  }

  static const _prefixes = [
    'national capital territory of ',
    'nct of ',
    'union territory of ',
    'the ',
  ];

  static const _suffixes = [' district', ' division', ' state'];

  /// Renamed places the OS and the backend may spell differently.
  static const _aliases = {
    'gurugram': 'gurgaon',
    'gurgaon': 'gurugram',
    'bengaluru': 'bangalore',
    'bangalore': 'bengaluru',
    'bengaluru urban': 'bangalore urban',
    'bangalore urban': 'bengaluru urban',
    'bengaluru rural': 'bangalore rural',
    'bangalore rural': 'bengaluru rural',
    'mysuru': 'mysore',
    'mysore': 'mysuru',
    'prayagraj': 'allahabad',
    'allahabad': 'prayagraj',
    'odisha': 'orissa',
    'orissa': 'odisha',
    'puducherry': 'pondicherry',
    'pondicherry': 'puducherry',
    'uttarakhand': 'uttaranchal',
    'uttaranchal': 'uttarakhand',
    'kolkata': 'calcutta',
    'calcutta': 'kolkata',
    'chennai': 'madras',
    'madras': 'chennai',
    'mumbai': 'mumbai city',
    'mumbai city': 'mumbai',
  };
}
