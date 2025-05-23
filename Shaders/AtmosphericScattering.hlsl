#ifndef URP_ATMOSPHERIC_SCATTERING_INCLUDED
#define URP_ATMOSPHERIC_SCATTERING_INCLUDED

#ifndef SHADERGRAPH_PREVIEW
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Debug/DebuggingFullscreen.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/GeometricTools.hlsl"
#include "./PhysicallyBasedSkyRendering.hlsl"
#include "./PhysicallyBasedSkyEvaluation.hlsl"

//#define OPAQUE_FOG_PASS
//#define ATMOSPHERE_NO_AERIAL_PERSPECTIVE

// [Do NOT enable] Precomputed Atmospheric Scattering
// [Reason] No significant performance improvement was observed on URP while losing visual quality.
#define SHADEROPTIONS_PRECOMPUTED_ATMOSPHERIC_ATTENUATION (0) // This feature is disabled on the CPU side

#define FOGCOLORMODE_CONSTANT_COLOR (0)
#define FOGCOLORMODE_SKY_COLOR (1)

#define _MipFogNear         _MipFogParameters.x
#define _MipFogFar          _MipFogParameters.y
#define _MipFogMaxMip       _MipFogParameters.z

#if AMBIENT_PROBE
TEXTURECUBE(_SkyTexture);
half _SkyTextureMipCounts;
#endif // AMBIENT_PROBE

// The "_SkyTexture" is not convolved, so we need an alternative method...
half3 GetFogColor(half3 V, float fragDist)
{
    half3 color = _FogColor.rgb;

    if (_FogColorMode == FOGCOLORMODE_SKY_COLOR)
    {
        // Based on Uncharted 4 "Mip Sky Fog" trick: http://advances.realtimerendering.com/other/2016/naughty_dog/NaughtyDog_TechArt_Final.pdf
#if AMBIENT_PROBE
        half mimMip = _SkyTextureMipCounts == 0.0 ? 7.0 - 1.0 : _SkyTextureMipCounts - 1.0;
#else
        half mimMip = half(6.0);
#endif // AMBIENT_PROBE
        half mipLevel = (1.0 - _MipFogMaxMip * saturate((fragDist - _MipFogNear) / (_MipFogFar - _MipFogNear))) * (mimMip);
        
        //half3 viewColor = SAMPLE_TEXTURECUBE_LOD(_SkyTexture, s_trilinear_clamp_sampler, -V, mipLevel).rgb; // '_FogColor' is the tint
        
        // For the atmospheric scattering, we use the environment cubemap. (no convolution)
        const half MIP_OFFSET_HORIZON = 2.0;
        const half MIP_OFFSET_LOW = 2.5;
        const half MIP_OFFSET_HIGH = 3.5;

        const half3 U = half3(0, 1, 0);
        const half3 D = half3(0, -1, 0);
        half3 horizontalV = half3(V.x, 0, V.z);

        half3 upDirection   = normalize(horizontalV - U);
        half3 downDirection = normalize(horizontalV - D);

        half3 viewColor;
#if AMBIENT_PROBE
        UNITY_BRANCH
        if (_SkyTextureMipCounts == 0.0)
#endif // AMBIENT_PROBE
        {
            // GGX convoluted cubemap (baked)
            half4 encodedIrradiance = SAMPLE_TEXTURECUBE_LOD(_GlossyEnvironmentCubeMap, s_trilinear_clamp_sampler, -V, mipLevel); // '_FogColor' is the tint
            viewColor = DecodeHDREnvironment(encodedIrradiance, _GlossyEnvironmentCubeMap_HDR);
        }
#if AMBIENT_PROBE
        else
        {
            half3 groundColor = SAMPLE_TEXTURECUBE_LOD(_SkyTexture, s_trilinear_clamp_sampler, -downDirection, mipLevel).rgb;
            half3 horizonColor = SAMPLE_TEXTURECUBE_LOD(_SkyTexture, s_trilinear_clamp_sampler, -V, mipLevel + MIP_OFFSET_HORIZON).rgb;
            half3 lowBlurColor = SAMPLE_TEXTURECUBE_LOD(_SkyTexture, s_trilinear_clamp_sampler, -V, mipLevel + MIP_OFFSET_LOW).rgb;
            half3 highBlurColor = SAMPLE_TEXTURECUBE_LOD(_SkyTexture, s_trilinear_clamp_sampler, -V, mipLevel + MIP_OFFSET_HIGH).rgb;

            half VdotD = saturate(dot(V, downDirection));
            half verticalLerp = 1.0 - VdotD * VdotD; // non-linear gradient

            
            half weight1 = saturate(1.0 - VdotD) * 0.4;
            half weight2 = saturate((1.0 - VdotD) * 3.0) * 0.6;

            viewColor = lerp(groundColor, horizonColor, verticalLerp);
            viewColor += lowBlurColor * weight1;
            viewColor += highBlurColor * weight2;
        }
#endif // AMBIENT_PROBE

        color *= viewColor;
    }

    return color;
}

