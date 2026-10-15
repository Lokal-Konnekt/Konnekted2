# Konnekted2

[![Android CI](https://github.com/Lokal-Konnekt/Konnekted2/actions/workflows/android-ci.yml/badge.svg)](https://github.com/Lokal-Konnekt/Konnekted2/actions/workflows/android-ci.yml)

**Android preview / work in progress.** Source is available here; features and
native output still require the validation described below.

Konnekted2 is a local-first Android music player that fuses Konnekted's
editorial, personal music experience with Flick's native audio architecture.
It is built around a Flutter/Riverpod/Isar UI, a Rust decoding and DSP engine,
Android MediaSession/background playback, and direct UAC 2.0 output where the
device and DAC support it.

## Product shape

- **Listen**: artwork-led home, recent plays, favorites, Flow and the live mini
  player.
- **Explore**: explicit opt-in YouTube Music catalog search and listener-owned
  HTTPS addon sources. No hidden proxy pool, account token or fake quality
  metadata.
- **Library**: songs, albums, artists, folders, favorites, playlists, recent
  collections, playlist links, Spotify import/sync and the Classipod player mode.
- **Settings**: audio/DSP, 31-band EQ, USB output diagnostics, lyrics, library,
  network sources, casting and inherited integrations.

See [docs/FEATURE_PARITY.md](docs/FEATURE_PARITY.md) for the source-backed
feature ledger and [docs/BUILD.md](docs/BUILD.md) for setup, build commands and
the hardware validation checklist.

## Build APKs on GitHub

Open **Actions → Android release → Run workflow**, choose `full`, `play`, or
`both`, and run from `main`. A successful run provides signed APKs and SHA-256
checksums as downloadable artifacts. Version tags (`v*`) also publish release
assets after all checks pass. See [docs/RELEASING.md](docs/RELEASING.md) for the
one-time signing setup, versioning rules, and release instructions.

## Important audio distinction

Konnekted exposes native/bit-perfect paths and a full DSP chain, but they are
different modes. EQ, dynamics, convolution, crossfade and software gain alter
samples. The output diagnostics and volume state machine keep passthrough and
wire DSD protected rather than silently applying those operations.

## License

The combined application is GPL-3.0. MIT-derived Flick material retains its
original notice in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Do not
commit signing material, tokens or local SDK configuration.
