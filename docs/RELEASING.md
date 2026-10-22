# Android stable releases and nightlies

## Two deliberate flows

- **Release Lokal Mobile** (`android-release.yml`): run manually from **main**.
  The version comes from `pubspec.yaml` (prepared for **1.0.0+1000**). Choose
  `full`, `play` or `both`; `full` is the default. Leave versionCode blank.
  **Draft** defaults to true so you can review the generated notes and assets
  before publishing. Uncheck it only when you want immediate stable publication.
  Matching stable `vMAJOR.MINOR.PATCH` tag pushes also publish; the tag must point
  into trusted main history and match pubspec. Prerelease tags do not trigger it.
- **Build Lokal Mobile Nightly** (`android-nightly.yml`): run manually from main.
  It publishes an immutable prerelease such as `v1.0.0-nightly.1`. Once `v1.0.0`
  exists, the next nightly is `1.0.1-nightly.N`. A rerun has `.rATTEMPT` appended
  to avoid overwriting an earlier nightly. It never receives the latest label.

The old merge-triggered beta publisher is removed. Branch/PR CI is unchanged;
merging code does not publish a beta, nightly or stable APK. The shared
`android-signed-build.yml` is called by these two flows, not run manually.

```sh
gh workflow run android-release.yml --ref main -f flavor=full -f draft=true
gh workflow run android-nightly.yml --ref main -f flavor=full
```

The first stable is **1.0.0**. For the next stable, update pubspec in a reviewed
PR, merge it, then run the stable workflow. There is no automatic version-bump PR
and no release on version-bump merge. Workflows must be merged to main before
GitHub exposes their Run workflow buttons. Do not run either flow merely to
validate this configuration: doing so builds and creates a real GitHub release.

## Signing, updates and version codes

Both channels keep the existing `com.lokalkonnekt.konnekted2` identity and the
same permanent key. Existing signing secrets remain:

| Actions secret | Purpose |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Base64 of the backed-up permanent JKS/PKCS12 key |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password |
| `ANDROID_KEY_ALIAS` | Signing alias |
| `ANDROID_KEY_PASSWORD` | Key password |
| `LOKAL_DISCORD_SDK_PASSPHRASE` | Unlock the pinned SDK bundle already used by releases |

Never replace the key to fix a build. Signing files are ephemeral and removed
on success/failure. APK signature, package, version, both ARM ABIs, required
native libraries and notices are verified before upload. Each APK contains
**arm64-v8a and armeabi-v7a**, with a checksum and non-secret certificate metadata.

Independent stable/nightly run counters must not be Android version codes.
Both flows now share a UTC clock: `seconds since 2020-01-01 + 100000`, at least
the pubspec build baseline, and share one concurrency group. Metadata is computed
once and handed unchanged to both flavor builders. Later builds therefore update
earlier signed beta/stable/nightly installations without counter collisions.
A manual override must be positive, at least this default, and at most
2,100,000,000. If you deliberately jump ahead, raise the pubspec baseline to
match before making another automatically numbered build. Reruns calculate a
fresh code; existing releases are refused rather than overwritten.

The channels share app data and cannot coexist as separate installations.
Android refuses a lower versionCode even if its human version says stable:
a newer nightly may require waiting for a later stable build to switch back.
No package-name or signature migration is introduced here.

## Banners and notes

`tool/render_release_banner.py` creates a PNG using bundled, licensed fonts and
the checked-in mobile icon. Stable is teal; nightly is coral, distinct from
desktop's lime/violet. Pillow is pinned in `tool/requirements-release-art.txt`;
no Playwright, browser, external rendering page or web-font request is needed.
The prepare job renders with a read-only token. The publish job stores the PNG
on `release-banners` and links its immutable commit URL, so draft previews work
before release assets become public. It also attaches `release-banner.png`.
The publish job runs fixed shell commands rather than checked-out project scripts.

GitHub generates change notes from the previous stable version tag, excluding
beta/nightly tags as the baseline. SHA-256 checksums cover the APKs; certificate
metadata identifies their signing key. Stable drafts are reviewed/published in
Releases; published stable builds are marked latest. No Discord/webhook messages
are sent by these workflows.

## Build performance and checks

Both flows reuse the existing pinned Android toolchain and Cargo dependency
caches (including their `beta-tools-v1`/`beta-rust-v1` cache namespaces), with
fingerprint/lockfile validation. No signed APKs or signing material are cached.
The first run or a toolchain change can still require a cold native build.
Normal CI remains independent; release builds do not rebuild all debug flavors
and rerun CI before compiling the signed artifact. Flutter/Rust/Gradle remain
pinned as documented in [BUILD.md](BUILD.md).

Fast configuration validation: release-helper unit tests, workflow YAML/action
lint and local banner/demo renders. No Actions run, APK build, tag, release or
repository secret is created as part of preparing this PR. Actual signing,
publication permissions and Android updates require the first intentional run.

## README visuals

The hero/release previews use the same renderer. Home and Library images are
rendered from real widgets with a fictional library and procedural cover art:

```sh
python3 -m pip install -r tool/requirements-release-art.txt
python3 tool/render_release_banner.py --demo-covers /tmp/lokal-readme-covers
flutter test tool/render_readme_test.dart
```

They are UI illustrations with demo data, not device/hardware-validation evidence.

## Beta updates

Previously, the beta workflow built `--debug` on a fresh runner. Each run could
create a different `~/.android/debug.keystore`, and the workflow did not retain
that keystore. Consequently beta 30 and beta 40 could have different signing
certificates even though their package name matched. An APK contains the public
certificate, not the private key needed to make a compatible update. A retained
old key must also be reused as the permanent signing identity to preserve that
installation's update path.

If the installed beta's original key was not backed up, it cannot receive an
in-place update signed by the new permanent key. Back up app data and any files
stored in app-private storage before a one-time uninstall/reinstall of the first
signed beta. Later signed betas built with that same key can update in place.
This change does not recover or rotate an existing key, uninstall an app, change
its data, or retroactively replace old release assets.
