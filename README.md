# Flappy Journey

A lightweight Flappy-style game built with Flutter `CustomPainter` (no image assets).
AdMob test ads are integrated. Replace test IDs before publishing.

## Build in GitHub Actions (no local Flutter needed)
The included workflow will:
1) Set up Flutter on GitHub runner
2) `flutter create .` (generates android/ios folders)
3) `flutter pub get`
4) `flutter build apk --release`
5) Upload APK as an artifact
6) If you push a tag like `v1.0.0`, it also creates a GitHub Release and attaches the APK

## Local quick start (if you ever install Flutter)
```
flutter create .
flutter pub get
flutter run
flutter build apk --release
```
