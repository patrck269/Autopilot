# Rotation controller flicker protection

Verified against the installed Create 6.0.8 binary: changing the target removes
and reconnects the controller's kinetic network. A powered controller incurs
five flicker points for stopping and five for restarting. The tally decays by
one per Minecraft tick; propagation destroys a block when its tally exceeds 128.
Repeated writes of the same integer do not invoke the change callback. There is
no 100-RPM destruction threshold.

Runtime now removes the partial-step hold bypass and tracks a conservative
flicker allowance per controller, permitting nonzero changes only up to 80
points. ComputerCraft game time supplies decay, so additional apply calls in
the same tick do not replenish the allowance. Attempted writes are charged even
when they fail; cache invalidation retains this accounting. Short bursts and
the existing elevation slew limit remain available within the allowance.

Zero bypasses the gate. Ordinary reductions wait when allowance is exhausted;
if holding the previous target would violate the stress budget, runtime sends
zero instead. Increases wait. This preserves immediate emergency and capacity
loss stops without allowing repeated restarts to exhaust Create's protection.

Regression coverage includes the original decreasing-target reproduction,
increasing targets, reversals, repeated zero/restart commands, capacity changes,
and many apply calls without advancing game time. The flight simulation now
advances game time and reports the actual applied elevation target to learning.
Existing altitude settling, manual release, hover, navigation, stress-budget,
and watchdog checks also pass. These checks simulate the installed scoring
rules; they do not constitute a live flight test or account for independent
writers changing the same kinetic network.
