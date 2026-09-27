# Ship autopilot

The engine-room computer flies the ship, draws the four command-center monitors, and is the only program that touches a relay or a rotation speed controller. The command-center computer is a keyboard on the wired network. The pocket computer is a remote, a GPS return control, and a diagnostic screen. It talks to the engine computer through ender modems.

World X and Z are the horizontal coordinates. World Y is altitude. The requirements draft calls the horizontal pair x,y. This spec uses X and Z.

## Hardware the programs expect

A config file on the engine computer maps each name below to the wired-network peripheral name, and gives each speed controller a ship-frame thrust direction that matches how that block is facing. It also stores `climb_rpm`, the RSC 11 setting used for a full climb. Names are assigned by the modem when a device is attached, so the mapping is data, not hardcoded network ids.

Redstone relays. Normal flight drives Relay 7 through Relay 10 on every side. Diagnostic mode can pick one side.

| Name | Normal job |
|---|---|
| Relay 2 | Stepped X throttle |
| Relay 3 | Cut off the X-axis propellers |
| Relay 5 | Cut off the Z-axis propellers |
| Relay 6 | Reverse the elevation propellers |
| Relay 7 | Cut off the port-bow elevation propeller |
| Relay 8 | Cut off the starboard-bow elevation propeller |
| Relay 9 | Cut off the starboard-stern elevation propeller |
| Relay 10 | Cut off the port-stern elevation propeller |

Rotation speed controllers:

| Name | Normal job |
|---|---|
| RSC 2 | Starboard-bow upward thruster |
| RSC 3 | Port-bow upward thruster |
| RSC 4 | Starboard-stern upward thruster |
| RSC 5 | Port-stern upward thruster |
| RSC 6 | Port-bow side thruster |
| RSC 7 | Starboard-aft side thruster |
| RSC 8 | Port-aft side thruster |
| RSC 9 | Bow-starboard side thruster |
| RSC 10 | X-axis Clockwork propeller throttle. Negative speed is reverse. |
| RSC 11 | Elevation-propeller throttle |

Telemetry: Speedometer 0 is main-engine shaft RPM before the gearbox. Stressometer 0 is the main engine's current stress use, in SU.

The engine computer has a wired modem on the back and an ender modem on the right. The command-center computer has a wired modem on the same cable. The pocket has an ender modem. GPS hosts are already in the world. This project does not build them.

The four monitors are advanced, so they accept touch. Two are 2×3 and two are 3×3. The program does not assume which network name is which size.

There is no manual-control stick relay. Manual flight comes from the command-center keyboard and the pocket.

## Messages

Both remotes send the same commands: set mode, set altitude, set bearing, set speed, set waypoint X and Z, set cruise or warp, stick, return-to-user, emergency stop, clear emergency, and the diagnostic commands below.

The last setpoint wins. A stick command applies only while fresh stick messages are arriving. When they stop, that axis is commanded to zero speed. Altitude, bearing, speed, and waypoint stay latched.

Emergency stop overrides every other command, including diagnostic. It sets every relay off and every speed controller to zero, and it stays there until a clear command.

The engine sends status to both remotes: mode, altitude, vertical speed, horizontal speed, heading, target, current SU, and outage state.

A message the engine does not recognize is ignored.

## Flight loop

Each pass the engine reads the ship position, velocity, orientation, and angular velocity, reads the speedometer and the stressometer, takes the latest command, and writes every output. Relay 3 stays off in flight. RSC 10 at zero stops the X propellers. Diagnostic mode can still turn Relay 3 on.

Above 20 m/s, the bow upward thrusters hold the nose and the side thrusters hold the heading.

### Hover and altitude

On request, the engine finds the RSC 11 setting where vertical speed stays near zero and stores it for that height. A climb commands RSC 11 to `climb_rpm` until the ship is close to the target, then holds with the stored hover setting. Gravity descends the ship when the throttle is below that setting. Relay 6 reverses the elevation propellers when the descent must be faster than gravity.

### Manual

A held stick commands ship-relative velocity, capped at 3 m/s. Forward and back go to RSC 10. Relay 2 gets an analog level from 0 to 15 in proportion to the size of that X command, and gets 0 when the command is 0. Sideways uses the side thrusters as translation. Up and down go to the elevation propellers. Releasing the stick commands zero on that axis.

On the command computer, the arrow keys are forward, back, and sideways. Space is up. Left shift is down. Keys send stick messages only while held.

### Semi-automatic

The pilot sets altitude, bearing, and speed. The ship accelerates so that it would reach that speed in 15 seconds. Horizontal speed is capped at 35 m/s. A reverse command runs RSC 10 backwards. The side thrusters hold the bearing.

### Automatic

