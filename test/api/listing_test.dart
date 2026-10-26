import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fquery/fquery.dart' show CacheProvider;
import 'package:pretty_dio_logger/pretty_dio_logger.dart';
import 'package:vibelive/app/api/homescreen/home_models.dart';
import 'package:vibelive/app/api/homescreen/home_queries.dart';
import 'package:vibelive/app/api/listingflow/filter_models.dart';
import 'package:vibelive/app/api/listingflow/listing_models.dart';
import 'package:vibelive/app/api/listingflow/listing_queries.dart';
import 'package:vibelive/app/api/listingflow/search_models.dart';
import 'package:vibelive/core/config/env.dart';
import 'package:vibelive/core/network/api_client.dart';
import 'package:vibelive/core/query/query_hooks.dart';

String abs(String path) => '${Env.apiBaseUrl}$path';

Map<String, dynamic> image(
  String name, {
  String status = 'approved',
  Object? priority,
  Object? isprimary,
}) => {
  'status_enum': status,
  'priority': priority,
  'isprimary': isprimary,
  'image': {
    'url': '/uploads/$name.jpg',
    'formats': {
      'medium': {'url': '/uploads/medium_$name.jpg'},
    },
  },
};

Map<String, dynamic> selection(String key, String label, String value) => {
  'snapshot': {
    'question': {'key': key},
    'option': {'label': label, 'value': value},
  },
};

/// Strapi v5 expert-profile row, as the Discover feed returns it.
Map<String, dynamic> expertRow() => {
  'id': 7,
  'documentId': 'exp7',
  'handler': 'riya',
  'tagline': '  Here to listen  ',
  'descriptions': 'Long bio ',
  'averageRating': '4.25',
  'reviewCount': 12,
  // The dot reads user_status, not isActive (schedule, always on).
  'isActive': false,
  'user_status': 'Online',
  'isApproved': true,
  'website': 'https://riya.example',
  'featured_sequence': 2,
  'rates': {'videoCallRate': 30, 'voiceCallRate': '15'},
  'audio_intro': {'url': '/uploads/intro.m4a'},
  'audio_intro_status': ' Approved ',
  'language': [
    {'languageNames': 'Hindi'},
    {'name': ' English '},
    {'label': ''},
  ],
  'categories': [
    {'name': 'Dating'},
    'Career',
  ],
  'expert_verifications': [
    {
      'Verified_Badge': 'TRUE',
      'insta_verified': true,
      'facebook_verified': 'true',
      'snapchat_verified': false,
      'insta_url': 'https://instagram.com/riya',
    },
  ],
  'service_area_selections': [
    selection('support_topic', ' Breakups ', 'breakup'),
    selection('gender', 'Female', 'female'),
  ],
  'host_profile_images': [
    image('a', priority: 2),
    image('b', status: 'pending', priority: 1),
    image('c', priority: 1),
    image('d', isprimary: 'TRUE', priority: 5),
  ],
  'user': {
    'id': 70,
    'documentId': 'usr70',
    'name': 'Riya Sen',
    'district': {'name': 'Pune'},
    'profilePic': {'url': '/uploads/pic.jpg'},
  },
};