// All units in meters!
// Assumes that there is NO sky occlusion along the ray AT ALL.
// We evaluate atmospheric scattering for the sky and other celestial bodies
// during the sky pass. The opaque atmospheric scattering pass applies atmospheric
// scattering to all other opaque geometry.
void EvaluatePbrAtmosphere(float3 positionPS, half3 V, float distAlongRay, bool renderSunDisk,
                           out half3 skyColor, out half3 skyOpacity)
{
    skyColor = skyOpacity = 0;

    const float  R = _PlanetaryRadius;
    const float2 n = float2(_AirDensityFalloff, _AerosolDensityFalloff);
    const float2 H = float2(_AirScaleHeight,    _AerosolScaleHeight);
    const float3 O = positionPS;

    const float  tFrag = abs(distAlongRay); // Clear the "hit ground" flag

    half3 N; float r; // These params correspond to the entry point
    float  tEntry = IntersectAtmosphere(O, V, N, r).x;
    float  tExit  = IntersectAtmosphere(O, V, N, r).y;

    half NdotV  = dot(N, V);
    half cosChi = -NdotV;
    float cosHor = ComputeCosineOfHorizonAngle(r);

    bool rayIntersectsAtmosphere = (tEntry >= 0);
    bool lookAboveHorizon        = (cosChi >= cosHor);

    // Our precomputed tables only contain information above ground.
    // Being on or below ground still counts as outside.
    // If it's outside the atmosphere, we only need one texture look-up.
    bool hitGround = distAlongRay < 0;
    bool rayEndsInsideAtmosphere = (tFrag < tExit) && !hitGround;

    if (rayIntersectsAtmosphere)
    {
        float2 Z = R * n;
        float r0 = r, cosChi0 = cosChi;

        float r1 = 0, cosChi1 = 0;
        half3 N1 = 0;

        if (tFrag < tExit)
        {
            float3 P1 = O + tFrag * -V;

            r1      = length(P1);
            N1      = P1 * rcp(r1);
            cosChi1 = dot(P1, -V) * rcp(r1);

            // Potential swap.
            cosChi0 = (cosChi1 >= 0) ? cosChi0 : -cosChi0;
        }

        float2 ch0, ch1 = 0;

        {
            float2 z0 = r0 * n;

            ch0.x = RescaledChapmanFunction(z0.x, Z.x, cosChi0);
            ch0.y = RescaledChapmanFunction(z0.y, Z.y, cosChi0);
        }

        if (tFrag < tExit)
        {
            float2 z1 = r1 * n;

            ch1.x = ChapmanUpperApprox(z1.x, abs(cosChi1)) * exp(Z.x - z1.x);
            ch1.y = ChapmanUpperApprox(z1.y, abs(cosChi1)) * exp(Z.y - z1.y);
        }

        // We may have swapped X and Y.
        float2 ch = abs(ch0 - ch1);

        float3 optDepth = ch.x * H.x * _AirSeaLevelExtinction.xyz
                        + ch.y * H.y * _AerosolSeaLevelExtinction;

        skyOpacity = 1 - TransmittanceFromOpticalDepth(optDepth); // from 'tEntry' to 'tFrag'

        //for (uint i = 0; i < _CelestialLightCount; i++)
        {
            //CelestialBodyData light = _CelestialBodyDatas[i];
            CelestialBodyData light = GetCelestialBody();
            half3 L = -light.forward.xyz;

            // The sun disk hack causes some issues when applied to nearby geometry, so don't do that.
            if (renderSunDisk && asint(light.angularRadius) != 0 && light.distanceFromCamera <= tFrag)
            {
                half c = dot(L, -V);

                if (-0.99999 < c && c < 0.99999)
                {
                    half alpha = light.angularRadius;
                    half beta = FastACos(c);
                    half gamma = min(alpha, beta);

                    // Make sure that if (beta = Pi), no rotation is performed.
                    gamma *= (PI - beta) * rcp(PI - gamma);

                    // Perform a shortest arc rotation.
                    half3   A = normalize(cross(L, -V));
                    half3x3 R = RotationFromAxisAngle(A, sin(gamma), cos(gamma));

                    // Rotate the light direction.
                    L = mul(R, L);
                }
            }

            // TODO: solve in spherical coords?
            float height = r - R;
            half  NdotL = dot(N, L);
            half3 projL = L - N * NdotL;
            half3 projV = V - N * NdotV;
            half  phiL  = FastACos(clamp(dot(projL, projV) * rsqrt(max(dot(projL, projL) * dot(projV, projV), FLT_EPS)), -1, 1));

            TexCoord4D tc = ConvertPositionAndOrientationToTexCoords(height, NdotV, NdotL, phiL);
            
            // Note: we switched the Y & Z of the LUT due to performance reason.
            float3 uvw0 = float3(tc.u, tc.w0, tc.v);
            float3 uvw1 = float3(tc.u, tc.w1, tc.v);

            half3 radiance = 0; // from 'tEntry' to 'tExit'

            // Single scattering does not contain the phase function.
            half LdotV = dot(L, V);

            // Air.
            radiance += lerp(SAMPLE_TEXTURE3D_LOD(_AirSingleScatteringTexture,     s_linear_clamp_sampler, uvw0, 0).rgb,
                             SAMPLE_TEXTURE3D_LOD(_AirSingleScatteringTexture,     s_linear_clamp_sampler, uvw1, 0).rgb,
                             tc.a) * AirPhase(LdotV);

            // Aerosols.
            // TODO: since aerosols are in a separate texture,
            // they could use a different max height value for improved precision.
            radiance += lerp(SAMPLE_TEXTURE3D_LOD(_AerosolSingleScatteringTexture, s_linear_clamp_sampler, uvw0, 0).rgb,
                             SAMPLE_TEXTURE3D_LOD(_AerosolSingleScatteringTexture, s_linear_clamp_sampler, uvw1, 0).rgb,
                             tc.a) * AerosolPhase(LdotV);

            // MS.
            radiance += lerp(SAMPLE_TEXTURE3D_LOD(_MultipleScatteringTexture,      s_linear_clamp_sampler, uvw0, 0).rgb,
                             SAMPLE_TEXTURE3D_LOD(_MultipleScatteringTexture,      s_linear_clamp_sampler, uvw1, 0).rgb,
                             tc.a) * MS_EXPOSURE_INV;

            if (rayEndsInsideAtmosphere)
            {
                half3 radiance1 = 0; // from 'tFrag' to 'tExit'

                // TODO: solve in spherical coords?
                float height1 = r1 - R;
                half  NdotV1 = -cosChi1;
                half  NdotL1 = dot(N1, L);
                half3 projL1 = L - N1 * NdotL1;
                half3 projV1 = V - N1 * NdotV1;
                half  phiL1  = FastACos(clamp(dot(projL1, projV1) * rsqrt(max(dot(projL1, projL1) * dot(projV1, projV1), FLT_EPS)), -1, 1));

                tc = ConvertPositionAndOrientationToTexCoords(height1, NdotV1, NdotL1, phiL1);

                // Note: we switched the Y & Z of the LUT due to performance reason.
                uvw0 = float3(tc.u, tc.w0, tc.v);
                uvw1 = float3(tc.u, tc.w1, tc.v);

                // Single scattering does not contain the phase function.

                // Air.
                radiance1 += lerp(SAMPLE_TEXTURE3D_LOD(_AirSingleScatteringTexture,     s_linear_clamp_sampler, uvw0, 0).rgb,
                                  SAMPLE_TEXTURE3D_LOD(_AirSingleScatteringTexture,     s_linear_clamp_sampler, uvw1, 0).rgb,
                                  tc.a) * AirPhase(LdotV);

                // Aerosols.
                // TODO: since aerosols are in a separate texture,
                // they could use a different max height value for improved precision.
                radiance1 += lerp(SAMPLE_TEXTURE3D_LOD(_AerosolSingleScatteringTexture, s_linear_clamp_sampler, uvw0, 0).rgb,
                                  SAMPLE_TEXTURE3D_LOD(_AerosolSingleScatteringTexture, s_linear_clamp_sampler, uvw1, 0).rgb,
                                  tc.a) * AerosolPhase(LdotV);

                // MS.
                radiance1 += lerp(SAMPLE_TEXTURE3D_LOD(_MultipleScatteringTexture,      s_linear_clamp_sampler, uvw0, 0).rgb,
                                  SAMPLE_TEXTURE3D_LOD(_MultipleScatteringTexture,      s_linear_clamp_sampler, uvw1, 0).rgb,
                                  tc.a) * MS_EXPOSURE_INV;

                // L(tEntry, tFrag) = L(tEntry, tExit) - T(tEntry, tFrag) * L(tFrag, tExit)
                radiance = max(0, radiance - (1 - skyOpacity) * radiance1);
            }

            radiance *= light.color.rgb; // Globally scale the intensity

            skyColor += radiance;
        }

        #ifndef DISABLE_ATMOS_EVALUATE_ARTIST_OVERRIDE
        AtmosphereArtisticOverride(cosHor, cosChi, skyColor, skyOpacity);
        #endif
    }
}

