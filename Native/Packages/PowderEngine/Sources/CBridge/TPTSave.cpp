// Native document and clone adapters for The Powder Toy 100.1.400.
// OPS serialization is the original upstream format, with its original quantization.
#include "TPTInternal.hpp"
#include "TPTGravity.hpp"
#include "client/GameSave.h"
#include "simulation/Air.h"
#include "simulation/Snapshot.h"
#include "simulation/SimulationSettings.h"
#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <exception>
#include <memory>
#include <stdexcept>
#include <vector>

namespace {
constexpr size_t maximumSaveBytes = 64U * 1024U * 1024U;

void requireWorld(const TPTWorld *world) {
    if (!world || !world->simulation) {
        throw std::invalid_argument("The simulation handle is missing.");
    }
}

void copyOptions(const Simulation &source, Simulation &destination) {
    destination.gravityMode = source.gravityMode;
    destination.customGravityX = source.customGravityX;
    destination.customGravityY = source.customGravityY;
    destination.legacy_enable = source.legacy_enable;
    destination.legacyFusionSideEffects = source.legacyFusionSideEffects;
    destination.water_equal_test = source.water_equal_test;
    destination.aheat_enable = source.aheat_enable;
    destination.pretty_powder = source.pretty_powder;
    destination.deco_space = source.deco_space;
    destination.GSPEED = source.GSPEED;
    destination.ensureDeterminism = source.ensureDeterminism;
    destination.air->airMode = source.air->airMode;
    destination.air->ambientAirTemp = source.air->ambientAirTemp;
    destination.air->edgePressure = source.air->edgePressure;
    destination.air->edgeVelocityX = source.air->edgeVelocityX;
    destination.air->edgeVelocityY = source.air->edgeVelocityY;
    destination.air->vorticityCoeff = source.air->vorticityCoeff;
    destination.air->convectionMode = source.air->convectionMode;
    destination.SetEdgeMode(source.edgeMode);
    destination.EnableNewtonianGravity(bool(source.grav));
}

void validateSave(const GameSave &save) {
    if (save.blockSize.X <= 0 || save.blockSize.Y <= 0 ||
        save.blockSize.X > XCELLS || save.blockSize.Y > YCELLS) {
        throw std::invalid_argument("The save dimensions exceed the original engine's canvas.");
    }
    if (save.missingElements) {
        throw std::invalid_argument("The save uses elements not present in the original 100.1.400 engine.");
    }
    if (save.particlesCount < 0 || save.particlesCount > NPART ||
        size_t(save.particlesCount) > save.particles.size()) {
        throw std::invalid_argument("The save contains an invalid particle count.");
    }
    if (save.gravityMode < 0 || save.gravityMode >= NUM_GRAVMODES ||
        save.airMode < 0 || save.airMode >= NUM_AIRMODES ||
        save.convectionMode < 0 || save.convectionMode >= NUM_CONVMODES ||
        save.edgeMode < 0 || save.edgeMode >= NUM_EDGEMODES) {
        throw std::invalid_argument("The save contains invalid simulation settings.");
    }
    for (float value : {save.customGravityX, save.customGravityY, save.ambientAirTemp,
                        save.edgePressure, save.edgeVelocityX, save.edgeVelocityY,
                        save.vorticityCoeff}) {
        if (!std::isfinite(value)) {
            throw std::invalid_argument("The save contains a nonfinite simulation setting.");
        }
    }
    for (int i = 0; i < save.particlesCount; ++i) {
        const auto &particle = save.particles[i];
        if (!std::isfinite(particle.x) || !std::isfinite(particle.y) ||
            !std::isfinite(particle.vx) || !std::isfinite(particle.vy) ||
            !std::isfinite(particle.temp)) {
            throw std::invalid_argument("The save contains a nonfinite particle value.");
        }
    }
    for (auto position : save.blockSize.OriginRect()) {
        for (float value : {save.pressure[position], save.velocityX[position], save.velocityY[position],
                            save.ambientHeat[position], save.fanVelX[position], save.fanVelY[position],
                            save.gravMass[position], save.gravForceX[position], save.gravForceY[position]}) {
            if (!std::isfinite(value)) {
                throw std::invalid_argument("The save contains a nonfinite air or gravity value.");
            }
        }
    }
    if (save.hasRngState && save.rngState[0] == 0 && save.rngState[1] == 0) {
        throw std::invalid_argument("The save contains an invalid random generator state.");
    }
}

void applySaveOptions(const GameSave &save, Simulation &simulation) {
    simulation.gravityMode = save.gravityMode;
    simulation.customGravityX = save.customGravityX;
    simulation.customGravityY = save.customGravityY;
    simulation.air->airMode = save.airMode;
    simulation.air->ambientAirTemp = save.ambientAirTemp;
    simulation.air->edgePressure = save.edgePressure;
    simulation.air->edgeVelocityX = save.edgeVelocityX;
    simulation.air->edgeVelocityY = save.edgeVelocityY;
    simulation.air->vorticityCoeff = save.vorticityCoeff;
    simulation.air->convectionMode = save.convectionMode;
    simulation.legacy_enable = save.legacyEnable;
    simulation.legacyFusionSideEffects = save.legacyFusionSideEffects;
    simulation.water_equal_test = save.waterEEnabled;
    simulation.aheat_enable = save.aheatEnable;
    simulation.SetEdgeMode(save.edgeMode);
    simulation.EnableNewtonianGravity(save.gravityEnable);
}
}

