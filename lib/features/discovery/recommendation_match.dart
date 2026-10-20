/// Matching Discovery's picks to real recordings, ported from desktop Lokal
/// (`src/recommendations.js`): the same keys, title clean-up and the rule
/// that a match needs both the title and the artist, so a cover, remix or
/// another artist's song never stands in for the one recommended.
library;

/// Precomposed Latin letters and the letter under the accent. Dart has no
/// Unicode normalisation, so this stands in for desktop's NFKD, which drops
/// the marks from Latin letters only ("Beyoncé" is "beyonce", "流線" stays).
const _foldFrom =
    'ÀÁÂÃÄÅÇÈÉÊËÌÍÎÏÑÒÓÔÕÖÙÚÛÜÝàáâãäåçèéêëìíîïñòóôõöùúûüýÿĀāĂăĄąĆ'
    'ćĈĉĊċČčĎďĒēĔĕĖėĘęĚěĜĝĞğĠġĢģĤĥĨĩĪīĬĭĮįİĴĵĶķĹĺĻļĽľŃńŅņŇňŌōŎŏŐő'
    'ŔŕŖŗŘřŚśŜŝŞşŠšŢţŤťŨũŪūŬŭŮůŰűŲųŴŵŶŷŸŹźŻżŽžƠơƯưǍǎǏǐǑǒǓǔǕǖǗǘǙǚǛ'
    'ǜǞǟǠǡǦǧǨǩǪǫǬǭǰǴǵǸǹǺǻȀȁȂȃȄȅȆȇȈȉȊȋȌȍȎȏȐȑȒȓȔȕȖȗȘșȚțȞȟȦȧȨȩȪȫȬȭȮȯ'
    'ȰȱȲȳḀḁḂḃḄḅḆḇḈḉḊḋḌḍḎḏḐḑḒḓḔḕḖḗḘḙḚḛḜḝḞḟḠḡḢḣḤḥḦḧḨḩḪḫḬḭḮḯḰḱḲḳḴḵḶḷ'
    'ḸḹḺḻḼḽḾḿṀṁṂṃṄṅṆṇṈṉṊṋṌṍṎṏṐṑṒṓṔṕṖṗṘṙṚṛṜṝṞṟṠṡṢṣṤṥṦṧṨṩṪṫṬṭṮṯṰṱṲṳ'
    'ṴṵṶṷṸṹṺṻṼṽṾṿẀẁẂẃẄẅẆẇẈẉẊẋẌẍẎẏẐẑẒẓẔẕẖẗẘẙẛẠạẢảẤấẦầẨẩẪẫẬậẮắẰằẲẳẴ'
    'ẵẶặẸẹẺẻẼẽẾếỀềỂểỄễỆệỈỉỊịỌọỎỏỐốỒồỔổỖỗỘộỚớỜờỞởỠỡỢợỤụỦủỨứỪừỬửỮữỰ'
    'ựỲỳỴỵỶỷỸỹ';
const _foldTo =
    'AAAAAACEEEEIIIINOOOOOUUUUYaaaaaaceeeeiiiinooooouuuuyyAaAaAaC'
    'cCcCcCcDdEeEeEeEeEeGgGgGgGgHhIiIiIiIiIJjKkLlLlLlNnNnNnOoOoOo'
    'RrRrRrSsSsSsSsTtTtUuUuUuUuUuUuWwYyYZzZzZzOoUuAaIiOoUuUuUuUuU'
    'uAaAaGgKkOoOojGgNnAaAaAaEeEeIiIiOoOoRrRrUuUuSsTtHhAaEeOoOoOo'
    'OoYyAaBbBbBbCcDdDdDdDdDdEeEeEeEeEeFfGgHhHhHhHhHhIiIiKkKkKkLl'
    'LlLlLlMmMmMmNnNnNnNnOoOoOoOoPpPpRrRrRrRrSsSsSsSsSsTtTtTtTtUu'
    'UuUuUuUuVvVvWwWwWwWwWwXxXxYyZzZzZzhtwysAaAaAaAaAaAaAaAaAaAaA'
    'aAaEeEeEeEeEeEeEeEeIiIiOoOoOoOoOoOoOoOoOoOoOoOoUuUuUuUuUuUuU'
    'uYyYyYyYy';

final Map<int, int> _fold = {
  for (var i = 0; i < _foldFrom.length; i++)
    _foldFrom.codeUnitAt(i): _foldTo.codeUnitAt(i),
};

final _latin = RegExp(r'\p{Script=Latin}', unicode: true);
final _mark = RegExp(r'\p{M}', unicode: true);
final _letter = RegExp(r'\p{L}', unicode: true);
final _notWord = RegExp(r'[^\p{L}\p{M}\p{N}]+', unicode: true);

