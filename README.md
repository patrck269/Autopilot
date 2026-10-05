# Autopilot

ComputerCraft ship control with engine, command, pocket, and independent watchdog programs.

Run the matching installer from install/ on each computer. It fetches a pinned source revision, stages its dependencies, and reboots after successful replacement. Hardware names and tuning defaults are in src/config.lua.

Engine modems default to back (wired) and right (ender). Command and pocket modems use back. Keyboard controls: arrows forward/back, A/D sideways, Space/Shift up/down, M/S/U modes, E emergency, C clear, K cancel. Altitude, bearing, speed and waypoint fields accept typed numbers.

The optional debug bridge is tools/ship-shell/bridge.py. Supply a settings JSON with a nonempty token. WebSocket defaults to 8766; HTTP control binds localhost on 8767. Engine and watchdog read debug.token and debug.url. Configure RCON for forced shutdown of an unresponsive evaluation.

See [review fixes and tests](docs/code-review-fixes.md) for behavior changes, calibration assumptions, and validation coverage.
