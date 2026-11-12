# Drel 1.5.2 App Review Notes — Draft

This document is a draft. Public demo links and physical-device acceptance must be verified before App Review submission.

Drel 1.5.2 adds `audioLevel` for signed, trusted HTML applications only. The app declares its purpose and exact allowed origin in the signed manifest; a foreground user tap is required to request access. Drel presents a revocable user consent choice, followed by iOS microphone authorization where required. It passes normalized sound level only to the game: raw microphone samples and recording files are not exposed by this action. Capture stops on stop, leaving the page, app background, interruption, or revocation. It is not available to arbitrary untrusted pages.

The existing actions are `haptic`, `vibrate`, `share`, `fullscreen`, `clipboard`, `getLocation`, `addToHomeScreen`, and `sensors`. Clipboard, getLocation, sensors and audioLevel require consent and support revocation where applicable. The remaining actions are gesture-gated; share presents the system sheet.

## Reviewer walkthrough — pending deployed demo URLs

1. Open a trusted signed Voice Jump or Dandelion demo from the app catalog.
2. Tap the microphone start button. Cancel and verify the game does not start.
3. Tap again, consent in Drel and the iOS microphone prompt, then make sound to interact.
4. Revoke the microphone grant in the app permission center; verify sound updates stop.

Hardware verification, stable demo links, privacy disclosures, and final App Store metadata remain pending.
