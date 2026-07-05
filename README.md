# CipherFlutter

CipherFlutter is a simple Material 3 app for encrypting and decrypting text.

Previously, this project was called **CipherJavaFX** and was built with JavaFX. It has now been migrated to **Flutter** so it can grow beyond Windows desktop and eventually support Android and possibly iOS.

> [!NOTE]
> File encryption is not implemented yet. Current releases focus on text encryption and decryption.

---

## Features

- Text encryption and decryption
- AES-256-GCM encryption
- PBKDF2-HMAC-SHA256 key derivation
- Random salt and nonce per encryption
- Compatibility with the app's `CJFX1` ciphertext format
- Legacy CipherJavaFX ciphertext decrypt support
- Material 3 / Material You style UI
- Dark and light themes
- Theme preference saving
- Secret token field with show/hide toggle
- Strong token generator
- Weak-token warning
- Explicit Encrypt and Decrypt modes
- Ciphertext output box is read-only
- Paste input, copy result, and clear actions
- Optional auto-copy after encryption
- MIT license page
- Hidden FPS overlay: open About, click `3.0.0` seven times

---

## Download

### Windows

1. Go to the **Releases** page.
2. Download the latest Windows ZIP.
3. Extract the ZIP.
4. Run the CipherFlutter executable inside the extracted folder.

### Android

APK files will be available on the Releases page once the Android version is finalized. I may also try to publish the app on the Google Play Store.

### iOS

iOS support is possible, but not guaranteed yet.

---

## Build From Source

### Requirements

- Flutter stable
- Dart, included with Flutter
- Visual Studio with **Desktop development with C++** for Windows builds
- Android Studio / Android SDK for Android builds
- macOS + Xcode for iOS builds

### Setup

```powershell
flutter pub get
```

### Run On Windows

```powershell
flutter run -d windows
```

### Analyze And Test

```powershell
flutter analyze
flutter test
```

### Build Windows Release

```powershell
flutter build windows
```

The Windows build output will be in:

```text
build\windows\x64\runner\Release
```

Zip the contents of that folder when creating a Windows release.

### Build Android APK

```powershell
flutter build apk --release
```

---

## Security Notes

CipherFlutter uses AES-GCM with a 256-bit key. The key is derived from the token using PBKDF2-HMAC-SHA256.

Your token is the secret. If you lose it, encrypted text cannot be recovered. If someone else gets it, they can decrypt your data.

Use the built-in generator for stronger tokens.

---

## Repository Notes

The following folders are build outputs and should not be committed:

- `build/`
- `.dart_tool/`
- platform build folders generated during release packaging

---

## License

MIT License.
