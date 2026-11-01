# X9 user app (Android + iPhone, Flutter)

The customer app of the X9 platform: offers near you, Scan & Pay, the X9 Club wallet, the X9 prepaid card,
payment requests and receipts. Shared code (API client, session, app lock, theme, widgets) lives in
`../x9_core`. The API contract is `docs/APP-API-v2.md` (+ `docs/API.md`). All money is integer paise.

## Screens

| Area | Screen | API |
|---|---|---|
| Start | Splash → Welcome (Google / mobile) → app lock setup → unlock → phone approval → Home | `GET /app/profile` |
| Sign-in | Mobile + optional e-mail + name → OTP boxes (SMS 5 digits, e-mail 6 digits, 30 s resend) | `/auth/otp/request`, `/auth/otp/verify` |
| Google | Account picker → (new account) mobile + OTP | `/auth/google`, `/auth/google/complete` |
| Phone approval | Enter MPIN, or create MPIN + SMS OTP; registers the device key | `/auth/mpin/otp`, `/auth/mpin`, `POST /app/device-key` |
| Home | Header (menu, city chip, wallet pill), push banner/video carousel, quick actions, categories, brands, nearby shops, floating Scan & Pay | `GET /app/feed`, `POST /app/location` (every 5 min) |
| Banner popup | Shop, rating, offer, product price → final price, distance, Get offer, Directions, View shop | `GET /app/ads/{id}`, `POST /app/ads/{id}/event` |
| Side bar | Profile, Wallet, Prepaid card, Offers, Payment requests, Transactions, Notifications, Security, Help, Sign out | |
| Discover | Category / brand / search lists with Nearest · Best offer · Top rated | `GET /app/discover`, `/app/categories`, `/app/brands` |
| Shop | Header, directions, call, Products / Services / Reviews, Get offer per product | `GET /app/merchants/{uuid}`, `/reviews` |
| Offers | Offer code (6 digits, countdown, copy, share), my codes | `POST /app/offers/claim`, `GET /app/offers/claims` |
| Wallet | Balance, Add money (UPI QR + open UPI app), To prepaid card, To bank / UPI ID, To X9 user, statement | `/app/wallet`, `/app/wallet/load`, `/app/wallet/pay`, `/app/beneficiaries`, `/app/ledger` |
| Prepaid card | Card face, balance, details (auto-hide 30 s), change PIN, usage limits, block / unblock, transactions, get virtual card | `/app/cards*` |
| Scan & Pay | X9 bill QR → bill review → wallet or card → result → rating; UPI QR → phone's UPI app | `/app/invoices/claim`, `/app/invoices/{id}/pay` |
| Payment requests | Merchant payment links, paid from the prepaid card | `/app/payment-links`, `/pay` |
| Transactions | History with filters, receipt (save to gallery, share), rate & review | `/app/history`, `/app/transactions/{id}`, `/app/receipts/{id}`, `/app/feedback` |
| Notifications | Inbox, mark read; FCM push with foreground banners | `/app/notifications`, `/app/notifications/read`, `/app/device-token` |
| Profile / Security | Name, change mobile / e-mail with OTP, Google link state; change PIN / pattern, fingerprint | `/app/profile`, `/app/profile/contact*` |

Every money call: review sheet → `AppLock.instance.confirm` (PIN / pattern / fingerprint) →
`Api.instance.money(...)`, which adds `Idempotency-Key` and the device signature `X-Txn-Signature`.

## iPhone (v6.19)

The same code builds for iOS on GitHub's macOS runners: **Actions → Build X9 iOS app**. The workflow runs
`flutter create --platforms=ios` around the committed `ios/Runner/AppDelegate.swift`, `ios/Podfile` and app icon
(`tool/make_ios_icons.py`), configures the project with `.github/scripts/patch_ios.py` and builds an unsigned
`.ipa` + Simulator app, or a signed `.ipa` / TestFlight upload when the Apple secrets are set. UPI payments on
iPhone use `lib/services/upi_apps_ios.dart` (picker of installed UPI apps). Full guide: `docs/IOS-BUILD.md`.

## Build

There is no local Flutter toolchain requirement for the server; the APK is built by GitHub Actions with the
latest stable Flutter. The workflow runs `flutter create` to generate the Android/Gradle files around the
committed `lib/`, `pubspec.yaml`, `android/app/src/main/AndroidManifest.xml`, `MainActivity.kt` and launcher icons, then:

```
flutter pub get
flutter build apk --release \
  --dart-define=API_BASE=https://<server>/api/v1 \
  --dart-define=ALLOW_SELF_SIGNED=true \
  --dart-define=GOOGLE_SERVER_CLIENT_ID=<web-client-id>.apps.googleusercontent.com
```

| `--dart-define` | Default | Meaning |
|---|---|---|
| `API_BASE` | `https://api.x9.com/api/v1` | X9 backend base URL |
| `ALLOW_SELF_SIGNED` | `true` | Trust the self-signed certificate of the `API_BASE` host only. Set `false` once the server has a domain with a real certificate. |
| `GOOGLE_SERVER_CLIENT_ID` | empty | Google "Web client ID" (Firebase → Authentication → Google). Needed for Google sign-in to return an ID token. |
| `SUPPORT_EMAIL`, `SUPPORT_PHONE` | empty | Optional contact buttons on the Help screen. |

Gradle requirements for the generated Android project (the CI must patch `android/app/build.gradle(.kts)`):

* `flutter_local_notifications` needs **core library desugaring**:
  `compileOptions { isCoreLibraryDesugaringEnabled = true }` and
  `dependencies { coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4") }`.
