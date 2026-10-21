# Konnekted2 feature parity

This is the implementation ledger for the Flutter fusion. A feature is marked
**delivered** only when it has a real code path and a focused automated check.
"Inherited" means the Flick implementation is present in this repository; it
does not mean a USB DAC or every Android OEM has been tested here.

## Konnekted / `flow-feature`

| Area | Status | Evidence / boundary |
| --- | --- | --- |
| Flow unlock at 16 favorites | Delivered | `lib/features/flow/domain/`, `test/flow/` |
| Flow mood pills and tuner | Delivered | Draft-until-Apply tuner, genre exclusion and discovery/memory axes |
| Persistent Flow session, bans and refresh | Delivered | Versioned store; partial/corrupt data is handled explicitly |
| Flow save as a local playlist | Delivered | Uses inherited `PlaylistService`, not a second playlist database |
| Local songs, albums, artists, folders | Inherited | Flick screens, Isar repository and scanner |
| Favorites and recent history | Inherited / shell integrated | Real providers feed Listen and Library |
| Local playlist creation, editing, M3U import/export | Inherited | `PlaylistService` and playlist screens |
| Playlist links and refresh | Delivered | Spotify public embed and YouTube Music browse; preview, partial safety, matching, refresh, unlink |
| Spotify OAuth and library | Delivered | PKCE, secure tokens, paginated Web API, playlist import, bounded retry |
| Spotify Liked Songs → local likes | Delivered | Explicit one-way sync, strict title/artist/duration matching, readback verification |
| YouTube Music catalog search | Delivered | Explicit guest catalog search; opens canonical source page |
| Authorized addon search/playback | Delivered | Opt-in HTTPS manifest/search/stream subset; bounded staging and native probe |
| Ordered multi-addon source registry | Delivered | Up to eight named sources; secure v1 migration; draft-only edit/reorder/enable/remove; source-bound credentials and stale-row refusal; `test/discovery/` |
| YouTube Music account sign-in/personalized shelves | Delivered | Opt-in in-app WebView session import, secure session storage, account shelves and local/add-on playback matching |
| Listen Together / jam invite links | Not yet ported | Requires a listener-owned realtime coordination service and lifecycle design; no fake local-only “sync” control is exposed |
| Classipod click-wheel shell and Cover Flow | Delivered local-library slice | Library entry; accessible wheel, songs/albums/artists, real shared playback/queue, Cover Flow-like artwork; 20 host tests; broader Kotlin/provider parity not claimed |
| Spotify/Tidal/Apple/community animated canvas providers | Partial | Flick animated artwork/theming is inherited; the full Konnekted provider precedence and canvas cache are not yet ported |
| JioSaavn / Octave / FLAC-downloader source resolver modules | Partial | Ordered listener-owned addon registry is implemented; provider adapters, cross-source matching and quality fallback graph remain unported |
| Subsonic / Jellyfin / WebDAV / SMB / UPnP | Inherited | Existing Flick network-source services and settings |
| Tidal device flow/source | Inherited | Existing Flick Tidal service; account/source behavior remains opt-in |
| Last.fm / ListenBrainz | Inherited | Existing scrobble providers and background queue flush |
| Discord Rich Presence | Inherited | Existing integration service; metadata uses actual player diagnostics |
| Chromecast / DLNA / UPnP casting | Inherited | Existing Android/native and Dart cast paths |
| Widgets and media notification | Inherited / shell preserved | Runtime mounts widget sync, intents and foreground playback |
| Lyrics search, synced words, translation/editor | Inherited | Existing lyric providers and player screens |
| Animated artwork, dynamic theming, recaps, stats | Inherited | Existing services/screens; not removed by the new shell |
| Automix, crossfade, gapless, skip silence, sleep timer | Inherited | Existing PlayerService/native audio path |
| Quality ceilings, downloads and offline cache | Inherited | Existing quality/download services; online discovery is separate and honest about limits |

## Flick audio and library architecture

| Capability | Status |
| --- | --- |
| Rust engine via `flutter_rust_bridge` | Inherited and build-wired |
| Symphonia decoding and metadata probing | Inherited |
| USB UAC 2.0 direct output | Inherited; requires physical DAC validation |
| Native DSD and DoP paths | Inherited; requires physical DAC validation |
| DAP hi-res Oboe/AAudio exclusive output | Inherited; requires target-DAP validation |
| DSP: 31-band EQ, dynamics, convolution, crossfade/gapless | Inherited; DSP is intentionally not bit-perfect |
| Bit-perfect safeguards | Inherited and preserved | Protected volume tiers and output diagnostics prevent unsupported software gain on wire DSD/passthrough |
| MediaStore/SAF and full-storage flavor | Inherited and build-wired | `play` omits All Files Access; `full` includes it |
| Metadata editing, CUE/EAC, duplicate detection, artwork | Inherited |