The ship climbs to Y=400, then flies a straight line in X and Z. Warp is 50 m/s. Cruise stays under 8 m/s. The engine measures the acceleration and starts reversing with enough distance left to stop. Arrival is within 10 blocks of the waypoint. The ship then descends to 10 blocks above the world's maximum build height. On this overworld that height is 319, so the descent target is Y=329.

Return-to-user is automatic mode aimed at the pocket's GPS X and Z. The player's altitude is not used. If `gps.locate()` returns nothing, the pocket reports no fix and sends no return command.

## Propeller failure

The engine classifies a failure from pitch rate and roll rate.

One elevation propeller quits. The corner that drops is the failed propeller. The engine cuts only the opposite corner and raises RSC 11 so the other two carry the ship. Relay 5 stays off, so the Z axis is not cut as a whole. Port-bow (Relay 7) is opposite starboard-stern (Relay 9). Starboard-bow (Relay 8) is opposite port-stern (Relay 10). The upward thrusters on the two live corners add lift and remove the remaining lean. If the ship cannot hold height, it keeps the level attitude and descends.

Both elevation propellers on one side quit, and the upward thrusters on that side still work. Those thrusters fire to replace the lost lift. The propellers on the live side run only as hard as those thrusters can balance. If that cannot also hold height, the live propellers are eased off until the roll stops, and the ship holds or descends on the thrusters.

Both elevation propellers on one side quit, and the upward thrusters on that side are dead too. The engine turns on Relay 5 and Relays 7 through 10, and sets RSC 2 through RSC 5 and RSC 11 to zero. The ship falls level. The side thrusters hold the heading.

One corner loses its elevation propeller and its upward thruster. The one-propeller procedure still runs. The dead thruster cannot push that corner up, so a leftover roll into that corner cannot be trimmed without also pitching.

## Monitors

The engine sets every monitor to text scale 0.5, reads `getSize()`, and sorts by width times height. The two largest start on Flight and Navigation. The two smaller start on Engines and Emergency. Equal sizes break the tie by peripheral name.

Pages:

- Flight: mode, altitude, vertical speed, horizontal speed, heading.
- Engines: shaft RPM, current SU, X throttle, elevation throttle, which corner propellers are cut.
- Navigation: waypoint, distance remaining, bearing, cruise or warp.
- Emergency: outage state, failed corner, emergency latch. Touching clear releases the latch.
- Systems: each configured peripheral as present or missing.

Each screen shows a button per monitor. Touching a button moves this screen's page to that monitor and brings the other page back. Every screen keeps one page. Systems is reached by moving a page onto a screen.

## Diagnostic mode

The pocket screen has a Diagnostic button. Entering it tells the engine to leave flight mode, zero every output except as the hover option says below, and ignore flight commands. Emergency stop still wins. Leaving the screen zeros every output, including elevation.

The pocket lists the relays and speed controllers the engine reports. One device is active at a time.

A speed controller is commanded from -32 to 32 RPM. The engine clamps any larger request to that range. A relay is commanded on one chosen side at a redstone strength from 0 to 15. The speedometer RPM and the current SU are shown so the test result is visible.

Hover diagnostic is an option on that screen. RSC 11 is left out of the device list and is not zeroed on entry. A separate control sets RSC 11 to the speed that holds the ship, with no 32 RPM cap. Vertical speed is shown so the hover can be trimmed. Relay 6 and Relays 7 through 10 stay locked, so a test cannot reverse or cut the propellers that are holding the ship. Every other speed controller still caps at 32 RPM.

## Startup

Before accepting flight or diagnostic commands, the engine checks the wired modem, the ender modem, and every name in the config. A missing device is written on the engine screen and on any monitor that is present. The ship does not fly, and every output stays at zero.

## Programs

- `engine` runs the flight loop, failure response, monitor drawing, and output writes.
- `command` is the keyboard menu and stick keys. It only sends commands and shows status.
- `pocket` is the remote, the return button, and the diagnostic screen.
- Flight decisions are pure functions: hover capture, the 15-second speed ramp and its caps, braking distance from the measured acceleration, monitor sorting, and outage classification. Peripheral calls stay outside those functions.

## Tests

A Lua test feeds fixed inputs to those functions and checks the outputs. It does not need Minecraft.

On the ship, the checks are: a missing peripheral keeps the ship shut down and shows the error; manual flight from both remotes caps at 3 m/s and stops when released; hover calibration holds a height; semi-automatic reaches a speed and a bearing; automatic climbs, tracks, stops inside 10 blocks, and descends; the two larger monitors start on Flight and Navigation; a touch swaps pages; emergency stop zeros every output and stays latched until cleared; return sends GPS X and Z only after a fix; diagnostic drives one device at a time and refuses a speed past 32 RPM, except RSC 11 while hover diagnostic is on.

## Out of scope

Downward thrusters are not added. Stick relays are not added. GPS hosts are not built. The program does not change Create's rotation limit or the vstuff thruster mod.
