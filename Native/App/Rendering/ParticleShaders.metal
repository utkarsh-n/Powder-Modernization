#include <metal_stdlib>
using namespace metal;

// 48 bytes; matches MetalUniforms. Traditional Metal, macOS 14+.
struct RenderUniforms {
    uint width, height, tick, flags; // 1 cinematic, 2 heat
    float bloomStrength, exposure, time, reliefStrength;
    uint outputWidth, outputHeight, quality, profileCount;
};
struct BlurUniforms {
    uint width, height, radius, horizontal;
    float sigma, reserved0, reserved1, reserved2;
};
// Exact compact CBridge cell ABI (16 bytes) and immutable profile ABI (32 bytes).
struct PackedCell { uint colorRGB, decorationARGB; float temperatureC; uint materialFlags; };
struct MaterialProfile { float4 surface; float4 optics; };

float3 linearColor(float3 c) {
    return select(c / 12.92f, pow((c + 0.055f) / 1.055f, float3(2.4f)), c > 0.04045f);
}
uint cellIndex(int2 cell, constant RenderUniforms &u) {
    int2 p = clamp(cell, int2(0), int2(int(u.width)-1, int(u.height)-1));
    return uint(p.y)*u.width+uint(p.x);
}
float cellNoise(uint2 cell, uint seed) {
    uint value = cell.x*1973u + cell.y*9277u + seed*26699u + 911u;
    value = (value ^ (value >> 13u))*1274126177u;
    return float(value & 65535u)/65535.0f;
}
float hash21(float2 p) {
    float3 q=fract(float3(p.x,p.y,p.x)*float3(.1031f,.1030f,.0973f));
    q+=dot(q,q.yzx+33.33f);return fract((q.x+q.y)*q.z);
}
float valueNoise(float2 p) {
    float2 i=floor(p), f=fract(p); f=f*f*(3.0f-2.0f*f);
    return mix(mix(hash21(i),hash21(i+float2(1,0)),f.x),
               mix(hash21(i+float2(0,1)),hash21(i+1.0f),f.x),f.y);
}
float4 defaultSurface(uint family) {
    // roughness, metalness, transmission, relief in particle-cell units
    switch(family) {
        case 1: return float4(.82f,0,0,.72f); // granular powder
        case 2: return float4(.12f,0,.78f,.48f); // water
        case 3: return float4(.86f,0,0,.85f); // stone / wall
        case 4: return float4(.83f,0,0,.76f); // wood
        case 5: return float4(.80f,0,0,.20f); // flame
        case 6: return float4(.95f,0,.70f,.12f); // gas
        case 7: return float4(.85f,0,.80f,.14f); // steam
        case 8: return float4(.20f,0,.35f,.48f); // oil
        case 9: return float4(.18f,0,.52f,.50f); // acid
        case 10: return float4(.17f,0,.60f,.72f); // ice
        case 11: return float4(.48f,0,0,.65f); // molten material
        case 12: return float4(.22f,1,0,.76f); // metal
        case 13: return float4(.07f,0,.90f,.66f); // glass
        case 14: return float4(.78f,0,.08f,.75f); // organic
        case 15: return float4(.35f,.18f,.05f,.75f); // radioactive
        case 16: return float4(.20f,0,0,.18f); // energy
        default: return float4(.65f,0,0,.65f);
    }
}
MaterialProfile profileAt(uint index, device const PackedCell *cells, device const MaterialProfile *profiles, constant RenderUniforms &u) {
    uint id=cells[index].materialFlags&0xFFFFu;
    if(id==0xFFFFu) { MaterialProfile wall; wall.surface=defaultSurface(3u); wall.optics=float4(3,0,0,0); return wall; }
    return profiles[id<u.profileCount?id:0u];
}
float4 metadataAt(uint index, device const PackedCell *cells, device const MaterialProfile *profiles, constant RenderUniforms &u) {
    PackedCell c=cells[index]; uint id=c.materialFlags&0xFFFFu;
    MaterialProfile profile=profileAt(index,cells,profiles,u);
    float family=isfinite(profile.optics.x)?clamp(profile.optics.x,0.0f,16.0f):0.0f;
    float fluid=(c.materialFlags&(1u<<16u))!=0u?1.0f:0.0f;
    if((c.materialFlags&(1u<<20u))!=0u) fluid=profile.optics.z; // exact QA fixture optical input
    return float4(c.temperatureC,family,id!=0u?1.0f:0.0f,fluid);
}
float4 materialSurface(uint index,uint family,device const PackedCell *cells,device const MaterialProfile *profiles,constant RenderUniforms &u) {
    float4 fallback=defaultSurface(family), given=profileAt(index,cells,profiles,u).surface;
    return clamp(select(fallback,given,isfinite(given)),float4(.035f,0,0,0),float4(1,1,1,2));
}
float3 rgbColor(uint color) { return float3((color>>16u)&255u,(color>>8u)&255u,color&255u)/255.0f; }
float4 particleAt(uint index,uint2 position,device const PackedCell *cells,device const MaterialProfile *profiles,constant RenderUniforms &u) {
    PackedCell c=cells[index]; MaterialProfile profile=profileAt(index,cells,profiles,u);
    float3 color=rgbColor(c.colorRGB);
    float emission=profile.optics.y;
    if((c.materialFlags&(1u<<18u))!=0u) {
        color*=((position.x+position.y)%2u)==0u?.78f:.45f;
        emission=(c.materialFlags&(1u<<19u))!=0u?.2f:0.0f;
    } else {
        float alpha=float((c.decorationARGB>>24u)&255u)/255.0f;
        color=color*(1.0f-alpha)+rgbColor(c.decorationARGB)*alpha;
        if((c.materialFlags&(1u<<20u))==0u) emission=max(emission,clamp((c.temperatureC-550.0f)/1500.0f,0.0f,1.8f));
    }
    return float4(color,emission);
}
float3 thermalColor(float temperature) {
    float t=saturate((temperature+30.0f)/1230.0f);
    float3 cold=float3(.12f,.22f,.95f), cool=float3(.08f,.85f,.90f);
    float3 warm=float3(1,.35f,.04f), hot=float3(1,.96f,.70f);
    if(t<.25f) return linearColor(mix(cold,cool,t*4.0f));
    if(t<.70f) return linearColor(mix(cool,warm,(t-.25f)/.45f));
    return linearColor(mix(warm,hot,(t-.70f)/.30f));
}

