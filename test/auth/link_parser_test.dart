import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/authscreen/helper/campaign_links.dart';
import 'package:vibelive/app/authscreen/helper/link_parser.dart';
import 'package:vibelive/core/router/app_router.dart';

void main() {
  group('LinkParser.parse (share links)', () {
    test('root slug is a host profile', () {
      final link = LinkParser.parse(
        'https://vibelive.angrymamba.com/john_doe',
      )!;
      expect(link.path, 'expert');
      expect(link.openUserId, 'john_doe');
    });

    test('custom scheme with and without the domain', () {
      expect(
        LinkParser.parse(
          'vibeexpoapp://vibelive.angrymamba.com/abc',
        )!.openUserId,
        'abc',
      );
      expect(LinkParser.parse('vibeexpoapp://wallet')!.path, 'wallet');
    });

    test('suffix -R / -I becomes the r marker', () {
      final link = LinkParser.parse(
        'https://vibelive.angrymamba.com/GFGNNV-I',
      )!;
      expect(link.params['handler'], 'GFGNNV');
      expect(link.params['r'], 'i');
    });

    test('legacy expert-profile.php?userid=', () {
      final link = LinkParser.parse(
        'https://www.vibelive.angrymamba.com/expert-profile.php?userid=doc1',
      )!;
      expect(link.path, 'expert-profile');
      expect(link.openUserId, 'doc1');
    });

    test('junk slugs and foreign hosts are dropped', () {
      expect(
        LinkParser.parse('https://vibelive.angrymamba.com/utm_source=x'),
        isNull,
      );
      expect(
        LinkParser.parse('https://vibelive.angrymamba.com/gclid123'),
        isNull,
      );
      expect(LinkParser.parse('https://evil.com/john'), isNull);
    });
  });

  group('LinkParser.referral', () {
    test('share shape /{code}?r=r|i', () {
      final refer = LinkParser.referral(
        'https://vibelive.angrymamba.com/ABC123?r=r',
      )!;
      expect((refer.handler, refer.intent), ('ABC123', ReferralIntent.refer));
      expect(refer.withSuffix, 'ABC123-R');
      final invite = LinkParser.referral(
        'https://vibelive.angrymamba.com/ABC123?r=i',
      )!;
      expect(invite.withSuffix, 'ABC123-I');
    });

    test('/invite/CODE, /referral?code=, generic ?referral=', () {
      expect(
        LinkParser.referral(
          'https://vibelive.angrymamba.com/invite/XYZ',
        )!.intent,
        ReferralIntent.invite,
      );
      expect(
        LinkParser.referral(
          'https://vibelive.angrymamba.com/referral?code=XYZ',
        )!.intent,
        ReferralIntent.refer,
      );
      expect(
        LinkParser.referral('https://other.site/?referral=XYZ')!.withSuffix,
        'XYZ',
      );
    });

    test('a plain profile share carries no attribution', () {
      expect(
        LinkParser.referral('https://vibelive.angrymamba.com/john'),
        isNull,
      );
    });
  });

  group('install referrer', () {
    test('referrer=CODE-R, double encoded utm_source, bare code', () {
      expect(LinkParser.installReferrer('referrer=ABC-R')!.withSuffix, 'ABC-R');
      expect(
        LinkParser.installReferrer(
          'utm_source%253DABC-I%2526utm_medium%253Dx',
        )!.withSuffix,
        'ABC-I',
      );
      final bare = LinkParser.installReferrer('ABC')!;
      expect((bare.handler, bare.intent), ('ABC', ReferralIntent.hostProfile));
    });

    test('organic / ad-network values are ignored', () {
      expect(
        LinkParser.installReferrer('utm_source=google-play&utm_medium=organic'),
        isNull,
      );
      expect(LinkParser.installReferrer('utm_medium=organic'), isNull);
      expect(LinkParser.installReferrer('(not set)'), isNull);
    });
  });

  test('share link builder', () {
    expect(
      LinkParser.shareLink('CODE', ReferralIntent.refer),
      'https://vibelive.angrymamba.com/CODE?r=r',
    );
    expect(
      LinkParser.shareLink('host'),
      'https://vibelive.angrymamba.com/host',
    );
  });

  group('CampaignLinks', () {
    test('presets, aliases and renamed params', () {
      final t = CampaignLinks.resolve(
        'vibecalling://expert-profile.php?userid=doc9',
      );
      expect(t.route!.route, AppRoutes.home);
      expect(t.params, {'tab': 'DISCOVER', 'openUserId': 'doc9'});
      expect(
        CampaignLinks.resolve('vibecalling://favorites').route!.route,
        AppRoutes.favourites,
      );
    });

    test('missing required params and unknown paths are reported', () {
      expect(CampaignLinks.resolve('vibecalling://page').missing, ['slug']);
      expect(CampaignLinks.resolve('vibecalling://nope').route, isNull);
    });

    test('home?q= becomes search', () {
      final t = CampaignLinks.resolve('vibecalling://home?q=dating');
      expect(t.route!.route, AppRoutes.search);
      expect(t.params, {'q': 'dating'});
    });

    test('web urls are normalized and hosts checked', () {
      expect(
        CampaignLinks.webUrl('https%3A%2F%2Fangrymamba.com%2Fx'),
        'https://angrymamba.com/x',
      );
      expect(
        CampaignLinks.webUrl('angrymamba.com/x'),
        'https://angrymamba.com/x',
      );
      expect(CampaignLinks.webUrl('javascript:alert(1)'), isNull);
      expect(
        CampaignLinks.isTrustedHost('https://vibelive.angrymamba.com/a'),
        isTrue,
      );
      expect(
        CampaignLinks.isTrustedHost('https://angrymamba.com.evil.com'),
        isFalse,
      );
    });
  });
}
