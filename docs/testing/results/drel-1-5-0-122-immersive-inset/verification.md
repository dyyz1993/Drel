# Drel 1.5.0 build 122 — immersive control inset

Date: 2026-10-30

## Scope

The collapsed immersive control exposed a 30pt sliver at the screen edge.
Build 122 reduces that exposure to 20pt, a one-third reduction, and recenters
the chevron fully inside the visible portion.

The control's 44pt frame and extended hit target are unchanged. Collapsing the
toolbar, closing with `×`, and the left-edge history gesture remain separate.

## Verification

Framework layout unit test:

```text
WebBridgeKitTests.ImmersivePWAExitControlLayoutTests
testCollapsedLeftControlUsesAOneThirdNarrowerSliver
PASS
```

The test asserts:

- `control.frame.maxX == 20 ± 0.5`
- the chevron remains inside the visible 20pt sliver

Drel simulator UI test:

```text
DrelUITests/PWAPermissionTests
testV2FullscreenUsesGestureWithoutPermissionPromptAndKeepsNativeExit
PASS
```

The test navigates to the immersive route fixture, enters fullscreen, asserts
that the collapsed control's screen-space `maxX` is `20 ± 1`, captures the
evidence image, then verifies collapse, re-expand, and close behavior.

Device: `Tongbuview 17 Pro Fresh`, iOS 26.4.1.

## Artifacts

- `simulator-full.png` — full simulator screenshot of the 20pt sliver.
- `simulator-left-edge.png` — cropped edge detail.
