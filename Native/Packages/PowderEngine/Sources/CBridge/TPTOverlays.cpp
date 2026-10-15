// GPL-3.0-or-later. Native wall and plain sign overlay adapters.
#include "TPTInternal.hpp"
#include "simulation/SimulationData.h"
#include "Format.h"
#include <algorithm>
#include <cstring>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
struct WallEntry { int id; std::string name,identifier,description; };
const std::vector<WallEntry> &wallCatalog() {
    tpt_initialize_engine();
    static const auto entries=[] {
        std::vector<WallEntry> result;
        const auto &walls=SimulationData::CRef().wtypes;
        for(size_t i=0;i<walls.size();++i) {
            const auto &wall=walls[i];
            result.push_back({int(i),wall.name.ToUtf8().c_str(),wall.identifier.c_str(),wall.descs.ToUtf8().c_str()});
        }
        return result;
    }();
    return entries;
}
Simulation &requireWorld(const TPTWorld *world) {
    if(!world || !world->simulation) throw std::invalid_argument("The simulation handle is missing.");
    return *world->simulation;
}
void requirePoint(int x,int y) { if(!InBounds(x,y)) throw std::out_of_range("The point is outside the simulation canvas."); }
void copyText(TPTSign &output,const String &text) {
    const auto clean=format::CleanString(text,false,true,true).ToUtf8();
    size_t length=std::min(clean.size(),sizeof(output.text)-1);
    output.text_truncated=length<clean.size();
    // Do not split a multibyte scalar when truncating the copied label.
    if(output.text_truncated) while(length>0 && (static_cast<unsigned char>(clean[length])&0xc0)==0x80) --length;
    std::memcpy(output.text,clean.data(),length); output.text[length]=0;
}
}
#define OVERLAY_BEGIN std::lock_guard<std::recursive_mutex> lock(tpt_engine_mutex()); tpt_set_error(""); try {
#define OVERLAY_END(failure) } catch(const std::exception &e) { tpt_set_error(e.what()); } catch(...) { tpt_set_error("The original engine could not update this overlay."); } return failure;
extern "C" size_t tpt_wall_type_count(void) { OVERLAY_BEGIN return wallCatalog().size(); OVERLAY_END(0) }
extern "C" int32_t tpt_wall_cell_size(void) { return CELL; }
extern "C" int32_t tpt_wall_type_info(size_t index,TPTWallInfo *output) {
    OVERLAY_BEGIN
    const auto &entries=wallCatalog();
    if(!output || index>=entries.size()) throw std::invalid_argument("Wall catalog index is invalid.");
    const auto &entry=entries[index]; const auto &wall=SimulationData::CRef().wtypes[index];
    *output={entry.id,entry.name.c_str(),entry.identifier.c_str(),entry.description.c_str(),wall.colour.Pack(),wall.eglow.Pack(),wall.drawstyle};
    return 1; OVERLAY_END(0)
}
extern "C" size_t tpt_world_copy_walls(const TPTWorld *world,TPTWallCell *output,size_t capacity) {
    OVERLAY_BEGIN
    auto &sim=requireWorld(world); size_t count=0;
    for(int y=0;y<YCELLS;++y) for(int x=0;x<XCELLS;++x) if(sim.bmap[y][x]) {
        if(output && count<capacity) output[count]={x*CELL,y*CELL,sim.bmap[y][x],sim.emap[y][x],sim.fvx[y][x],sim.fvy[y][x]};
        ++count;
    }
    return output ? std::min(count,capacity) : count; OVERLAY_END(0)
}
extern "C" int32_t tpt_world_wall_at(const TPTWorld *world,int32_t x,int32_t y,TPTWallCell *output) {
    OVERLAY_BEGIN
    const auto &sim=requireWorld(world); requirePoint(x,y);
    if(!output) throw std::invalid_argument("Wall output is missing.");
    const int bx=x/CELL, by=y/CELL;
    if(!sim.bmap[by][bx]) return 0;
    *output={bx*CELL,by*CELL,sim.bmap[by][bx],sim.emap[by][bx],sim.fvx[by][bx],sim.fvy[by][bx]};
    return 1; OVERLAY_END(-1)
}
extern "C" int32_t tpt_world_set_wall(TPTWorld *world,int32_t x,int32_t y,int32_t type) {
    OVERLAY_BEGIN
    auto &sim=requireWorld(world); requirePoint(x,y);
    if(type<0 || size_t(type)>=wallCatalog().size()) throw std::invalid_argument("Unknown wall identifier.");
    world->eraseIndexValid=false;
    const int previous=sim.bmap[y/CELL][x/CELL];
    const int result=sim.CreateWalls(x,y,0,0,type,nullptr);
    if(previous!=sim.bmap[y/CELL][x/CELL]) sim.emap[y/CELL][x/CELL]=0;
    return result; OVERLAY_END(0)
}
extern "C" int32_t tpt_world_wall_may_change(const TPTWorld *world,int32_t x,int32_t y,int32_t type) {
    OVERLAY_BEGIN
    const auto &sim=requireWorld(world); requirePoint(x,y);
    if(type<0 || size_t(type)>=wallCatalog().size()) throw std::invalid_argument("Unknown wall identifier.");
    const int bx=x/CELL, by=y/CELL;
    // CreateWalls refuses a streamline even when the nearby one is the target itself.
    if(type==WL_STREAM) {
        for(int row=std::max(0,by-1);row<=std::min(YCELLS-1,by+1);++row)
            for(int column=std::max(0,bx-1);column<=std::min(XCELLS-1,bx+1);++column)
                if(sim.bmap[row][column]==WL_STREAM) return 0;
    }
    if(type==WL_ERASEALL) {
        if(sim.bmap[by][bx]) return 1;
        // Original delete_part removes the visible energy layer first, then matter
        // on a later invocation. Do not replace it with the native all-layer eraser.
        for(int py=by*CELL;py<(by+1)*CELL;++py)
            for(int px=bx*CELL;px<(bx+1)*CELL;++px)
                if(sim.photons[py][px] || sim.pmap[py][px]) return 1;
        for(const auto &sign:sim.signs)
            if(sign.x>=bx*CELL && sign.x<=(bx+1)*CELL &&
               sign.y>=by*CELL && sign.y<=(by+1)*CELL) return 1;
        return 0;
    }
    if(sim.bmap[by][bx]!=type) return 1;
    // Repainting a fan can reset velocity despite retaining the same wall ID.
    if(type==WL_FAN && (sim.fvx[by][bx]!=0.0f || sim.fvy[by][bx]!=0.0f)) return 1;
    // Re-marking an identical gravity wall only recomputes the same derived mask.
    return 0; OVERLAY_END(-1)
}
extern "C" size_t tpt_world_copy_signs(const TPTWorld *world,TPTSign *output,size_t capacity) {
    OVERLAY_BEGIN
    auto &sim=requireWorld(world);
    if(!output) return sim.signs.size();
    const size_t count=std::min(capacity,sim.signs.size());
    for(size_t index=0;index<count;++index) {
        const auto &sign=sim.signs[index]; TPTSign value{};
        value.index=int(index);value.x=sign.x;value.y=sign.y;value.justification=int(sign.ju);
        const auto text=sign.getDisplayText(&sim,value.bounds_x,value.bounds_y,value.bounds_width,value.bounds_height,false);
        copyText(value,text); output[index]=value;
    }
    return count; OVERLAY_END(0)
}
extern "C" int32_t tpt_world_set_sign(TPTWorld *world,int32_t index,const char *text,int32_t x,int32_t y,int32_t justification) {
    OVERLAY_BEGIN
    auto &sim=requireWorld(world);requirePoint(x,y);
    if(!text || strnlen(text,4097)>4096) throw std::invalid_argument("Sign text must contain at most 4096 UTF-8 bytes.");
    if(justification<0 || justification>=sign::Max) throw std::invalid_argument("Sign alignment is invalid.");
    auto label=ByteString(text).FromUtf8(false);
    if(label.empty() || label.size()>45 || std::any_of(label.begin(),label.end(),[](auto character) { return character<32 || character>126; }))
        throw std::invalid_argument("Original OPS signs require 1 to 45 printable ASCII characters.");
    sign value(label,x,y,static_cast<sign::Justification>(justification));
    if(index==-1) {
        if(sim.signs.size()>=MAXSIGNS) throw std::invalid_argument("The original engine supports at most 16 signs.");
        sim.signs.push_back(value); return int(sim.signs.size())-1;
    }
    if(index<0 || size_t(index)>=sim.signs.size()) throw std::invalid_argument("The sign is no longer present.");
    sim.signs[index]=value;return index; OVERLAY_END(-1)
}
extern "C" int32_t tpt_world_remove_sign(TPTWorld *world,int32_t index) {
    OVERLAY_BEGIN auto &sim=requireWorld(world);
    if(index<0 || size_t(index)>=sim.signs.size()) throw std::invalid_argument("The sign is no longer present.");
    sim.signs.erase(sim.signs.begin()+index);return 1; OVERLAY_END(0)
}