kernel void shadeParticles(device const PackedCell *cells [[buffer(0)]],
                           device const MaterialProfile *profiles [[buffer(1)]],
                           constant RenderUniforms &u [[buffer(2)]],
                           texture2d<half,access::write> scene [[texture(0)]],
                           texture2d<half,access::write> emission [[texture(1)]],
                           uint2 position [[thread_position_in_grid]]) {
    if(position.x>=u.width || position.y>=u.height) return;
    uint index=position.y*u.width+position.x;
    float4 data=metadataAt(index,cells,profiles,u), particle=particleAt(index,position,cells,profiles,u);
    uint family=uint(clamp(data.y,0.0f,16.0f));
    float3 color=float3(0), radiance=float3(0); float height=0;
    if(data.z>0) {
        color=linearColor(clamp(particle.xyz,0.0f,1.0f));
        height=materialSurface(index,family,cells,profiles,u).w*saturate(data.z);
        if((u.flags&2u)!=0u) color=thermalColor(data.x);
        else if((u.flags&1u)!=0u && particle.w>0) {
            // All temporal terms come from simulation tick, so paused views freeze.
            float phase=cellNoise(position,29u)*6.283185f;
            float flicker=family==5u ? .76f+.24f*sin(u.time*12.0f+phase) :
                          (family==15u ? .93f+.07f*sin(u.time*2.8f+phase*.25f) : 1.0f);
            float3 source=max(color,float3(.012f));
            if(family==5u) source=mix(source,float3(1,.52f,.12f),.24f);
            // Radioactive glow is an intentional game visual. Palette darkness
            // must not suppress its requested radiance; preserve hue, not value.
            if(family==15u) source=source*(1.2f/max(max(source.x,source.y),source.z));
            radiance=source*clamp(particle.w,0.0f,12.0f)*flicker;
        }
    }
    scene.write(half4(half3(color),half(height)),position);
    emission.write(half4(half3(radiance),1),position);
}
kernel void downsampleEmission(texture2d<half, access::read> source [[texture(0)]],
                               texture2d<half, access::write> target [[texture(1)]],
                               uint2 position [[thread_position_in_grid]]) {
    if (position.x >= target.get_width() || position.y >= target.get_height()) return;
    uint2 start = uint2(position.x * source.get_width() / target.get_width(),
                       position.y * source.get_height() / target.get_height());
    uint2 end = uint2((position.x + 1u) * source.get_width() / target.get_width(),
                     (position.y + 1u) * source.get_height() / target.get_height());
    end = max(end, start + 1u);
    float3 total = float3(0.0f);
    uint count = 0u;
    for (uint y = start.y; y < end.y; ++y) {
        for (uint x = start.x; x < end.x; ++x) {
            total += float3(source.read(uint2(x, y)).xyz);
            count += 1u;
        }
    }
    target.write(half4(half3(total / float(max(count, 1u))), 1.0h), position);
}

