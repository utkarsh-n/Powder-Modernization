#ifndef TPT_BRIDGE_H
#define TPT_BRIDGE_H
#include <stdint.h>
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif

typedef struct TPTWorld TPTWorld;
typedef struct {
    int32_t id;
    const char *name;
    const char *identifier;
    const char *description;
    const char *category;
    uint32_t color_rgb;
    uint32_t properties;
    float default_temperature_kelvin;
    int32_t menu_visible;
} TPTElementInfo;

typedef struct {
    int32_t index;
    int32_t type;
    int32_t life;
    int32_t ctype;
    int32_t tmp;
    int32_t tmp2;
    int32_t tmp3;
    int32_t tmp4;
    uint32_t dcolour;
    float x;
    float y;
    float vx;
    float vy;
    float temperature_kelvin;
} TPTParticle;

typedef struct {
    float pressure;
    float velocity_x;
    float velocity_y;
    float temperature_kelvin;
} TPTAirSample;

/* Every entry point serializes access to upstream process-global simulation data.
   Failure details are thread-local and remain valid until the next bridge call. */
const char *tpt_last_error(void);
TPTWorld *tpt_world_create(void);
void tpt_world_destroy(TPTWorld *world);
TPTWorld *tpt_world_clone(const TPTWorld *world);
int32_t tpt_world_width(void);
int32_t tpt_world_height(void);
uint64_t tpt_world_tick(const TPTWorld *world);
int32_t tpt_world_particle_count(const TPTWorld *world);
int32_t tpt_world_step(TPTWorld *world, int32_t steps);
int32_t tpt_world_clear(TPTWorld *world);
int32_t tpt_world_seed(TPTWorld *world, uint32_t seed);
int32_t tpt_world_set_legacy_fusion(TPTWorld *world, int32_t enabled);
int32_t tpt_world_legacy_fusion(const TPTWorld *world);
int32_t tpt_world_set_newtonian_gravity(TPTWorld *world, int32_t enabled);
int32_t tpt_world_newtonian_gravity(const TPTWorld *world);
int32_t tpt_world_gravity_at(const TPTWorld *world, int32_t x, int32_t y, float *force_x, float *force_y);

/* Negative temperature selects the original element's default temperature.
   Energy particles coexist with matter. Erase removes both layers. */
int32_t tpt_world_paint_particle(TPTWorld *world, int32_t x, int32_t y, int32_t type, float temperature_kelvin);
int32_t tpt_world_erase(TPTWorld *world, int32_t x, int32_t y);
/* Native circular brush with the same inclusive Bresenham traversal as the Swift
   point path. type 0 erases every stacked particle at a visited pixel.
   may_change is conservative and read-only apart from the derived erase index;
   paint_line returns 1 if any particle changed, 0 for a no-op, -1 on error. */
int32_t tpt_world_brush_may_change(TPTWorld *world, int32_t from_x, int32_t from_y,
    int32_t to_x, int32_t to_y, int32_t radius, int32_t type);
int32_t tpt_world_paint_line(TPTWorld *world, int32_t from_x, int32_t from_y,
    int32_t to_x, int32_t to_y, int32_t radius, int32_t type);

int32_t tpt_world_particle_at(const TPTWorld *world, int32_t x, int32_t y, int32_t energy_layer, TPTParticle *output);
size_t tpt_world_copy_particles(const TPTWorld *world, TPTParticle *output, size_t capacity);
int32_t tpt_world_set_particle(TPTWorld *world, const TPTParticle *particle);
int32_t tpt_world_air_at(const TPTWorld *world, int32_t x, int32_t y, TPTAirSample *output);
int32_t tpt_world_set_pressure(TPTWorld *world, int32_t x, int32_t y, float pressure);

/* Dense immutable presentation snapshot, row-major at original pixel resolution.
   Exactly 16 bytes per cell, with native-endian four-byte words. The RGB palette
   and decoration remain separate so the GPU can reproduce floating-point alpha
   blending without quantizing decorated colors. Empty cells contain all zeros.
   Walls occupy profile ID 0xFFFF; apply the native checker (.78/.45 at even/odd
   x+y) and .2 emission when powered. Particles replace walls; energy wins over
   matter; later particle indices win within a layer. PHOT RGB includes spectrum.
   This is presentation only and does not alter upstream physics or RNG state. */
