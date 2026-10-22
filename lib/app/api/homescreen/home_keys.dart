/// Query keys for the Discover tab. Same key ⇒ same data type everywhere.
abstract final class HomeKeys {
  static const all = ['home'];

  /// Infinite query: `InfiniteQueryData<HostPage, int>`.
  static const feed = ['home', 'feed'];

  /// `List<HostCard>`.
  static const popular = ['home', 'popular'];
}
