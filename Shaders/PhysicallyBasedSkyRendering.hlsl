#ifndef URP_PHYSICALLY_BASED_SKY_RENDERING_INCLUDED
#define URP_PHYSICALLY_BASED_SKY_RENDERING_INCLUDED

#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

#include "./PhysicallyBasedSkyCommon.hlsl"

float3 _PBRSkyCameraPosPS;
int _DisableSunDisk;

#define _RenderSunDisk (_DisableSunDisk == 0.0)

struct CelestialBodyData
{
    float3 color;
    float radius;
    float3 forward; // high precision required
    float distanceFromCamera;
    half3 right;
    float angularRadius;
    half3 up;
    int type;
    float3 surfaceColor;
    float earthshine;
    float4 surfaceTextureScaleOffset;
    half3 sunDirection;
    half flareCosInner;
    //half2 phaseAngleSinCos;
    half flareCosOuter;
    half flareSize;
    float3 flareColor;
    half flareFalloff;
    //float3 padding;
    //int shadowIndex;
};

CelestialBodyData GetCelestialBody()
{
    CelestialBodyData light;

    light.color = _CelestialBody_Color;
    light.radius = _CelestialBody_Radius;
    light.forward = _CelestialBody_Forward;
    light.distanceFromCamera = _CelestialBody_DistanceFromCamera;
    light.right = _CelestialBody_Right;
    light.angularRadius = _CelestialBody_AngularRadius;
    light.up = _CelestialBody_Up;
    light.type = _CelestialBody_Type;
    light.surfaceColor = _CelestialBody_SurfaceColor;
    light.earthshine = _CelestialBody_Earthshine;
    light.surfaceTextureScaleOffset = _CelestialBody_SurfaceTextureScaleOffset;
    light.sunDirection = _CelestialBody_SunDirection;
    light.flareCosInner = _CelestialBody_FlareCosInner;
    light.flareCosOuter = _CelestialBody_FlareCosOuter;
    light.flareSize = _CelestialBody_FlareSize;
    light.flareColor = _CelestialBody_FlareColor;
    light.flareFalloff = _CelestialBody_FlareFalloff;

    return light;
}

float ComputeMoonPhase(CelestialBodyData moon, float3 V)
{
    float3 M = moon.forward.xyz * moon.distanceFromCamera;

    float radialDistance = moon.distanceFromCamera, rcpRadialDistance = rcp(radialDistance);
    float2 t = IntersectSphere(moon.radius, dot(moon.forward.xyz, -V), radialDistance, rcpRadialDistance);

    float3 N = normalize(M - t.x * V);

    return saturate(-dot(N, moon.sunDirection));
}

float ComputeEarthshine(CelestialBodyData moon)
{
    // Approximate earthshine: sun light reflected from earth
    // cf. A Physically-Based Night Sky Model

    // Compute the percentage of earth surface that is illuminated by the sun as seen from the moon
    //float earthPhase = PI - FastACos(dot(sun.forward.xyz, -light.forward.xyz));
    //float earthshine = 1.0f - sin(0.5f * earthPhase) * tan(0.5f * earthPhase) * log(rcp(tan(0.25f * earthPhase)));

    // Cheaper approximation of the above (https://www.desmos.com/calculator/11ny6d5j1b)
    float sinPhase = sqrt(max(1 - dot(moon.sunDirection, moon.forward), 0.0)) * INV_SQRT2;
    float earthshine = 1.0 - sinPhase * sqrt(sinPhase);

    return earthshine * moon.earthshine;
}

float3 RenderSunDisk(inout float tFrag, float tExit, float3 V)
{
    float3 radiance = 0;

    // Intersect and shade emissive celestial bodies.
    // Unfortunately, they don't write depth.
    //for (uint i = 0; i < _CelestialBodyCount; i++)
    {
        CelestialBodyData light = GetCelestialBody();

        // Celestial body must be outside the atmosphere (request from Pierre D).
        float lightDist = max(light.distanceFromCamera, tExit);

        float angularRadius = light.angularRadius;
        if (asint(angularRadius) != 0 && lightDist < tFrag)
        {
            // We may be able to see the celestial body.
            float3 L = -light.forward.xyz;

            float LdotV = -dot(L, V);
            float radInner = light.angularRadius;

            if (LdotV >= light.flareCosInner) // Sun disk.
            {
                tFrag = lightDist;
                float3 color = light.surfaceColor;

                if (light.type != 0)
                    color *= ComputeMoonPhase(light, V) * INV_PI + ComputeEarthshine(light); // Lambertian BRDF

                /*
                if (light.surfaceTextureScaleOffset.x > 0)
                {
                    float2 proj = float2(dot(V, light.right), dot(V, light.up));
                    float2 angles = float2(FastASin(proj.x), FastASin(-proj.y));
                    float2 uv = angles * rcp(radInner) * 0.5 + 0.5;
                    color *= SampleCookie2D(uv, light.surfaceTextureScaleOffset);
                }
                */

                radiance = color;
            }
            else if (LdotV >= light.flareCosOuter) // Flare region.
            {
                float rad = acos(LdotV); // high precision required
                float r = max(0, rad - radInner);
                float w = saturate(1 - r * rcp(light.flareSize));

                float3 color = light.flareColor;
                color *= SafePositivePow(w, light.flareFalloff);
                radiance += color;
            }
        }
    }

    return radiance;
}

#endif // URP_PHYSICALLY_BASED_SKY_RENDERING_INCLUDED