extern "C" TPTWorld *tpt_world_clone(const TPTWorld *world) {
    std::lock_guard<std::recursive_mutex> lock(tpt_engine_mutex());
    tpt_set_error("");
    try {
        requireWorld(world);
        auto snapshot = world->simulation->CreateSnapshot();
        std::unique_ptr<TPTWorld> copy(tpt_world_create());
        if (!copy) { return nullptr; }
        copyOptions(*world->simulation, *copy->simulation);
        copy->simulation->Restore(*snapshot);
        auto &source = *world->simulation;
        auto &destination = *copy->simulation;
        // Restore rebuilds a sorted free list and spatial maps. A value clone
        // must also preserve edits made since the last simulation tick, including
        // free-slot order and which overlapping particle each map points to.
        destination.parts = source.parts;
        std::memcpy(destination.pmap, source.pmap, sizeof(source.pmap));
        std::memcpy(destination.photons, source.photons, sizeof(source.photons));
        std::memcpy(destination.pmap_count, source.pmap_count, sizeof(source.pmap_count));
        destination.NUM_PARTS = source.NUM_PARTS;
        // Upstream undo snapshots omit a few control counters. Preserve these
        // for a value-semantic clone, especially the stacking flag: forcing a
        // check would skip the next RNG draw and change subsequent evolution.
        destination.currentTick = source.currentTick;
        destination.force_stacking_check = source.force_stacking_check;
        destination.elementRecount = source.elementRecount;
        std::copy(std::begin(source.elementCount), std::end(source.elementCount),
                  std::begin(destination.elementCount));
        destination.CGOL = source.CGOL;
        destination.ISWIRE = source.ISWIRE;
        destination.Element_PPIP_ppip_changed = source.Element_PPIP_ppip_changed;
        destination.emp_trigger_count = source.emp_trigger_count;
        destination.emp_decor = source.emp_decor;
        destination.etrd_count_valid = source.etrd_count_valid;
        destination.etrd_life0_count = source.etrd_life0_count;
        destination.lightningRecreate = source.lightningRecreate;
        destination.gravWallChanged = source.gravWallChanged;
        destination.gravForceRecalc = source.gravForceRecalc;
        if (source.grav && destination.grav) {
            tpt_copy_gravity_state(*source.grav, *destination.grav);
        }
        destination.sandcolour_frame = source.sandcolour_frame;
        destination.sandcolour = source.sandcolour;
        destination.sandcolour_interface = source.sandcolour_interface;
        destination.fighcount = source.fighcount;
        return copy.release();
    } catch (const std::exception &error) {
        tpt_set_error(error.what());
    } catch (...) {
        tpt_set_error("The original engine could not clone this simulation.");
    }
    return nullptr;
}

