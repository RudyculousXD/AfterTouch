# Contributing to Nocta

Thanks for taking an interest. Nocta is a small, opinionated app, so this document is short.

## Building

```bash
brew install xcodegen
./Scripts/build.sh
```

`Nocta.xcodeproj` is **generated from `project.yml`** by XcodeGen and only `project.pbxproj` is
tracked. Never edit the project in Xcode and commit the result — change `project.yml` and
regenerate, or your change will be lost the next time someone builds.

Run the tests with:

```bash
xcodebuild -project Nocta.xcodeproj -scheme Nocta test
```

### Iterating on the Lock Screen UI

The Lock Screen space is invisible until the Mac locks, which makes designing against it slow.
Launch with the preview flag and the card is drawn over the desktop instead, while the Mac
stays unlocked:

```bash
open -n --env NOCTA_PREVIEW_LOCK_SCREEN=1 dist/Nocta.app
```

In preview mode the panel is deliberately *not* moved into the Lock Screen space, so you are
looking at the real view hierarchy without the private-API path in the way.

## What most needs help

- **New providers.** This is the highest-value contribution and the cheapest. A provider is one
  file in `Sources/Providers/` conforming to `MediaProvider`, plus one entry in
  `ProviderRegistry.standard()`. YouTube Music, Tidal and Amazon Music are all unclaimed.
- **Verification on other systems.** The Lock Screen technique is verified on exactly one
  machine (macOS 26.6.2, Apple silicon). Reports from other macOS builds, Intel Macs, and
  multi-display setups are genuinely useful — open an issue with your macOS build number and
  what you saw, even if the answer is "it worked".
- **Multi-display placement**, which is currently best-effort. See `docs/LOCK_SCREEN.md`.

## Things a pull request must not break

These are the load-bearing invariants. A change that violates one will be sent back.

1. **The Lock Screen panel can never accept keyboard input.** It is a non-activating `NSPanel`
   with `canBecomeKey` and `canBecomeMain` overridden to `false`. Password capture is prevented
   by construction, not by policy, and it stays that way. Do not add a text field, do not make
   the panel key, do not add a `CGEventTap`.
2. **The card stays clear of the authentication UI.** Placement is clamped away from the clock,
   avatar, password field and Touch ID prompt. `LockScreenLayoutTests` asserts this across four
   screen geometries; keep it passing.
3. **The UI must not know which provider is active.** Views read `MediaController`, never a
   concrete provider.
4. **No dead buttons.** If a service cannot do something, express it as a
   `ProviderCapabilities` member and let the UI hide the control, rather than showing one that
   silently fails.
5. **Private APIs stay quarantined.** `SkyLightBridge` and `SkyLightLockScreenPresenter` are the
   only files permitted to touch SkyLight. Everything else goes through the
   `LockScreenPresenting` protocol, so an unsupported macOS degrades instead of crashing.
6. **Nothing secret is logged or written to `UserDefaults`.** Spotify tokens live in the
   Keychain. There is no client secret in the binary and there must never be one — the OAuth
   flow is PKCE precisely so each user registers their own app.

## Style

Match the surrounding code. Swift 5 language mode (see the note in `project.yml` about why),
and comments that explain *why* rather than restating the line beneath them — the existing
files are the reference.

## Reporting bugs

Please include your **macOS build number** (`sw_vers -b`), the music app and version, and
whether the Mac was locked or unlocked. For Lock Screen faults, the log is the useful part:

```bash
log show --last 10m --predicate 'subsystem == "app.nocta.Nocta"' --info --debug
```