kernel void gaussianBloom(texture2d<half, access::read> source [[texture(0)]],
                          texture2d<half, access::write> target [[texture(1)]],
                          constant BlurUniforms &u [[buffer(0)]],
                          uint2 position [[thread_position_in_grid]]) {
    if (position.x >= u.width || position.y >= u.height) return;
    float3 total = float3(0.0f);
    float weightTotal = 0.0f;
    int2 direction = u.horizontal != 0u ? int2(1, 0) : int2(0, 1);
    for (int tap = -int(u.radius); tap <= int(u.radius); ++tap) {
        float weight = exp(-float(tap * tap) / (2.0f * u.sigma * u.sigma));
        int2 point = clamp(int2(position) + direction * tap, int2(0), int2(int(u.width) - 1, int(u.height) - 1));
        total += float3(source.read(uint2(point)).xyz) * weight;
        weightTotal += weight;
    }
    target.write(half4(half3(total / max(weightTotal, 0.0001f)), 1.0h), position);
}

struct CompositeVertex {
    float4 position [[position]];
    float2 uv;
};

vertex CompositeVertex particleFullscreenVertex(uint index [[vertex_id]]) {
    float2 positions[3] = { float2(-1.0f, -1.0f), float2(3.0f, -1.0f), float2(-1.0f, 3.0f) };
    CompositeVertex result;
    result.position = float4(positions[index], 0.0f, 1.0f);
    result.uv = float2(positions[index].x * 0.5f + 0.5f, 0.5f - positions[index].y * 0.5f);
    return result;
}

float3 filmicToneMap(float3 value) {
    return saturate((value * (2.51f * value + 0.03f)) /
                    (value * (2.43f * value + 0.59f) + 0.14f));
}


