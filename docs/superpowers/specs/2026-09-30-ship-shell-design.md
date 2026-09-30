# Ship debug shell

A LAN websocket lets an operator run Lua inside the engine computer, replace files on that computer, and reboot it. A second computer on the ship's wired network forces every relay and rotation speed controller to zero if that Lua stalls. The flight laws are unchanged except for this latch.

With the bridge stopped and no `debug.token` on the engine, the ship flies as it does today.

## Machines

The engine program runs the flight loop and a shell coroutine together with `parallel.waitForAll`. The shell catches its own errors. An error in the shell does not stop the flight loop. The shell retries a failed dial every 5 seconds from its own coroutine.

The watchdog is a normal computer on the engine-room wired network, with its wired modem on the back. It loads with the ship. It does not open an ender modem and it does not run the flight loop. It wraps the relays and speed controllers named in `config.default()` and writes them only while a zero latch is held.

The bridge is one Python 3 process on the operator's machine, standard library only. It accepts the ship websocket on the LAN address and port in its local settings, default port 8766. It serves control HTTP on `127.0.0.1` port 8767 and on no other address. The websocket handshake advertises no extensions and does not offer per-message compression.

## One-time server rule

ComputerCraft on this world denies HTTP and websocket connections to private addresses. One allow rule is inserted above the `$private` deny in the world's `computercraft-server.toml`. Earlier rules override later ones, so the allow has to be first.

```toml
[[http.rules]]
host = "<ws_host from the bridge settings>"
port = 8766
action = "allow"
```

The dedicated server reads that file on startup. One restart is required before the first session. Later sessions do not need a restart.

## Token and local settings

`tools/ship-shell/bridge.local.json` is gitignored. It holds:

| Field | Meaning |
|---|---|
| `token` | Shared secret. Empty refuses every websocket. |
| `ws_host` | LAN address the bridge binds and the allow rule names. |
| `ws_port` | Websocket port. Default 8766. |
| `http_port` | Loopback control port. Default 8767. |
| `rcon_host` | Dedicated server address. |
| `rcon_port` | Dedicated server RCON port. |
| `rcon_password` | Dedicated server RCON password. |

The same token is written into `debug.token` in the root of the engine computer and the watchdog computer, beside `startup.lua`. The file is placed in the world save. It is not part of the repo and it is not downloaded by an installer. The bridge does not log the token or the RCON password.

A computer with no `debug.token` never opens a socket. The engine still flies. The watchdog stays disarmed and does not write peripherals.

## Link

`src/link.lua` reads the token, connects, and reconnects. The first frame a computer sends is `hello`. Any other first frame closes the socket. The bridge answers `ready` or closes the socket.

```json
{"type":"hello","id":12,"role":"engine","label":"engine","token":"<token>"}
{"type":"ready"}
```

`id` is `os.getComputerID()`. `role` is `engine` or `watchdog`. A token mismatch closes the socket. A second hello for a role replaces that role's socket.

Frames are JSON text. Binary frames are ignored. A frame larger than 96 KB is rejected so it stays under the server's 128 KB websocket cap. The bridge rejects an oversized control request with an HTTP error and does not send it. A result that would exceed 96 KB is truncated and the result object sets `truncated` to true.

## Wire protocol

The bridge assigns an id to every engine request. The engine echoes it in `result`.

| Frame | Direction | Effect |
|---|---|---|
| `eval` | bridge to engine | Compile and run one Lua chunk. |
| `write` | bridge to engine | Replace one file under the computer root. |
| `read` | bridge to engine | Return one file. |
| `reboot` | bridge to engine | Answer, then reboot. |
| `zero` | bridge to engine and watchdog | Latch zero on both. |
| `clear` | bridge to engine and watchdog | Drop both latches. |
| `result` | engine to bridge | Return values, captured prints, or an error. |
| `status` | engine to bridge | Once per second while the shell is between evals. |
| `arm` | bridge to watchdog | Start the silence watch. Includes `engine_id`. |
| `disarm` | bridge to watchdog | Stop the silence watch when no latch is held. |

`arm` is sent after a good engine `hello`. `disarm` is sent when that engine socket closes cleanly. `arm` does not clear a latch.

One eval runs at a time. A second `eval` gets `result` with `ok` false and `error` `"busy"`.

```json
{"type":"eval","id":"4","code":"return state.mode, state.hover_rpm"}
{"type":"result","id":"4","ok":true,"values":["idle",430],"output":""}
{"type":"result","id":"5","ok":false,"error":"busy"}
```

