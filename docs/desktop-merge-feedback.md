# Desktop library merge and file copies

The Desktop link screen keeps a merge status card after approval. It reports
catalogue song counts, history/library activity, profile/badge finalization,
completion time, and paused/disconnected state. Sync now retries the merge.
The last successful timestamp is retained for the paired desktop/user.

Merge imports desktop songs as streamable entries and combines likes, playlists
and completed-play history. It does not silently copy every audio file. The
paired desktop profile supplies the You display name, username and a locally
saved avatar. Older desktop builds without the profile endpoint still merge
history and library data. A desktop update is required for profile import.

Copy missing song files is a separate action with a two-direction count preview.
The phone compares local readable files with the desktop's playable catalogue,
using the existing desktop track matching and artist/title/duration matching on
the phone. These are song-level matches, not proof that two encodings are
byte-identical. Existing local versions are kept. Content URI access is checked
when its individual upload is staged; an inaccessible grant is a failed copy.

Copies run sequentially while both apps stay open and linked. Each file becomes
permanent only after a complete response (and the SHA-256 check when provided).
The desktop original-file endpoint avoids playback transcodes. The phone never
overwrites an existing destination file, and originals are never moved/deleted.
The result lists failed song titles. Checking again rebuilds the plan, skipping
completed files and retrying unfinished work. There is no background/resumable
byte-range transfer service: a disconnected/incomplete file starts over next
time. Desktop uploads retain the existing supported-format and 1 GiB limit.
A desktop update is required for two-way original-file copying.

Merged history is deduplicated by event ID. Milestone totals include the journal,
including events whose song is no longer available. Imported listening time is
read separately from the persisted local counter so repeat merges do not add it
again. All newly reached badge tiers are reconciled after history import; the You
page and milestone screen refresh from milestone change notifications.

Desktop artwork markers are retained even when thumbnail indexing has not
finished. The artwork service can recover an older markerless desktop row from
its source URI, ask the desktop for full/embedded artwork, and let newly mounted
cover cards immediately reuse an already resolved local image.

Validation is source-level only; paired-device transfer, image display and
interrupted-copy behavior still need device verification.
