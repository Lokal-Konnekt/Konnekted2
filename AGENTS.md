# Konnekted2

Android music player: Flutter / Riverpod / Isar over Flick's Rust / Symphonia / Oboe / UAC2 engine. The public product is Konnekted; the internal `flick` Dart package and native namespace intentionally remain stable for generated FFI/JNI compatibility.

## Rules
- Preserve native PCM/DSD paths. Never describe DSP-processed or Android-mixed audio as bit-perfect.
- Do not replace USB transport with a mock. Hardware validation is separate from unit tests.
- New online services are opt-in. Never commit account tokens, signing keys, local SDK paths, or private logs.
- Preserve upstream licenses. This fusion is GPL-3.0; MIT-derived Flick code retains its original attribution in THIRD_PARTY_NOTICES.md.
- Keep the feature status document honest: source reuse is not proof of a device test or full Konnekted parity.

## Checks
```
flutter pub get
flutter analyze
flutter test
# Host cargo tests need libclang.dll for vendored bindgen crates; Android
# validation is performed through Cargokit during the APK build.
cargo test --lib --manifest-path rust/Cargo.toml
flutter build apk --debug --flavor full --target-platform android-arm64
# Windows: actual applied-plugin guard and launcher exit-code regression
android\gradlew.bat -p android verifyBuiltInKotlin
powershell.exe -NoProfile -File tool/test_cargokit_launcher.ps1
```

See README.md and docs/BUILD.md for prerequisites and exact validated scope.