`output` is text from `print` during the chunk, truncated at 8 KB. `values` is the list of return values as JSON. A value JSON cannot encode becomes a string of its Lua serialization. On failure, `error` is the Lua error text and `values` is empty.

`status` carries mode, job, phase, emergency, diagnostic, the altitude setpoint, `hover_rpm`, `x_rpm`, world Y, vertical speed, horizontal speed, heading, and current SU. Mode, job, phase, the flags, the setpoint, and the two RPM fields come from `state`. World position, vertical speed, and heading come from `session.ship`, the table the flight loop already builds for `engine_tick.tick`. Horizontal speed is the horizontal magnitude of that velocity. SU comes from `session.su`, the stressometer reading stored on that same tick. Anything else is an eval.

`write` takes `path` and `content`. The path stays inside the computer's own filesystem. The shell writes `path .. ".tmp"`, closes that handle, deletes `path` if it exists, and `fs.move`s the temp file onto `path`. A crash before the delete leaves the previous file and the temp file. `read` of a missing path returns `ok` false.

`reboot` sends its `result`, yields for half a second so that frame can flush, then calls `os.reboot()`. The computer boots from disk. In-memory mode, hover RPM, PID state, and the engine emergency flag start over. A watchdog latch still held writes zeros across that reboot, and the new boot honors the latch message below.

## Eval

Each chunk is loaded with `load(code, "=eval", "t", env)`. `env` has `__index` set to the computer's real `_G`, so the chunk can call the same functions the autopilot can. These names point at the live session on every eval:

| Name | What it is |
|---|---|
| `state` | The flight table `engine_tick.tick` mutates and returns. |
| `cfg` | The `config.default()` table the flight loop passes into each tick. |
| `devices` | The wrapped relays, speed controllers, and gauges. |
| `engine_tick`, `runtime`, `config`, `protocol`, `package` | The module tables the flight loop already calls. |
| `session` | Latch flag and the latest ship sample. |

The flight loop assigns `session.state` from the table `tick` returns, every tick. Replacing `engine_tick.tick` or `runtime.apply` on those module tables is what the next tick calls. `require` uses `package.loaded`, so a replaced module stays replaced until reboot.

`state.hover_rpm = 430` and `state.mode = "idle"` are visible to the next tick. `devices.rsc11.setTargetSpeed` writes the Create block during the eval. The next tick overwrites it with whatever `runtime.apply` sends. A hardware write stays only when that next tick would send the same value: emergency zero, diagnostic mode, or a patched `state` or `tick`.

`print` is redirected for the duration of the chunk and restored afterward, including when the chunk errors.

The chunk runs on the shell coroutine. Until it returns, the shell does not send `status` and does not start another eval. A chunk that does not yield blocks the flight loop as well, because `parallel` only pulls the next event after every coroutine yields. A chunk that yields lets the flight loop run during the eval. Yields inside the chunk are yields of the shell coroutine.

An eval that returns in under 3 seconds does not change the emergency flag. Thrust stays at the last applied outputs. An eval whose wall time reaches 3 seconds sets `session.latched` and `state.emergency` before it yields back to the flight loop.

## Watchdog

`src/watchdog.lua` is a pure step function. `programs/watchdog.lua` does the I/O.

The bridge's `arm` frame names the engine computer id and sets `last_status_at` to the time of arming. While armed and not latched, the watchdog listens on the wired modem. A rednet table from that computer id whose `mode` is a string refreshes `last_status_at`. Messages from any other computer do not.

If `now - last_status_at` reaches 3 seconds, the watchdog latches. A `zero` frame latches immediately. While latched, every 0.2 seconds the program calls `runtime.apply` with `mix.zero()`:

- every rotation speed controller `setTargetSpeed(0)`
- Relay 2 analog 0 on the bottom
- every other named relay off on every side

On that same cadence it broadcasts `{type="watchdog", latched=true}`. The engine honors that table from any sender, the same way it honors other broadcast commands. Receiving `latched=true` sets `session.latched` and `state.emergency`. At the start of a timer tick the flight loop does three things in order. A pending `clear_emergency` clears `session.latched` and `state.emergency`. Otherwise a set latch sets `state.emergency`. Then `engine_tick.tick` runs, so a latched tick returns `mix.zero()` and does not write the previous RPM back. A timer event already queued ahead of the latch message can apply the old outputs once. The watchdog's next 0.2 second write puts the zeros back.