// A procedural studio illuminant, not a reflected scene or a ray-traced asset.
float3 environmentLight(float3 direction,float roughness) {
    float up=saturate(direction.y*.5f+.5f);
    float3 env=mix(float3(.12f,.16f,.23f),float3(.42f,.53f,.67f),1.0f-up);
    float window=exp(-pow((direction.x+.34f)/( .15f+roughness*.45f),2.0f)) *
                 exp(-pow((direction.y+.45f)/(.35f+roughness*.40f),2.0f));
    float rim=pow(saturate(direction.x*.65f-direction.y*.25f+.2f),4.0f);
    float stripWidth=.027f+roughness*.29f;
    float strip=exp(-pow((direction.x+direction.y*.68f+.035f)/stripWidth,2.0f));
    return env+float3(1.8f,1.6f,1.25f)*window+float3(.12f,.32f,.50f)*rim+
        float3(2.25f,2.45f,2.60f)*strip*(1.0f-roughness*.65f);
}
float3 substrate(float2 p,constant RenderUniforms &u) {
    float2 uv=p/float2(u.width,u.height);
    float center=saturate(1.0f-length((uv-.5f)*float2(1.1f,1.5f)));
    float fine=.5f+.5f*sin(p.x*.17f)*sin(p.y*.17f);
    return float3(.006f,.010f,.016f)+float3(.004f,.007f,.011f)*center + fine*.0012f;
}
float heightAt(texture2d<half> scene,float2 p,constant RenderUniforms &u) {
    constexpr sampler s(coord::normalized,address::clamp_to_edge,filter::linear);
    if(any(p<0.0f)||any(p>=float2(u.width,u.height))) return 0;
    return float(scene.sample(s,p/float2(u.width,u.height)).w);
}
float contactVisibility(texture2d<half> scene,float2 p,float height,constant RenderUniforms &u) {
    if(u.reliefStrength<=0) return 1;
    float obstruction=0;
    const float2 lightStep=float2(-.64f,-.77f);
    uint taps=u.quality==0u?3u:5u;
    for(uint i=0;i<taps;++i) {
        float distance=.65f+float(i)*.85f;
        float other=heightAt(scene,p+lightStep*distance,u);
        obstruction=max(obstruction,saturate((other-height-distance*.22f)*2.5f)/(1.0f+distance*.20f));
    }
    return 1.0f-obstruction*.72f*saturate(u.reliefStrength);
}
float3 pbrLighting(float3 albedo,float3 N,float3 V,float roughness,float metalness,float occlusion) {
    const float PI=3.14159265f;
    float3 L=normalize(float3(-.52f,-.66f,1.10f)), H=normalize(V+L);
    float NdotL=max(dot(N,L),.001f), NdotV=max(dot(N,V),.02f), NdotH=max(dot(N,H),0.0f);
    float a=max(.035f,roughness*roughness), a2=a*a;
    float denominator=NdotH*NdotH*(a2-1.0f)+1.0f;
    float D=a2/max(PI*denominator*denominator,.0001f);
    float k=pow(roughness+1.0f,2.0f)/8.0f;
    float G=(NdotV/(NdotV*(1.0f-k)+k))*(NdotL/(NdotL*(1.0f-k)+k));
    // Upstream palette colors are display tints, not measured conductor reflectance.
    // Lift their cinematic reflectance while preserving the tint and exact crisp colors.
    float3 conductorReflectance=max(sqrt(max(albedo,0.0f)),float3(.24f));
    float3 F0=mix(float3(.04f),conductorReflectance,metalness);
    float3 F=F0+(1.0f-F0)*pow(1.0f-max(dot(H,V),0.0f),5.0f);
    float3 diffuse=(1.0f-F)*(1.0f-metalness)*albedo/PI;
    float3 specular=D*G*F/max(4.0f*NdotV*NdotL,.0001f);
    float3 direct=(diffuse+specular)*float3(3.2f,3.08f,2.86f)*NdotL;
    float3 reflected=environmentLight(reflect(-V,N),roughness);
    float3 ambient=albedo*(.24f+.12f*N.z)*(1.0f-metalness*.75f);
    float3 fresnel=F0+(1.0f-F0)*pow(1.0f-NdotV,5.0f);
    return (direct+ambient)*occlusion+reflected*fresnel*(.40f+.60f*(1.0f-roughness));
}

