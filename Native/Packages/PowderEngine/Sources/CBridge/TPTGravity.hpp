#pragma once
class Gravity;

// Preserve the completed/pending solver exchange when cloning a simulation.
// Both worlds must be protected by the bridge's engine mutex.
void tpt_copy_gravity_state(Gravity &source, Gravity &destination);
