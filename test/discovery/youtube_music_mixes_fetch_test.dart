import 'dart:convert';

import 'package:flick/features/discovery/youtube_music_account.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, Object?> signed(Map<String, Object?> body) => {
  'responseContext': {
    'mainAppWebResponseContext': {'loggedOut': false},
  },
  ...body,
};
Map<String, Object?> card(String id, String title) => {
  'musicTwoRowItemRenderer': {
    'title': {
      'runs': [
        {'text': title},
      ],
    },
    'thumbnailOverlay': {
      'musicItemThumbnailOverlayRenderer': {
        'content': {
          'musicPlayButtonRenderer': {
            'playNavigationEndpoint': {
              'watchPlaylistEndpoint': {'playlistId': id},
            },
          },
        },
      },
    },
  },
};
YoutubeMusicAccount account(http.Client client) => YoutubeMusicAccount(
  client,
  const YoutubeMusicSession(cookies: {'SAPISID': 'fixture-signing-cookie'}),
);
void main() {
  test('refresh reads current page context and mixes embedded in the signed-in home page', () async {
    forgetYoutubeMusicAccount();
    addTearDown(forgetYoutubeMusicAccount);
    var revision = 1, pageReads = 0;
    final client = MockClient((request) async {
      if (request.method == 'GET') {
        pageReads++;
        final initial = signed({
          'musicCarouselShelfRenderer': {
            'header': {
              'musicCarouselShelfBasicHeaderRenderer': {
                'title': {
                  'runs': [
                    {'text': 'Mixed for you'},
                  ],
                },
              },
            },
            'contents': [card('RDTMAKfixture123', 'Mix $revision { \" }')],
          },
        });
        return http.Response(
          '<script>ytcfg.set(${jsonEncode({'INNERTUBE_CLIENT_VERSION': '1.current', 'VISITOR_DATA': 'fresh-visitor'})}); var ytInitialData = ${jsonEncode(initial)};</script>',
          200,
        );
      }
      final body = jsonDecode(request.body) as Map;
      expect((body['context'] as Map)['client']['clientVersion'], '1.current');
      expect(request.headers['x-youtube-client-version'], '1.current');
      return http.Response(jsonEncode(signed({})), 200);
    });
    addTearDown(client.close);
    final source = account(client);
    final first = await loadYoutubeMusicDiscovery(source);
    expect(first.mixes!.single.title, startsWith('Mix 1'));
    revision = 2;
    final refreshed = await loadYoutubeMusicDiscovery(source, force: true);
    expect(refreshed.mixes!.single.title, startsWith('Mix 2'));
    expect(pageReads, 2);
  });

  test(
    'mix cards can expose their playlist only on the artwork play button',
    () {
      final parsed = parseYoutubeMusicMixes({
        'musicCarouselShelfRenderer': {
          'header': {
            'musicCarouselShelfBasicHeaderRenderer': {
              'title': {
                'runs': [
                  {'text': 'Mixed for you'},
                ],
              },
            },
          },
          'contents': [card('RDTMAKfixture123', 'Supermix')],
        },
      });
      expect(parsed.single.id, 'RDTMAKfixture123');
    },
  );
  test(
    'an empty mix shelf loads its own chained continuation without a header',
    () async {
      final tokens = <String>[];
      final client = MockClient((request) async {
        final body = jsonDecode(request.body) as Map;
        final continuation = body['continuation'];
        if (continuation != null) {
          tokens.add(continuation as String);
          if (continuation == 'first')
            return http.Response(
              jsonEncode(
                signed({
                  'continuationContents': {
                    'musicCarouselShelfContinuation': {
                      'contents': [card('RDTMAKfixture123', 'Supermix')],
                      'continuations': [
                        {
                          'nextContinuationData': {'continuation': 'second'},
                        },
                      ],
                    },
                  },
                }),
              ),
              200,
            );
          return http.Response(
            jsonEncode(
              signed({
                'onResponseReceivedActions': [
                  {
                    'appendContinuationItemsAction': {
                      'continuationItems': [
                        card('RDTMAKfixture456', 'My Mix 1'),
                      ],
                    },
                  },
                ],
              }),
            ),
            200,
          );
        }
        if (body['browseId'] == 'FEmusic_home')
          return http.Response(
            jsonEncode(
              signed({
                'musicCarouselShelfRenderer': {
                  'header': {
                    'musicCarouselShelfBasicHeaderRenderer': {
                      'title': {
                        'runs': [
                          {'text': 'Mixed for you'},
                        ],
                      },
                    },
                  },
                  'contents': [
                    {
                      'continuationItemRenderer': {
                        'continuationEndpoint': {
                          'commandExecutorCommand': {
                            'commands': [
                              {
                                'continuationCommand': {'token': 'first'},
                              },
                            ],
                          },
                        },
                      },
                    },
                  ],
                },
              }),
            ),
            200,
          );
        return http.Response(jsonEncode(signed({})), 200);
      });
      addTearDown(client.close);
      final result = await account(client).fetch();
      expect(result.mixes.map((m) => m.title), ['Supermix', 'My Mix 1']);
      expect(tokens, ['first', 'second']);
      expect(result.mixError, isNull);
    },
  );
  test(
    'More shelf continuation retains the personal mix browse parameters',
    () async {
      var continued = false;
      final client = MockClient((request) async {
        final body = jsonDecode(request.body) as Map;
        if (body['browseId'] == 'FEmusic_home')
          return http.Response(
            jsonEncode(
              signed({
                'musicCarouselShelfRenderer': {
                  'header': {
                    'musicCarouselShelfBasicHeaderRenderer': {
                      'title': {
                        'runs': [
                          {'text': 'Mixed for you'},
                        ],
                      },
                      'moreContentButton': {
                        'buttonRenderer': {
                          'navigationEndpoint': {
                            'browseEndpoint': {
                              'browseId': 'FEpersonal_mixes',
                              'params': 'personal-filter',
                            },
                          },
                        },
                      },
                    },
                  },
                  'contents': [],
                },
              }),
            ),
            200,
          );
        if (body['browseId'] == 'FEpersonal_mixes') {
          expect(body['params'], 'personal-filter');
          if (body['continuation'] == 'more') {
            continued = true;
            return http.Response(
              jsonEncode(
                signed({
                  'gridContinuation': {
                    'items': [card('PLpersonal123', 'Personal mix')],
                  },
                }),
              ),
              200,
            );
          }
          return http.Response(
            jsonEncode(
              signed({
                'gridRenderer': {
                  'continuations': [
                    {
                      'nextContinuationData': {'continuation': 'more'},
                    },
                  ],
                },
              }),
            ),
            200,
          );
        }
        return http.Response(jsonEncode(signed({})), 200);
      });
      addTearDown(client.close);
      final result = await account(client).fetch();
      expect(continued, isTrue);
      expect(result.mixes.single.id, 'PLpersonal123');
    },
  );
}
