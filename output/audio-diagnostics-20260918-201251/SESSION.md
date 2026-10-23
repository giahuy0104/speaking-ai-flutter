# Completed diagnostic capture

- Device: ORH6S4ZT85BMWGSK (Redmi 23054RA19C), package com.innotrik.aispeaking.
- Installed successfully: 2026-09-18 20:12:44 Asia/Bangkok, version 1.0.8+10.
- APK: build/app/outputs/flutter-apk/app-release.apk (release, arm64).
- Build log: output/audio-diagnostic-build-retry.log; exit 0.
- Dart define: HOMI_AUDIO_DIAGNOSTICS=true.
- Native logging: log.tag.HomiDiag=DEBUG; diagnostics.native.ready verified.
- Persistent local adb capture PID: 1804. Device app PID at launch: 9557.
- Capture stopped after user completion; native diagnostic tag set back to INFO. See ANALYSIS.md.
- Capture: device.log; stderr: capture.stderr.log. Keep USB connected.
- User will manually test, then report completion. Do not fix behavior before that request.
- After completion, inspect this capture and verify PID 1804 is this adb logcat before stopping it.
- Disable native logging afterwards with adb shell setprop log.tag.HomiDiag INFO.

Validation: 71 focused tests passed with diagnostics enabled; analyze lib passed.
Whole-repo analysis has existing unrelated tool/output issues. Initial Gradle
attempt failed with Metaspace OOM; successful retry used a build-local
GRADLE_OPTS override (2 GB heap, 1 GB metaspace) in tool/build_audio_diagnostic_apk.ps1.
