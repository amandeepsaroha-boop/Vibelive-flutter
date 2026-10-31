import '../analytics.dart';

/// ME tab, settings and account events (Firebase + Meta).
/// Catalog: docs/analytics_events.md.
abstract final class MeEvents {
  /// RN `profile_open`: the ME tab (own profile) was opened.
  static void profileOpen({String? userId, required bool isExpert}) =>
      Analytics.log('profile_open', {
        'user_id': userId,
        'is_expert': isExpert,
        'screen': 'me',
      });

  /// A row / card / chip on the ME tab or its menus. [section]: `wallet`,
  /// `identity`, `hub`, `resources`, `menu_sheet`, `referral_card`,
  /// `badge_chip`, `profile_preview`.
  static void itemTapped({required String item, required String section}) =>
      Analytics.log('me_item_tapped', {'item': item, 'section': section});

  /// Hosts: Dashboard | Settings switch.
  static void sectionSwitched(String section) =>
      Analytics.log('me_section_switched', {'section': section});

  /// The avatar opened the photo preview.
  static void avatarTapped({required bool isExpert}) =>
      Analytics.log('me_avatar_tapped', {'is_expert': isExpert});

  /// Theme: `system` / `light` / `dark`.
  static void themeChanged(String theme) {
    Analytics.log('theme_changed', {'theme': theme});
    Analytics.userProperty('app_theme', theme);
  }

  /// App language picked in Settings: `en`, `hi`, `bn`… (the user property
  /// `app_language` is set by LocaleController).
  static void languageChanged({required String from, required String to}) =>
      Analytics.log('language_changed', {'from': from, 'to': to});

  /// The user's own host profile link shared. [source]: `me_list`,
  /// `me_menu`, `profile_preview`, `resources`.
  static void profileShared({required String source, String? hostId}) {
    Analytics.log('own_profile_shared', {'source': source, 'host_id': hostId});
    Analytics.firebase('share', {
      'method': 'system_share',
      'content_type': 'own_profile',
      'item_id': hostId,
    });
  }

  /// Share tapped without a profile link to share.
  static void profileShareUnavailable({required String source}) =>
      Analytics.log('own_profile_share_unavailable', {'source': source});

  static void profileLinkCopied({required String source}) =>
      Analytics.log('own_profile_link_copied', {'source': source});

  /// "Become a Host" tapped. [eligible]: Personal Info complete (else the
  /// "fill in first" dialog shows).
  static void becomeHostTapped({
    required String source,
    required bool eligible,
    int? missingCount,
  }) => Analytics.log('become_host_tapped', {
    'source': source,
    'eligible': eligible,
    'missing_count': missingCount,
  });

  /// The "fill in Personal Info first" dialog: `fill_info` / `cancel`.
  static void becomeHostLocked({required String action}) =>
      Analytics.log('become_host_locked_action', {'action': action});

  /// Logout: tapped (`me_menu`, `resources`), then confirmed / cancelled.
  /// The `logout` event itself comes from AnalyticsIdentity.
  static void logoutTapped({required String source}) =>
      Analytics.log('logout_tapped', {'source': source});

  static void logoutConfirmed({required String source}) =>
      Analytics.log('logout_confirmed', {'source': source});

  static void logoutCancelled({required String source}) =>
      Analytics.log('logout_cancelled', {'source': source});

  static void deleteAccountTapped() =>
      Analytics.log('delete_account_tapped');

  static void deleteAccountConfirmed() =>
      Analytics.log('delete_account_confirmed');

  static void deleteAccountCancelled() =>
      Analytics.log('delete_account_cancelled');

  /// Pull-to-refresh on the ME tab.
  static void refreshed() => Analytics.log('me_refreshed');
}

/// Personal Info (profile form) events.
abstract final class PersonalInfoEvents {
  /// Save tapped. [fields]: names of the edited fields (`name,email,…`).
  static void saveTapped({required String fields, required int count}) =>
      Analytics.log('personal_info_save_tapped', {
        'fields_changed': fields,
        'changed_count': count,
      });

  /// Validation stopped the save. [issue]: the i18n key of the message.
  static void invalid(String issue) =>
      Analytics.log('personal_info_invalid', {'issue': issue});

  static void saved({
    required String fields,
    required int count,
    required bool firstCompletion,
  }) => Analytics.log('personal_info_saved', {
    'fields_changed': fields,
    'changed_count': count,
    'first_completion': firstCompletion,
  });

  static void saveFailed(Object error) => Analytics.log(
    'personal_info_save_failed',
    {'error': Analytics.errorCode(error)},
  );

  /// RN `user_signup`: a user finished registration (first complete
  /// profile save), once per user per install.
  static void userSignup(String userKey) => Analytics.logOncePersisted(
    'user_signup_$userKey',
    'user_signup',
    {'category': 'user'},
  );

  /// Profile photo: tapped, then updated / cancelled / failed
  /// ([stage]: `pick` / `upload`).
  static void photoTapped() => Analytics.log('profile_photo_tapped');

  static void photoUpdated({String source = 'gallery'}) =>
      Analytics.log('profile_photo_updated', {'source': source});

