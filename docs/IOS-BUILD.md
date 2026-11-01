# X9 user app for iPhone — build, sign and publish (v6.19)

The X9 user app is a Flutter app, so the same code (`apps/user/lib`, `apps/x9_core`) runs on Android and iPhone.
An iPhone app can only be compiled on a Mac with Xcode, so the build runs on GitHub's macOS computers
(`.github/workflows/ios.yml`) — you do not need a Mac.

| What you get | Needs | Installs on |
|---|---|---|
| `x9-user-ios-simulator.app.zip` | nothing | the iOS Simulator on any Mac (for demos and screen checks) |
| `x9-user-ios-unsigned.ipa` | nothing | not directly; can be sideloaded with your Apple ID (AltStore / Sideloadly), 7-day limit |
| `x9-user-ios-ad-hoc.ipa` / `-development.ipa` | Apple Developer account + certificate + profile with the iPhones' UDIDs | the registered iPhones |
| `x9-user-ios-app-store-connect.ipa` → TestFlight / App Store | Apple Developer account + App Store profile (+ API key for automatic upload) | any iPhone via TestFlight, then the App Store |

Apple requires a paid **Apple Developer Program** membership (₹ fee per year, enrol as the company
with its D-U-N-S number) for anything that installs on a normal iPhone.

## Part A. First build (no Apple account yet)

1. Push the repository (with the v6.19 files) to GitHub.
2. **Actions → Build X9 iOS app → Run workflow** (or just push a change under `apps/user`).
3. After ~25–40 minutes open the run → **Artifacts → x9-user-ios-run<N>**. Inside: the unsigned `.ipa` and the
   Simulator app. This proves the iPhone app compiles. To look at it: on a Mac, unzip the Simulator app and drag
   `Runner.app` onto an open iOS Simulator window.

## Part B. Signed builds (Apple Developer account)

Done once, on developer.apple.com (Certificates, Identifiers & Profiles):

1. **Identifier**: App IDs → `+` → App → Bundle ID (explicit) `in.donezo.x9.user`. Tick **Push Notifications**.
   (Another bundle id? Set repository variable `X9_IOS_BUNDLE_ID`.)
2. **Certificate**: Certificates → `+` → **Apple Distribution**. Create the CSR on any Mac (Keychain Access →
   Certificate Assistant → Request a Certificate from a CA) or with openssl, download the `.cer`, open it in
   Keychain Access, then right-click the certificate → Export → `.p12` with a password.
   Without a Mac: `openssl req -new -newkey rsa:2048 -nodes -keyout x9.key -out x9.csr -subj "/CN=X9/emailAddress=you@example.com"`,
   upload `x9.csr`, download `distribution.cer`, then
   `openssl x509 -inform der -in distribution.cer -out x9.pem && openssl pkcs12 -export -inkey x9.key -in x9.pem -out x9.p12`.
3. **Profile**: Profiles → `+` → **App Store Connect** (for TestFlight / App Store) or **Ad Hoc** (for test iPhones
   whose UDIDs you registered under Devices) → App ID `in.donezo.x9.user` → the certificate → download the
   `.mobileprovision`.
4. GitHub → Settings → Secrets and variables → Actions → **New repository secret**:

| Secret | Value |
|---|---|
| `IOS_DIST_CERT_P12_BASE64` | `base64 -i x9.p12` (macOS) or `base64 -w0 x9.p12` (Linux) |
| `IOS_DIST_CERT_PASSWORD` | the .p12 password |
| `IOS_PROVISION_PROFILE_BASE64` | `base64 -w0 X9_User_AppStore.mobileprovision` |

The workflow reads the team id, profile name and type (App Store / Ad Hoc / Development) from the profile itself,
signs the app and names the file after the profile type. Push is switched on when the profile has the Push
Notifications capability.

## Part C. TestFlight and the App Store

1. App Store Connect → **Apps → `+` → New App**: platform iOS, name "X9", bundle id `in.donezo.x9.user`, SKU `x9-user`.
2. App Store Connect → **Users and Access → Integrations → App Store Connect API → `+`** (role App Manager).
   Download the `.p8` key once. Add secrets `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`,
   `APP_STORE_CONNECT_KEY_P8_BASE64` (`base64 -w0 AuthKey_XXXX.p8`).
3. Run the workflow with **testflight = true**, or push a tag `v1.5.0`. The build appears under TestFlight after
   Apple's processing; add internal testers (up to 100) by e-mail. Each run uses build number 100 + run number,
   so every upload is newer than the last.