void main() {
  group('HostCard.fromJson', () {
    test('expert-profile payload (Strapi v5)', () {
      final h = HostCard.fromJson(expertRow());

      expect(h.id, 7);
      expect(h.receiverId, 70);
      expect(h.documentId, 'usr70');
      expect(h.userDocumentId, 'usr70');
      expect(h.expertProfileDocumentId, 'exp7');
      expect(h.name, 'RIYA SEN');
      expect(h.city, 'PUNE');
      expect(h.rating, 4.25);
      expect(h.ratingLabel, '4.3');
      expect(h.reviewCount, 12);
      expect(h.vPrice, 30);
      expect(h.aPrice, 15);
      expect(h.tagline, 'Here to listen');
      expect(h.description, 'Long bio');
      expect(h.handler, 'riya');
      expect(h.isAvailable, isTrue);
      expect(h.isApprovedHost, isTrue);
      expect(h.isFeatured, isTrue);
      expect(h.featuredSequence, 2);
      expect(h.websiteUrl, 'https://riya.example');

      expect(h.languages, ['Hindi', 'English']);
      expect(h.categories, ['Dating', 'Career']);
      expect(h.specialization, 'Dating');
      expect(h.tags, [' Breakups ', 'Female']);
      expect(h.topics, ['Breakups']);
      expect(h.topicValues, ['breakup']);

      expect(h.verified, isTrue);
      expect(h.instaVerified, isTrue);
      expect(h.facebookVerified, isTrue);
      expect(h.snapchatVerified, isFalse);
      expect(h.instaUrl, 'https://instagram.com/riya');
      expect(h.badgeFlags['instaVerified'], isTrue);

      // Approved only; primary first, then priority, ties in server order.
      expect(h.images, [
        abs('/uploads/d.jpg'),
        abs('/uploads/c.jpg'),
        abs('/uploads/a.jpg'),
      ]);
      expect(h.cardImage, abs('/uploads/medium_d.jpg'));
      expect(h.audioIntro, abs('/uploads/intro.m4a'));
      expect(h.toJson()['documentId'], 'exp7');
    });

    test('public-user payload with the expert nested', () {
      final h = HostCard.fromJson(const {
        'id': 70,
        'documentId': 'usr70',
        'name': 'arjun',
        'mobile': '9999999999',
        'profilePic': {
          'url': '/uploads/pic.jpg',
          'formats': {
            'small': {'url': '/uploads/small_pic.jpg'},
          },
        },
        'expert': {
          'id': 9,
          'documentId': 'exp9',
          'handler': 'arjun_h',
          'isActive': true,
          'rates': {'videoCallRate': 0, 'voiceCallRate': 10},
          'expert_profile_approvals': [
            {'status': 'Approved'},
          ],
        },
      });

      expect(h.id, 9);
      expect(h.receiverId, 70);
      expect(h.documentId, 'usr70');
      expect(h.expertProfileDocumentId, 'exp9');
      expect(h.name, 'ARJUN');
      expect(h.handler, 'arjun_h');
      expect(h.vPrice, 0);
      expect(h.aPrice, 10);
      expect(h.isAvailable, isFalse);
      expect(h.isApprovedHost, isTrue);
      // No gallery: the profile picture, card-sized for the grid.
      expect(h.images, [abs('/uploads/pic.jpg')]);
      expect(h.cardImage, abs('/uploads/small_pic.jpg'));
      expect(h.refersTo('exp9'), isTrue);
      expect(h.refersTo(70), isTrue);
      expect(h.refersTo('someone-else'), isFalse);
    });

    test('Strapi v4 wrapped row with rate rows', () {
      final h = HostCard.fromJson(const {
        'data': {
          'id': 3,
          'attributes': {
            'documentId': 'exp3',
            'handler': 'kabir',
            'isActive': 1,
            'user_status': 'busy',
            'rates': {
              'data': [
                {
                  'id': 1,
                  'attributes': {'callType': 'Audio Call', 'ratePerMin': 12},
                },
                {
                  'id': 2,
                  'attributes': {'callType': 'VIDEO', 'ratePerMin': '25'},
                },
              ],
            },
            'user': {
              'data': {
                'id': 30,
                'attributes': {
                  'documentId': 'usr30',
                  'profile_pic_status': 'pending',
                  'profilePic': {'url': 'https://cdn.example/p.jpg'},
                  'district': {
                    'data': {
                      'id': 1,
                      'attributes': {'name': 'Delhi'},
                    },
                  },
                },
              },
            },
          },
        },
      });

      expect(h.id, 3);
      expect(h.receiverId, 30);
      expect(h.userDocumentId, 'usr30');
      expect(h.expertProfileDocumentId, 'exp3');
      // No user name: the handler.
      expect(h.name, 'KABIR');
      expect(h.city, 'DELHI');
      expect(h.vPrice, 25);
      expect(h.aPrice, 12);
      expect(h.isAvailable, isTrue);
      // Pending profile picture is withheld.
      expect(h.images, isEmpty);
      expect(h.cardImage, isNull);
    });

    test('rate rows without a call type fall back by position', () {
      final h = HostCard.fromJson(const {
        'id': 1,
        'rates': [
          {'ratePerMin': 40},
          {'ratePerMin': 20},
        ],
      });
      expect(h.vPrice, 40);
      expect(h.aPrice, 20);
    });

    test('empty payload leaves fallbacks to the UI', () {
      final h = HostCard.fromJson(null, index: 4);

      expect(h.id, 5);
      expect(h.receiverId, isNull);
      expect(h.documentId, isNull);
      expect(h.name, isEmpty);
      expect(h.city, isEmpty);
      expect(h.tags, isEmpty);
      expect(h.rating, 0);
      expect(h.ratingLabel, '0.0');
      expect(h.vPrice, 0);
      expect(h.images, isEmpty);
      expect(h.cardImage, isNull);
      expect(h.audioIntro, isNull);
      expect(h.isFeatured, isFalse);
      expect(h.featuredSequence, isNull);
      expect(h.verified, isFalse);
      expect(h.isApprovedHost, isFalse);
    });

    test('moderation and badge gates', () {
      final h = HostCard.fromJson({
        'id': 2,
        'audio_intro': const {'url': '/uploads/intro.m4a'},
        'audio_intro_status': 'pending',
        'isFeatured': false,
        'featured_sequence': '',
        'isApproved': 'false',
        'expert_profile_approvals': const [
          {'status': 'pending', 'is_approved': 'true'},
        ],
        // Social claims without a verified badge are not shown.
        'expert_verifications': const [
          {'Verified_Badge': false, 'insta_verified': true},
        ],
        'host_profile_images': [image('x', status: 'rejected')],
        'user': const {
          'id': 20,
          'profile_pic_status': 'approved',
          'profilePic': {'url': '/uploads/pic.jpg'},
        },
      });

      expect(h.audioIntro, isNull);
      expect(h.isFeatured, isFalse);
      expect(h.isApprovedHost, isFalse);
      expect(h.verified, isFalse);
      expect(h.instaVerified, isFalse);
      expect(h.images, [abs('/uploads/pic.jpg')]);

      final viaFlag = HostCard.fromJson(const {'id': 2, 'isVerified': 'true'});
      expect(viaFlag.verified, isTrue);
      final viaNumber = HostCard.fromJson(const {
        'id': 2,
        'expert_verifications': [
          {'Verified_Badge': 1, 'snapchat_verified': 'true'},
        ],
      });
      expect(viaNumber.verified, isTrue);
      expect(viaNumber.snapchatVerified, isTrue);
    });
  });

  group('HostBadges.fromRow', () {
    test('same gate as the card, search rule set', () {
      final b = HostBadges.fromRow(const {
        'documentId': 'exp1',
        'expert_verifications': [
          {'Verified_Badge': 'True', 'insta_verified': 'true'},
        ],
      });
      expect(b.verified, isTrue);
      expect(b.instaVerified, isTrue);
      expect(b.facebookVerified, isFalse);

      final ungated = HostBadges.fromRow(const {
        'expert_verifications': [
          {'Verified_Badge': 1, 'insta_verified': true},
        ],
      });
      expect(ungated.verified, isFalse);
      expect(ungated.instaVerified, isFalse);
    });
  });

  group('SearchResults', () {
    final body = {
      'results': {
        'experts': [
          {
            'documentId': 'exp1',
            'userDocumentId': 'usr1',
            'name': 'Meera',
            'categories': [
              'Career',
              {'name': 'Dating'},
              {'name': ''},
              null,
            ],
            'languages': [
              {'name': 'Tamil'},
              'Hindi',
            ],
            'topics': [
              {'label': 'Breakups'},
              {'name': 'Stress'},
            ],
            'averageRating': '3.5',
            'reviewCount': '4',
            'isVerified': true,
            'insta_verified': true,
            'profilePic': '/uploads/m.jpg',
            'rates': {'voiceCallRate': '9', 'videoCallRate': null},
            'durations': {'TotalMin': 1250},
          },
          {'documentId': null},
          'junk',
        ],
        'categories': [
          {'documentId': 'c1', 'name': 'Career', 'callsCount': 12},
        ],
        'category_and_location': [
          {
            'category': {'name': 'Career'},
            'location': {'name': 'Pune'},
          },
        ],
      },
    };

    test('maps the summary rows', () {
      final r = SearchResults.fromResponse(body);
      expect(r.experts, hasLength(2));
      final m = r.experts.first;
      expect(m.categories, ['Career', 'Dating']);
      expect(m.specialization, 'Career');
      expect(m.categoryLabel, 'Career • Dating');
      expect(m.languages, ['Tamil', 'Hindi']);
      expect(m.topics, ['Breakups', 'Stress']);
      expect(m.rating, 3.5);
      expect(m.reviewCount, 4);
      expect(m.isVerified, isTrue);
      expect(m.instaVerified, isTrue);
      expect(m.profilePic, abs('/uploads/m.jpg'));
      expect(m.voiceRate, 9);
      expect(m.videoRate, 0);
      expect(m.callMinutes, 1250);
      expect(r.experts.last.name, isEmpty);
      expect(r.expertDocumentIds, ['exp1']);
      expect(r.categories.single.callsCount, 12);
      expect(r.categoryLocations.single.query, 'Career');
      expect(r.categoryLocations.single.label, isEmpty);
      expect(r.isEmpty, isFalse);
      expect(SearchResults.fromResponse(null).isEmpty, isTrue);
    });

    test('badges upgrade rows in place', () {
      final r = SearchResults.fromResponse(body).withBadges({
        'exp1': const HostBadges(verified: true, facebookVerified: true),
      });
      final m = r.experts.first;
      expect(m.isVerified, isTrue);
      expect(m.instaVerified, isFalse);
      expect(m.facebookVerified, isTrue);
      expect(r.experts.last.isVerified, isFalse);
    });
  });

  group('filters', () {
    final host = HostCard.fromJson(expertRow());

    test('HostFilter matches language and topic', () {
      expect(HostFilter.none.matches(host), isTrue);
      expect(const HostFilter(languages: [' hindi ']).matches(host), isTrue);
      expect(const HostFilter(languages: ['Tamil']).matches(host), isFalse);
      expect(const HostFilter(topic: 'breakups').matches(host), isTrue);
      expect(const HostFilter(topic: 'BREAKUP').matches(host), isTrue);
      expect(const HostFilter(topic: 'career').matches(host), isTrue);
      expect(
        const HostFilter(languages: ['Hindi'], topic: 'Stress').matches(host),
        isFalse,
      );
      const f = HostFilter(languages: ['Hindi', 'English'], topic: 'x');
      expect(f.count, 3);
      expect(f.withoutLanguage('hindi').languages, ['English']);
      expect(f.withTopic(null).isActive, isTrue);
      expect(f.withTopic(null).count, 2);
    });

    test('SupportTopic from the interests form', () {
      final topics = SupportTopic.fromForm({
        'questions': [
          {
            'key': 'gender',
            'options': [
              {'label': 'Male', 'value': 'male'},
            ],
          },
          {
            'key': 'support_topic',
            'options': [
              {'label': ' Breakups ', 'value': 'breakup'},
              {'label': 'Breakups', 'value': 'dup'},
              {'label': '', 'value': 'stress'},
              {'label': 'No value'},
            ],
          },
        ],
      });
      expect(topics, const [
        SupportTopic(label: 'Breakups', value: 'breakup'),
        SupportTopic(label: 'stress', value: 'stress'),
      ]);
      expect(SupportTopic.fromForm(null), isEmpty);
      expect(SupportTopic.fromHosts([host]), const [
        SupportTopic(label: 'Breakups', value: 'breakup'),
      ]);
    });

    test('FilterOptions', () {
      expect(FilterOptions.cleanLanguageName('LANG_TAMIL_NADU'), 'TAMIL NADU');
      expect(FilterOptions.cleanLanguageName('language_hindi'), 'hindi');
      expect(FilterOptions.cleanLanguageName(null), '');

      final options = FilterOptions.fromSources(
        languages: const [
          'LANG_Hindi',
          {'label': 'Bengali'},
          {'name': 'Hindi'},
          {'language': ''},
        ],
        topics: const [SupportTopic(label: 'Stress', value: 's')],
      );
      expect(options.languages, ['Bengali', 'Hindi']);
      expect(options.topics, ['Stress']);

      final discover = options.withHosts([host]);
      expect(discover.languages, ['Bengali', 'English', 'Hindi']);
      expect(discover.topics, ['Breakups', 'Stress']);

      final search = options.withHosts([host], includeCategories: true);
      expect(search.topics, ['Breakups', 'Career', 'Dating', 'Stress']);
    });
  });

  group('Discover feed', () {
    Map<String, dynamic> row(int id, {String? doc}) => {
      'id': id,
      'documentId': doc ?? 'exp$id',
      'user': {'id': id * 10, 'documentId': 'usr$id'},
    };

    test('HostPage paging rules', () {
      final withMeta = HostPage.fromResponse(
        {
          'data': [row(1), row(2)],
          'meta': const {
            'pagination': {'page': 1, 'pageCount': 3},
          },
        },
        page: 1,
        pageSize: 16,
      );
      expect(withMeta.hasMore, isTrue);
      expect(withMeta.hosts.map((h) => h.id), [1, 2]);

      final last = HostPage.fromResponse(
        {
          'data': [row(3)],
          'meta': const {
            'pagination': {'page': 3, 'pageCount': 3},
          },
        },
        page: 3,
        pageSize: 16,
      );
      expect(last.hasMore, isFalse);

      final noMeta = HostPage.fromResponse(
        {
          'data': [row(1), row(2)],
        },
        page: 1,
        pageSize: 2,
      );
      expect(noMeta.hasMore, isTrue);
    });

    test('merge keeps order and drops duplicates', () {
      final p1 = HostPage.fromResponse(
        {
          'data': [row(1), row(2)],
        },
        page: 1,
        pageSize: 2,
      );
      final p2 = HostPage.fromResponse(
        {
          'data': [row(2), row(3)],
        },
        page: 2,
        pageSize: 2,
      );
      expect(HostPage.merge([p1, p2]).map((h) => h.id), [1, 2, 3]);
    });

    test('DiscoverTab topic matching', () {
      final host = HostCard.fromJson(expertRow());
      const topics = [SupportTopic(label: 'Heartbreak', value: 'breakup')];

      expect(DiscoverTab.all.matches(host, topics), isTrue);
      // Matched by option value even though the label was reworded.
      expect(
        const DiscoverTab.topic('heartbreak').matches(host, topics),
        isTrue,
      );
      expect(
        const DiscoverTab.topic('Breakups').matches(host, const []),
        isTrue,
      );
      expect(const DiscoverTab.topic('Stress').matches(host, topics), isFalse);

      expect(DiscoverTab.fromParam('Popular'), isNull);
      expect(DiscoverTab.fromParam(' '), isNull);
      expect(
        DiscoverTab.fromParam('Stress'),
        const DiscoverTab.topic('Stress'),
      );
      expect(DiscoverTab.popular.titleKey, 'home:tabs.popular');
      expect(const DiscoverTab.topic('x').titleKey, isNull);
      expect(const DiscoverTab.topic('x').emptyKey, 'home:empty.topic');
    });
  });

  group('hooks', () {
    late _FakeFeed api;
    late DiscoverFeed feed;
    late List<HostCard> visible;

    late HttpClientAdapter original;

    setUpAll(() {
      original = ApiClient.dio.httpClientAdapter;
      ApiClient.dio.interceptors.removeWhere((i) => i is PrettyDioLogger);
    });

    tearDownAll(() => ApiClient.dio.httpClientAdapter = original);

    setUp(() {
      queryCache.clear();
      api = _FakeFeed(pageCount: 2);
      ApiClient.dio.httpClientAdapter = api;
    });

    Future<void> pumpFeed(
      WidgetTester tester, {
      HostFilter filter = HostFilter.none,
    }) async {
      await tester.pumpWidget(
        CacheProvider(
          cache: queryCache,
          child: HookBuilder(
            builder: (context) {
              feed = useDiscoverFeed(context);
              visible = useDiscoverHosts(feed: feed, filter: filter);
              return const SizedBox();
            },
          ),
        ),
      );
      await settle(tester);
    }

    Future<void> unmount(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      queryCache.clear();
      // Let fquery's garbage-collection timers run out.
      await tester.pump(const Duration(minutes: 10));
    }

    testWidgets('pages, then pull-to-refresh starts over at page 1', (
      tester,
    ) async {
      await pumpFeed(tester);
      expect(api.pages, [1]);
      expect(feed.hosts.map((h) => h.id), [1, 2]);
      expect(feed.hasMore, isTrue);

      feed.loadMore();
      await settle(tester);
      expect(api.pages, [1, 2]);
      expect(feed.hosts.map((h) => h.id), [1, 2, 3, 4]);
      expect(feed.hasMore, isFalse);
      expect(feed.isLoadingMore, isFalse);

      // Past the last page: no request.
      feed.loadMore();
      await settle(tester);
      expect(api.pages, [1, 2]);

      var refreshed = false;
      unawaited(feed.refresh().then((_) => refreshed = true));
      await settle(tester);
      expect(refreshed, isTrue);
      expect(api.pages, [1, 2, 1]);
      expect(feed.hosts.map((h) => h.id), [1, 2]);
      expect(feed.hasMore, isTrue);

      await unmount(tester);
    });

    testWidgets('a filter matching too few hosts pulls more pages', (
      tester,
    ) async {
      await pumpFeed(tester, filter: const HostFilter(topic: 'nobody'));
      expect(api.pages, [1, 2]);
      expect(visible, isEmpty);
      expect(feed.hasMore, isFalse);

      await unmount(tester);
    });

    testWidgets('search merges badges and keeps results while typing', (
      tester,
    ) async {
      final term = ValueNotifier('riya');
      late QueryResult<SearchResults, ApiException> search;
      await tester.pumpWidget(
        CacheProvider(
          cache: queryCache,
          child: HookBuilder(
            builder: (context) {
              search = useSearch(context, useValueListenable(term));
              return const SizedBox();
            },
          ),
        ),
      );
      await settle(tester);
      expect(api.searches, ['riya']);
      expect(api.badgeBatches, [
        ['exp-riya'],
      ]);
      final riya = search.data!.experts.single;
      expect(riya.isVerified, isTrue);
      expect(riya.instaVerified, isTrue);

      term.value = 'kabir';
      await tester.pump();
      // The next query is loading: the previous rows stay on screen.
      expect(search.data!.experts.single.name, 'riya');
      expect(search.isFetching, isTrue);

      await settle(tester);
      expect(api.searches, ['riya', 'kabir']);
      expect(search.data!.experts.single.name, 'kabir');
      expect(search.data!.experts.single.instaVerified, isTrue);

      term.value = '  ';
      await tester.pump();
      expect(search.data, isNull);
      expect(api.searches, ['riya', 'kabir']);

      await unmount(tester);
    });
  });
}

