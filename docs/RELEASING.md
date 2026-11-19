# Releasing a new version (build the APK, give it to users)

Everyone installs the APK once by hand. After that, every update is offered inside the app (progress bar, then Android's own
"Install" button). The app never opens a browser or Google Drive for updates.

## Why the whole file is downloaded
Android cannot install "just the changed part" of an app that is installed from a file. Only Google Play does that (it sends a patch
automatically) and Play needs a Google developer account. What we do instead: build a **64-bit-only APK** (about a third of the
size of the universal one) and download it inside the app. Phones made since about 2017 are 64-bit. If a very old phone refuses to install, build
the universal one (leave out `--target-platform android-arm64`).

## Every release
1. **Raise the build number** in `pubspec.yaml`: `version: 1.0.3+4` -> `1.0.4+5` (the number after `+` is the build number the app compares).
2. **Build** (from the project folder): `flutter build apk --release --target-platform android-arm64`
   The file is `build/app/outputs/flutter-apk/app-release.apk`.
3. **Upload it as a GitHub release** with a fixed file name, so the download link never changes:
   `gh release create v1.0.4 "build/app/outputs/flutter-apk/app-release.apk#FOLK-Tracker.apk" --repo <owner>/folk-releases --title "FOLK Tracker 1.0.4" --notes "What changed"`
   The permanent link is `https://github.com/<owner>/folk-releases/releases/latest/download/FOLK-Tracker.apk`
   (`folk-releases` is a small PUBLIC repo that holds only these files; GitHub does not allow downloads from a private repo without a login.)
4. **Tell the app**: Admin > Settings > App update: Latest build = `5`, Download link = the permanent link above, a short message, Save.
   Minimum build (optional) blocks every phone below that number until it updates. Use it only for critical fixes.
5. Phones see "Update available" the next time the app opens or returns to the foreground.

Backend changes (Worker) are separate: run any new `backend/scripts/phase*.py` first, then `npx wrangler deploy` from `backend/`.

## First install for a new user
Send the permanent link (WhatsApp is fine) or the APK file. On the phone: open it, allow "Install unknown apps" for that app when
Android asks, tap Install. Phones managed by an organisation (MDM) may block this: they need the setting allowed by the owner.

## Keep the signing key safe
Release builds are currently signed with this Mac's debug key (`~/.android/debug.keystore`). Android only installs an update if it is signed
with the **same key as the installed app**. So: build releases only on this Mac and back that file up. A build made on another computer will
fail to update with "App not installed". Moving to a proper release key later is possible but every user must uninstall and reinstall once.

## Sign-in by SMS code (MSG91)
There are no passwords. A Coordinator or Admin enters their mobile number, gets a 6-digit code by SMS and is signed in.
The session is renewed every time the app opens, so people stay signed in (it ends only after 180 days without opening the app,
or at once when an admin disables the account or makes it Public).

- Worker secrets: `MSG91_AUTH_KEY` and `MSG91_OTP_TEMPLATE_ID` (`npx wrangler secret put <NAME>` from `backend/`).
- **Reading the code with no "Allow" prompt** needs the SMS to END with the app's 11-character hash (Android SMS Retriever API).
  The app sends its hash with every request; the server passes it to MSG91 as the variable `##hash##`.
  1. In MSG91 + DLT, get a template approved that ends with the hash variable, for example:
     `Hare Krishna. Your FOLK Tracker login code is ##otp##. Do not share it. HKM Hyderabad ##hash##`
     (keep the whole SMS under 140 characters; nothing may come after `##hash##`).
  2. `npx wrangler secret put MSG91_OTP_TEMPLATE_ID` with the new template ID.
  3. In `backend/wrangler.jsonc` set `"OTP_SMS_HAS_APP_HASH": "1"`, then `npx wrangler deploy`.
  Until then the app uses the one-tap "Allow" prompt (SMS User Consent API). Typing the code always works.
- The hash depends on the signing key. Releases are signed with this Mac's debug key, so it stays the same for every release built here.
