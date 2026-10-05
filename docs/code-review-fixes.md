# Review fixes and validation

All source modules, programs, installers, tests, bridge code, and design documents were reviewed. The 16 reproduced findings are addressed:

1. Emergency commands have queue priority and immediately latch the engine.
2. Waypoints steer a world-space bearing and project targets into ship coordinates.
3. Velocity feedback and force-to-RPM conversion replace velocity-as-RPM commands.
4. Quaternion rotation supplies measured ship-relative velocities and angular rates.
5. Nonfinite numerical inputs are rejected; angle wrapping uses constant-time modulo.
6. Hover diagnostic entry captures the current elevation RPM.
7. Diagnostic exit clears jobs and keeps outputs zero until another explicit command.
8. Lost engine connections retain independent watchdog arming.
9. Shutdown state resets for each eval/session; failed RCON shutdowns can retry.
10. Held keyboard inputs repeat every 0.1 seconds; engine freshness expires after 0.35 seconds.
11. Pocket renders telemetry and diagnostic controls, with controller selection.
12. Automatic braking targets zero velocity, then approaches if it stopped short.
13. Reconnection clears stale eval state and wakes old request waiters.
14. Encoded replies respect the 96 KiB wire limit and report truncation. Print, table export, and reads are bounded.
15. Superseded sockets close and stale source messages cannot update a new session.
16. WebSocket port defaults to 8766; explicitly configured zero still supports ephemeral testing.

Additional changes include staged syntax-checked installers with rollback, file replacement backups, best-effort writes to every actuator when a peripheral fails, zero output on engine termination, guarded modem discovery, measured loop timing, combined translation/yaw forces, outage timer reset, diagnostic lift cutoff protection, forward propulsion stress accounting, monitor page swapping, smaller monitor controls, and malformed HTTP/RCON/WebSocket input handling. Semi mode combines an altitude job with speed control.

## Tests

Run from the repository root with Lua 5.2+ and Python 3:

    lua tests/run.lua
    python tools/ship-shell/test_regressions.py
    python tools/ship-shell/test_bridge.py

Set LUA_EXE when Lua is not on PATH. The Lua suite includes all existing altitude/control tests, the shipped engine event loop with mocked peripherals, installer download/commit failure recovery, sustained speed caps, four rotated navigation scenarios with initial crosswind, and encoded reply bounds. Python tests exercise bridge lifecycle regressions and the shipped bridge/Lua shell over actual loopback sockets.

## Calibration and operational limits

Validation is simulated; an individual Minecraft ship still needs calibration. Verify peripheral mappings, thruster directions, mass, available shaft stress, and hover equilibrium against the installed ship. The default body frame is forward +X, right -Z, up +Y, rotated into world coordinates by the ship quaternion. Heading zero faces +X; increasing heading faces -Z. Targets are 3 m/s manual, 35 m/s semi, and 7/50 m/s cruise/warp. External forces and saturated actuators can prevent immediate velocity correction.

RCS force uses 100,000 N at 256 RPM with exponent 1.2. Propeller control uses calibrated sea-level hover equilibrium with altitude density correction. Tune these assumptions to the installed mod configuration. Default modeled stress includes four elevation bearings and one forward bearing; adjust X_PROPS in src/stress.lua to the actual forward bearing count. Residual shaft load is estimated from measured stress. Actual RCS force and shared stress capacity determine side stopping distance; the old one-block lateral stopping claim is unsupported at the default mass.

Lost engine connections keep the watchdog armed. Operator clear releases a watchdog latch. Diagnostic exit holds all outputs at zero until another explicit control command. Pocket directions are short pulses with release-to-stop.

Installers stage and syntax-check every dependency before changing live files, replace startup last, and roll back commit failures without rebooting. If rollback fails, staging files remain for recovery.
