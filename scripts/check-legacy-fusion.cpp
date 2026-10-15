// SPDX-License-Identifier: GPL-3.0-or-later
// Headless regression of the vendored production engine, not a physics mock.
// C ABI exercises creation, painting, settings, clone and save/load. Direct
// production reaction dispatch isolates fusion conditions from air/gravity
// integration and avoids relying on frame scheduling or rare random events.
#include "TPTInternal.hpp"
#include "simulation/ElementClasses.h"
#include "simulation/SimulationData.h"
#include "simulation/TransitionConstants.h"
#include <cmath>
#include <iomanip>
#include <iostream>
#include <memory>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

using WorldPtr = std::unique_ptr<TPTWorld, decltype(&tpt_world_destroy)>;

static void check(bool condition, const char *message)
{
    if (!condition)
        throw std::runtime_error(message);
}

static WorldPtr newWorld()
{
    WorldPtr world(tpt_world_create(), tpt_world_destroy);
    check(bool(world), "C API could not create world");
    return world;
}

static std::vector<TPTParticle> particles(TPTWorld *world)
{
    std::vector<TPTParticle> output(tpt_world_copy_particles(world, nullptr, 0));
    auto count = tpt_world_copy_particles(world, output.data(), output.size());
    check(count <= output.size(), "Particle count exceeded caller capacity");
    output.resize(count);
    return output;
}

static int countType(TPTWorld *world, int type)
{
    int count = 0;
    for (const auto &particle : particles(world))
        count += particle.type == type;
    return count;
}

static void reset(TPTWorld *world, bool legacy)
{
    check(tpt_world_clear(world), "C API clear failed");
    check(tpt_world_set_legacy_fusion(world, legacy), "C API mode setter failed");
    check(tpt_world_legacy_fusion(world) == int(legacy), "C API mode getter mismatch");
}

static int prepareOxygen(TPTWorld *world, unsigned seed, int x = 100, int y = 100)
{
    int index = tpt_world_paint_particle(world, x, y, PT_O2, MAX_TEMP);
    check(index >= 0, "Could not create oxygen fixture");
    check(tpt_world_set_pressure(world, x, y, MAX_PRESSURE), "Could not set fusion pressure");
    auto &sim = *world->simulation;
    sim.gravOut.forceX[Vec2{ x, y } / CELL] = 21.f;
    sim.gravOut.forceY[Vec2{ x, y } / CELL] = 0.f;
    sim.rng.seed(seed);
    return index;
}

static void updateOxygen(TPTWorld *world, int index, int x = 100, int y = 100)
{
    auto &sim = *world->simulation;
    SimulationData::CRef().elements[PT_O2].Update(&sim, index, x, y, 1, 0, sim.parts, sim.pmap);
}

static std::string stateDigest(TPTWorld *world)
{
    std::ostringstream value;
    value << std::setprecision(9);
    for (const auto &p : particles(world))
        value << p.index << ':' << p.type << ':' << p.life << ':' << p.ctype << ':'
              << p.tmp << ':' << p.tmp2 << ':' << p.tmp3 << ':' << p.tmp4 << ':'
              << p.x << ':' << p.y << ':' << p.vx << ':' << p.vy << ':'
              << p.temperature_kelvin << ';';
    for (auto state : world->simulation->rng.state())
        value << state << ';';
    value << world->simulation->pv[100/CELL][100/CELL];
    return value.str();
}

// Run this mode once linked to the production O2 object and once linked to an
// unmodified, pinned-release O2 object. Equal fingerprints check actual modern
// reactions/RNG against the upstream reference rather than against this patch.
static void printModernFingerprint()
{
    auto world = newWorld();
    uint64_t fingerprint = UINT64_C(14695981039346656037);
    for (unsigned seed = 1; seed <= 256; ++seed)
    {
        check(tpt_world_clear(world.get()), "Clear failed");
        check(!tpt_world_legacy_fusion(world.get()), "Default mode unexpectedly enabled");
        auto index = prepareOxygen(world.get(), seed);
        updateOxygen(world.get(), index);
        for (unsigned char byte : stateDigest(world.get()))
        {
            fingerprint ^= byte;
            fingerprint *= UINT64_C(1099511628211);
        }
    }
    std::cout << std::hex << fingerprint << '\n';
}