/// Lets real async work (Dio, platform channels) and frames interleave.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// `/expert-profiles` feed of two hosts per page.
class _FakeFeed implements HttpClientAdapter {
  _FakeFeed({required this.pageCount});

  final int pageCount;
  final pages = <int>[];
  final searches = <String>[];
  final badgeBatches = <List<String>>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode(_reply(options)),
    200,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  Object _reply(RequestOptions options) {
    final q = options.queryParameters;
    if (options.path.endsWith('/search')) {
      final term = '${q['q']}';
      searches.add(term);
      return {
        'results': {
          'experts': [
            {'documentId': 'exp-$term', 'name': term, 'isVerified': false},
          ],
        },
      };
    }
    if (q.containsKey(r'filters[documentId][$in][0]')) {
      final ids = [
        for (final e in q.entries)
          if (e.key.startsWith(r'filters[documentId][$in]')) '${e.value}',
      ];
      badgeBatches.add(ids);
      return {
        'data': [
          for (final id in ids)
            {
              'documentId': id,
              'expert_verifications': [
                {'Verified_Badge': true, 'insta_verified': true},
              ],
            },
        ],
      };
    }
    final page = int.parse('${q['pagination[page]']}');
    pages.add(page);
    return {
      'data': [
        for (final id in [page * 2 - 1, page * 2])
          {
            'id': id,
            'documentId': 'exp$id',
            'user': {'id': id * 10, 'documentId': 'usr$id'},
          },
      ],
      'meta': {
        'pagination': {'page': page, 'pageCount': pageCount},
      },
    };
  }

  @override
  void close({bool force = false}) {}
}
