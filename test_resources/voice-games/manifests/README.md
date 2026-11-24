# Voice game staging manifests

These unsigned manifest inputs target a temporary HTTPS test server running on the development Mac and routed through legacy backend. They are not production-ready or strong-offline packages. Register them only as device-key-scoped private manifests on the trusted gateway; do not add them to the public catalog while deployed Drel versions lack `audioLevel`. Verify each returned signature and device visibility before opening it in the microphone-enabled TestFlight build. No device key, admin token or signing key belongs in these files.