A clean `disarm` while no latch is held stops the silence watch. A `disarm` while a latch is held does not stop the 0.2 second writes. If the watchdog socket drops without a `disarm` frame, the watch stays armed. The next engine status while a latch is not held disarms it. Status does not clear a latch.

`clear` from the bridge, and a broadcast `{type="clear_emergency"}`, clear the latch. The watchdog broadcasts `{type="watchdog", latched=false}` once and stops writing. The engine clears `session.latched` and `state.emergency` on that frame and on `clear_emergency`. A stale `latched=true` still in the queue can turn emergency back on. Another clear turns it off.

The pocket's existing clear-emergency command is that broadcast, so a dead bridge is not the only way to drop the latch.

## Bridge

Control HTTP is JSON. The bridge generates request ids.

| Request | Body | Behavior |
|---|---|---|
| `GET /session` | | Engine id, both sockets, armed, latched, age of the last websocket status, and whether shutdown was sent. |
| `GET /status` | | Latest `status` frame. |
| `POST /eval` | `{"code":"..."}` | Wait up to 8 seconds for `result`. |
| `POST /write` | `{"path":"...","content":"..."}` | Wait for `result`. |
| `GET /read?path=` | | Wait for `result`. |
| `POST /reboot` | | Wait for `result`. The engine reboots after sending it. |
| `POST /zero` | | Send `zero` to both sockets. |
| `POST /clear` | | Send `clear` to both sockets. |

`POST /eval` returns `{"ok":false,"error":"timeout"}` at 8 seconds. The eval stays outstanding. If an eval is outstanding and the engine socket has delivered neither `result` nor any other frame for 10 seconds, the bridge opens RCON and sends `computercraft shutdown #<id>`, using the engine computer id from `hello`. It does not send `computercraft turn-on`. Shutdown stops a tight Lua loop from holding the server's computer-time budget. It does not by itself change speed-controller setpoints. The watchdog has been writing zeros since the 3 second mark. Turning the computer back on is a separate RCON command after the disk copy is one the operator is willing to boot.

Stdout logs connects, disconnects, eval ids, and shutdown. It is not the control API.

A live `write` is an experiment on that computer. The copy that is kept is the one committed in the repo and installed with the pinned installer URL.

## Install

The engine installer also downloads `src/link.lua` and `src/shell.lua`. `programs/engine.lua` requires the shell and runs it beside the flight loop. The flight loop publishes `session.state`, `session.cfg`, `session.devices`, `session.ship`, and `session.su` each tick.

`install/watchdog.lua` saves `programs/watchdog.lua` as `startup.lua` and downloads `src/watchdog.lua`, `src/link.lua`, `src/config.lua`, `src/mix.lua`, `src/speed.lua`, and `src/runtime.lua`.

Both installers keep the current rule. `BASE` is an immutable commit, and both installers are updated together when a build is published.

`.gitignore` includes `tools/ship-shell/bridge.local.json`.

## Tests

Lua, on the desktop suite:

- Watchdog step: arming does not latch; status from the engine id refreshes the timer; status from any other id does not; 3 seconds of silence latches; `zero` latches immediately; a latch keeps writing across `disarm`; status does not clear a latch; `clear` and `clear_emergency` clear it; a socket drop without `disarm` stays armed until a non-latched status.
- Shell: a missing token does not dial; a second eval while one is running returns busy; `print` and return values are captured; wall time of 3 seconds sets the latch before the flight loop runs again.

Python, in `tools/ship-shell/test_bridge.py`: a loopback client completes hello and one eval; an oversized frame is rejected; a client that accepts `eval` and sends nothing causes the shutdown command to be issued at 10 seconds. The test uses a fake RCON sink.

The in-game check after installation:

1. Bridge stopped, no token: the ship still flies.
2. Token in place and bridge running: `GET /session` shows the engine and the watchdog.
3. `POST /eval` with `return state.mode` returns the current mode.
4. `POST /write` and `GET /read` round-trip one file.
5. `POST /zero` latches emergency and the speed controllers stay at 0.
6. `POST /clear` drops the latch.

## Out of scope

No public listener, no command-computer queue, and no shell on the command-center computer or the pocket. The bridge is not an MCP server. Flight tuning, hover gains, and the rednet command set stay as they are. The watchdog does not fly the ship and does not write peripherals while it is disarmed and unlatched.
