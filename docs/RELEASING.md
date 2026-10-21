# Android CI and releases

## What runs

`Android CI` runs on branch pushes and pull requests, including forks, with a
read-only token and no signing secrets. Required checks are **Focused Flutter
regressions** and **Native source and Android build**. They run the focused
command in `BUILD.md` (including share/picker tests), host Rust library tests,
both debug flavors, and `verifyBuiltInKotlin`. Debug APKs use development signing;
they are not production-signed releases. Failures stop the workflow. The live
catalog test retains its existing opt-in skip. This does not claim the full
inherited Flutter suite or physical-device audio checks pass.

`Android release` repeats those checks before signing. Manual runs must select
`main`; choose `full`, `play`, or `both`. Each flavor produces one APK containing
**arm64-v8a and armeabi-v7a**, a checksum file, and non-secret build metadata.
Manual runs upload Actions artifacts for 14 days and never create a public
GitHub Release. `v*` tag pushes build both flavors and publish only after all
checks, signatures, APK versions, native ABI presence, and checksums pass.
Tags must point to a commit reachable from `main`. Existing releases are not
overwritten; a rerun of an already-published tag fails publication deliberately.

## One-time repository setup

1. Import all source, vendored native sources, Gradle wrapper (including JAR),
   fonts/assets, `pubspec.lock`, and `rust/Cargo.lock`; enable GitHub Actions on
   `Lokal-Konnekt/lokal-mobile`. The workflows must exist on `main` for dispatch.
2. Use GitHub-hosted `ubuntu-24.04` runners and permit the SHA-pinned checkout,
   setup-java, flutter-action, setup-android, upload/download-artifact actions.
   Outbound access to Google/Flutter, Maven/Gradle, Pub, Rust/crates.io, GitHub,
   Adoptium and Ubuntu packages is required. No restored native build cache is
   used. Allow up to 120 minutes for each native/release job.
3. Configure main-branch protections and a `v*` tag ruleset so only release
   maintainers can create tags and tags cannot be updated/deleted. The ancestry
   check supplements these controls; it cannot protect a workflow that an
   untrusted tag author has rewritten. Require the two CI checks above.
4. A maintainer creates and backs up the user-authorized dedicated Android key.
   Preserve it for updates; `full` and `play` share an application ID and key.
   Add these four repository **Actions secrets** (never repository files):

   | Secret | Value |
   | --- | --- |
   | `ANDROID_KEYSTORE_BASE64` | Base64 of the dedicated JKS/PKCS12 keystore |
   | `ANDROID_KEYSTORE_PASSWORD` | Keystore password |
   | `ANDROID_KEY_ALIAS` | Signing entry alias |
   | `ANDROID_KEY_PASSWORD` | Signing entry password |

   Encode the keystore locally into the secret input; Linux `base64 -w0` avoids
   wrapping, and the helper also accepts wrapped base64. Do not paste passwords
   in shell arguments/history or logs. Missing secrets fail by **name only**.

Signing material is decoded only during the build into
`$RUNNER_TEMP/konnekted-signing` (directory `0700`, key `0600`). Gradle reads the
temporary path and password environment variables directly. The helper removes
the key on success/failure, and an `always()` step repeats cleanup. Only APKs,
checksums and metadata are uploaded. No CI `key.properties` is generated. The
signer certificate is compared with the dedicated key before upload; there is
no debug-signing fallback. The build jobs have only `contents: read`; only the
separate trusted-tag publish job gets `contents: write`, and it executes no
checked-out project code.

## Toolchain and clean checkout

Pinned: Flutter **3.47.1**, Dart **3.13.1**, Rust **1.98.0**, Temurin
**17.0.17+10**, Android CLI **15859902**, platform **37.0** (API 37), build tools
**36.0.0**, NDK **28.2.13676358**, and CMake **3.22.1**. Platforms 35/36 support
plugin compile SDKs. Gradle **9.8.1** plus its distribution SHA-256, AGP **9.4.1**,
Compose **2.4.21**, and `android.builtInKotlin=true` come from the checked-in
Android configuration. Action release refs were resolved read-only with `gh`
and pinned to their full commit SHAs.

