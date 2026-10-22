import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../../core/network/strapi.dart';
import '../../../core/query/query_hooks.dart';
import '../../../core/query/query_persist.dart';
import '../../../core/session/session_store.dart';
import '../../../core/utils/log.dart';
import '../client/client_keys.dart';
import '../client/profile_api.dart';
import '../component/upload_api.dart';
import '../paymentscreen/checkout_models.dart';
import '../splashscreen/splash_queries.dart';
import 'approval_api.dart';
import 'approval_models.dart';
import 'badge_payment_api.dart';
import 'catalog_api.dart';
import 'catalog_models.dart';
import 'expertise_api.dart';
import 'expertise_models.dart';
import 'handle_api.dart';
import 'hosthub_keys.dart';
import 'images_api.dart';
import 'onboarding_models.dart';
import 'profile_api.dart';
import 'profile_models.dart';
import 'profile_patch.dart';
import 'stats_api.dart';
import 'stats_models.dart';
import 'verification_api.dart';
import 'verification_models.dart';

part 'host_profile_queries.dart';
part 'host_status_queries.dart';
part 'host_onboarding_queries.dart';

typedef HostProfileUpdate = ({String expertId, HostProfilePatch patch});
typedef HostImagesSync = ({
  String expertId,
  List<Object?> slots,
  List<HostProfileImage> existing,
});
typedef GoLiveInput = ({String expertId, String? name, String? email});
typedef VerificationPaymentStart = ({int userId, String verificationId});
typedef VerificationPaymentResult = ({String verificationId, JsonMap payload});
typedef ExpertiseSave = ({ExpertiseAnswers selections, String source});

/// The signed-in host's expert id (documentId first).
String? _ownExpertId(SessionState s) =>
    s.expertDocumentId ?? s.expertId?.toString();