static unsigned testOxygenModes()
{
    auto implicitModern = newWorld();
    auto explicitModern = newWorld();
    auto legacy = newWorld();
    check(tpt_world_legacy_fusion(implicitModern.get()) == 0, "Legacy mode must default off");
    unsigned firstSingularitySeed = 0;
    int modernFusions = 0, legacySingularities = 0;
    for (unsigned seed = 1; seed <= 256; ++seed)
    {
        check(tpt_world_clear(implicitModern.get()), "Clear failed");
        reset(explicitModern.get(), false);
        reset(legacy.get(), true);
        auto index = prepareOxygen(implicitModern.get(), seed);
        auto explicitIndex = prepareOxygen(explicitModern.get(), seed);
        auto legacyIndex = prepareOxygen(legacy.get(), seed);
        updateOxygen(implicitModern.get(), index);
        updateOxygen(explicitModern.get(), explicitIndex);
        updateOxygen(legacy.get(), legacyIndex);
        check(stateDigest(implicitModern.get()) == stateDigest(explicitModern.get()),
              "Default mode differs from explicit modern mode, including RNG");
        check(countType(implicitModern.get(), PT_SING) == 0, "Modern fusion produced a legacy singularity");
        bool fused = implicitModern->simulation->parts[index].type == PT_BRMT;
        modernFusions += fused;
        check((legacy->simulation->parts[legacyIndex].type == PT_BRMT) == fused,
              "Legacy mode changed the modern fusion trigger");
        for (const auto &particle : particles(legacy.get()))
        {
            check(std::isfinite(particle.temperature_kelvin) && particle.temperature_kelvin <= MAX_TEMP,
                  "Legacy byproduct temperature exceeds engine bounds");
            if (particle.type == PT_SING)
            {
                check(particle.life >= 50 && particle.life <= 74, "Legacy SING lifespan out of range");
                check(particle.temperature_kelvin == MAX_TEMP, "Legacy SING has incorrect temperature");
                check(legacy->simulation->parts[legacyIndex].life == 0,
                      "Historical source-particle lifetime corruption was reintroduced");
                ++legacySingularities;
                if (!firstSingularitySeed)
                    firstSingularitySeed = seed;
            }
        }
    }
    check(modernFusions > 0 && legacySingularities > 0, "Seed sweep did not exercise fusion and SING creation");
    std::cout << "PASS O2: " << modernFusions << " modern fusion events; " << legacySingularities
              << " legacy singularities across 256 identical seeds; default/explicit modern state and RNG match\n";
    return firstSingularitySeed;
}

static int photonHydrogenReaction(TPTWorld *world, bool legacy, bool fusionPhoton, float pressure)
{
    reset(world, legacy);
    int photon = tpt_world_paint_particle(world, 100, 100, PT_PHOT, MAX_TEMP);
    check(photon >= 0, "Could not create photon fixture");
    check(tpt_world_paint_particle(world, 101, 100, PT_H2, 300.f) >= 0, "Could not create H2 fixture");
    TPTParticle value{};
    check(tpt_world_particle_at(world, 100, 100, 1, &value), "Could not read photon fixture");
    value.tmp = fusionPhoton ? 1 : 0;
    value.vx = 1.f;
    value.vy = 0.f;
    check(tpt_world_set_particle(world, &value), "Could not configure photon fixture");
    check(tpt_world_set_pressure(world, 100, 100, pressure), "Could not set photon pressure");
    world->simulation->try_move(photon, 100, 100, 101, 100);
    return world->simulation->parts[photon].type;
}

static void testPhotons()
{
    auto world = newWorld();
    for (float pressure : { 0.f, 44.99f, 45.f, 100.f })
    {
        check(photonHydrogenReaction(world.get(), false, true, pressure) == PT_PHOT,
              "Modern mode converted a fusion-origin photon");
        check(photonHydrogenReaction(world.get(), true, true, pressure) == (pressure < 45.f ? PT_PROT : PT_PHOT),
              "Legacy fusion-photon conversion violates historical low-pressure eligibility");
        for (bool legacy : { false, true })
            check(photonHydrogenReaction(world.get(), legacy, false, pressure) == PT_PROT,
                  "Legacy option changed modern unflagged-photon behavior");
    }
    std::cout << "PASS PHOT/H2: flagged photons convert only in legacy mode below pressure45; unflagged reactions unchanged\n";
}

