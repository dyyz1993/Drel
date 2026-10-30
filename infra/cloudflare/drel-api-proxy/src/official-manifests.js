/**
 * Immutable manifests served directly by the official Drel gateway.
 *
 * The App Review action demo is content-addressed by cache.version and must
 * stay available even when the dynamic manifest registry reaches a storage
 * quota. Keeping this record in the Worker lets its GET path sign the exact
 * published bytes without reading or writing a Durable Object.
 */
export const OFFICIAL_MANIFESTS = Object.freeze([
  {
    schemaVersion: "1",
    appId: "dev.drel.action-demo",
    name: "Drel Action Demo",
    startURL: "https://drel.app/test/actions/v1/index.html",
    allowedOrigins: ["https://drel.app"],
    capabilities: [],
    capabilities_v2: [
      {
        action: "haptic",
        origins: ["https://drel.app"],
        purposeId: "action-demo-haptic",
        purpose: "Demonstrate brief haptic feedback",
        scope: "appSession",
      },
      {
        action: "vibrate",
        origins: ["https://drel.app"],
        purposeId: "action-demo-vibrate",
        purpose: "Demonstrate brief vibration",
        scope: "appSession",
      },
      {
        action: "share",
        origins: ["https://drel.app"],
        purposeId: "action-demo-share",
        purpose: "Share the Drel action demo",
        scope: "appSession",
      },
      {
        action: "fullscreen",
        origins: ["https://drel.app"],
        purposeId: "action-demo-fullscreen",
        purpose: "Present the demo immersively",
        scope: "appSession",
      },
      {
        action: "clipboard",
        origins: ["https://drel.app"],
        purposeId: "action-demo-clipboard",
        purpose: "Read or write clipboard content for this demo",
        scope: "always",
      },
      {
        action: "getLocation",
        origins: ["https://drel.app"],
        purposeId: "action-demo-get-location",
        purpose: "Get the current position for this demo",
        scope: "always",
      },
      {
        action: "addToHomeScreen",
        origins: ["https://drel.app"],
        purposeId: "action-demo-home",
        purpose: "Add this demo to the Drel home screen",
        scope: "appSession",
      },
    ],
    routes: ["/test/actions/v1/index.html"],
    webManifest: {
      url: "https://drel.app/test/actions/manifest.webmanifest",
      sha256: "f864c7f7ae45fcaee9c7fc0a96f6f7855a470793008194e69f7016309d93dbb9",
    },
    cache: {
      strategy: "networkOnly",
      version: "4",
      persistent: false,
      restoresLastState: true,
    },
  },
]);
