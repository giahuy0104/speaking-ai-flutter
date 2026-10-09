# HOMI runtime audio gap-6 — ElevenLabs, 2026-09-17

## Scope

The current source/catalog audit and Flutter inventory tests found six fixed Vietnamese outputs without an exact authored recording after the branch merge:

1. `RUNTIME-CHALLENGE-CUE-001`: “Bạn trả lời nhé”.
2. `RUNTIME-CONVERSATION-RECOVERY-001`: “Cô chưa nghe thấy bạn nói. Bạn nói lại nhé.”
3. `RUNTIME-MAIN-NAVIGATION-001`: current MAIN opening prompt.
4. `RUNTIME-MAIN-NAVIGATION-002`: current MAIN retry prompt.
5. `RUNTIME-TRANSLATION-CONTROL-001`: menu shown after stopping translation.
6. `RUNTIME-TRANSLATION-CONTROL-002`: “Mình tiếp tục nhé.”

The current translation introduction differs from `AI-022` only by capitalization in “Dừng lại”. It reuses the verified recording through `lookupTexts` instead of making a duplicate paid request.

No English fixed output was missing. Existing English recordings keep voice `Nhs7eitvQWFTQBsf0yiT` at 0.75x. The six new Vietnamese recordings use voice `5CVDNcIPiOYgRUQuxXd7` at 0.9x.

## Production boundary

Generation runs only through the Node tools under `tool/`; the API key is read from an external file and is never stored in Flutter code, manifests, receipts, or bundled assets. The app receives only verified MP3 files plus manifest metadata. Raw provider output and request receipts remain under `deliverables/main_assistant_audio_sources/` and are not declared in `pubspec.yaml`.

All six requests use model `eleven_v3`, language `vi`, seed `164109`, and provider speed 1.0. FFmpeg applies pitch-preserving `atempo=0.9` exactly once; runtime playback stays at 1.0x.

## Small rollout groups and rollback

| Group | Prompts | Enabled by default | Disable switch |
|---|---|---:|---|
| `main-navigation` | 2 | yes | `--dart-define=HOMI_ASSISTANT_AUDIO_MAIN_NAVIGATION=false` |
| `translation-controls` | 2 new + 1 reused | yes | `--dart-define=HOMI_ASSISTANT_AUDIO_TRANSLATION_CONTROLS=false` |
| `challenge-cues` | 1 | yes | `--dart-define=HOMI_ASSISTANT_AUDIO_CHALLENGE_CUES=false` |
| `conversation-recovery` | 1 | yes | `--dart-define=HOMI_ASSISTANT_AUDIO_CONVERSATION_RECOVERY=false` |

When a group is disabled, missing, corrupt, ambiguous, or cannot be played, `MainAssistantAudioPromptService` invokes the original TTS delegate. The global `HOMI_ASSISTANT_AUTHORED_AUDIO=false` switch still disables every authored assistant group.

Only the audio source selection changed. MAIN decisions, translation state, challenge flow, microphone timing, recording, recognition, scoring, learning transitions, and progress persistence were not modified.

## Verified outputs

| ID | Final duration | Final bytes | SHA-256 |
|---|---:|---:|---|
| `RUNTIME-CHALLENGE-CUE-001` | 1.770975 s | 29,301 | `b1477489fae21a6ba3129e0dd8cfd3c25175c9cd4bc4070dee691bb69c0bd45a` |
| `RUNTIME-CONVERSATION-RECOVERY-001` | 3.006077 s | 49,363 | `705eb9c2a6809537a126d1b217102d901f1057a5f327138be5f3f3653d95f513` |
| `RUNTIME-MAIN-NAVIGATION-001` | 4.349138 s | 70,679 | `9009fbfd926af0bb456cf8078c426445b62725c3fc9d9679039804e5fe4986fc` |
| `RUNTIME-MAIN-NAVIGATION-002` | 3.177029 s | 51,871 | `33b45c1f28a907bbe53ebd4ada1e910c19a879f63a2e3c80908271108ba8180b` |
| `RUNTIME-TRANSLATION-CONTROL-001` | 3.452245 s | 56,468 | `190f082720d967cd8b0ea1bdf07c53c71550e5a759353251e0c96b34087691ac` |
| `RUNTIME-TRANSLATION-CONTROL-002` | 1.315850 s | 22,195 | `c24059d45ac1d3fe0018cf6b33b6528ea42f04b3ca3f85a21d5eb6b88ca2135f` |

The audit reports 2,866 audio files, zero integrity failures, and 2,068/2,068 current fixed text/locale outputs ready. This is metadata, decode, checksum, route, and source-code verification; human listening and physical H20 testing remain separate release checks.