void EvaluateAtmosphericScattering(half3 V, float2 positionNDC, float tFrag, out half3 skyColor, out half3 skyOpacity)
{
#if SHADEROPTIONS_PRECOMPUTED_ATMOSPHERIC_ATTENUATION
    EvaluateCameraAtmosphericScattering(V, positionNDC, tFrag, skyColor, skyOpacity);
#else
    #ifdef LOCAL_SKY
    float3 O = _PBRSkyCameraPosPS;
    #else
    float3 O = GetCameraPositionWS() - _PlanetCenterPosition;
    #endif
    EvaluatePbrAtmosphere(O, -V, tFrag, false, skyColor, skyOpacity);
    skyColor *= _IntensityMultiplier;
#endif
}

// Returns false when fog is not applied
bool EvaluateAtmosphericScattering(PositionInputs posInput, half3 V, out half3 color, out half3 opacity)
{
    color = opacity = 0;

#ifdef DEBUG_DISPLAY
    half4 debugColor = 0;

    if (CanDebugOverrideOutputColor(debugColor, posInput.positionNDC, debugColor))
    {
        return false;
    }
#endif

    #ifdef OPAQUE_FOG_PASS
    bool isSky = posInput.deviceDepth == UNITY_RAW_FAR_CLIP_VALUE;
    #else
    bool isSky = false;
    #endif

    // Convert depth to distance along the ray. Doesn't work with tilt shift, etc.
    // When a pixel is at far plane, the world space coordinate reconstruction is not reliable.
    // So in order to have a valid position (for example for height fog) we just consider that the sky is a sphere centered on camera with a radius of 5km (arbitrarily chosen value!)
    float tFrag = posInput.deviceDepth == UNITY_RAW_FAR_CLIP_VALUE ? _MaxFogDistance : posInput.linearDepth * rcp(dot(-V, GetViewForwardDir()));

    // Analytic fog starts where volumetric fog ends
    float volFogEnd = 0.0;

    bool underWater = IsUnderWater(posInput.positionWS.y);

    if (_FogEnabled)
    {
        half4 volFog = half4(0.0, 0.0, 0.0, 0.0);

        float distDelta = tFrag - volFogEnd;
        if (!underWater && distDelta > 0)
        {
            // Apply the distant (fallback) fog.
            half cosZenith = -dot(V, _PlanetUp);

            //float startHeight = dot(GetPrimaryCameraPosition() - V * volFogEnd, _PlanetUp);
            float startHeight = volFogEnd * cosZenith;

            startHeight += _CameraAltitude; // for non camera-relative rendering

            // For both homogeneous and exponential media,
            // Integrate[Transmittance[x] * Scattering[x], {x, 0, t}] = Albedo * Opacity[t].
            // Note that pulling the incoming radiance (which is affected by the fog) out of the
            // integral is wrong, as it means that shadow rays are not volumetrically shadowed.
            // This will result in fog looking overly bright.

            half3 volAlbedo = _HeightFogBaseScattering.xyz / _HeightFogBaseExtinction;
            float  odFallback = OpticalDepthHeightFog(_HeightFogBaseExtinction, _HeightFogBaseHeight,
                _HeightFogExponents, cosZenith, startHeight, distDelta);
            half  trFallback = saturate(TransmittanceFromOpticalDepth(odFallback));
            half  trCamera = 1.0 - volFog.a;

            volFog.rgb += trCamera * GetFogColor(V, tFrag) * volAlbedo * (1.0 - trFallback);//* GetCurrentExposureMultiplier() 
            volFog.a = 1.0 - (trCamera * trFallback);
        }

        color = volFog.rgb; // Already pre-exposed
        opacity = volFog.a;
    }

#ifndef ATMOSPHERE_NO_AERIAL_PERSPECTIVE
    // Sky pass already applies atmospheric scattering to the far plane.
    // This pass only handles geometry.
    if (_PBRFogEnabled && !isSky)
    {
        half3 skyColor = 0, skyOpacity = 0;

        EvaluateAtmosphericScattering(-V, posInput.positionNDC, tFrag, skyColor, skyOpacity);

        // Rendering of fog and atmospheric scattering cannot really be decoupled.
        #if 0
        // The best workaround is to deep composite them.
        half3 fogOD = OpticalDepthFromOpacity(fogOpacity);

        half3 fogRatio;
        fogRatio.r = (fogOpacity.r >= FLT_EPS) ? (fogOD.r * rcp(fogOpacity.r)) : 1;
        fogRatio.g = (fogOpacity.g >= FLT_EPS) ? (fogOD.g * rcp(fogOpacity.g)) : 1;
        fogRatio.b = (fogOpacity.b >= FLT_EPS) ? (fogOD.b * rcp(fogOpacity.b)) : 1;
        half3 skyRatio;
        skyRatio.r = (skyOpacity.r >= FLT_EPS) ? (skyOD.r * rcp(skyOpacity.r)) : 1;
        skyRatio.g = (skyOpacity.g >= FLT_EPS) ? (skyOD.g * rcp(skyOpacity.g)) : 1;
        skyRatio.b = (skyOpacity.b >= FLT_EPS) ? (skyOD.b * rcp(skyOpacity.b)) : 1;

        half3 logFogColor = fogRatio * fogColor;
        half3 logSkyColor = skyRatio * skyColor;

        half3 logCompositeColor = logFogColor + logSkyColor;
        half3 compositeOD = fogOD + skyOD;

        opacity = OpacityFromOpticalDepth(compositeOD);

        half3 rcpCompositeRatio;
        rcpCompositeRatio.r = (opacity.r >= FLT_EPS) ? (opacity.r * rcp(compositeOD.r)) : 1;
        rcpCompositeRatio.g = (opacity.g >= FLT_EPS) ? (opacity.g * rcp(compositeOD.g)) : 1;
        rcpCompositeRatio.b = (opacity.b >= FLT_EPS) ? (opacity.b * rcp(compositeOD.b)) : 1;

        color = rcpCompositeRatio * logCompositeColor;
        #else
        // Deep compositing assumes that the fog spans the same range as the atmosphere.
        // Our fog is short range, so deep compositing gives surprising results.
        // Using the "shallow" over operator is more appropriate in our context.
        // We could do something more clever with deep compositing, but this would
        // probably be a waste in terms of perf.
        CompositeOver(color, opacity, skyColor, skyOpacity, color, opacity);
        #endif
    }
#endif

    return true;
}
#endif