  static void photoCancelled() => Analytics.log('profile_photo_cancelled');

  static void photoFailed({required String stage, Object? error}) =>
      Analytics.log('profile_photo_failed', {
        'stage': stage,
        'error': error == null ? null : Analytics.errorCode(error),
      });

  /// "Use current location" / the automatic fill. [trigger]: `auto` /
  /// `tap`; [result]: `filled`, `state_only`, `failed`; [reason] for a
  /// failure (`denied`, `service_off`, `not_found`, `api`…).
  static void locationAutofill({
    required String trigger,
    required String result,
    String? reason,
    String? source,
  }) => Analytics.log('location_autofill', {
    'trigger': trigger,
    'result': result,
    'reason': reason,
    'source': source,
  });

  /// State / district picker: a row picked. [level]: `state` / `district`;
  /// [source]: `personal_info` / `gst`.
  static void geoSelected({required String level, required String source}) =>
      Analytics.log('geo_picker_selected', {'level': level, 'source': source});

  /// District tapped before a state was picked.
  static void geoNeedsState({required String source}) =>
      Analytics.log('geo_picker_needs_state', {'source': source});

  static void genderSelected(String gender) =>
      Analytics.log('gender_selected', {'gender': gender.toLowerCase()});

  /// Back with unsaved edits / without saving.
  static void left({required bool dirty}) =>
      Analytics.log('personal_info_left', {'unsaved_changes': dirty});
}

/// GST details, favourites, blocked users, host categories.
abstract final class AccountListEvents {
  /// GST: edit toggled, registration switch, declaration, document picked,
  /// save outcome. No GST number / business details are sent.
  static void gstEditToggled({required bool editing}) =>
      Analytics.log('gst_edit_toggled', {'editing': editing});

  static void gstRegistrationSet({required bool registered}) =>
      Analytics.log('gst_registration_set', {'registered': registered});

  static void gstDeclarationToggled({required bool confirmed}) =>
      Analytics.log('gst_declaration_toggled', {'confirmed': confirmed});

  /// [document]: `certificate` / `logo`; [picked]: false when cancelled.
  static void gstDocumentPicked({
    required String document,
    required bool picked,
  }) => Analytics.log('gst_document_picked', {
    'document': document,
    'picked': picked,
  });

  static void gstSaveTapped({required bool registered}) =>
      Analytics.log('gst_save_tapped', {'registered': registered});

  static void gstInvalid({required int errorCount}) =>
      Analytics.log('gst_invalid', {'error_count': errorCount});

  static void gstSaved({required bool registered}) =>
      Analytics.log('gst_saved', {'registered': registered});

  static void gstSaveFailed(Object error) =>
      Analytics.log('gst_save_failed', {'error': Analytics.errorCode(error)});

  /// Favourites list loaded (once per visit).
  static void favouritesViewed(int count) =>
      Analytics.log('favourites_viewed', {'count': count, 'empty': count == 0});

  static void favouriteOpened({String? hostId, required int position}) =>
      Analytics.log('favourite_opened', {
        'host_id': hostId,
        'position': position,
        'source': 'favourites',
      });

  static void favouriteRemoved({String? hostId}) => Analytics.log(
    'favourite_removed',
    {'host_id': hostId, 'source': 'favourites'},
  );

  static void favouriteRemoveFailed(Object error) => Analytics.log(
    'favourite_remove_failed',
    {'error': Analytics.errorCode(error), 'source': 'favourites'},
  );

  static void favouritesRefreshed() => Analytics.log('favourites_refreshed');

  /// Blocked users list loaded (once per visit).
  static void blockedViewed(int count) =>
      Analytics.log('blocked_users_viewed', {'count': count});

  static void unblockTapped({String? userId}) =>
      Analytics.log('unblock_tapped', {'user_id': userId});

  static void unblockCancelled({String? userId}) =>
      Analytics.log('unblock_cancelled', {'user_id': userId});

  static void unblocked({String? userId}) =>
      Analytics.log('user_unblocked', {'user_id': userId});

  static void unblockFailed({String? userId, required Object error}) =>
      Analytics.log('unblock_failed', {
        'user_id': userId,
        'error': Analytics.errorCode(error),
      });

  /// Host categories screen (`/me/categories`).
  static void categoryToggled({
    required String category,
    required bool selected,
    required int count,
  }) => Analytics.log('category_toggled', {
    'category': category,
    'selected': selected,
    'count': count,
  });

  static void categorySearched({required int queryLength}) =>
      Analytics.log('category_searched', {'query_length': queryLength});

  /// RN `specialization_selected`: the host saved their categories.
  static void specializationSelected({
    String? expertId,
    required List<String> ids,
    required List<String> names,
  }) => Analytics.log('specialization_selected', {
    'expert_id': expertId,
    'category_ids': ids.join(','),
    'category_names': names.join(', '),
    'categories_count': ids.length,
    'source': 'categories',
  });

  static void categoriesSaveFailed(Object error) => Analytics.log(
    'categories_save_failed',
    {'error': Analytics.errorCode(error)},
  );

  static void categoriesEmptySave() => Analytics.log('categories_none_picked');
}

