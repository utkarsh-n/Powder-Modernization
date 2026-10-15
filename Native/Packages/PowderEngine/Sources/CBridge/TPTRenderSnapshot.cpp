// GPL-3.0-or-later. Compact read-only presentation adapter for the native app.
#include "TPTInternal.hpp"
#include "simulation/SimulationData.h"
#include "simulation/ElementClasses.h"
#include <algorithm>
#include <bit>
#include <cmath>
#include <cstddef>
#include <cstring>
#include <stdexcept>
#include <type_traits>

static_assert(sizeof(TPTRenderCell) == 16);
static_assert(offsetof(TPTRenderCell, material_flags) == 12);
static_assert(sizeof(TPTRenderInfo) == 32);
static_assert(std::is_trivially_copyable_v<TPTRenderCell>);

namespace {
uint32_t photonColor(int ctype) {
    const auto spectrum = uint32_t(ctype);
    // Match the native app's existing spectrum presentation, including its
    // truncation after converting the ten wavelength bins to byte intensity.
    const auto channel = [](uint32_t bits) {
        return uint32_t((float(std::popcount(bits)) / 10.0f) * 255.0f);
    };
    return (channel(spectrum & 0x3FF00000u) << 16) |
           (channel(spectrum & 0x000FFC00u) << 8) |
            channel(spectrum & 0x000003FFu);
}
}

extern "C" int32_t tpt_world_copy_render_snapshot(const TPTWorld *world,
    TPTRenderCell *cells, size_t capacity, TPTRenderInfo *info) {
    std::lock_guard<std::recursive_mutex> lock(tpt_engine_mutex());
    tpt_set_error("");
    try {
        if (!world || !world->simulation) throw std::invalid_argument("The simulation handle is missing.");
        if (!cells || !info || capacity < size_t(XRES) * YRES)
            throw std::invalid_argument("The render snapshot requires a complete cell buffer and header.");
        const auto &sim = *world->simulation;
        const auto &sd = SimulationData::CRef();
        std::memset(cells, 0, sizeof(TPTRenderCell) * XRES * YRES);
        TPTRenderInfo result{sim.frameCount, XRES, YRES, 0, 0, 0, sizeof(TPTRenderCell)};
        if (sim.legacyFusionSideEffects) result.world_flags |= TPT_RENDER_LEGACY_FUSION;
        if (sim.grav) result.world_flags |= TPT_RENDER_NEWTONIAN_GRAVITY;

        for (int y = 0; y < YCELLS; ++y) for (int x = 0; x < XCELLS; ++x) {
            const auto type = sim.bmap[y][x];
            if (!type || size_t(type) >= sd.wtypes.size()) continue;
            ++result.wall_count;
            const bool powered = sim.emap[y][x] > 0;
            const auto &wall = sd.wtypes[type];
            const TPTRenderCell cell{
                powered ? wall.eglow.Pack() : wall.colour.Pack(), 0, 20.0f,
                uint32_t(TPT_RENDER_WALL_ID | TPT_RENDER_WALL) |
                    (powered ? uint32_t(TPT_RENDER_POWERED_WALL) : 0u)};
            for (int dy = 0; dy < CELL; ++dy) {
                auto *row = cells + (y * CELL + dy) * XRES + x * CELL;
                std::fill_n(row, CELL, cell);
            }
        }

        for (int i = 0; i < sim.parts.active; ++i) {
            const auto &p = sim.parts[i];
            if (!p.type) continue;
            ++result.particle_count;
            if (p.type < 0 || p.type >= PT_NUM ||
                !std::isfinite(p.x) || !std::isfinite(p.y) ||
                p.x < -0.5f || p.x >= float(XRES) - 0.5f ||
                p.y < -0.5f || p.y >= float(YRES) - 0.5f) continue;
            const int x = int(std::lround(p.x)), y = int(std::lround(p.y));
            if (!InBounds(x, y)) continue;
            const auto &element = sd.elements[p.type];
            const bool energy = (element.Properties & TYPE_ENERGY) != 0;
            auto &destination = cells[y * XRES + x];
            if ((destination.material_flags & TPT_RENDER_ENERGY) && !energy) continue;
            const uint32_t flags = uint32_t(p.type) |
                ((element.Properties & TYPE_LIQUID) ? uint32_t(TPT_RENDER_LIQUID) : 0u) |
                (energy ? uint32_t(TPT_RENDER_ENERGY) : 0u);
            destination = {p.type == PT_PHOT ? photonColor(p.ctype) : element.Colour.Pack(),
                           p.dcolour, p.temp - 273.15f, flags};
        }
        *info = result;
        return 1;
    } catch (const std::exception &error) { tpt_set_error(error.what()); }
      catch (...) { tpt_set_error("The engine could not prepare a render snapshot."); }
    return 0;
}
