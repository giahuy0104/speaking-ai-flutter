# HOMI assistant: ElevenLabs audio integration

This is the assistant-only delivery snapshot. The later lesson pack and current combined build results are documented in [curriculum-elevenlabs-audio.md](curriculum-elevenlabs-audio.md).

Update 2026-09-16: a subsequent runtime-gap batch adds 28 Vietnamese prompts (MAIN now 219; combined total 2,860). See [gap-28 delivery](D:/Code/HuaMei/App_noi/flutter/18_16th9/speaking-ai-flutter/docs/homi-gap28-elevenlabs-2026-09-16.md). Counts below describe the original 191-prompt snapshot.

## Delivered scope (2026-09-16)

- 191 unique fixed prompts, all generated and enabled: 184 Vietnamese and 7 English.
- Model: `eleven_v3`.
- Vietnamese voice: `5CVDNcIPiOYgRUQuxXd7`, speed 0.9x.
- English voice: `Nhs7eitvQWFTQBsf0yiT`, speed 0.75x.
- Final MP3 size: 8,765,820 bytes; total duration: 534.707 seconds; longest: 10.472 seconds.
- Covers MAIN greeting/menu/navigation, fixed AI/SIL/FB catalog entries, silence/fallback responses, vocabulary menus, age-specific feedback, fixed lesson/challenge instructions, module replies and review announcements.
- Exact duplicate text shares one file. Source references and aliases are in `assets/data/main_assistant_audio.json`.
- The original AI-001 was reused; the other 190 recordings were generated in the batch workflow.

This is the fixed **assistant/guide** pack, not a regeneration of every curriculum sentence or song. Dynamic lesson/topic/level names and numbers, user-provided vocabulary and free-form translations remain on their existing paths. Legacy age-group random guide clips, lesson samples, songs and child recordings are not overwritten. Some catalog entries are retained for compatibility; inclusion does not mean every legacy entry is currently reachable.

All 191 MP3 files are explicitly bundled in `pubspec.yaml`. They play locally without ElevenLabs credentials or audio hosting. Source recordings and generation receipts are not bundled.

## Playback and safety

`createVoicePromptService` wraps platform playback with `MainAssistantAudioPromptService` for all owners. When an audio-turn coordinator is supplied, the wrapper is inside the existing `CoordinatedVoicePromptService`, preserving its exclusive lease.

Lookup requires exact runtime text and an allowed locale, with exactly one enabled match. Known English feedback has explicit en-US and legacy vi-VN lookup aliases, always using the English file. Missing, disabled, ambiguous, unsupported or corrupt entries fall back to existing TTS. Styled dynamic translation requests retain their original TTS styling.

Each file's SHA-256 is checked before playback. Files over 2 MiB or 45 seconds are refused. Manifest/file loading is bounded to 500 ms. Authored playback has a duration-plus-3-second watchdog; MAIN's outer budget is duration plus 10 seconds. Unknown/dynamic MAIN text keeps its existing 8-second watchdog. No artificial delay follows successful completion.

Stop/dispose invalidates the prompt generation, cancels pending load/playback watchdogs immediately and prevents late audio or fallback TTS. Tests cover operations that never complete, stop/reopen and delayed completion. Recognition, ready cues, command resolution, scoring and learning progress are not rewritten.

- Android reuses the existing VoicePromptBridge MediaPlayer route and cleanup, with the same shared +8 dB speech boost used by lesson audio and device TTS.
- iOS uses AVAudioPlayer under the existing MAIN/session route lease. Native iOS compilation/device testing is not confirmed on Windows.
- Web uses Blob-backed HTMLAudio with completion/error/cancellation and object-URL cleanup. Browser autoplay failure falls back to existing browser TTS; real browser audio policies still need device testing.

Speed is baked into each MP3 once; playback rate is 1.0.

## Reproduce or extend safely

Do not change the manifest while a batch is running. Review exact source text before billable requests.

```powershell
# Inventory only: no key read, requests or writes.
node tool/prepare_assistant_audio_manifest.mjs

# Refresh reviewed inventory, preserving previous recordings by exact text.
node tool/prepare_assistant_audio_manifest.mjs --write

# Preview files to reuse/generate.
node tool/generate_all_assistant_audio.mjs

# Sequential generation, verification and per-file activation.
node tool/generate_all_assistant_audio.mjs --generate --api-key-file "C:/path-outside-repo/elevenlabs-key.txt"

# Single-prompt dry-run.
node tool/generate_main_assistant_audio.mjs --id AI-001
```

One paid request per missing source; no automatic network retry. Sources and receipts remain in `deliverables/main_assistant_audio_sources/`. Each final MP3 is decoded, its duration/receipt verified, then enabled in the manifest and explicitly added to pubspec. Existing final recordings are not overwritten. A resumed batch verifies and reuses completed files without regenerating them. For uncertain API outcomes, check provider history before retrying. Windows file-lock retries affect only the local manifest rename, never a repeated paid request.

The key is read from an external file, sent only to api.elevenlabs.io, redacted from errors and never written to the app or receipts.

## Speed method

ElevenLabs' [product guide](https://elevenlabs.io/docs/eleven-creative/playground/text-to-speech) and [speed help](https://elevenlabs.io/docs/help-center/product/core-capabilities/text-to-speech/can-i-change-the-pace-of-the-voice) have differed on v3 speed support. The reproducible method used here is v3 at default pace followed by pitch-preserving FFmpeg `atempo=0.9` or `atempo=0.75`. Duration is checked against source duration / speed with an MP3 padding tolerance. Receipts record the request, model, voice, source/final digest and processing method.

Endpoint: [ElevenLabs Create speech](https://elevenlabs.io/docs/api-reference/text-to-speech/convert).

## Rollback

- Disable one entry or the top-level manifest, then rebuild to return to TTS.
- Build switch: `--dart-define=HOMI_ASSISTANT_AUTHORED_AUDIO=false`. The older `HOMI_MAIN_AUTHORED_AUDIO=false` also disables the pack.
- No learning-data migration, progress reset or replacement of old audio files is needed.
- A new bundle does not remotely update an already-installed APK.

## Verification

Automated checks cover catalog/local-reply coverage; every entry's enabled state, bundled bytes, SHA-256, voice/model/speed receipt and duration; TTS recovery; locale routing; cancellation; audio ownership; and MAIN waiting for a prompt longer than eight seconds before opening its response window.

The mocked browser lifecycle test covers completion, cancellation, stale callbacks and autoplay errors, with all Blob URLs released. This is not human listening approval.

Validated results:

- 599 tests passed across all core audio tests, the new inventory checks, voice navigation, listening, vocabulary and continuous translation.
- Analysis of all lib code and the added/modified tests: no issues found.
- All 191 generated MP3 files decoded successfully and matched their bundled checksums and generation receipts.
- Android debug build succeeded: `build/app/outputs/flutter-apk/app-debug.apk`, 296,041,390 bytes.
- APK audit verified all 191 MP3 digests and scanned 1,098 nonempty archive entries. No supplied API key, raw generation source, generation script or audio receipt was bundled.
- Key scan of 1,956 tracked/unignored workspace files found no copy of the supplied key.
- Browser playback lifecycle test passed; source diff whitespace checks passed.
- Web production build succeeded: `build/web`.
- Web bundle audit verified all 191 audio digests and scanned 559 files: no supplied key, source recordings or generation receipts included.

Human listening and physical-device MAIN/microphone/Bluetooth/offline checks remain necessary before production release. No device installation or production deployment was performed.
