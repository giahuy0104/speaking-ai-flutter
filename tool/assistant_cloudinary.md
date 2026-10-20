# Assistant audio on Cloudinary

Only `assets/data/assistant_core_audio.json` is migrated. Its `url` fields
are the delivery URLs consumed by both assistant playback implementations.
The `asset` fields and original MP3s remain in the repository for integrity
checks, regeneration, and rollback; `pubspec.yaml` excludes this directory
from the application bundle. Do not rename keys, change prompt text, or
transform the delivery files without recalculating their checksums.

Some assistant prompts are also used by lesson navigation and feedback.
Those prompts now use the same CDN/cache path. The separate lesson,
challenge, vocabulary, GAP66, song, and sound-effect packs stay bundled.
An uncached assistant recording needs connectivity; on download failure,
the existing TTS fallback is used. Cached recordings can be reused offline
while present in the cache. This does not migrate dynamic generated speech
or microphone recordings.

## Publishing

From the repository root, use a local credential file outside Git containing
`Cloud name: ...`, `API Key: ...`, and `API Secret: ...`.

```powershell
node tool/upload_assistant_cloudinary.mjs C:/path/to/credentials.txt
node tool/upload_assistant_cloudinary.mjs C:/path/to/credentials.txt --upload
```

The first command checks all local source hashes without uploading. The second
uploads only assistant-core, without overwriting existing public IDs, and
downloads each delivery URL to verify its original bytes. It can resume using
`build/assistant-cloudinary-receipt.json`; no credentials are written there.
Only after all files verify, copy receipt URLs into the matching prompt `url`
fields, bump the pack version, and update that pack's version and
`manifestSha256` in `assets/data/audio_pack_index.json`. Other packs must not
change. The script deliberately does not modify manifests automatically.

To roll back delivery, restore the previous manifest/index and re-add
`assets/audio/assistant-core/` to `pubspec.yaml`, then rebuild. Source MP3s
remain available locally. No Cloudinary deletion is needed.

## Migration verification (2026-10-19)

- All 81 Cloudinary delivery files were downloaded and matched local SHA-256
  and size, without audio transformations.
- All original prompt fields were preserved; only URLs and the pack version
  were added/updated. Other audio index entries were unchanged.
- Targeted Dart analysis passed. After reconciling the GAP66-001 and GAP66-003
  historical receipts with the replacement MP3s installed by commit
  `1af624ad9f942cd1362448045b4d133c67cf1952`, all 174 regression tests passed.
  Each receipt retains original provider metadata and adds a separately
  verified `replacementArtifact`. The GAP66 manifest, MP3s, and runtime
  behavior were not changed by the receipt correction.
- Automated tests cover absent bundled assistant files, remote/cache playback,
  offline timeout/TTS, unavailable cache storage, lesson hooks and guided
  lesson flows, assistant route payloads, and the other media registries.
- Android release APK built successfully. ZIP inspection confirmed zero
  assistant-core MP3s, 81 Cloudinary URLs in the packaged manifest, and 2,815
  remaining audio files. The APK is at
  `build/app/outputs/flutter-apk/app-release.apk` (259.65 MiB). This total
  includes the current checkout and build configuration; it is not a
  controlled size comparison against older APKs.
- Physical Android/iOS playback still needs a device smoke test. Windows
  cannot validate an iOS release build.
