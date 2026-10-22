/// The eleven screens of "Become a Host", in order. The intro and the
/// success screen have their own chrome; the form steps share the progress
/// header and the sticky Continue bar.
enum HostStep {
  intro,
  basic,
  interests,
  photos,
  tagline,
  bio,
  rates,
  availability,

  /// How clients will see the profile, with an Edit link per section.
  preview,

  /// Do / Don't, the agreement, "Submit for review".
  guidelines,
  submitted;

  static const total = 11;

  /// "N of 11".
  int get number => index + 1;

  /// Index in the flow's page view (basic = 0).
  int get page => index - 1;

  /// Steps with Continue; the success screen is the last page.
  static const pages = [
    basic,
    interests,
    photos,
    tagline,
    bio,
    rates,
    availability,
    preview,
    guidelines,
    submitted,
  ];

  static HostStep fromName(String? name) {
    // Drafts saved before the review step was split resume on the preview.
    if (name == 'review') return preview;
    for (final s in values) {
      if (s.name == name) return s;
    }
    return intro;
  }

  HostStep? get previous => index == 0 ? null : values[index - 1];
  HostStep? get next => index == values.length - 1 ? null : values[index + 1];

  /// i18n key of the Continue bar's label.
  String get continueLabel => switch (this) {
    guidelines => 'hostflow:review.submit',
    submitted => 'hostflow:submitted.cta',
    _ => 'hostflow:continue',
  };

  bool get continueArrow => this != guidelines;
}