static void testBoundsAndCapacity(unsigned seed)
{
    auto world = newWorld();
    for (auto position : { Vec2{CELL, CELL}, Vec2{XRES-CELL-1, CELL},
                           Vec2{CELL, YRES-CELL-1}, Vec2{XRES-CELL-1, YRES-CELL-1} })
    {
        reset(world.get(), true);
        int index = prepareOxygen(world.get(), seed, position.X, position.Y);
        updateOxygen(world.get(), index, position.X, position.Y);
        check(countType(world.get(), PT_SING) == 1, "Corner fusion fixture did not create a singularity");
        for (const auto &particle : particles(world.get()))
            check(particle.x >= 0 && particle.x < XRES && particle.y >= 0 && particle.y < YRES,
                  "Legacy byproduct escaped world bounds");
    }
    reset(world.get(), true);
    int index = prepareOxygen(world.get(), seed);
    auto &sim = *world->simulation;
    while (sim.create_part(-3, 200, 200, PT_DMND) >= 0) {}
    check(sim.parts.active == NPART, "Capacity fixture did not fill the particle pool");
    // Reseed after filling so this follows the same tested fusion event.
    sim.rng.seed(seed);
    updateOxygen(world.get(), index);
    check(sim.parts.active == NPART, "Legacy fusion exceeded capacity or lost a source particle");
    check(sim.parts[index].type == PT_BRMT && sim.parts[index].life == 0,
          "Allocation failure corrupted the source particle");
    check(countType(world.get(), PT_SING) == 0, "Legacy fusion created a singularity beyond particle capacity");
    std::cout << "PASS bounds/capacity: four active-grid corners and a full " << NPART << "-particle pool\n";
}

static void testPersistence()
{
    for (bool enabled : { false, true })
    {
        auto world = newWorld();
        check(tpt_world_paint_particle(world.get(), 100, 100, PT_SING, 500.f) >= 0, "Persistence fixture failed");
        auto before = stateDigest(world.get());
        check(tpt_world_set_legacy_fusion(world.get(), enabled), "Mode change failed");
        check(before == stateDigest(world.get()), "Changing mode altered particles or RNG");
        WorldPtr cloned(tpt_world_clone(world.get()), tpt_world_destroy);
        check(bool(cloned) && tpt_world_legacy_fusion(cloned.get()) == int(enabled), "Clone lost legacy setting");
        check(tpt_world_set_legacy_fusion(cloned.get(), !enabled), "Clone mode change failed");
        check(tpt_world_legacy_fusion(world.get()) == int(enabled), "Changing clone mode changed original");
        size_t length = 0;
        auto *bytes = tpt_world_serialize(world.get(), &length);
        check(bytes && length > 12, "C API OPS serialization failed");
        WorldPtr loaded(tpt_world_deserialize(bytes, length), tpt_world_destroy);
        tpt_bytes_free(bytes);
        check(bool(loaded) && tpt_world_legacy_fusion(loaded.get()) == int(enabled), "OPS round trip lost legacy setting");
        check(countType(loaded.get(), PT_SING) == 1, "OPS round trip lost particles");
    }
    std::cout << "PASS persistence: default off, non-destructive setting changes, independent clone, OPS both modes\n";
}

int main(int argc, char **argv)
{
    try
    {
        if (argc == 2 && std::string(argv[1]) == "--modern-fingerprint")
        {
            printModernFingerprint();
            return 0;
        }
        auto seed = testOxygenModes();
        testPhotons();
        testBoundsAndCapacity(seed);
        testPersistence();
        std::cout << "PASS all production-engine legacy fusion regressions\n";
        return 0;
    }
    catch (const std::exception &error)
    {
        std::cerr << "FAIL " << error.what() << '\n';
        return 1;
    }
}