/// Referral programme and the invite card.
abstract final class ReferralEvents {
  /// RN `referral_opened`: the referral screen showed its dashboard.
  static void opened({String? referralCode, int? joined, int? clicks}) =>
      Analytics.log('referral_opened', {
        'referral_code': referralCode,
        'joined_count': joined,
        'share_count': clicks,
      });

  /// RN `referral_shared` (+ Firebase `share`). [method]: `system_share`,
  /// `whatsapp`, `copy`; [source]: `referral_screen` / `invite_card`.
  static void shared({
    String? referralCode,
    required String method,
    required String source,
  }) {
    Analytics.log('referral_shared', {
      'referral_code': referralCode,
      'share_method': method,
      'source': source,
    });
    Analytics.firebase('share', {
      'method': method,
      'content_type': 'referral',
      'item_id': referralCode,
    });
  }

  static void codeCopied({String? referralCode, required String source}) =>
      Analytics.log('referral_code_copied', {
        'referral_code': referralCode,
        'source': source,
      });

  /// Share tapped with no code to share.
  static void codeUnavailable({required String source}) =>
      Analytics.log('referral_code_unavailable', {'source': source});

  static void refreshed() => Analytics.log('referral_refreshed');

  /// The ME tab's "Invite & Earn" card was shown (once per app session).
  static void inviteCardShown({String? referralCode}) => Analytics.logOnce(
    'referral_invite_card_shown',
    'referral_invite_card_shown',
    {'referral_code': referralCode},
  );
}

/// Resources: profile-menu categories, CMS pages, links, support.
abstract final class ResourceEvents {
  /// A row of a category menu (`/me/category-menu`). [action]: `route`,
  /// `share`, `dropdown`, `logout`, `delete_account`.
  static void menuItemTapped({
    required String item,
    required String action,
    String? menu,
  }) => Analytics.log('resource_item_tapped', {
    'item': item,
    'action': action,
    'menu': menu,
  });

  /// A dropdown row opened / closed.
  static void dropdownToggled({required String item, required bool open}) =>
      Analytics.log('resource_dropdown_toggled', {'item': item, 'open': open});

  /// A CMS page failed to load / has no content.
  static void pageLoadFailed({required String slug, required Object error}) =>
      Analytics.log('page_load_failed', {
        'slug': slug,
        'error': Analytics.errorCode(error),
      });

  static void pageEmpty(String slug) =>
      Analytics.log('page_empty', {'slug': slug});

  static void pageRefreshed(String slug) =>
      Analytics.log('page_refreshed', {'slug': slug});

  /// A link inside a page / support contact. [scheme]: `https`, `mailto`,
  /// `tel`…; [domain] for web links only.
  static void linkOpened({
    required String source,
    String? scheme,
    String? domain,
    required bool opened,
  }) => Analytics.log('link_opened', {
    'source': source,
    'scheme': scheme,
    'domain': domain,
    'opened': opened,
  });

  /// A support contact tapped. [channel]: `email`, `phone`, `whatsapp`.
  /// Also Meta's standard `Contact`.
  static void supportContact(String channel) {
    Analytics.log('support_contact_tapped', {'channel': channel});
    Analytics.meta('Contact', {'channel': channel});
  }

  /// The support page fell back to the app-config contacts.
  static void supportFallbackShown() =>
      Analytics.logOnce('support_fallback', 'support_fallback_shown');

  /// `/webview`: [result] `opened`, `failed`, `offline`, `invalid`;
  /// [mode] `in_app` / `external`.
  static void webview({
    required String result,
    String? domain,
    String mode = 'in_app',
  }) => Analytics.log('webview_opened', {
    'result': result,
    'domain': domain,
    'mode': mode,
  });

  static void webviewRetry(String? domain) =>
      Analytics.log('webview_retry', {'domain': domain});
}

/// Shared components: share sheet, QR, photo preview, alert dialogs.
abstract final class UiEvents {
  /// The OS share sheet. [result]: `shared`, `dismissed`, `unavailable`,
  /// `copied` (fallback). [contentType]: what was shared.
  static void shareSheet({required String contentType, required String result}) =>
      Analytics.log('share_sheet_result', {
        'content_type': contentType,
        'result': result,
      });

  /// A profile QR code was shown. [source] when the caller knows it.
  static void qrShown({String? source}) =>
      Analytics.log('qr_code_shown', {'source': source});

  /// The photo preview: opened, then an action (`favorite`, `share`,
  /// `copy_link`, `qr`).
  static void imagePreviewOpened(String name) =>
      Analytics.log('image_preview_opened', {'preview': name});

  static void imagePreviewAction({
    required String name,
    required String action,
  }) => Analytics.log('image_preview_action', {
    'preview': name,
    'action': action,
  });

  /// Any app alert dialog's outcome: `primary`, `secondary`, `dismissed`.
  static void dialogAction({required String dialog, required String action}) =>
      Analytics.log('dialog_action', {'dialog': dialog, 'action': action});

  /// An error alert reached the user.
  static void errorAlert(Object error) => Analytics.log(
    'error_alert_shown',
    {'error': Analytics.errorCode(error)},
  );
}
