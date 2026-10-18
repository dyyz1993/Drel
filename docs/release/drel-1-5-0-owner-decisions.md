# Drel 1.5.0 Owner Decisions

Date: 2026-10-18

Status: accepted for implementation and TestFlight preparation. The owner
explicitly authorized 1.5.0 development and TestFlight distribution; 1.4.1 and
its existing release state remain out of scope.

## Decision 1 — Audit history follows grant-based capabilities

A user-visible, local, bounded permission audit history is required before
Drel ships data-bearing capabilities that use reusable grants or protected
system permissions. The first 1.5.0 review train ships only declared,
foreground-gesture-bound `haptic`, `vibrate`, `share`, and `fullscreen`
actions and creates no reusable grants, so it does not introduce a
permission-audit screen. The system share sheet remains the per-share user
decision point; Drel must not record share content or destination.

Requirements for data-bearing capabilities:

- Record prompt shown, user decision, selected scope, system authorization
  result, denied requests, successful protected-action execution, revocation,
  session expiry, and manifest update that removes an action.
- Store only metadata: action, capability family, purpose ID, subject identity,
  timestamp, and bounded outcome.
- Never store action payloads, share content, scanned values, or full user
  input.
- Keep the history local to the device and prune it by both age and count.
- Expose it from the same permission review surface that shows current grants.

## Decision 2 — Low-impact actions are declared, not persistently authorized

`haptic`, `vibrate`, `share`, and `fullscreen` require an exact signed action
declaration and a foreground user gesture, but do not create a reusable
per-app privacy grant. Share must always use the native iOS share sheet so the
user reviews the content and chooses the destination for each share action.

Rationale:

- Declarations make the SDK action inventory visible and prevent undeclared
  remote content from invoking native actions.
- Haptics disclose no user data and should not be presented as a privacy
  permission.
- Sharing can disclose user content, so user intent must be explicit for each
  action; a persistent grant is not a substitute for the system share sheet.

Boundary:

- `haptic` and `vibrate` are limited to tactile feedback and must be rate- and
  duration-bounded.
- `fullscreen` only hides host navigation/status chrome. The host-owned exit
  control remains visible; the action cannot rotate the device, disable
  scrolling, or dismiss the app.
- `share` accepts only the payload supplied for the user-triggered operation;
  it must not run silently in the background.
- Duration and repetition must be bounded.
- They must be foreground-gesture initiated.
- No persistent user grant is stored for these four actions.

Data-bearing capabilities such as camera, photos, Bluetooth, and microphone
remain separately gated. When implemented, they require just-in-time purpose
copy, minimum necessary system permission, and a user-visible denial path.


The first 1.5.0 review train remains limited to the selected low-risk actions:
`haptic`, `vibrate`, `share`, and `fullscreen`. A scan-only camera action is not
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

The first 1.5.0 review train remains limited to the selected low-risk actions:
`haptic`, `vibrate`, `share`, and `fullscreen`. A scan-only camera action is not
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