/// Latin accents dropped, and full-width forms ("ＡＢＣ") read as ASCII.
String foldLatin(String value) {
  final out = StringBuffer();
  var afterLatin = false;
  for (final rune in value.runes) {
    var code = _fold[rune] ?? rune;
    if (code >= 0xff01 && code <= 0xff5e) code -= 0xfee0;
    if (code == 0x3000) code = 0x20;
    final char = String.fromCharCode(code);
    if (afterLatin && _mark.hasMatch(char)) continue;
    afterLatin = _latin.hasMatch(char);
    out.write(char);
  }
  return out.toString();
}

/// Desktop's `recommendationKey`: lower case, Latin accents dropped, anything
/// that isn't a letter or digit a single space.
String recommendationKey(String? value) =>
    foldLatin(value ?? '').toLowerCase().replaceAll(_notWord, ' ').trim();

/// Desktop's `songKey`: one key per artist and title.
String recommendationSongKey(String? artist, String? title) =>
    '${recommendationKey(artist)}\u0000${recommendationKey(title)}';

String _stripFeatured(Match match) {
  final suffix = match[0]!;
  return RegExp(r'\b(?:remix|live|cover)\b').hasMatch(recommendationKey(suffix))
      ? suffix
      : '';
}

// The same recording under another label: "(2011 Remaster)", "- Remastered
// 2003", "- Original Mix", "(Mono)". Live, remix, edit... stay different songs.
const _sameRecording =
    r'(?:(?:\d{4}\s+)?(?:digital(?:ly)?\s+)?remaster(?:ed)?(?:\s+\d{4})?(?:\s+version)?|(?:album|single|mono|stereo|lp)\s+version|original\s+mix|mono|stereo)';
final _sameRecordingBracket = RegExp(
  '\\s*[(\\[]$_sameRecording[)\\]]',
  caseSensitive: false,
);
final _sameRecordingSuffix = RegExp(
  '\\s+[-–—]\\s+$_sameRecording\\s*\$',
  caseSensitive: false,
);
// "[Explicit]", "(Clean Version)": labels of the same recording.
final _contentLabel = RegExp(
  r'\s*[(\[](?:explicit|clean)(?:\s+version)?[)\]]',
  caseSensitive: false,
);
// A credit in brackets or after the name: "[feat. Joi]", "(ft. X)", " feat. Y".
final _featBracket = RegExp(
  r'\s*[(\[](?:feat\.?|ft\.?|featuring|with)\s+[^)\]]*[)\]]',
  caseSensitive: false,
);
final _featSuffix = RegExp(
  r'\s+(?:feat\.?|ft\.?|featuring)\s+.+$',
  caseSensitive: false,
);
final _videoLabel = RegExp(
  r'\s*[(\[](?:official (?:music video|audio|video)|lyrics?|audio|hq|hd|album version|single version)[)\]]',
  caseSensitive: false,
);
final _featBracketStrict = RegExp(
  r'\s*[(\[](?:feat\.?|ft\.?|featuring|with)\s+[^)\]]+[)\]]',
  caseSensitive: false,
);

/// An artist without the guests credited with them: "Estelle [feat. Joi]"
/// is "Estelle".
String mainArtist(String? artist) => (artist ?? '')
    .replaceAll(_featBracket, '')
    .replaceAll(_featSuffix, '')
    .trim();

// Imports flatten semicolon-separated credits into commas. Keep known
// comma-containing artist names intact, including when followed by guests.
const _commaArtists = [
  'Tyler, The Creator',
  'Earth, Wind & Fire',
  'Crosby, Stills, Nash & Young',
  'Crosby, Stills & Nash',
  'Emerson, Lake & Palmer',
];

/// The first credited artist.
String leadArtist(String? artist) {
  final name = mainArtist(artist);
  if (name.contains(';')) return name.split(';').first.trim();
  final lower = name.toLowerCase();
  for (final kept in _commaArtists) {
    final k = kept.toLowerCase();
    if (lower == k || lower.startsWith('$k,')) {
      return name.substring(0, kept.length);
    }
  }
  return name.split(',').first.trim();
}

/// A title to search with: without guests, "[Explicit]" and remaster labels.
/// A remix or live version keeps its label.
String searchTitle(String? title) {
  final raw = title ?? '';
  final clean = raw
      .replaceAll(_contentLabel, '')
      .replaceAll(_sameRecordingBracket, '')
      .replaceAll(_sameRecordingSuffix, '')
      .replaceAllMapped(_featBracket, _stripFeatured)
      .replaceAllMapped(_featSuffix, _stripFeatured)
      .replaceAll(RegExp(r'\s{2,}'), ' ')
      .trim();
  return clean.isEmpty ? raw.trim() : clean;
}

/// The key two titles of the same recording share.
String titleKey(String? title) => recommendationKey(
  (title ?? '')
      .replaceAll(_contentLabel, '')
      .replaceAll(_sameRecordingBracket, '')
      .replaceAll(_sameRecordingSuffix, '')
      .replaceAll(_videoLabel, '')
      .replaceAllMapped(_featBracketStrict, _stripFeatured)
      .replaceAllMapped(_featSuffix, _stripFeatured),
);