## Required Flick baseline

These are the capabilities that must remain part of the Konnekted product
baseline. The status describes source-backed behavior; **hardware-unverified**
does not mean a USB DAC, Bluetooth codec, receiver, or background route has
passed on a physical phone.

| Capability | Status | Boundary |
| --- | --- | --- |
| Preload library analysis/cache | Delivered | Caches waveform/loudness/artwork analysis; it is not a decoded playback-buffer cache |
| ReplayGain | Delivered | Local PCM tag/analysis paths; DSD/DFF/WavPack and network-source scans need separate validation |
| Remove duplicates | Partial | Groups by normalized title/artist and removes library rows; it does not delete files or fingerprint audio |
| Scanning settings | Delivered | Filters, deep scan, M3U import, and preload preference are persisted and routed through Android scan engines |
| Preload audio data after scanning | Delivered | The setting now schedules the shared preload pass for Rust, MediaStore, and SAF scan paths; `content://` and unsupported formats remain explicit skips |
| Network sources / remote libraries | Delivered | Subsonic, Jellyfin, WebDAV, SMB, UPnP, and Tidal source paths are opt-in; live server coverage remains device/integration work |
| Gapless playback | Partial | Same-rate buffered paths work; bit-perfect, raw-DSD, and incompatible-rate transitions intentionally renegotiate |
| Background playback anchor | Partial | Wired/speaker route pinning exists; Bluetooth and OEM background-kill behavior require device validation |
| Motion art during bit-perfect playback | Partial / opt-in | Suppressed by default to protect direct output; the opt-in path requires USB/DAP validation |
| USB audio UAC2 | Hardware-unverified | Native discovery, negotiation, stream, volume, and recovery paths exist; requires a real UAC2 DAC |
| Bluetooth Hi-Res direct | Partial / hardware-unverified | Engine and codec preference paths exist, but OEM codec negotiation is not guaranteed by the app |
| Bluetooth low latency | Partial / hardware-unverified | Preference/routing path exists; measured latency and dropout targets are not yet proven |
| Casting | Partial / hardware-unverified | Chromecast/DLNA discovery, transport, and controls exist; real receiver queue/disconnect behavior remains to test |
| Two-way remote with Lokal | Delivered | Authenticated HTTP LAN state polling and commands, secure credentials, reconnect backoff and stale-state suppression; mDNS pairing and stronger multi-client revisions remain outside this slice |

## Explicit non-claims

- Spotify metadata is not Spotify audio. Imported playlist entries must match
  local files before they can play.
- YouTube catalog results are not stream extraction. The app opens YouTube
  Music externally unless the user configures an authorized addon.
- A source's word “lossless”, sample rate or bit depth is never accepted as
  proof. The local/native probe and the selected output route decide what is
  verified.
- Automated checks use fake transports and controller seams. They do not prove
  native output on a specific phone, DAC, DAP, Android version or USB cable.

## Remaining work for full parity

Remaining gaps include unported product features and real-device validation:

1. Extend the Lokal remote with mDNS pairing and stronger multi-client
   revision/acknowledgement semantics.
2. Harden duplicate removal with duration/content identity checks and an
   explicit library-only versus filesystem-delete choice.
3. Validate preload cache hits through MediaStore/SAF, including removable
   storage and unsupported-format behavior.
4. Port the remaining source-backed features above: Listen Together, provider
   canvas precedence, and the Konnekted source registry/fallback graph.
5. Update inherited localization/tutorial copy from Flick to Konnekted.
6. Run the Spotify OAuth flow with a registered Spotify developer app and an
   authorized account.
7. Run linked-playlist refresh against real public Spotify/YouTube playlists;
   both providers can change undocumented web response shapes.
8. Validate each native output mode on real USB DACs and DAPs, including volume
   rejection, DoP/native DSD, route changes, Bluetooth codecs/latency,
   background playback and widgets.
9. Add design assets and a release signing configuration outside the repository;
   signing material must never be committed.

### Discord Rich Presence

Android integration adapted from Mornye’s official Social SDK bridge is prepared, opt-in under Online sources → Accounts. Lokal application ID is configured; the verified SDK is encrypted in the repository and staged by signed build workflows using an Actions secret. SDK-enabled native bridge compiles/links for both ARM ABIs. APK/device behavior is not yet validated. See [setup and limitations](DISCORD_PRESENCE.md).