fragment float4 particleComposite(CompositeVertex in [[stage_in]],
                                   texture2d<half> scene [[texture(0)]],
                                   texture2d<half> bloom [[texture(1)]],
                                   texture2d<half> emission [[texture(2)]],
                                   constant RenderUniforms &u [[buffer(0)]],
                                   device const PackedCell *cells [[buffer(1)]],
                                   device const MaterialProfile *profiles [[buffer(2)]]) {
    constexpr sampler smoothSampler(coord::normalized,address::clamp_to_edge,filter::linear);
    constexpr sampler pixelSampler(coord::normalized,address::clamp_to_edge,filter::nearest);
    float2 dims=float2(u.width,u.height), uv=clamp(in.uv,0.0f,.999999f), p=uv*dims;
    int2 cell=int2(p); uint index=cellIndex(cell,u); float4 data=metadataAt(index,cells,profiles,u);
    bool occupied=data.z>0, cinematic=(u.flags&1u)!=0u, thermal=(u.flags&2u)!=0u;
    float3 albedo=float3(scene.sample(pixelSampler,uv).xyz);
    // These two modes remain exact cell views, with no PBR, texture, distortion, or bloom.
    if(thermal) return float4(occupied?albedo:linearColor(float3(.035f,.047f,.067f)),1);
    if(!cinematic) return float4(occupied?saturate(albedo*u.exposure):linearColor(float3(.035f,.047f,.067f)),1);

    uint family=uint(clamp(data.y,0.0f,16.0f));
    float4 material=materialSurface(index,family,cells,profiles,u);
    float roughness=material.x, metalness=material.y, transmission=material.z;
    float fluid=saturate(data.w);
    float2 q=fract(p)-.5f;
    float pixelsPerCell=min(float(u.outputWidth)/dims.x,float(u.outputHeight)/dims.y);
    float detail=smoothstep(.75f,2.0f,pixelsPerCell);
    float coverage=1, height=occupied?material.w:0;
    float3 N=float3(0,0,1);
    float3 V=normalize(float3((float2(.5f)-uv)*float2(.52f,.40f),1));
    float opticalDepth=.6f;
    float3 background=substrate(p,u);
    float3 color=background;
    if(occupied) {
        float4 neighbors=float4(metadataAt(cellIndex(cell+int2(-1,0),u),cells,profiles,u).z,
            metadataAt(cellIndex(cell+int2(1,0),u),cells,profiles,u).z,metadataAt(cellIndex(cell+int2(0,-1),u),cells,profiles,u).z,
            metadataAt(cellIndex(cell+int2(0,1),u),cells,profiles,u).z);
        float2 macroGradient=float2(heightAt(scene,p-float2(.45f,0),u)-heightAt(scene,p+float2(.45f,0),u),
                                    heightAt(scene,p-float2(0,.45f),u)-heightAt(scene,p+float2(0,.45f),u));
        float cellRandom=cellNoise(uint2(cell),family+13u);
        bool grain=family==1u || (family==15u && fluid<.1f);
        if(grain) {
            // Search adjacent occupied cells for the nearest jittered ellipsoid.
            // This removes the regular dotted lattice without moving simulation cells.
            float best=100, selectedRandom=cellRandom;
            float2 selectedRadial=q, selectedNormal=q;
            for(int gy=-1;gy<=1;++gy) for(int gx=-1;gx<=1;++gx) {
                int2 candidate=cell+int2(gx,gy);
                if(any(candidate<0)||any(candidate>=int2(u.width,u.height))) continue;
                uint ci=cellIndex(candidate,u);float4 cm=metadataAt(ci,cells,profiles,u);
                if(cm.z<=0 || uint(cm.y)!=family) continue;
                float random=cellNoise(uint2(candidate),family+13u);
                float angle=cellNoise(uint2(candidate),77u)*6.283185f;
                float2 center=float2(candidate)+.5f+float2(random-.5f,cellNoise(uint2(candidate),89u)-.5f)*.40f;
                float radius=.34f+.17f*cellNoise(uint2(candidate),113u);
                float2 delta=p-center;
                float c=cos(angle),s=sin(angle);
                float2 rotated=float2(delta.x*c+delta.y*s,-delta.x*s+delta.y*c);
                float2 aspect=float2(.82f+random*.36f,1.08f-random*.16f);
                float2 radial=rotated/(radius*aspect);
                float distance=dot(radial,radial);
                if(distance<best) {
                    best=distance;selectedRandom=random;selectedRadial=radial;
                    float2 slope=radial/aspect;
                    selectedNormal=float2(slope.x*c-slope.y*s,slope.x*s+slope.y*c);
                }
            }
            float aa=max(.055f,.60f/max(pixelsPerCell,1.0f));
            coverage=mix(1.0f,1.0f-smoothstep(1.0f-aa,1.0f+aa,best),detail);
            float dome=sqrt(max(.04f,1.0f-min(best,.99f)));
            N=normalize(float3(selectedNormal*.82f*u.reliefStrength,dome));
            height*=.34f+.66f*dome;
            albedo*=.72f+.45f*selectedRandom;
        } else {
            // Connected material interiors merge; only exposed boundaries bevel.
            float4 same=float4(0);
            int2 offsets[4]={int2(-1,0),int2(1,0),int2(0,-1),int2(0,1)};
            for(uint n=0;n<4;++n) {
                float4 other=metadataAt(cellIndex(cell+offsets[n],u),cells,profiles,u);
                same[n]=(other.z>0 && uint(other.y)==family)?1.0f:0.0f;
            }
            float4 distance=float4(q.x+.5f,.5f-q.x,q.y+.5f,.5f-q.y);
            float4 edge=(1.0f-same)*(1.0f-smoothstep(float4(0),float4(.28f),distance));
            float2 bevel=float2(edge.y-edge.x,edge.w-edge.z)*material.w*1.45f;
            N=normalize(float3((macroGradient*.75f+bevel)*u.reliefStrength,1));
            height*=1.0f-.28f*max(max(edge.x,edge.y),max(edge.z,edge.w));
        }

        // Analytic and procedural normals are evaluated per drawable pixel.
        if(fluid>.05f || family==2u || family==8u || family==9u || family==11u) {
            float speed=family==11u?.23f:1.0f;
            float phase=u.time*speed;
            float2 flow=float2(phase*.11f,-phase*.075f);
            float2 smallFlow=float2(-phase*.14f,phase*.09f);
            float2 base=p*.135f+flow, fine=p*.37f+smallFlow;
            float2 ripples=float2(
                valueNoise(base+float2(.17f,0))-valueNoise(base-float2(.17f,0)),
                valueNoise(base+float2(0,.17f))-valueNoise(base-float2(0,.17f)));
            ripples+=.27f*float2(valueNoise(fine+float2(.19f,0))-valueNoise(fine-float2(.19f,0)),
                                 valueNoise(fine+float2(0,.19f))-valueNoise(fine-float2(0,.19f)));
            float surfaceEdge=saturate(1.0f-neighbors.z);
            N=normalize(N+float3(ripples*(.27f+.23f*surfaceEdge)*u.reliefStrength,0));
            float depthSamples=0;
            int depths[3]={2,5,11};
            for(uint d=0;d<3;++d) {
                float4 above=metadataAt(cellIndex(cell-int2(0,depths[d]),u),cells,profiles,u);
                depthSamples+=(above.z>0 && uint(above.y)==family)?1.0f:0.0f;
            }
            opticalDepth=.18f+.82f*depthSamples/3.0f;
            if(family==2u) {
                float luminance=dot(albedo,float3(.2126f,.7152f,.0722f));
                float3 waterTint=float3(.018f,.130f,.145f)*(.8f+luminance*.6f);
                albedo=mix(albedo,waterTint,.90f);
            }
            float meniscus=surfaceEdge*(.65f+.35f*valueNoise(float2(p.x*.22f,phase*.12f)));
            albedo+=float3(.014f,.035f,.036f)*meniscus;
        }
        if(family==4u) {
            float warp=sin(p.x*.075f)*2.8f+valueNoise(p*.11f)*4.0f;
            float grainLine=sin(p.y*1.35f+warp);
            float fineGrain=pow(.5f+.5f*sin(p.y*4.1f+warp*2.3f),9.0f);
            float luminance=dot(albedo,float3(.2126f,.7152f,.0722f));
            float3 timber=float3(.19f,.078f,.028f)*(.65f+sqrt(luminance)*.8f);
            albedo=mix(albedo,timber,.82f)*(.61f+.48f*smoothstep(-.8f,.7f,grainLine));
            albedo*=1.0f-.23f*fineGrain*detail;
            N=normalize(N+float3(.021f*cos(p.x*.075f),.060f*grainLine+.025f*fineGrain,0)*u.reliefStrength);
        } else if(family==12u) {
            float brushed=sin(p.y*17.0f+valueNoise(p*.42f)*2.0f);
            albedo*=.93f+.07f*brushed*detail;
            N=normalize(N+float3(.018f*sin(p.x*.065f),.012f*brushed*detail+.045f*sin(p.y*.045f),0)*u.reliefStrength);
        } else if(family==14u) {
            float veins=pow(abs(sin(p.x*.68f+sin(p.y*.21f)*1.8f)),12.0f);
            float tissue=valueNoise(p*.65f);
            // Green botanical cells use a subdued leaf reflectance. Other organic
            // palette colors retain their identity (for example red tissue).
            bool botanical=albedo.y>albedo.x*1.25f && albedo.y>albedo.z*1.25f;
            if(botanical) albedo=albedo*float3(.8f,.44f,.75f)+float3(.009f,.005f,.003f);
            albedo*=.59f+.49f*tissue;
            albedo+=float3(.017f,.036f,.005f)*veins;
            N=normalize(N+float3(cos(p.x*.68f)*.11f,sin(p.y*.61f)*.08f,0)*u.reliefStrength);
        } else if(family==3u || family==0u || family==10u) {
            float mineral=valueNoise(p*1.7f)*.55f+valueNoise(p*.31f)*.45f;
            albedo*=.78f+.34f*mineral;
            N=normalize(N+float3((valueNoise(p+float2(.3f,0))-mineral)*.14f,
                                (valueNoise(p+float2(0,.3f))-mineral)*.14f,0)*detail*u.reliefStrength);
            if(family==10u) albedo=mix(albedo,float3(.35f,.54f,.65f),mineral*.12f);
        }
        float visibility=contactVisibility(scene,p,height,u);
        float cavity=1.0f-.09f*(neighbors.x+neighbors.y+neighbors.z+neighbors.w)*
            (grain?.55f:.18f)*saturate(u.reliefStrength);
        color=pbrLighting(albedo,N,V,roughness,metalness,visibility*cavity);

        if(transmission>.001f) {
            // Approximate the transmitted substrate and nearby scene in screen space.
            // This is an optical presentation model; no particle position changes.
            float2 displacement=N.xy*(family==13u?2.8f:1.8f);
            float2 refractedUV=clamp((p+displacement)/dims,0.0f,1.0f);
            uint behindIndex=cellIndex(int2(refractedUV*dims),u);
            float4 behindMeta=metadataAt(behindIndex,cells,profiles,u);
            float3 behind=(behindMeta.z>0 && uint(behindMeta.y)!=family)
                ?float3(scene.sample(smoothSampler,refractedUV).xyz):substrate(p+displacement,u)*1.8f;
            float thickness=family==2u ? .35f+opticalDepth*1.6f : .55f+material.w*1.4f;
            float3 transmittance=exp(-(1.0f-saturate(albedo))*(family==13u?.55f:1.45f)*thickness);
            float fresnel=.025f+.975f*pow(1.0f-max(dot(N,V),0.0f),5.0f);
            float3 transmitted=behind*transmittance+albedo*(1.0f-transmittance)*.32f;
            float3 reflection=environmentLight(reflect(-V,N),roughness);
            color=mix(color,transmitted,transmission*(1.0f-fresnel));
            color+=reflection*(fresnel+((family==13u || family==10u)?.012f:.025f))*(1.0f-roughness*.6f);
            if(family==2u) color+=float3(.006f,.025f,.029f)*(1.0f-exp(-opticalDepth*1.8f));
            if(family==13u) color+=albedo*.012f+float3(.08f,.14f,.17f)*length(N.xy);
        }
        if(family==6u || family==7u) {
            float density=.20f+.48f*valueNoise(p*.55f+float2(u.time*.13f,-u.time*.26f));
            color=mix(background,color+(family==7u?float3(.055f):float3(.005f)),density);
        }
        float3 glow=float3(emission.sample(pixelSampler,uv).xyz);
        if(family==5u || family==16u) {
            float curl=valueNoise(p*.65f+float2(u.time*.35f,-u.time*1.8f));
            color=albedo*(.45f+curl*.65f)+glow*(.72f+.28f*curl);
            coverage=mix(coverage,.66f+.34f*curl,.5f);
        } else color+=glow*(family==15u?.85f:.62f);
        color=mix(background*(grain?.68f:1.0f),color,coverage);
    } else {
        color*=contactVisibility(scene,p,0,u);
    }
    if(u.bloomStrength>0) {
        float3 halo=float3(bloom.sample(smoothSampler,uv).xyz);
        if(u.quality>0u) {
            float2 spread=float2(2.4f)/dims;
            halo=halo*.78f+(float3(bloom.sample(smoothSampler,uv+float2(spread.x,0)).xyz)+
                float3(bloom.sample(smoothSampler,uv-float2(spread.x,0)).xyz)+
                float3(bloom.sample(smoothSampler,uv+float2(0,spread.y)).xyz)+
                float3(bloom.sample(smoothSampler,uv-float2(0,spread.y)).xyz))*.055f;
        }
        // Nearby emitters illuminate occupied surfaces as well as the air around them.
        color+=halo*u.bloomStrength*(occupied?(.32f+albedo*.52f):float3(.62f));
    }
    return float4(filmicToneMap(max(color,0.0f)*u.exposure),1);
}