4. For the App Store: fill the listing (screenshots — the HD screens from the presentation pack fit the 6.1" size —,
   description, privacy policy URL, support URL, privacy "nutrition label": contact info, location, financial info,
   identifiers), then **Submit for Review**.

**Review notes that matter for X9**

* Give Apple a demo login (a test mobile number whose OTP you can share, or a review OTP bypass on a test account).
* Sign-in: if the Google button is shown, Apple's guideline 4.8 may ask for an equivalent option such as
  *Sign in with Apple*. Mobile + OTP stays the main sign-in. Ask us to hide the Google button on iPhone if review raises it.
* Real-money wallet, prepaid card and UPI payments are allowed (they are not digital goods, so no in-app purchase).
* Location is used "when in use" only; camera for QR and KYC; photos for receipts — the texts are set in Info.plist.

## Firebase on iPhone (push + Google sign-in)

1. Firebase console → the X9 project → **Add app → iOS**, bundle id `in.donezo.x9.user` → download
   `GoogleService-Info.plist` → secret `GOOGLE_SERVICE_INFO_PLIST_USER` (paste the file text, or its base64).
2. Firebase → Project settings → **Cloud Messaging → Apple app configuration → APNs Authentication Key**: upload the
   `.p8` key from developer.apple.com → Keys → `+` (Apple Push Notifications service), with Key ID and Team ID.
3. The X9 server needs no change: it already sends FCM messages with a `notification` block, which Firebase delivers
   to iPhones through APNs. The app registers its token with `platform: IOS`.

## What is different on iPhone

| Area | Android | iPhone (v6.19) |
|---|---|---|
| Pay with UPI app | the phone lists every UPI app (native list with icons) | X9 checks Google Pay, PhonePe, Paytm, BHIM, CRED, Amazon Pay, MobiKwik by their link schemes and shows the installed ones, plus "Other UPI app"; the chosen app opens with its own link (`phonepe://pay?...`). Same X9 UPI ID, amount and reference; the credit is confirmed by the UPI auto-alert / UTR exactly as on Android |
| Unlock | PIN / pattern / fingerprint | PIN / Face ID / Touch ID |
| Push | FCM | FCM → APNs (needs the APNs key in Firebase) |
| Offer links | `x9://offer/...` and `https://portal.x9.com/o/...` | `x9://offer/...`; https links open the web page until Associated Domains + `apple-app-site-association` are set up |
| Orientation | portrait | portrait (iPhone app; runs on iPad in iPhone mode) |
| Minimum OS | Android 6 (API 23) | iOS 15.5 |

The per-app UPI link schemes are not officially documented by the UPI apps; Google Pay, PhonePe and Paytm are the
widely used ones. Check each on a real iPhone during TestFlight; if one does not open, "Other UPI app" and the
**Copy UPI ID** / **Enter UTR** buttons still complete the payment.

## Files

| File | Purpose |
|---|---|
| `.github/workflows/ios.yml` | macOS build, signing, TestFlight upload |
| `.github/scripts/patch_ios.py` | bundle id, iOS 15.5, Info.plist texts, UPI schemes, deep link, push, signing |
| `.github/scripts/ios_add_resource.rb` | adds GoogleService-Info.plist to the Xcode target |
| `apps/user/ios/Runner/AppDelegate.swift` | iPhone entry point (foreground notifications) |
| `apps/user/ios/Podfile` | CocoaPods, iOS 15.5 |
| `apps/user/ios/Runner/Assets.xcassets/AppIcon.appiconset/` | X9 app icon (from `tool/make_ios_icons.py`) |
| `apps/user/lib/services/upi_apps_ios.dart` | iPhone UPI app picker |

The rest of the Xcode project is generated by `flutter create` during the build, the same way the Android Gradle
files are, so Flutter upgrades never leave an outdated Xcode project in the repository.

## Problems

| Message | Fix |
|---|---|
| `Provisioning profile ... is for 'X' but the app bundle id is 'Y'` | make the profile for `in.donezo.x9.user` or set variable `X9_IOS_BUNDLE_ID` |
| `No signing certificate "iOS Distribution" found` / `doesn't include signing certificate` | the .p12 and the profile must be the same certificate; recreate the profile after a new certificate |
| `pod install` fails on a minimum iOS version | a plugin needs a newer iOS: raise `MIN_IOS` in ios.yml and `platform :ios` in `apps/user/ios/Podfile` |
| TestFlight: `bundle version must be higher` | re-run the workflow (each run has a higher build number) |
| Push never arrives on iPhone | APNs key missing in Firebase, profile without Push, or the app was built without `GOOGLE_SERVICE_INFO_PLIST_USER` |