The setup action isolates SDK, Gradle, Pub, Cargo and Rustup state under
`RUNNER_TEMP`. It creates the `android-37` SDK alias and discovers a loadable
**host** `libclang.so`; the NDK clang executable is not a libclang replacement.
Ubuntu dependencies include libclang, clang, cmake, ninja, pkg-config, ALSA,
udev, libusb, autoconf, automake and libtool development tools/libraries.
Cargokit calls `rustup run stable` explicitly, so only the fresh job-local
Rustup directory aliases `stable` to 1.98.0. Android Rust targets include arm64,
armv7 and both emulator ABIs, because debug Cargokit adds x86/x86_64 itself.
The Rust audio/USB engine is compiled from source with default features enabled;
no native-task bypass or precompiled engine substitution is used. Third-party
Flutter plugins retain their normal upstream dependency setup (including Rive).

Dependency resolution enforces `pubspec.lock`, host Cargo uses `--locked`, and
jobs reject changes to the root Pub/Rust locks after builds. Reproducibility here
means pinned tools, source and dependency resolution; hosted image/Ubuntu package
updates and upstream plugin setup are not a bit-for-bit reproducible APK claim.

## Versioning and commands

- `pubspec.yaml` is the default version source. Local Flutter builds retain its
  build number unless explicitly overridden; `0` is never injected.
- CI release `versionCode` defaults to **pubspec build + `github.run_number`**.
  Re-running the same workflow run preserves the code. Manual `build_number`
  accepts a positive integer at least that default, at most 2,100,000,000.
  Keep the pubspec build baseline nondecreasing. If an explicit code jumps ahead,
  raise the pubspec build baseline before the next automatically numbered release.
  Maintainers must keep published codes increasing across all distribution
  channels, including external/local builds; GitHub counters do not track those.
- Tags accept `vMAJOR.MINOR.PATCH` or a SemVer prerelease such as
  `v0.1.0-alpha.1`. The numeric version must match pubspec; a prerelease pubspec
  must match exactly. Tag build metadata (`+...`) and leading-zero numeric
  identifiers are rejected. Alpha tags are published as prereleases, and no
  release is automatically promoted to GitHub's `latest` label.

After reviewing/importing and pushing the code, a maintainer may run:

```sh
gh workflow run android-release.yml --ref main -f flavor=both
# Only supply build_number when coordinating a deliberately higher versionCode:
gh workflow run android-release.yml --ref main -f flavor=full -f build_number=123
gh run list --workflow android-release.yml
gh run download RUN_ID --dir release-artifacts
# Inside one extracted flavor artifact directory:
sha256sum --check SHA256SUMS-full.txt
```

For public publication, update pubspec as needed, merge reviewed source to main,
then create/push a matching protected tag (for example `v0.1.0-alpha.1`). This
document and implementation do not assert any build or hardware test has run.

Local signing remains supported through ignored `android/key.properties` with
`storeFile`, `storePassword`, `keyAlias`, `keyPassword`. Alternatively set
`ANDROID_KEYSTORE_PATH` and the three password/alias environment variables above:

```sh
flutter pub get --enforce-lockfile
flutter build apk --release --flavor full --target-platform android-arm64,android-arm --no-pub
python3 -B -m unittest discover -s tool -p 'ci_*_test.py' -v
actionlint .github/workflows/android-ci.yml .github/workflows/android-release.yml
```

USB, DSD/DoP, DAP and background-playback validation still require the physical
device checklist in `BUILD.md`.


## Beta updates

`Android beta APK` publishes signed full-flavor release APKs on main pushes or
manual main dispatches. It uses the existing four `ANDROID_KEYSTORE_*` /
`ANDROID_KEY_*` Actions secrets listed above, the pinned toolchain and the same
release packaging helper. It never generates a debug key or falls back to one.
Missing signing secrets stop the build before toolchain installation. Only APKs,
checksums and public metadata are uploaded; decoded keys are removed on success,
failure and cancellation. No test jobs are added to the beta workflow.

Each beta gets the pubspec build number plus the beta workflow run number as
its Android versionCode. Keep the pubspec build number non-decreasing between
betas. A rerun keeps the code of that original beta, so rerunning an old beta is
not a way to update a newer installation. Beta run numbers and Android release
run numbers are independent: when switching between the beta and tag/manual
release channels, choose a release build number greater than the installed
versionCode. APK filenames and the GitHub repository name do not determine
Android update compatibility.

Android updates require the same application ID, a compatible signing
certificate, and a non-decreasing versionCode (a greater code for a new build).
The application ID remains `com.lokalkonnekt.konnekted2` despite the repository
rename. Changing it would create a different app. Keep the signing identity and
its backups unchanged too; do not generate a replacement key for the rename.
The public `*-metadata.json` records `signingCertificateSha256` and versionCode
so published builds can be compared without exposing private signing material.

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
