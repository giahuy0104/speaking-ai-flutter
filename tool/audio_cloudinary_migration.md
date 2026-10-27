# Application audio delivery on Cloudinary

The delivery catalog maps all 2,897 original application MP3 files (117,036,170
bytes) to immutable Cloudinary URLs. Original files remain in `assets/audio`
for source integrity, regeneration and rollback. User microphone recordings
and dynamically generated speech are outside this migration.

## Preserved behavior and metadata

The current `dev` manifests remain the source of truth for prompt keys, text,
locale, duration, enabled state, provenance and audio checksums. This includes
all 82 assistant prompts, `assistant.main.song_skipped.vi`, the three topic
prompts and `system.hm-d001.speaker_test`. Migration adds delivery URLs and
missing byte lengths, updates manifest versions, and regenerates the pack
index hashes/counts/sizes. It does not replace current manifests with an old
project snapshot.

The 17 prompt/media manifests and `remote_audio_catalog.json` retain asset paths
as logical identifiers for stable prompt keys, loudness and playback tracking.
The two listening content snapshots use the same verified song mappings. Native
legacy `asset:` calls resolve through the catalog to checksum-verified downloads;
web media resolves to the public URL after catalog initialization.

## Connectivity and offline behavior

Removing MP3 asset declarations reduces the installed audio payload. Uncached
audio then requires network connectivity. Prompt speech retains its existing TTS
fallback; songs and sound effects do not synthesize a replacement. Downloaded
audio can play offline while retained in cache. The registry object cache is
limited to 128 MiB; the separate native media cache is limited to 64 MiB and 256
files. Cache eviction can remove a previously heard clip. Installation does not
download the full library, and cache is not a guaranteed offline lesson pack.

The speech/translation model preparation, local recognition, retry-scoring state
and navigation guards introduced on `dev` remain in place. Speech-model downloads
do not download this audio library. See [topic offline learning](../docs/topic-offline-learning.md).

## Local regeneration and verification

Run from the repository root with Node.js. These commands use local source files
and the existing committed catalog, with no credentials or network requests:

```powershell
# Read-only inventory of original audio.
node tool/migrate_audio_cloudinary.mjs

# Read-only checks: source hashes/sizes, immutable catalog URLs, every manifest
# reference, indexed manifest hashes/counts/sizes, and content song URLs.
node tool/migrate_audio_cloudinary.mjs --check

# Reapply existing catalog URLs atop the current manifests, preserving metadata.
# Validates all planned updates before writing the JSON files.
node tool/migrate_audio_cloudinary.mjs --apply-catalog
```

`--check` validates local integrity and mapping consistency. It does not prove
that the CDN is currently reachable or that remote files are still available.
The existing catalog URLs are reused; these commands do not create, overwrite
or delete Cloudinary resources. Keep a reviewed diff of generated JSON changes.

## Publishing new source audio

Use this only when a new or changed original requires a new remote object. Keep
Cloudinary credentials in a local file outside Git containing `Cloud name:`,
`API Key:` and `API Secret:`. Public delivery URLs are the only remote identifiers
included in app assets; secrets must remain outside the repository.

```powershell
# Upload content-addressed objects without overwriting existing public IDs,
# download each delivery URL, verify SHA-256/size, and save local receipts.
node tool/migrate_audio_cloudinary.mjs C:/path/to/credentials.txt --upload

# Apply only after every original has a matching verified receipt.
node tool/migrate_audio_cloudinary.mjs C:/path/to/credentials.txt --apply
node tool/migrate_audio_cloudinary.mjs --check
```

Publishing resumes using the ignored local file
`build/cloudinary-all-audio-receipt.json`. Do not commit credentials or receipts.
The upload mode performs network writes; local regeneration does not need it.

## Validation scope

Migration tests use deterministic local HTTP fixtures for cache, corruption,
cancellation, loudness and unavailable-network behavior. The local script checks
all original audio bytes and the full metadata mapping. Real iPhone/Android and
HM-D001 playback still need a device smoke test; a passing fixture test does not
establish current Cloudinary delivery availability.

## Rollback

Restore runtime delivery behavior, manifests/index and MP3 asset declarations
together, then rebuild. Original MP3s remain in the repository; Cloudinary
objects do not need to be removed. Restoring an old manifest alone does not
restore bundled offline playback.