// [WIP] Shader Graph functions
/*
void TransparentAtmosphericScattering_half(float4 ScreenPositionRaw, half3 ViewDirectionWS, half3 Emission, half Alpha, out half3 FinalEmission, out half FinalAlpha)
{
#ifndef SHADERGRAPH_PREVIEW
    float2 screenUV = ScreenPositionRaw.xy;
    float deviceDepth = ScreenPositionRaw.z;

    half3 color = 0;
    half3 opacity = 0;

    // Convert depth to distance along the ray. Doesn't work with tilt shift, etc.
    // When a pixel is at far plane, the world space coordinate reconstruction is not reliable.
    // So in order to have a valid position (for example for height fog) we just consider that the sky is a sphere centered on camera with a radius of 5km (arbitrarily chosen value!)
    float tFrag = deviceDepth == UNITY_RAW_FAR_CLIP_VALUE ? _MaxFogDistance : LinearEyeDepth(deviceDepth, _ZBufferParams) * rcp(dot(-ViewDirectionWS, GetViewForwardDir()));

    // Analytic fog starts where volumetric fog ends
    float volFogEnd = 0.0;

#ifndef ATMOSPHERE_NO_AERIAL_PERSPECTIVE
    half3 skyColor = 0, skyOpacity = 0;

    // Sky pass already applies atmospheric scattering to the far plane.
    // This pass only handles geometry.
    if (_PBRFogEnabled) //_EnableAtmosphericScattering
    {
        
        EvaluateAtmosphericScattering(-ViewDirectionWS, screenUV, tFrag, skyColor, skyOpacity);

        // Deep compositing assumes that the fog spans the same range as the atmosphere.
        // Our fog is short range, so deep compositing gives surprising results.
        // Using the "shallow" over operator is more appropriate in our context.
        // We could do something more clever with deep compositing, but this would
        // probably be a waste in terms of perf.
        CompositeOver(color, opacity, skyColor, skyOpacity, color, opacity);
    }

    half atmosphericOpacity = 1.0 - Min3(opacity.x, opacity.y, opacity.z);
    FinalAlpha = saturate(Alpha - atmosphericOpacity);

    FinalEmission = Emission;
#endif

#else
    FinalAlpha = Alpha;
    FinalEmission = Emission;
#endif
}

void TransparentAtmosphericScattering_float(float4 ScreenPositionRaw, half3 ViewDirectionWS, half3 Emission, half Alpha, out half3 FinalEmission, out half FinalAlpha)
{
    TransparentAtmosphericScattering_half(ScreenPositionRaw, ViewDirectionWS, Emission, Alpha, FinalEmission, FinalAlpha);
}
*/

#endif // URP_ATMOSPHERIC_SCATTERING_INCLUDED