enum {
    TPT_RENDER_ELEMENT_MASK = 0xFFFF,
    TPT_RENDER_WALL_ID = 0xFFFF,
    TPT_RENDER_LIQUID = 1 << 16,
    TPT_RENDER_ENERGY = 1 << 17,
    TPT_RENDER_WALL = 1 << 18,
    TPT_RENDER_POWERED_WALL = 1 << 19,
    TPT_RENDER_LEGACY_FUSION = 1 << 0,
    TPT_RENDER_NEWTONIAN_GRAVITY = 1 << 1
};
typedef struct {
    uint32_t color_rgb;
    uint32_t decoration_argb;
    float temperature_celsius;
    uint32_t material_flags;
} TPTRenderCell;
typedef struct {
    uint64_t tick;
    uint32_t width, height;
    uint32_t particle_count, wall_count;
    uint32_t world_flags, cell_stride;
} TPTRenderInfo;
/* Atomically copies cells and header under a single engine lock. Caller owns the
   output allocation. Capacity must cover width*height cells; undersized buffers
   and missing arguments fail without writing. Returns 1 on success, 0 on error. */
int32_t tpt_world_copy_render_snapshot(const TPTWorld *world, TPTRenderCell *cells,
                                     size_t capacity, TPTRenderInfo *info);

/* The returned metadata strings have process lifetime. Entries include enabled
   hidden engine elements; menu_visible marks elements intended for the palette. */
size_t tpt_element_count(void);
int32_t tpt_element_info(size_t catalog_index, TPTElementInfo *output);
int32_t tpt_element_id_for_name(const char *name_or_identifier);

/* Wall coordinates are the top-left particle pixel of a CELL x CELL block.
   Wall metadata strings have process lifetime. Copy APIs return required count
   for a null output, otherwise the number actually written. */
typedef struct {
    int32_t id;
    const char *name;
    const char *identifier;
    const char *description;
    uint32_t color_rgb;
    uint32_t powered_color_rgb;
    int32_t draw_style;
} TPTWallInfo;
typedef struct {
    int32_t x, y, type, power;
    float fan_velocity_x, fan_velocity_y;
} TPTWallCell;
size_t tpt_wall_type_count(void);
int32_t tpt_wall_type_info(size_t catalog_index, TPTWallInfo *output);
int32_t tpt_wall_cell_size(void);
size_t tpt_world_copy_walls(const TPTWorld *world, TPTWallCell *output, size_t capacity);
/* Reads one wall block without scanning or allocating the full wall grid.
   Returns 1 for a wall, 0 for empty, -1 for invalid input. */
int32_t tpt_world_wall_at(const TPTWorld *world, int32_t x, int32_t y, TPTWallCell *output);
/* Read-only single-block wall-tool preflight. Includes fan resets and ERASEALL's
   particle/sign effects; returns 1 for a real change, 0 for no-op, -1 on error. */
int32_t tpt_world_wall_may_change(const TPTWorld *world, int32_t x, int32_t y, int32_t type);
int32_t tpt_world_set_wall(TPTWorld *world, int32_t x, int32_t y, int32_t type);

/* Signs contain plain resolved display labels, never executable link actions.
   Justification: 0 left, 1 center, 2 right, 3 no pointer. Bounds and anchors use
   original particle-pixel coordinates. UTF-8 is copied and always terminated. */
typedef struct {
    int32_t index, x, y, justification;
    int32_t bounds_x, bounds_y, bounds_width, bounds_height;
    int32_t text_truncated;
    char text[1024];
} TPTSign;
size_t tpt_world_copy_signs(const TPTWorld *world, TPTSign *output, size_t capacity);
/* index -1 appends; returns the resulting index, or -1 on error.
   Text follows original OPS restrictions: 1 to 45 printable ASCII characters. */
int32_t tpt_world_set_sign(TPTWorld *world, int32_t index, const char *text, int32_t x, int32_t y, int32_t justification);
int32_t tpt_world_remove_sign(TPTWorld *world, int32_t index);

/* OPS save buffers are malloc-allocated; release with tpt_bytes_free. */
uint8_t *tpt_world_serialize(const TPTWorld *world, size_t *length);
TPTWorld *tpt_world_deserialize(const uint8_t *bytes, size_t length);
void tpt_bytes_free(void *bytes);

#ifdef __cplusplus
}
#endif
#endif