* `minSdk` 23 or higher (Firebase messaging, local_auth, mobile_scanner).
* `applicationId = "in.donezo.x9.user"`; namespace `com.donezo.x9.x9_user`.
* `MainActivity` must extend `FlutterFragmentActivity` for fingerprint / face unlock (`local_auth`) — it already does.
* Google sign-in: register the SHA-1 of the signing key (debug and release) for `in.donezo.x9.user` in the
  Firebase / Google Cloud project, otherwise the account picker returns an error.

### Firebase (push notifications)

Put the Firebase Android config at **`android/app/google-services.json`** (Firebase console → Project settings →
Android app `in.donezo.x9.user`) and apply the `com.google.gms.google-services` Gradle plugin. Without it the app
runs normally, just without push. Payment-link pushes should carry `data.type = "PAYMENT_LINK"` so a tap opens
Payment requests (any other push opens Notifications).

### Launcher icons

`python3 tool/make_icons.py` (needs Pillow) builds the launcher icons (legacy, round, adaptive foreground) and the white-splash mark from the brand artwork in `/root/x9/brand` into `android/app/src/main/res`. The splash (`drawable/launch_background.xml`) is white with the X9 mark centred.

## Code layout

```
lib/
  main.dart            init session, app lock, push → runApp
  app.dart             MaterialApp + RootGate (sign-in / lock / device approval / relock on resume)
  state/app_state.dart feed, balances, badge counts, sign-out (ChangeNotifier singleton)
  services/            location (GPS, geocoding, 5-min heartbeat), push (FCM + local notifications), google_auth
  util/helpers.dart    JSON helpers, navigation, external links, error messages
  widgets/             banner carousel, merchant card, amount entry + review sheet, result screen, receipt view,
                       OTP boxes, paged list, skeletons, rating sheet, small UI bits
  screens/<area>/      auth, setup, home, merchant, offers, wallet, card, pay, payment_links, history,
                       notifications, profile, security, help
```

## Offers v3 (see /root/x9/docs/OFFERS-V3.md)

- Home "Offers" section and a full infinite-scroll Offers feed (filters All/Price offers/Cashback, sort,
  pull-to-refresh), offer detail (gallery, countdown, products MRP/offer/pay balance, cashback explainer, shop,
  share), search screen (`GET /app/search`, debounced, grouped), merchant screen gallery + live offers.
- Invoice / pay / receipt screens use `widgets/invoice_breakdown.dart` (lines, MRP/net total, GST, TOTAL TO PAY,
  cashback line); wallet and history show CASHBACK rows.
- Deep links: `x9://offer/CODE` and `https://HOST/o/CODE` via `app_links`
  (`services/deep_link.dart`, manifest intent filters). The https filter currently lists the server IP:
  add the real domain in `AndroidManifest.xml` once it exists.
- New dependency: `app_links`.

## Wrong server address / blank screen

The address compiled in with `API_BASE` can be changed on the phone: **Server settings** (link at the bottom of the sign-in screen, long-press on the logo, or the button on the start-up error screen). It can also test the connection and copy diagnostics for support. See `x9_core/README.md`.

## v6 features (1.1.0+3)

API contract: `docs/SIGNUP-KYC-VIP-UPI-V6.md`. All additive; the existing sign-in, wallet, card and Scan & Pay flows are unchanged.

| Area | What the app does | API |
|---|---|---|
| Create account | Welcome → "New to X9? Create account" → details (name, mobile, e-mail, Aadhaar address, 6-digit pin code, location via "Use my location", optional Aadhaar / PAN / bank) → WhatsApp code (resend countdown) → signed in. The form lives in `x9_core` (`SignupScreen`). | `POST /auth/signup/request`, `POST /auth/signup/verify` |
| Sign-in without account | `404 SIGNUP_REQUIRED` shows "No account for this number. Create one." and opens sign-up with the mobile filled in. | `/auth/otp/request`, `/auth/otp/verify` |
| Secure this device | A new account clears any app lock left on the phone, so the root gate always shows the lock setup (PIN / pattern / fingerprint / screen lock) after sign-up. | |
| KYC | Home banner "Complete KYC" (hidden when VERIFIED), Profile / Security / side bar entry "KYC verification": status chip, remarks, upload form (PAN, Aadhaar front/back, selfie, optional bank + cancelled cheque; photos via `image_picker`, max 5 MB each). Any `403 KYC_REQUIRED` (wallet add money / pay / transfer, prepaid card, payment requests, invoices, VIP purchase) opens the "Complete KYC to use wallet, prepaid card and banking" dialog. | `GET/POST /app/kyc` |
| X9 VIP Club | Home tile, Profile and side bar entry. Plans with price and benefits → "Join VIP Club" → dynamic UPI QR + "Pay with UPI app" → polls every 3 s → "Collect your physical card" with the fulfilment status. | `GET /app/vip`, `POST /app/vip/purchase` (Idempotency-Key), `GET /app/vip/purchases/{id}` |
| Add money | Maximum ₹99,000 enforced on the amount screen; the dynamic QR (`qr` data URI, falls back to the `upi_intent` QR) is polled every 3 s for the instant credit. | `POST /app/wallet/load`, `GET /app/wallet/loads/{load_id}` |
| UPI QR | Scan & Pay still handles X9 bill QR codes; a scanned `upi://` code offers "Pay with UPI app". | |

Build notes: `image_picker: 1.1.2` was added (document photos); `flutter_test` is a dev dependency for the unit tests in `test/`.
Shared pieces added to `x9_core`: `SignupApi`, `SignupScreen`, `X9OtpBoxes`, `KycApi`, `UserKycScreen`, `KycGate`, `isKycRequired`, `Api.uploadMulti`.
