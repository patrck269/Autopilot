# Autopilot logic review, 2026-10-08

## Reproduced and fixed

- Bearing correction replaced all four side commands, discarding lateral
  navigation or braking. Commands now combine signed forces before converting
  back to RPM. A regression verifies simultaneous braking and turning.
- Actuator writes were remembered before success. A failed zero write was
  subsequently treated as already applied. Failed writes now invalidate the
  cache so the next apply retries them.
- Cached targets were never compared with actual controller targets after the
  initial read. A replacement peripheral or independent writer could therefore
  leave propulsion active despite a zero command. Each apply reconciles the
  cache with getTargetSpeed when available; absent devices invalidate it.
- Corner-outage handling enabled the elevation reverser, directing surviving
  lift downward. Failure detection now controls cutoffs without reversing lift.
- A watchdog actuator failure could abort the periodic retry loop or suppress
  latch broadcasts from a socket command. Stop writes now report failures while
  preserving retry ticks and latch broadcasts. A program-level regression
  reproduces consecutive failures followed by recovery.
- The flight loop retained subtraction-based angle wrapping despite the numeric
  module's bounded implementation. Large shell-injected angles could stall the
  loop. The flight loop now uses numeric.wrap.
- Bearing control ignored yaw velocity, including inside its position deadband.
  It now combines bearing error with configured yaw damping, so it brakes
  existing angular momentum even at the requested bearing.
- Automatic side control used the forward-propeller acceleration model rather
  than the side-thruster force model. It now uses the same mass and four-unit
  force conversion as manual translation. A force-level regression verifies
  the requested acceleration below shaft saturation.
- Stress limiting only considered requested targets. A held elevation target
  could combine with a new forward target and exceed the shaft budget. Runtime
  now budgets the selected held/stepped integers and commits reductions before
  increases. A failed reduction suppresses subsequent increases, while stop
  attempts continue. The flight loop records applied stress and displays applied
  outputs. The watchdog installer includes the new runtime stress dependency.
- A measured zero shaft capacity was treated as unavailable telemetry and fell
  back to the full default budget. Known zero capacity now permits zero load;
  missing capacity remains distinct and uses the configured fallback.
- The stress display divided measured SU by raw RPM, ignoring different stress
  impacts and the four elevation bearings. Group estimates now weight the
  applied RPM by the same impacts and bearing counts as the control budget.

## Confirmed recovery limitation

- Outage handling only cuts the opposite corner; it does not increase surviving
  lift or actively stabilize pitch/roll. balance_time is reset in every branch,
  and outage_fail_seconds is unused. Current hardware config omits the upward
  RSC 2–5 devices described in the original design. Recovery behavior must be
  assessed against the current hardware rather than assuming those exist.
  The operator confirmed those upward thrusters are unavailable. The shared
  elevation throttle and cutoff relays cannot independently apply the upward
  corner forces described in the original recovery design. Current cutoff
  handling must therefore not be represented as verified altitude-preserving
  or pitch/roll-stabilizing recovery. No nonexistent devices were added.
  This remains an identified limitation, rather than a verified recovery feature.

## Actuator budget behavior

Ordinary elevation changes retain the existing 99-RPM step and hold rules.
Budget limiting may shed forward and side load before the hold expires. If
measured capacity abruptly falls below an elevation target by more than the
permitted nonzero step, runtime uses the existing immediate-zero stop. This
protects the shaft budget but does not guarantee altitude during a capacity
failure. Applied-target accounting models stress; it does not measure thrust.

## Validation

The full Lua suite passes, including the new force-conflict, outage-direction,
actuator-retry, external-target-change and watchdog-program regressions. Yaw
settles from three initial bearings with the shipped actuator holds. Automatic
navigation arrives within ten blocks from four initial headings with crosswind,
the shipped holds, and live-target stress budgeting. Runtime stress tests check
both final allocations and every intermediate hardware write, including failed
load reductions. Both Python bridge suites passed. These checks use simulated
hardware; they do not establish ship-specific thrust calibration or live
peripheral reliability.
