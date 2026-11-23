# How Nocta draws on the Lock Screen

This document exists because the technique behind Nocta's headline feature is **not an
official Apple API**, and pretending otherwise would be dishonest. Everything below was
verified on this machine rather than taken from documentation.

**Verified on:** macOS 26.6.2 (build 25G83), Xcode 26.6, Swift 6.3.3.

---

## API classification

The brief asked that each mechanism be classified rather than lumped together. Here is every
API Nocta relies on for the Lock Screen feature.

| Mechanism | Tier | Notes |
|---|---|---|
| `NSWindow.canBecomeVisibleWithoutLogin` | **① Public Apple API** | AppKit, `API_AVAILABLE(macos(10.5))`. Apple's own header comment: *"This API controls whether the receiver is permitted onscreen before the user has logged in."* |
| `NSPanel` + `.nonactivatingPanel`, window levels, `collectionBehavior` | **① Public Apple API** | Ordinary AppKit. |
| `CGSessionCopyCurrentDictionary()` → `CGSSessionScreenIsLocked` | **① Public Apple API** | Declared in `CoreGraphics/CGSession.h`. Our authoritative lock-state check. |
| `NSWorkspace` screen sleep/wake + session active/resign notifications | **① Public Apple API** | Covers display sleep and fast user switching. |
| `com.apple.screenIsLocked` / `com.apple.screenIsUnlocked` distributed notifications | **② Undocumented, not private** | Not in Apple's documentation, but require no entitlement, no private framework and no SIP change. Used only as a fast hint; tier ① polling is the source of truth. |
| `SLSMainConnectionID`, `SLSSpaceCreate`, `SLSSpaceSetAbsoluteLevel`, `SLSShowSpaces`, `SLSSpaceAddWindowsAndRemoveFromSpaces` | **③ Private API (SkyLight)** | Resolved via `dlopen`/`dlsym`. **This is the load-bearing piece and it is unsupported.** |

## The technique

SkyLight is the private C layer that WindowServer uses to drive every window on screen. Spaces
have an *absolute level*, and the lock screen shield sits at level `300`. Notification Center,
which remains interactive while the Mac is locked, sits at `400`.

Nocta therefore:

1. `dlopen`s SkyLight and resolves the five symbols above.
2. `SLSSpaceCreate` — makes a new space.
3. `SLSSpaceSetAbsoluteLevel(cid, sid, 400)` — raises it above the lock screen shield.
4. `SLSShowSpaces` — makes it visible.
5. `SLSSpaceAddWindowsAndRemoveFromSpaces(cid, sid, [windowNumber], 7)` — moves the panel in.

All five calls returned `kCGErrorSuccess` (`0`) during verification.

### Steps 4 and 5 are not one-shot

Sleeping and waking the displays while the Mac is locked makes the window server rebuild the
lock screen's set of shown spaces, and ours is not in the set it rebuilds from. The panel is
still *in* our space afterwards; our space is simply no longer *shown*, so re-adopting the
window (step 5) on its own puts it somewhere invisible. Both steps have to be re-issued.

Re-issuing once at the moment of wake is also not enough: the wake notification lands before
loginwindow has finished rebuilding, so an immediate repair gets undone a fraction of a second
later. `SkyLightLockScreenPresenter.reassertPersistently()` therefore repeats the repair on a
short bounded schedule (120ms → 2s), and the 5-second reconcile poll in `LockStateMonitor` is
the backstop for a wake that is never reported at all. Every repair is logged under subsystem
`app.nocta.Nocta`, category `lockscreen`, with which path triggered it.

### Lock Screen, not Login Window

Nocta only exists inside a logged-in user session, so the controller appears when the Mac
is **locked**. After a restart or a full log-out, nothing is running and nothing is drawn.
Nocta does not touch the login window and does not install an authorisation plug-in.

## Safety

Two structural decisions, not merely policies:

1. **The panel is a non-activating `NSPanel` with `canBecomeKey` and `canBecomeMain`
   hard-overridden to `false`.** Mouse events reach it; keyboard events never can. Capturing a
   password is therefore impossible by construction, and we cannot steal focus from the
   password field or prevent an unlock. This is a deliberate divergence from SkyLightWindow,
   which sets `canBecomeKey = true`.
