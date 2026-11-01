# x9_core

Shared Dart package for the X9 apps (API client, session, theme, widgets).

Offers v3 additions:

- `lib/src/offer_math.dart`: integer-paise offer / GST / cashback math (`percentOf` round-half-up, `lineMath`,
  `billTotals`, `cashbackAmount`). Unit tests: `test/offer_math_test.dart` (contract vectors V1-V4).
- `lib/src/ui/offers_ui.dart`: `Countdown`, `ImageCarousel`, `showImageViewer`, `fmtIst`, `cashbackSkippedText`.
- `Api.upload(path, files: [...], fields: {...})` for multipart image upload.
- New dependencies: `http_parser`; dev: `flutter_test`.

## Start-up safety and server address (v1.0.1)

* `runX9App(...)` (`lib/src/bootstrap.dart`) starts every app: guarded zone, `FlutterError.onError`, a readable error panel instead of a
  blank / grey widget, each init step in its own try/catch with a 5 s timeout, a persisted start-up log, and `runApp` is always reached.
* `ServerSettings` (`lib/src/server_settings.dart`) keeps an on-device override of `API_BASE` (secure storage). Rules: `https://`
  (plain `http://` only for localhost, 10.x, 192.168.x), path ends in `/api/v1` (added when only the host is typed). `X9Config.effectiveApiBase`
  and `Api` read it at call time; an EMPTY `API_BASE` define means the default. A self-signed certificate is accepted only for the configured host and
  only when `ALLOW_SELF_SIGNED` is on or the host is an IPv4 address.
* `ServerSettingsScreen` (Server settings link on the sign-in screens, long-press on the logo, and the error panel) changes the address, tests
  `/up`, `{base}/health` and `{base}/categories` (HTTP status, latency, TLS error) and copies diagnostics incl. the start-up log.