extern "C" uint8_t *tpt_world_serialize(const TPTWorld *world, size_t *length) {
    std::lock_guard<std::recursive_mutex> lock(tpt_engine_mutex());
    tpt_set_error("");
    if (length) { *length = 0; }
    try {
        requireWorld(world);
        if (!length) { throw std::invalid_argument("A save length output is required."); }
        auto save = world->simulation->Save(true, RES.OriginRect());
        // Preserve upstream RNG and frame metadata. OPS still rounds positions,
        // temperature, velocity, and air values; snapshots are used for clones.
        save->ensureDeterminism = true;
        save->legacyFusionSideEffects = world->simulation->legacyFusionSideEffects;
        auto result = save->Serialise();
        const auto &data = result.second;
        if (data.empty() || data.size() > maximumSaveBytes) {
            throw std::runtime_error("The encoded save exceeds the 64 MB limit.");
        }
        auto *output = static_cast<uint8_t *>(std::malloc(data.size()));
        if (!output) { throw std::bad_alloc(); }
        std::memcpy(output, data.data(), data.size());
        *length = data.size();
        return output;
    } catch (const std::exception &error) {
        tpt_set_error(error.what());
    } catch (...) {
        tpt_set_error("The original engine could not encode this simulation.");
    }
    return nullptr;
}

extern "C" TPTWorld *tpt_world_deserialize(const uint8_t *bytes, size_t length) {
    std::lock_guard<std::recursive_mutex> lock(tpt_engine_mutex());
    tpt_set_error("");
    try {
        if (!bytes || length < 16 || length > maximumSaveBytes) {
            throw std::invalid_argument("A valid save between 16 bytes and 64 MB is required.");
        }
        // OPS and legacy PSv/fuC share a little-endian decompressed-size field.
        // Bound it before upstream allocates or decompresses any payload.
        const bool ops = bytes[0] == 'O' && bytes[1] == 'P' && bytes[2] == 'S';
        const bool psv = bytes[0] == 'P' && bytes[1] == 'S' && bytes[2] == 'v';
        const bool fuc = bytes[0] == 'f' && bytes[1] == 'u' && bytes[2] == 'C';
        if (!ops && !psv && !fuc) { throw std::invalid_argument("This is not an OPS or legacy Powder Toy save."); }
        const uint32_t expandedSize = uint32_t(bytes[8]) | (uint32_t(bytes[9]) << 8)
            | (uint32_t(bytes[10]) << 16) | (uint32_t(bytes[11]) << 24);
        if (expandedSize == 0 || expandedSize > maximumSaveBytes) {
            throw std::invalid_argument("The save's decompressed data exceeds the 64 MB limit.");
        }
        tpt_initialize_engine();
        GameSave save(std::vector<char>(reinterpret_cast<const char *>(bytes),
                                       reinterpret_cast<const char *>(bytes) + length), false);
        validateSave(save);
        std::unique_ptr<TPTWorld> world(tpt_world_create());
        if (!world) { return nullptr; }
        auto &simulation = *world->simulation;
        simulation.clear_sim();
        applySaveOptions(save, simulation);
        simulation.Load(&save, true, {0, 0});
        // Loading uses create_part, which can consume random values. Reset the
        // recorded clock/RNG only after reconstruction has completed.
        simulation.frameCount = save.frameCount;
        simulation.ensureDeterminism = save.ensureDeterminism;
        if (save.hasRngState) { simulation.rng.state(save.rngState); }
        return world.release();
    } catch (const std::exception &error) {
        tpt_set_error(error.what());
    } catch (...) {
        tpt_set_error("The original engine could not decode this save.");
    }
    return nullptr;
}

extern "C" void tpt_bytes_free(void *bytes) {
    std::free(bytes);
}
