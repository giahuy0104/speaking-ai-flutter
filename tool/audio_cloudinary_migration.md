# Application audio on Cloudinary

All 2,897 original application MP3 files (117,036,170 bytes) are delivered from
Cloudinary. No MP3 is declared in `pubspec.yaml`. Original files remain in the
repository for integrity checks, regeneration and rollback; they are not shipped
inside APK/IPA/web assets. User microphone recordings and dynamically generated
speech are not uploaded by this migration.

## Public mapping

- `assets/data/remote_audio_catalog.json` maps every original asset path to a
  verified HTTPS URL, SHA-256 and size, including direct media such as songs,
  H20 test, Star Ting and the song-skipped recording.
- All 17 prompt/media manifests contain their delivery URLs. The pack index
  contains the updated versions and checksums. Content snapshots use the new
  song URLs as well.
- Asset fields remain **logical identifiers**, preserving stable keys and
  loudness metadata. They no longer imply that an MP3 is bundled.
- Prompt text, locale, duration, original audio bytes and hashes are preserved.
  No Cloudinary audio transformations are requested.

## Playback and storage

The registry reads verified device cache before downloading a prompt. The legacy
fixed-prompt service (including GAP66) also uses persistent verified cache. Each
new cache write trims the shared registry object cache toward 64 MiB. The general
media cache has its existing separate 64 MiB / 256-file limit. Cache is downloaded
on demand and can be evicted; installing the app does not download the library.

Legacy `asset:` media calls are resolved through the catalog to Cloudinary and
checksum-verified local downloads before native playback. Logical identity is
retained for completion tracking and volume metadata. A failed verification does
not hand an unchecked URL to the native player. Browser media resolves to the
public URL synchronously after the catalog is loaded in `main()`, preserving
Safari's user-gesture path and using browser HTTP caching.

Uncached audio needs connectivity. Fixed speech keeps the existing TTS fallback;
songs and sound effects do not synthesize a replacement. Previously cached audio
can play offline while retained. Audio routing and microphone recordings keep
their existing behavior.

## Upload and regenerate

Keep Cloudinary credentials in a local file outside Git containing `Cloud name:`,
`API Key:` and `API Secret:`. The app contains only public delivery URLs; secrets
are neither logged nor copied into source, receipts or application assets.

```powershell
# Inventory only; no upload or source edits.
node tool/migrate_audio_cloudinary.mjs C:/path/to/credentials.txt

# Upload every original, download its URL, verify hash and size, save receipts.
node tool/migrate_audio_cloudinary.mjs C:/path/to/credentials.txt --upload

# After every file has verified receipts, update manifests and URL catalog.
node tool/migrate_audio_cloudinary.mjs C:/path/to/credentials.txt --apply
```

Uploads use content-addressed public IDs with `overwrite=false`. The script retries
transient failures, runs eight workers, and resumes using
`build/cloudinary-all-audio-receipt.json`. Keep that local receipt for audit and
resume. If the build directory is cleaned, rerun upload/verification; stable IDs
avoid overwriting existing content. `--apply` can be rerun without uploading.

The old `upload_assistant_cloudinary.mjs` script is retained for compatibility
but covers only assistant-core. Use the all-audio script for this application.

## Validation (2026-10-22)

- All 2,897 URLs were fetched from Cloudinary and matched source SHA-256 and size.
- Every original file and all manifest references are covered by the catalog.
- Existing prompt keys, text, locale, duration and audio hashes were compared
  against the pre-migration manifests and remained unchanged.
- `test/remote_audio_migration_test.dart` checks zero bundled audio, all-file
  coverage, registry resolution, offline cache, failed/corrupt downloads,
  cancellation, original loudness metadata and legacy media mapping.
- Related registry, GAP66, hook, media, cache and playback-routing tests cover
  the existing behavior. Network tests use local verified fixtures; the upload
  receipt is the separate evidence for real CDN delivery.
- The pre-migration Flutter asset bundle contained 2,815 MP3s totaling
  114,074,780 bytes. The other 82 source MP3s were already excluded from the app.
  The new release Flutter asset output contains zero MP3s.

- 112 migration/registry/cache/routing tests and 170 module regression tests
  passed (282 tests total). All 3,942 enabled static registry prompts resolved
  to verified remote or cached audio in the deterministic fixture test.
- Dart analysis of all production `lib` code and the migration tests passed.
- Android release build succeeded. ZIP inspection of
  `build/app/outputs/flutter-apk/app-release.apk` found zero audio files, all
  2,897 catalog URLs, and valid hashes for all 16 indexed packaged manifests.
  APK size: 158,104,444 bytes (150.78 MiB).
- The previous local APK was 272,743,177 bytes (260.11 MiB), an observed
  difference of 109.33 MiB. That existing APK is not a controlled rebuild of the
  exact same source/configuration; the directly measured removed audio payload
  is 114,074,780 bytes (108.79 MiB).
- Web release build succeeded and contains zero audio files and the URL catalog.
- Local source scanning found zero files containing the supplied Cloudinary
  API key or secret in `lib`, `assets/data`, and `tool`.

Physical phone/Bluetooth playback still needs device testing; iOS release
compilation requires a macOS/Xcode environment. No Git commit or push was made.

## Rollback

Restore the previous runtime source/manifests and MP3 asset declarations together,
then rebuild. Original MP3s remain in the repository, and no existing Cloudinary
assets were deleted. Restoring just an old manifest without restoring packaging
does not restore offline bundled playback.
