# Discord Rich Presence (Android)

Lokal uses the Android bridge from [Mornye](https://github.com/mornyeapp/Mornye),
which uses Discord's official Social SDK 1.10.19337. It connects through the
installed Discord app's signed-in session. No client secret, bot token, user
token or public verification key is required. Attribution and the MIT license
are in `third_party/mornye_discord` and `THIRD_PARTY_NOTICES.md`.

## Configure a Discord-enabled build

1. At <https://discord.com/developers/applications>, create/select **Lokal**.
   Create a [Developer Team](https://discord.com/developers/teams) and assign
   the application to it (Discord’s documented prerequisite). Copy its
   **Application ID** from **General Information** (public).
2. Open **Discord Social SDK → Getting Started** (direct link for Lokal:
   <https://discord.com/developers/applications/1562522741817479302/social-sdk/getting-started>).
   Complete Discord’s access/setup
   process and download the mobile SDK from **Downloads**. Access availability
   and application requirements are controlled by Discord.
3. Extract SDK **1.10.19337**, then stage it locally:

   ```sh
   python3 tool/setup_discord_sdk.py /path/to/extracted/discord_social_sdk
   flutter pub get
   ```

4. Lokal’s public application ID `1562522741817479302` is configured in source.
   Build using the usual Flutter APK command, for example:

   ```sh
   flutter build apk --release --flavor full --target-platform android-arm64
   ```

   Forks can override the public ID with
   `--dart-define=LOKAL_DISCORD_APPLICATION_ID=<their application ID>`.
   Release signing and the existing Android/Rust build prerequisites still apply.
   For release automation, provision the official SDK in the build workspace and
   run the staging command before Flutter builds; do not commit SDK archives or
   local paths. The staging script verifies the pinned SDK file hashes and
   packages Discord's required license notices. Enabled SDK builds fail if a
   requested ABI is missing, rather than shipping a silently broken ABI.

5. Install Discord and sign in on the phone. Enable activity sharing in Discord
   as needed, then enable **Settings → Online sources → Accounts → Discord Rich
   Presence** in Lokal. Play a song and check the account's activity from another
   Discord client. Check track changes, seeks, pause/stop and disabling sharing.

## Behavior and current validation

Sharing is off by default. It follows the playback service across navigation;
track/seek changes coalesce over 15 seconds, timestamps advance without constant
network requests, and pausing, stopping or disabling clears presence immediately
and stops the SDK callback timer. Playback is independent of SDK failures.

The activity says **Listening to Lokal**, with the song title, artist and timing.
Only recognized public HTTPS cover URLs without credentials/query parameters
are shared. Local covers and desktop/private-server artwork are never uploaded.
They may therefore appear without artwork on Discord.

Clean builds without the SDK or application ID still work, but the setting
explains that Discord is unavailable in that build. The native bridge and Dart
integration are prepared; an SDK-enabled APK and real Discord device session
have **not** been validated in this environment. Android activity privacy,
connectivity and background restrictions can affect availability. iOS support
is not included in this Android integration.
