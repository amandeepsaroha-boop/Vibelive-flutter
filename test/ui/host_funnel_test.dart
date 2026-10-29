import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/hosthub/onboarding/helper/draft_controller.dart';
import 'package:vibelive/app/hosthub/onboarding/helper/flow_controller.dart';
import 'package:vibelive/app/hosthub/onboarding/helper/host_funnel.dart';
import 'package:vibelive/app/hosthub/onboarding/helper/host_steps.dart';
import 'package:vibelive/core/analytics/analytics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<(String, Map<String, Object>)> events;

  setUp(() {
    events = [];
    Analytics.debugSink = (e, p) => events.add((e, p));
  });
  tearDown(() => Analytics.debugSink = null);

  List<String> names() => [for (final e in events) e.$1];

  HostFunnel funnelFor(HostDraftController draft, {String mode = 'new'}) =>
      HostFunnel(
        draft: draft,
        mode: mode,
        source: 'become_host',
        routePath: '/host/onboarding',
      );

  test('open, step changes and exit: one view per step, then exited', () {
    final draft = HostDraftController('t', persist: false);
    final funnel = funnelFor(draft)..start();
    expect(
      names(),
      containsAllInOrder(['host_onboarding_started', 'host_ob_intro_viewed']),
    );

    draft.step.value = HostStep.basic;
    draft.step.value = HostStep.basic; // no change: no second view
    draft.step.value = HostStep.interests;
    final views = names().where((n) => n.endsWith('_viewed')).toList();
    expect(views, [
      'host_ob_intro_viewed',
      'host_ob_basic_viewed',
      'host_ob_interests_viewed',
    ]);

    final view = events
        .firstWhere((e) => e.$1 == 'host_ob_interests_viewed')
        .$2;
    expect(view['step_number'], HostStep.interests.number);
    expect(view['mode'], 'new');
    expect(view['source'], 'become_host');

    funnel.dispose();
    final exit = events.lastWhere((e) => e.$1 == 'host_onboarding_exited').$2;
    expect(exit['last_step'], 'interests');
    expect(exit['completed'], 'false');
    draft.dispose();
  });

  test(
    'submitted: SubmitApplication + expert_signup, exit counts as completed',
    () {
      final draft = HostDraftController('t', persist: false)
        ..step.value = HostStep.guidelines;
      final funnel = funnelFor(draft)..start();
      funnel.submitted('user-1');
      expect(names(), contains('host_onboarding_submitted'));
      expect(names(), contains('meta:SubmitApplication'));
      funnel.dispose();
      expect(
        events
            .lastWhere((e) => e.$1 == 'host_onboarding_exited')
            .$2['completed'],
        'true',
      );
      draft.dispose();
    },
  );

  test(
    'Continue: refused step logs validation, a passing step completes',
    () async {
      final draft = HostDraftController('t', persist: false)
        ..step.value = HostStep.tagline;
      final funnel = funnelFor(draft)..start();
      final pages = PageController();
      final flow = HostFlowController(
        draft: draft,
        pages: pages,
        submit: () async => null,
        exit: () {},
        explore: () {},
        rateFloors: () => (0, 0),
        funnel: funnel,
      );

      await flow.next(); // empty tagline: refused
      expect(names(), contains('host_onboarding_validation_failed'));
      expect(names(), isNot(contains('host_ob_tagline_completed')));

      draft.tagline.text = 'Here to listen and help';
      await flow.next();
      expect(names(), contains('host_ob_tagline_completed'));
      expect(names(), contains('host_ob_bio_viewed'));

      flow.back();
      expect(names(), contains('host_onboarding_step_back'));

      flow.dispose();
      pages.dispose();
      funnel.dispose();
      draft.dispose();
    },
  );
}
