#pragma once
#include "include/TPTBridge.h"
#include "simulation/Simulation.h"
#include <memory>
#include <mutex>
#include <vector>

struct TPTWorld {
    std::unique_ptr<Simulation> simulation;
    // Lazily rebuilt spatial index makes repeated erase/carve cells linear overall.
    bool eraseIndexValid = false;
    std::vector<int> eraseHeads, eraseNext;
};

// Recursive because save adapters call public allocation entry points while locked.
std::recursive_mutex &tpt_engine_mutex();
void tpt_initialize_engine();
void tpt_set_error(const char *message);