final _versionWords = RegExp(
  r'\b(?:remix|live|cover|instrumental|acoustic|karaoke|edit|sped up|slowed|nightcore)\b',
  caseSensitive: false,
);

bool _nonLatinLetters(String value) => value.runes.any((rune) {
  final char = String.fromCharCode(rune);
  return _letter.hasMatch(char) && !_latin.hasMatch(char);
});

/// A title and its explicit bilingual aliases, e.g. "流線 - ryusen".
List<String> recommendationTitles(String? title) {
  final original = (title ?? '').trim();
  final parts = original
      .split(RegExp(r'\s+[-–—|/]\s+'))
      .map((part) => part.trim())
      .toList();
  if (parts.length != 2 ||
      _versionWords.hasMatch(original) ||
      _nonLatinLetters(parts[0]) == _nonLatinLetters(parts[1]) ||
      !parts.any((part) => !_nonLatinLetters(part) && _latin.hasMatch(part))) {
    return [original];
  }
  return [
    original,
    ...parts.where((part) => !_nonLatinLetters(part)),
    ...parts.where(_nonLatinLetters),
  ];
}

/// A song to find, or a search result to check.
class RecommendationCandidate {
  const RecommendationCandidate({
    required this.title,
    required this.artist,
    this.album,
    this.duration,
    this.youtube = false,
  });

  final String title;
  final String artist;
  final String? album;
  final Duration? duration;

  /// A YouTube upload, whose title may carry the artist ("Artist - Song").
  final bool youtube;
}

/// Up to six searches for [candidate]: clean names first, then as given.
List<String> recommendationQueries(RecommendationCandidate candidate) {
  final artist = candidate.artist.trim();
  final names = <String>{
    for (final name in [leadArtist(artist), mainArtist(artist), artist])
      if (name.isNotEmpty) name,
  };
  final titles = <String>{
    ...recommendationTitles(searchTitle(candidate.title)),
    ...recommendationTitles(candidate.title),
  };
  return <String>{
    for (final title in titles)
      for (final name in names) '$name $title'.trim(),
  }.take(6).toList();
}

bool _matchingDuration(Duration? expected, Duration? actual) =>
    expected == null ||
    actual == null ||
    expected <= Duration.zero ||
    actual <= Duration.zero ||
    (expected - actual).abs() <= const Duration(seconds: 10);

/// The first of [results] that is [candidate]'s song: the same title (or an
/// alias) by the same artist, within ten seconds when both lengths are
/// known. A match from the same album comes first.
T? recommendationMatch<T>(
  RecommendationCandidate candidate,
  Iterable<T> results,
  RecommendationCandidate Function(T result) describe,
) {
  final titles = recommendationTitles(candidate.title).map(titleKey).toList();
  final artist = recommendationKey(candidate.artist);
  if (titles.first.isEmpty || artist.isEmpty) return null;
  String clean(String key) => key.replaceFirst(RegExp(r' topic$'), '');
  final artistKeys = <String>{
    artist,
    clean(recommendationKey(leadArtist(candidate.artist))),
    recommendationKey(mainArtist(candidate.artist)),
  }..remove('');
  bool sameArtist(String? name) =>
      artistKeys.contains(clean(recommendationKey(mainArtist(name))));
  final matches = <(T, String?)>[];
  for (final result in results) {
    final found = describe(result);
    if (!_matchingDuration(candidate.duration, found.duration)) continue;
    final name = found.title;
    final prefix = RegExp(r'^(.+?)\s+[-–—|]\s+(.+)$').firstMatch(name);
    final suffix = RegExp(r'^(.+)\s+[-–—|]\s+(.+)$').firstMatch(name);
    final prefixedArtist = prefix != null && sameArtist(prefix[1]);
    final suffixedArtist =
        found.youtube && suffix != null && sameArtist(suffix[2]);
    final resultTitle = prefixedArtist
        ? prefix[2]!
        : suffixedArtist
        ? suffix[1]!
        : name;
    if (!recommendationTitles(resultTitle).map(titleKey).any(titles.contains)) {
      continue;
    }
    // Video uploaders need not be the performer: only an explicit
    // artist/title pair counts there.
    if (found.youtube && (prefixedArtist || suffixedArtist)) {
      matches.add((result, found.album));
      continue;
    }
    if (sameArtist(found.artist) || sameArtist(leadArtist(found.artist))) {
      matches.add((result, found.album));
    }
  }
  if (matches.isEmpty) return null;
  final album = recommendationKey(candidate.album);
  if (album.isNotEmpty) {
    for (final (result, other) in matches) {
      if (recommendationKey(other) == album) return result;
    }
  }
  return matches.first.$1;
}