2. **A reserved exclusion zone.** The top 26% (clock and date) and bottom 24% (avatar, user
   name, password field, Touch ID prompt) are off limits. Every position preset is clamped into
   the band between them. `LockScreenLayoutTests` asserts this on four screen geometries
   including a non-origin second display.

Nocta never installs an `SFAuthorizationPluginView`, never monitors the keyboard, never
requests Accessibility or Screen Recording, and never attempts to bypass authentication.

### The click-swallowing defect

The Stage 1 spike used a full-screen transparent panel. Because `NSView.hitTest` reports a hit
anywhere within bounds regardless of transparency, it swallowed clicks meant for apps
underneath. The shipping panel is **sized to the card** instead, with `PassthroughHostingView`
returning `nil` outside the content as a second line of defence.

Since the card can expand, the panel is sized to the union of both footprints — the collapsed
card is the wider, the expanded column the taller — resizing a window
that lives in the Lock Screen's own space mid-animation is not something to rely on — and
`PassthroughHostingView` narrows the interactive area to the card's *current* rect, which it
reads from the shared `LockScreenCardState`. The collapsed bar therefore leaves the rest of the
panel click-through, exactly as a content-sized panel would.

Collapsed, the controller is a single card with the artwork inset inside it; expanding lifts the
artwork out of it — bare, with no surface of its own — above a player that keeps the card's
width, so the bar changes height but never shape. The two surfaces are plain
sibling views rather than a `GlassEffectContainer` — the container composites its merged glass
pass *above* sibling views, which frosted the artwork drawn on top of the collapsed card.

The expanded player is only offered where it fits inside the exclusion band; on a short screen
`LockScreenLayout.Metrics.allowsExpansion` is false and the artwork stops being a control. The
card is anchored to the edge of the band matching the user's position preference, so expanding
always grows *away* from the clock and the unlock UI.

### Previewing the card without locking

`NOCTA_PREVIEW_LOCK_SCREEN=1` shows the card over the desktop while the Mac is unlocked and
skips the move into the SkyLight space (that space is invisible until the Mac actually locks):

```bash
NOCTA_PREVIEW_LOCK_SCREEN=1 dist/Nocta.app/Contents/MacOS/Nocta
```

## Verification results

From the Stage 1 spike (`spike/spike.log`), macOS 26.6.2:

```
[15:31:37.311] [locked=YES] EVENT: screenIsLocked
[15:31:39.552] [locked=YES] >>> BUTTON CLICKED (#1) — HAPPENED WHILE LOCKED
   … 7 clicks between 15:31:39.552 and 15:31:40.909 …
[15:31:42.306] [locked=no ] EVENT: screenIsUnlocked
```

- Renders above the lock screen shield, with a live-updating clock. ✓
- Seven clicks registered while `CGSSessionScreenIsLocked == 1`. ✓
- Password unlock unimpeded, twice, with the panel on screen. ✓

## Fragility — read this before relying on it

Private APIs carry no compatibility promise. Real, current evidence from the Atoll issue
tracker (which uses the same SkyLightWindow technique):

- Crash when locking or starting the screensaver on **macOS 27 beta** (issue #659)
- General macOS 27 beta incompatibility (issue #632)
- Recurring **multi-display** problems — lock screen widgets appearing only on the built-in
  display (issues #374, #524, #93)

Nocta mitigates the first class of failure by probing for every required symbol with
`dlsym` at launch. If any is missing, `LockScreenPresenterFactory` returns
`UnsupportedLockScreenPresenter` and Settings shows *"Lock Screen controls aren't supported on
this version of macOS."* The app keeps working as a menu-bar and window player.

Multi-display is **best-effort**. Nocta creates one panel per screen and re-adopts on
`didChangeScreenParametersNotification`, but placement on external displays is exactly the area
where the technique is known to be unreliable.

## What this costs

Because Nocta is not sandboxed (Apple Events to arbitrary apps, plus `dlopen` of a private
framework), **it cannot ship on the Mac App Store.** Distribution is Developer ID + notarisation.

## Licensing

The call sequence was learned from **SkyLightWindow** by Lakr233, which is **MIT licensed** and
therefore safe to learn from and attribute. **Atoll is GPL-3.0** and **AtollExtensionKit is
LGPL-3.0**; neither was copied, and only high-level architectural ideas (manager/panel
separation, poll-plus-notification lock detection) were taken from them. Ideas are not
copyrightable; code is. See `NOTICE`.
