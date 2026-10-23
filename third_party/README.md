# Android-only ML Kit plugins

These local packages copy `google_mlkit_translation` 0.15.1 and
`google_mlkit_commons` 0.13.0 from pub.dev. Their Dart and Android implementations
are unchanged. The iOS plugin declarations and iOS sources are omitted so Flutter
does not link Google ML Kit into the iOS app. The original licenses are included
in each package.

Update both packages together when upgrading ML Kit, and keep the iOS platform
entries absent unless iOS simulator and device support have been verified.
