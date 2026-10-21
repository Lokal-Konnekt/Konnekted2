# Discord mobile SDK 1.10.19337

`discord-mobile-1.10.19337.zip.gpg` is an AES-256 encrypted archive of the three
SDK files supplied by the application owner: `include/discordpp.h`,
`lib/release/discord_partner_sdk.aar` and `License-Notices.txt`.

The decryption key belongs only in the repository Actions secret
`LOKAL_DISCORD_SDK_PASSPHRASE` (or a local environment variable). It is not
stored in this repository. Trusted beta/release builds run
`python3 tool/prepare_discord_sdk.py` to decrypt, verify the pinned file hashes
and stage native libraries plus required license notices. Plaintext staging is
ignored by Git. See `docs/DISCORD_PRESENCE.md` for setup.
