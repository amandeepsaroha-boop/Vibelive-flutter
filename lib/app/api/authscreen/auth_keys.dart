/// Query keys for the auth feature (session, onboarding, interests).
/// Same key ⇒ same data type everywhere. User-scoped entries carry the
/// user key (`SessionState.userKey`).
abstract final class AuthKeys {
  static const all = ['auth'];

  /// `/auth/verify-token` user.
  static const sessionUser = ['auth', 'session-user'];

  /// `/public-users/:documentId` (profilePic populated).
  static const users = ['auth', 'user'];
  static List<Object> user(String documentId) => [...users, documentId];

  static const referrals = ['auth', 'referral'];
  static List<Object> referral(String code) => [...referrals, code];

  static const interestForm = ['auth', 'interests', 'form'];
  static const myInterestsAll = ['auth', 'interests', 'mine'];
  static List<Object> myInterests(String userKey) => [
    ...myInterestsAll,
    userKey,
  ];

  static const languageSteps = ['auth', 'language-step'];
  static List<Object> languageStep(String userKey) => [
    ...languageSteps,
    userKey,
  ];

  static const languageQuestions = ['auth', 'language-question'];
  static List<Object> languageQuestion(String userKey) => [
    ...languageQuestions,
    userKey,
  ];

  /// `/languages` (the Languages collection), A→Z, every page.
  static const languages = ['auth', 'languages'];
}
