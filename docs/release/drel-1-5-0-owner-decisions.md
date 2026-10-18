# Drel 1.5.0 Owner Decisions

Date: 2026-10-18

Status: accepted for planning. This document settles the four open questions from
`docs/release/drel-1-5-0-preproject-assessment.md`. It does not authorize an
App Store Connect version, feature branch, code change, or submission.

## Decision 1 — Local audit history is required

Drel 1.5.0 must ship a user-visible, local, bounded permission audit history.
The current permission list is not sufficient because it records only the
current grant state, not the authorization and execution lifecycle.

Requirements:

- Record prompt shown, user decision, selected scope, system authorization
  result, denied requests, successful protected-action execution, revocation,
  session expiry, and manifest update that removes an action.
- Store only metadata: action, capability family, purpose ID, subject identity,
  timestamp, and bounded outcome.
- Never store action payloads, share content, scanned values, or full user
  input.
- Keep the history local to the device and prune it by both age and count.
- Expose it from the same permission review surface that shows current grants.

## Decision 2 — Haptic and vibrate require signed declarations

`haptic` and `vibrate` must use the same signed action-level declaration,
authorization, audit, and revocation path as `share` and `scan`.

Rationale:

- A uniform trust boundary is easier to review and explain.
- Even non-data actions can disturb the user or be used for abuse.
- Keeping all protected actions on one contract avoids a second, weaker policy
  path in the first release.

Boundary:

- `haptic` and `vibrate` are limited to tactile feedback.
- Duration and repetition must be bounded.
- They must be foreground-gesture initiated.
- They support only `once` or `appSession`, never `always`.


The first 1.5.0 review train remains limited to the already selected low-risk
actions: `haptic`, `vibrate`, and `share`. A scan-only camera action is not
authorized for the first 1.5.0 review train.

Later 1.5.x candidates may be evaluated separately in this order:

1. scan-only camera;
2. photo access only when a concrete user-selected import/export journey and
   privacy package exist;
3. Bluetooth only with device discovery/pairing semantics and a user-visible
   purpose;
4. microphone or voice-controlled game input last, after audio retention,
   background capture, and on-device processing boundaries are specified.

This decision keeps the first review train easier to explain and avoids mixing
several sensitive iOS prompts into one release. It does not authorize any
additional capability.

## Decision 5 — First 1.5.0 release scope excludes camera, photos, Bluetooth,
and microphone

The first 1.5.0 review train remains limited to the already selected low-risk
actions: `haptic`, `vibrate`, and `share`. A scan-only camera action is not
authorized for the first 1.5.0 review train.

Later 1.5.x candidates may be evaluated separately in this order:

1. scan-only camera;
2. photo access only when a concrete user-selected import/export journey and
   privacy package exist;
3. Bluetooth only with device discovery/pairing semantics and a user-visible
   purpose;
4. microphone or voice-controlled game input last, after audio retention,
   background capture, and on-device processing boundaries are specified.

This decision keeps the first review train easier to explain and avoids mixing
several sensitive iOS prompts into one release. It does not authorize any
additional capability.

## Decision 3 — Security review ownership

The Drel product owner owns security review and final security sign-off.

The owner may commission another reviewer or security engineer, but the product
owner remains accountable for accepting the result. A 1.5.0 implementation plan
must name the reviewer before code starts and must record the reviewer’s
sign-off before TestFlight distribution.

## Decision 4 — App Review and privacy ownership

The Drel product owner owns the App Review narrative, privacy disclosure, and
final privacy sign-off.

The owner may delegate drafting, but not the acceptance decision. Before any
ASC version is created, the owner must approve:

- the exact action catalog and data-flow description;
- iOS usage strings;
- privacy manifests and questionnaire answers;
- the signed demo app and deterministic manifest;
- the App Review video and notes;
- the statement that Drel does not provide a generic or remotely extensible
  JavaScript-to-native Bridge.

## Consequences

These decisions make the first 1.5.0 implementation slightly larger, but they
remove the two highest-risk ambiguities: a partial permission ledger and an
inconsistent declaration policy. They also make security and App Review
accountability explicit before implementation begins.
