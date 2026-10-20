import 'package:flick/features/discovery/recommendation_match.dart';
import 'package:flutter_test/flutter_test.dart';

RecommendationCandidate _song(
  String artist,
  String title, {
  String? album,
  int? seconds,
  bool youtube = false,
}) => RecommendationCandidate(
  title: title,
  artist: artist,
  album: album,
  duration: seconds == null ? null : Duration(seconds: seconds),
  youtube: youtube,
);

RecommendationCandidate? _match(
  RecommendationCandidate wanted,
  List<RecommendationCandidate> results,
) => recommendationMatch(wanted, results, (result) => result);

void main() {
  test('keys drop Latin accents and punctuation but keep other scripts', () {
    expect(recommendationKey('Beyoncé — Halo!'), 'beyonce halo');
    expect(recommendationKey('ＡＢＣ'), 'abc');
    expect(recommendationKey('流線 - ryusen'), '流線 ryusen');
    expect(recommendationKey('Sigur Rós'), 'sigur ros');
  });

  test('titles lose guests and remaster labels, not versions', () {
    expect(searchTitle('American Boy (feat. Kanye West)'), 'American Boy');
    expect(searchTitle('Song (Remix) feat. X'), 'Song (Remix)');
    expect(searchTitle('Song (with X Remix)'), 'Song (with X Remix)');
    expect(titleKey('Hey Jude - Remastered 2015'), 'hey jude');
    expect(titleKey('Hey Jude [Explicit]'), 'hey jude');
    expect(titleKey('Hey Jude (Live)'), isNot('hey jude'));
    expect(mainArtist('Estelle [feat. Joi]'), 'Estelle');
    expect(leadArtist('Tyler, The Creator, Kali Uchis'), 'Tyler, The Creator');
    expect(leadArtist('A; B'), 'A');
  });

  test('bilingual titles match either name', () {
    expect(recommendationTitles('流線 - ryusen'), [
      '流線 - ryusen',
      'ryusen',
      '流線',
    ]);
    expect(
      _match(_song('Artist', '流線'), [_song('Artist', '流線 - ryusen')]),
      isNotNull,
    );
  });

  test('a match needs the title and the artist', () {
    final wanted = _song('Estelle', 'American Boy');
    final right = _song(
      'Estelle feat. Kanye West',
      'American Boy (feat. Kanye West)',
    );
    expect(
      _match(wanted, [_song('Someone Else', 'American Boy'), right]),
      right,
    );
    expect(_match(wanted, [_song('Estelle', 'American Boy (Live)')]), isNull);
    expect(_match(wanted, [_song('Estelle', 'Grateful')]), isNull);
  });

  test('the same album wins, and lengths must agree when known', () {
    final wanted = _song('A', 'Song', album: 'First', seconds: 200);
    final compilation = _song('A', 'Song', album: 'Hits', seconds: 201);
    final album = _song('A', 'Song', album: 'First', seconds: 199);
    expect(_match(wanted, [compilation, album]), album);
    expect(_match(wanted, [_song('A', 'Song', seconds: 260)]), isNull);
  });

  test('YouTube uploads count only with the artist in the title', () {
    final wanted = _song('Daft Punk', 'One More Time');
    final upload = _song(
      'Some Channel',
      'Daft Punk - One More Time',
      youtube: true,
    );
    expect(_match(wanted, [upload]), upload);
    expect(
      _match(wanted, [_song('Some Channel', 'One More Time', youtube: true)]),
      isNull,
    );
  });

  test('queries try clean names first', () {
    final queries = recommendationQueries(
      _song('Estelle [feat. Kanye West]', 'American Boy (feat. Kanye West)'),
    );
    expect(queries.first, 'Estelle American Boy');
    expect(queries.length, lessThanOrEqualTo(6));
  });
}
