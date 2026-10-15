// GPL-3.0-or-later. Native C boundary around The Powder Toy v100.1.400.
#include "TPTInternal.hpp"
#include "simulation/SimulationData.h"
#include "simulation/ElementClasses.h"
#include "graphics/Renderer.h"
#include <algorithm>
#include <cmath>
#include <exception>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
thread_local std::string lastError;
struct CatalogEntry {
    int id;
    std::string name, identifier, description, category;
};
std::vector<CatalogEntry> catalog;
Simulation &requireWorld(const TPTWorld *world) {
    if (!world || !world->simulation) throw std::invalid_argument("The simulation handle is missing.");
    return *world->simulation;
}
void requirePoint(int x, int y) {
    if (!InBounds(x,y)) throw std::out_of_range("The point is outside the simulation canvas.");
}
TPTParticle exportParticle(int i, const Particle &p) {
    return {i,p.type,p.life,p.ctype,p.tmp,p.tmp2,p.tmp3,p.tmp4,p.dcolour,p.x,p.y,p.vx,p.vy,p.temp};
}
void ensureEraseIndex(TPTWorld *world, const Simulation &sim) {
    if(world->eraseIndexValid) return;
    world->eraseHeads.assign(XRES*YRES,-1);
    world->eraseNext.assign(sim.parts.active,-1);
    for(int i=0;i<sim.parts.active;++i) if(sim.parts[i].type) {
        int px=int(sim.parts[i].x+0.5f), py=int(sim.parts[i].y+0.5f);
        if(InBounds(px,py)) { int cell=py*XRES+px; world->eraseNext[i]=world->eraseHeads[cell]; world->eraseHeads[cell]=i; }
    }
    world->eraseIndexValid=true;
}
int eraseAt(TPTWorld *world, Simulation &sim, int x, int y) {
    ensureEraseIndex(world,sim);
    int removed=0, cell=y*XRES+x;
    for(int i=world->eraseHeads[cell];i>=0;i=world->eraseNext[i]) if(sim.parts[i].type) { sim.kill_part(i); ++removed; }
    world->eraseHeads[cell]=-1;
    return removed;
}
bool mayPaintAt(const Simulation &sim, int x, int y, int type) {
    const auto &elements=SimulationData::CRef().elements;
    // The native brush uses create_part(-1), including its special SPRK path.
    if(type==PT_SPRK) {
        const auto packed=sim.pmap[y][x];
        const int existing=TYP(packed), index=ID(packed);
        if(existing==PT_WIRE) return sim.parts[index].ctype!=PT_DUST;
        return (existing==PT_INST || (elements[existing].Properties&PROP_CONDUCTS)) && sim.parts[index].life==0;
    }
    // Reuse the original collision rules, including matter/energy coexistence
    // and conditional walls. Character CreateAllowed callbacks may still reject
    // an otherwise valid location, so this is deliberately conservative.
    return sim.pmap[y][x] ? sim.eval_move(type,x,y,nullptr)==2 :
        (!sim.bmap[y/CELL][x/CELL] || sim.eval_move(type,x,y,nullptr)!=0);
}
template<typename Visit>
bool visitBrushLine(int fromX,int fromY,int toX,int toY,int radius,bool stopOnChange,Visit visit) {
    requirePoint(fromX,fromY); requirePoint(toX,toY);
    radius=std::clamp(radius,0,40);
    int x=fromX,y=fromY;
    const int dx=std::abs(toX-fromX),dy=-std::abs(toY-fromY);
    const int sx=fromX<toX ? 1 : -1,sy=fromY<toY ? 1 : -1;
    int error=dx+dy;
    bool changed=false;
    while(true) {
        for(int py=std::max(0,y-radius);py<=std::min(YRES-1,y+radius);++py)
            for(int px=std::max(0,x-radius);px<=std::min(XRES-1,x+radius);++px)
                if((px-x)*(px-x)+(py-y)*(py-y)<=radius*radius && visit(px,py)) {
                    changed=true;
                    if(stopOnChange) return true;
                }
        if(x==toX && y==toY) break;
        const int twice=error*2;
        if(twice>=dy) { error+=dy; x+=sx; }
        if(twice<=dx) { error+=dx; y+=sy; }
    }
    return changed;
}
void requireBrushType(int type) {
    if(type!=PT_NONE && !SimulationData::CRef().IsElement(type))
        throw std::invalid_argument("Unknown element identifier.");
}

}
std::recursive_mutex &tpt_engine_mutex() { static std::recursive_mutex mutex; return mutex; }
void tpt_set_error(const char *message) { lastError = message ? message : ""; }
void tpt_initialize_engine() {
    static auto simulationData = std::make_unique<SimulationData>();
    static const bool initialized = [] {
        Renderer::PopulateTables();
        const auto &sd = SimulationData::CRef();
        for (int id=0; id<PT_NUM; ++id) {
            const auto &e=sd.elements[id];
            if (!e.Enabled) continue;
            catalog.push_back({id,e.Name.ToUtf8().c_str(),e.Identifier.c_str(),e.Description.ToUtf8().c_str(),
                e.MenuSection>=0 && size_t(e.MenuSection)<sd.msections.size() ? sd.msections[e.MenuSection].name.ToUtf8().c_str() : "Special"});
        }
        return true;
    }();
    (void)initialized;
}
#define TPT_BEGIN std::lock_guard<std::recursive_mutex> lock(tpt_engine_mutex()); tpt_set_error(""); try {
#define TPT_END(failure) } catch (const std::exception &e) { tpt_set_error(e.what()); } catch (...) { tpt_set_error("The original simulation engine could not complete this operation."); } return failure;
extern "C" const char *tpt_last_error(void) { return lastError.c_str(); }
extern "C" TPTWorld *tpt_world_create(void) {
    TPT_BEGIN
    tpt_initialize_engine();
    auto world=std::make_unique<TPTWorld>();
    world->simulation=Simulation::Factory();
    return world.release();
    TPT_END(nullptr)
}
extern "C" void tpt_world_destroy(TPTWorld *world) {
    std::lock_guard<std::recursive_mutex> lock(tpt_engine_mutex());
    delete world;
}
extern "C" int32_t tpt_world_width(void) { return XRES; }
extern "C" int32_t tpt_world_height(void) { return YRES; }
extern "C" uint64_t tpt_world_tick(const TPTWorld *world) { TPT_BEGIN return requireWorld(world).frameCount; TPT_END(0) }
extern "C" int32_t tpt_world_particle_count(const TPTWorld *world) { TPT_BEGIN return requireWorld(world).NUM_PARTS; TPT_END(0) }
extern "C" int32_t tpt_world_step(TPTWorld *world, int32_t steps) {
    TPT_BEGIN
    if (steps<0 || steps>10000) throw std::invalid_argument("Step count must be between 0 and 10000.");
    auto &sim=requireWorld(world); world->eraseIndexValid=false;
    for(int i=0;i<steps;++i) { sim.BeforeSim(true); sim.UpdateParticles(0,NPART); sim.AfterSim(); }
    return 1;
    TPT_END(0)
}
extern "C" int32_t tpt_world_clear(TPTWorld *world) { TPT_BEGIN requireWorld(world).clear_sim(); world->eraseIndexValid=false; return 1; TPT_END(0) }
extern "C" int32_t tpt_world_seed(TPTWorld *world, uint32_t seed) { TPT_BEGIN requireWorld(world).rng.seed(seed); return 1; TPT_END(0) }
extern "C" int32_t tpt_world_set_legacy_fusion(TPTWorld *world, int32_t enabled) { TPT_BEGIN requireWorld(world).legacyFusionSideEffects=enabled!=0; return 1; TPT_END(0) }
extern "C" int32_t tpt_world_legacy_fusion(const TPTWorld *world) { TPT_BEGIN return requireWorld(world).legacyFusionSideEffects ? 1 : 0; TPT_END(0) }
extern "C" int32_t tpt_world_set_newtonian_gravity(TPTWorld *world, int32_t enabled) { TPT_BEGIN requireWorld(world).EnableNewtonianGravity(enabled!=0); return 1; TPT_END(0) }
extern "C" int32_t tpt_world_newtonian_gravity(const TPTWorld *world) { TPT_BEGIN return requireWorld(world).grav ? 1 : 0; TPT_END(0) }
extern "C" int32_t tpt_world_gravity_at(const TPTWorld *world, int32_t x,int32_t y,float *forceX,float *forceY) {
    TPT_BEGIN auto &sim=requireWorld(world); requirePoint(x,y); if(!forceX || !forceY) throw std::invalid_argument("Gravity outputs are missing.");
    *forceX=sim.gravOut.forceX[{x/CELL,y/CELL}]; *forceY=sim.gravOut.forceY[{x/CELL,y/CELL}]; return 1; TPT_END(0)
}
extern "C" int32_t tpt_world_paint_particle(TPTWorld *world,int32_t x,int32_t y,int32_t type,float temperature) {
    TPT_BEGIN
    auto &sim=requireWorld(world); requirePoint(x,y);
    if (!SimulationData::CRef().IsElement(type)) throw std::invalid_argument("Unknown element identifier.");
    if (!std::isfinite(temperature)) throw std::invalid_argument("Temperature must be finite.");
    world->eraseIndexValid=false;
    int index=sim.create_part(-1,x,y,type);
    if (index>=0 && temperature>=0) sim.parts[index].temp=std::clamp(temperature,MIN_TEMP,MAX_TEMP);
    return index;
    TPT_END(-1)
}
extern "C" int32_t tpt_world_erase(TPTWorld *world,int32_t x,int32_t y) {
    TPT_BEGIN
    auto &sim=requireWorld(world); requirePoint(x,y);
    return eraseAt(world,sim,x,y);
    TPT_END(-1)
}
extern "C" int32_t tpt_world_brush_may_change(TPTWorld *world,int32_t fromX,int32_t fromY,int32_t toX,int32_t toY,int32_t radius,int32_t type) {
    TPT_BEGIN
    const auto &sim=requireWorld(world); requireBrushType(type);
    if(type==PT_NONE) ensureEraseIndex(world,sim);
    return visitBrushLine(fromX,fromY,toX,toY,radius,true,[&](int x,int y) {
        return type==PT_NONE ? world->eraseHeads[y*XRES+x]>=0 : mayPaintAt(sim,x,y,type);
    }) ? 1 : 0;
    TPT_END(-1)
}
extern "C" int32_t tpt_world_paint_line(TPTWorld *world,int32_t fromX,int32_t fromY,int32_t toX,int32_t toY,int32_t radius,int32_t type) {
    TPT_BEGIN
    auto &sim=requireWorld(world); requireBrushType(type);
    // Validate before changing derived indexes or any particle.
    requirePoint(fromX,fromY); requirePoint(toX,toY);
    if(type!=PT_NONE) world->eraseIndexValid=false;
    return visitBrushLine(fromX,fromY,toX,toY,radius,false,[&](int x,int y) {
        if(type==PT_NONE) return eraseAt(world,sim,x,y)>0;
        // Repeated sparks on a Wireworld cell with the same ctype are a no-op.
        const bool changesWire=type!=PT_SPRK || TYP(sim.pmap[y][x])!=PT_WIRE || sim.parts[ID(sim.pmap[y][x])].ctype!=PT_DUST;
        return sim.create_part(-1,x,y,type)>=0 && changesWire;
    }) ? 1 : 0;
    TPT_END(-1)
}
extern "C" int32_t tpt_world_particle_at(const TPTWorld *world,int32_t x,int32_t y,int32_t energy,TPTParticle *output) {
    TPT_BEGIN
    auto &sim=requireWorld(world); requirePoint(x,y);
    if(!output) throw std::invalid_argument("Particle output is missing.");
    int packed=energy ? sim.photons[y][x] : sim.pmap[y][x];
    if(!packed) return 0;
    const int index=ID(packed);
    if(index<0 || index>=sim.parts.active || !sim.parts[index].type) return 0;
    *output=exportParticle(index,sim.parts[index]); return 1;
    TPT_END(0)
}
extern "C" size_t tpt_world_copy_particles(const TPTWorld *world,TPTParticle *output,size_t capacity) {
    TPT_BEGIN
    auto &sim=requireWorld(world); size_t count=0;
    for(int i=0;i<sim.parts.active;++i) if(sim.parts[i].type) {
        if(output && count<capacity) output[count]=exportParticle(i,sim.parts[i]);
        ++count;
    }
    return output ? std::min(count,capacity) : count;
    TPT_END(0)
}
extern "C" int32_t tpt_world_set_particle(TPTWorld *world,const TPTParticle *input) {
    TPT_BEGIN
    auto &sim=requireWorld(world);
    if(!input || input->index<0 || input->index>=sim.parts.active || !sim.parts[input->index].type) throw std::invalid_argument("The particle is no longer present.");
    world->eraseIndexValid=false;
    auto &p=sim.parts[input->index];
    if(!input->type) { sim.kill_part(input->index); return 1; }
    if(!SimulationData::CRef().IsElement(input->type)) throw std::invalid_argument("Unknown element identifier.");
    if(!std::isfinite(input->vx) || !std::isfinite(input->vy) || !std::isfinite(input->temperature_kelvin)) throw std::invalid_argument("Particle properties must be finite.");
    if(input->x!=p.x || input->y!=p.y) throw std::invalid_argument("Use painting to move a particle to a new cell.");
    if(p.type!=input->type) {
        if(sim.part_change_type(input->index,int(p.x+0.5f),int(p.y+0.5f),input->type)) return 1;
        if(p.type!=input->type) throw std::invalid_argument("The element does not allow that transformation.");
    }
    p.life=input->life; p.ctype=input->ctype; p.tmp=input->tmp; p.tmp2=input->tmp2; p.tmp3=input->tmp3; p.tmp4=input->tmp4; p.dcolour=input->dcolour;
    p.vx=std::clamp(input->vx,-10000.0f,10000.0f); p.vy=std::clamp(input->vy,-10000.0f,10000.0f); p.temp=std::clamp(input->temperature_kelvin,MIN_TEMP,MAX_TEMP);
    return 1;
    TPT_END(0)
}
extern "C" int32_t tpt_world_air_at(const TPTWorld *world,int32_t x,int32_t y,TPTAirSample *output) {
    TPT_BEGIN auto &sim=requireWorld(world); requirePoint(x,y); if(!output) throw std::invalid_argument("Air output is missing.");
    *output={sim.pv[y/CELL][x/CELL],sim.vx[y/CELL][x/CELL],sim.vy[y/CELL][x/CELL],sim.hv[y/CELL][x/CELL]}; return 1; TPT_END(0)
}
extern "C" int32_t tpt_world_set_pressure(TPTWorld *world,int32_t x,int32_t y,float pressure) {
    TPT_BEGIN auto &sim=requireWorld(world); requirePoint(x,y); if(!std::isfinite(pressure)) throw std::invalid_argument("Pressure must be finite."); sim.pv[y/CELL][x/CELL]=std::clamp(pressure,MIN_PRESSURE,MAX_PRESSURE); return 1; TPT_END(0)
}
extern "C" size_t tpt_element_count(void) { TPT_BEGIN tpt_initialize_engine(); return catalog.size(); TPT_END(0) }
extern "C" int32_t tpt_element_info(size_t index,TPTElementInfo *output) {
    TPT_BEGIN tpt_initialize_engine(); if(index>=catalog.size() || !output) throw std::invalid_argument("Catalog index is invalid.");
    const auto &entry=catalog[index]; const auto &e=SimulationData::CRef().elements[entry.id];
    *output={entry.id,entry.name.c_str(),entry.identifier.c_str(),entry.description.c_str(),entry.category.c_str(),e.Colour.Pack(),e.Properties,e.DefaultProperties.temp,e.MenuVisible}; return 1; TPT_END(0)
}
extern "C" int32_t tpt_element_id_for_name(const char *name) {
    TPT_BEGIN tpt_initialize_engine(); if(!name) return -1;
    for(const auto &entry:catalog) if(entry.name==name || entry.identifier==name || entry.identifier==std::string("DEFAULT_PT_")+name) return entry.id;
    return -1; TPT_END(-1)
}
