Shader "Hidden/Sky/PhysicallyBasedSkyPrecomputation"
{
    Properties
    {

    }

    SubShader
    {
        Cull Off ZWrite Off
        ZTest Always

        // Pass 0: Sky Precomputation (Camera Space)
        // Pass 1: Multiple Scattering Precomputation
        // Pass 2: InScattered Radiance Precomputation
        // Pass 3: Ground Irradiance Precomputation (World Space)
        // Pass 4: Opaque Atmospheric Scattering
        // Pass 5: Precomputed Atmospheric Scattering (Currently Unused)

        Pass
        {
            Name "Sky View LUT"
            Tags { "PreviewType" = "None" "LightMode" = "Physically Based Sky" }

            HLSLPROGRAM
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            #include "./PhysicallyBasedSkyRendering.hlsl"
            #include "./PhysicallyBasedSkyEvaluation.hlsl"

            #pragma vertex Vert
            #pragma fragment frag

            #pragma target 3.5

            // URP pre-defined the following variable on 2023.2+.
        #if UNITY_VERSION < 202320
            float4 _BlitTexture_TexelSize;
        #endif

            #pragma multi_compile_local_fragment _ ATMOSPHERIC_SCATTERING_LOW_RES

            // O is position in planet space, V is view dir in world space
            void EvaluateAtmosphericColor(float3 O, half3 V, float tExit,
            #ifdef OUTPUT_MULTISCATTERING
                half3 L, out half3 multiScattering,
            #endif
                out half3 skyColor, out half3 skyTransmittance)
            {
                skyColor = 0.0;
                skyTransmittance = 1.0;

            #ifdef OUTPUT_MULTISCATTERING
                multiScattering = 0.0;
            #endif

                const uint sampleCount = 16;

                for (uint s = 0; s < sampleCount; s++)
                {
                    float t, dt;
                    GetSample(s, sampleCount, tExit, t, dt);

                    const float3 P = O + t * V;
                    const float  r = max(length(P), _PlanetaryRadius);
                    const float3 N = P * rcp(r);
                    const float  height = r - _PlanetaryRadius;

                    const float3 sigmaE       = AtmosphereExtinction(height);
                    const float3 scatteringMS = AirScatter(height) + AerosolScatter(height);
                    const float3 transmittanceOverSegment = TransmittanceFromOpticalDepth(sigmaE * dt);

                #ifdef OUTPUT_MULTISCATTERING
                    multiScattering += IntegrateOverSegment(scatteringMS, transmittanceOverSegment, skyTransmittance, sigmaE);

                    const half3 phaseScatter = scatteringMS * IsotropicPhaseFunction();
                    const half3 S = EvaluateSunColorAttenuation(dot(N, L), r) * phaseScatter;
                    skyColor += IntegrateOverSegment(S, transmittanceOverSegment, skyTransmittance, sigmaE);
                #else
                    /*
                    for (uint i = 0; i < _CelestialLightCount; i++)
                    {
                        CelestialBodyData light = _CelestialBodyDatas[i];
                        half3 L = -light.forward.xyz;

                        const half3 sunTransmittance = EvaluateSunColorAttenuation(dot(N, L), r);
                        const half3 phaseScatter = AirScatter(height) * AirPhase(-dot(L, V)) + AerosolScatter(height) * AerosolPhase(-dot(L, V));
                        const half3 multiScatteredLuminance = EvaluateMultipleScattering(dot(N, L), height);

                        half3 S = sunTransmittance * phaseScatter + multiScatteredLuminance * scatteringMS;
                        skyColor += IntegrateOverSegment(light.color * S, transmittanceOverSegment, skyTransmittance, sigmaE);
                    }
                    */

                    {
                        CelestialBodyData light = GetCelestialBody();
                        half3 L = -light.forward.xyz;

                        const half3 sunTransmittance = EvaluateSunColorAttenuation(dot(N, L), r);
                        const half3 phaseScatter = AirScatter(height) * AirPhase(-dot(L, V)) + AerosolScatter(height) * AerosolPhase(-dot(L, V));
                        const half3 multiScatteredLuminance = EvaluateMultipleScattering(dot(N, L), height);

                        half3 S = sunTransmittance * phaseScatter + multiScatteredLuminance * scatteringMS;
                        skyColor += IntegrateOverSegment(light.color * S, transmittanceOverSegment, skyTransmittance, sigmaE);
                    }
                #endif

                    skyTransmittance *= transmittanceOverSegment;
                }
            }

            half3 SkyViewLUT(float2 screenUV)
            {
                const half3 N = half3(0, 1, 0);
                const float r = _PlanetaryRadius;
                const float3 O = r * N;

                uint2 coord = screenUV * _BlitTexture_TexelSize.zw;

                half3 V;
                UnmapSkyView(coord, V);

                float tExit = IntersectSphere(_AtmosphericRadius, dot(N, V), r).y;

                half3 skyColor, skyTransmittance;
                EvaluateAtmosphericColor(O, V, tExit, skyColor, skyTransmittance);

                return skyColor / _CelestialLightExposure;
            }

            half4 frag(Varyings input) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
                float2 screenUV = input.texcoord.xy;

                half4 color = half4(SkyViewLUT(screenUV), 1.0);
                return color;
            }
            ENDHLSL
        }

        Pass
        {
            Name "Multiple Scattering LUT"
            Tags { "PreviewType" = "None" "LightMode" = "Physically Based Sky" }

            HLSLPROGRAM
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Sampling/Hammersley.hlsl"

            #include "./PhysicallyBasedSkyRendering.hlsl"
            #include "./PhysicallyBasedSkyEvaluation.hlsl"

            #pragma vertex Vert
            #pragma fragment frag

            #pragma target 3.5

            // URP pre-defined the following variable on 2023.2+.
        #if UNITY_VERSION < 202320
            float4 _BlitTexture_TexelSize;
        #endif

            #define OUTPUT_MULTISCATTERING
            // O is position in planet space, V is view dir in world space
            void EvaluateAtmosphericColor(float3 O, half3 V, float tExit,
            #ifdef OUTPUT_MULTISCATTERING
                half3 L, out half3 multiScattering,
            #endif
                out half3 skyColor, out half3 skyTransmittance)
            {
                skyColor = 0.0;
                skyTransmittance = 1.0;

            #ifdef OUTPUT_MULTISCATTERING
                multiScattering = 0.0;
            #endif

                const uint sampleCount = 16;

                for (uint s = 0; s < sampleCount; s++)
                {
                    float t, dt;
                    GetSample(s, sampleCount, tExit, t, dt);

                    const float3 P = O + t * V;
                    const float  r = max(length(P), _PlanetaryRadius);
                    const float3  N = P * rcp(r);
                    const float  height = r - _PlanetaryRadius;

                    const float3 sigmaE = AtmosphereExtinction(height);
                    const float3 scatteringMS = AirScatter(height) + AerosolScatter(height);
                    const float3 transmittanceOverSegment = TransmittanceFromOpticalDepth(sigmaE * dt);

            #ifdef OUTPUT_MULTISCATTERING
                    multiScattering += IntegrateOverSegment(scatteringMS, transmittanceOverSegment, skyTransmittance, sigmaE);

                    const float3 phaseScatter = scatteringMS * IsotropicPhaseFunction();
                    const float3 S = EvaluateSunColorAttenuation(dot(N, L), r) * phaseScatter;
                    skyColor += IntegrateOverSegment(S, transmittanceOverSegment, skyTransmittance, sigmaE);
            #else
                    /*
                    for (uint i = 0; i < _CelestialLightCount; i++)
                    {
                        CelestialBodyData light = _CelestialBodyDatas[i];
                        half3 L = -light.forward.xyz;

                        const half3 sunTransmittance = EvaluateSunColorAttenuation(dot(N, L), r);
                        const half3 phaseScatter = AirScatter(height) * AirPhase(-dot(L, V)) + AerosolScatter(height) * AerosolPhase(-dot(L, V));
                        const half3 multiScatteredLuminance = EvaluateMultipleScattering(dot(N, L), height);

                        half3 S = sunTransmittance * phaseScatter + multiScatteredLuminance * scatteringMS;
                        skyColor += IntegrateOverSegment(light.color * S, transmittanceOverSegment, skyTransmittance, sigmaE);
                    }
                    */

                    {
                        CelestialBodyData light = GetCelestialBody();
                        half3 L = -light.forward.xyz;

                        const half3 sunTransmittance = EvaluateSunColorAttenuation(dot(N, L), r);
                        const half3 phaseScatter = AirScatter(height) * AirPhase(-dot(L, V)) + AerosolScatter(height) * AerosolPhase(-dot(L, V));
                        const half3 multiScatteredLuminance = EvaluateMultipleScattering(dot(N, L), height);

                        half3 S = sunTransmittance * phaseScatter + multiScatteredLuminance * scatteringMS;
                        skyColor += IntegrateOverSegment(light.color * S, transmittanceOverSegment, skyTransmittance, sigmaE);
                    }
            #endif

                    skyTransmittance *= transmittanceOverSegment;
                }
            }

            half3 RenderPlanet(float3 P, half3 L)
            {
                half3 N = normalize(P);

                half3 albedo = _GroundAlbedo.xyz;
                half3 gBrdf = INV_PI * albedo;

                float cosHoriz = ComputeCosineOfHorizonAngle(_PlanetaryRadius);
                float cosTheta = dot(N, L);

                half3 intensity = 0.0;
                if (cosTheta >= cosHoriz)
                {
                    float3 opticalDepth = ComputeAtmosphericOpticalDepth(_PlanetaryRadius, cosTheta, true);
                    intensity = TransmittanceFromOpticalDepth(opticalDepth);
                }

                return gBrdf * (saturate(dot(N, L)) * intensity);
            }

            #define SAMPLE_COUNT 64

            half3 frag(Varyings input) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
                float2 screenUV = input.texcoord.xy;
                half3 multipleScattering = 0.0;

                uint2 coord = screenUV * _BlitTexture_TexelSize.zw;

                for (uint threadIdx = 0; threadIdx < SAMPLE_COUNT; threadIdx++)
                {
                    /// Map thread id to position in planet space + light direction

                    float sunZenithCosAngle;
                    float radialDistance;
                    UnmapMultipleScattering(coord, sunZenithCosAngle, radialDistance);

                    half3  L = half3(0.0, sunZenithCosAngle, SinFromCos(sunZenithCosAngle));
                    float3 O = float3(0.0, radialDistance, 0.0);

                    float2 U = Hammersley2d(threadIdx, SAMPLE_COUNT);
                    float3 V = SampleSphereUniform(U.x, U.y);

                    /// Compute single scattering light in direction V

                    half3 N; float r; // These params correspond to the entry point
                    float tEntry = IntersectAtmosphere(O, -V, N, r).x;
                    float tExit = IntersectAtmosphere(O, -V, N, r).y;

                    float cosChi = dot(N, V);
                    float cosHor = ComputeCosineOfHorizonAngle(r);

                    bool rayIntersectsAtmosphere = (tEntry >= 0);
                    bool lookAboveHorizon = (cosChi >= cosHor);
                    bool seeGround = rayIntersectsAtmosphere && !lookAboveHorizon;

                    if (seeGround)
                        tExit = tEntry + IntersectSphere(_PlanetaryRadius, cosChi, r).x;

                    half3 multiScattering = 0.0, skyColor = 0.0, skyTransmittance = 1.0;
                    if (tExit > 0.0)
                        EvaluateAtmosphericColor(O, V, tExit, L, multiScattering, skyColor, skyTransmittance);

                    if (seeGround)
                        skyColor += RenderPlanet(O + tExit * V, L) * skyTransmittance;

                    const half dS = FOUR_PI * IsotropicPhaseFunction() / SAMPLE_COUNT;
                    half3 radiance = skyColor * dS;
                    half3 radianceMS = multiScattering * dS;

                    /// Accumulate light from all directions using LDS
                    //ParallelSum(threadIdx, radiance, radianceMS);

                    /// Approximate infinite multiple scattering
                    const half3 F_ms = 1.0 * rcp(1.0 - radianceMS); // Equation 9
                    const half3 MS = radiance * F_ms;               // Equation 10

                    multipleScattering += MS;
                }

                return multipleScattering;
            }
            ENDHLSL
        }

        Pass
        {
            Name "InScattered Radiance LUT"
            Tags { "PreviewType" = "None" "LightMode" = "Physically Based Sky" }

            HLSLPROGRAM
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Sampling/Hammersley.hlsl"

            #include "./PhysicallyBasedSkyRendering.hlsl"
            #include "./PhysicallyBasedSkyEvaluation.hlsl"

            #pragma vertex Vert
            #pragma fragment frag

            #pragma target 3.5

            // URP pre-defined the following variable on 2023.2+.
        #if UNITY_VERSION < 202320
            float4 _BlitTexture_TexelSize;
        #endif

            #pragma multi_compile_local_fragment _ LOCAL_SKY
            #pragma multi_compile_local_fragment _ ATMOSPHERIC_SCATTERING_LOW_RES

            #ifndef LOCAL_SKY
            #define CAMERA_SPACE
            #endif

            #define TABLE_SIZE uint3(PBRSKYCONFIG_IN_SCATTERED_RADIANCE_TABLE_SIZE_X, \
                         PBRSKYCONFIG_IN_SCATTERED_RADIANCE_TABLE_SIZE_Y, \
                         PBRSKYCONFIG_IN_SCATTERED_RADIANCE_TABLE_SIZE_Z)

            int PBSky_TableCoord_Z;

            void frag(Varyings input, out half3 airSingleScattering : SV_Target0, out half3 aerosolSingleScattering : SV_Target1, out half3 multipleScattering : SV_Target2)
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
                float2 screenUV = input.texcoord.xy; // x and z

                const float A = _AtmosphericRadius;
                const float R = _PlanetaryRadius;

                const uint zTexSize = PBRSKYCONFIG_IN_SCATTERED_RADIANCE_TABLE_SIZE_Z; // Now the depth is 32
                const uint zTexCnt = PBRSKYCONFIG_IN_SCATTERED_RADIANCE_TABLE_SIZE_W; // Now the width is 1024

                // We don't care about the extremal points for XY, but need the full range of Z values.
                const float3 scale = rcp(float3(TABLE_SIZE.x, TABLE_SIZE.y, 1));
                const float3 bias = float3(0.5 * scale.x, 0.5 * scale.y, 0);

                // Let the hardware and the driver handle the ordering of the computation.
                uint3 tableCoord = float3((screenUV * _BlitTexture_TexelSize.zw), PBSky_TableCoord_Z);
                tableCoord.yz = tableCoord.zy;
                uint  texId = tableCoord.z / zTexSize;          // [0, zTexCnt  - 1]
                uint  texCoord = tableCoord.z & (zTexSize - 1); // [0, zTexSize - 1]

                float3 uvw = float3(tableCoord) * scale + bias;

                // Convention:
                // V points towards the camera.
                // The normal vector N points upwards (local Z).
                // The view vector V spans the local XZ plane.
                // The light vector is represented as {phiL, cosThataL} w.r.t. the XZ plane.
                half cosChi = UnmapAerialPerspective(uvw.xy).x;                              // [-1, 1]
                float height = UnmapAerialPerspective(uvw.xy).y;                             // [0, _AtmosphericDepth]
                half phiL   = PI * saturate(texCoord * rcp(zTexSize - 1));                   // [-Pi, Pi]
                half NdotL  = UnmapCosineOfZenithAngle(saturate(texId * rcp(zTexCnt - 1)));  // [-0.5, 1]

                half NdotV = -cosChi;
                float r = height + R;
                half cosHor = ComputeCosineOfHorizonAngle(r);

                bool lookAboveHorizon = (cosChi >= cosHor);
                bool viewAboveHorizon = (NdotV >= cosHor);

                half3 N = half3(0, 0, 1);
                half3 V = SphericalToCartesian(0, NdotV);
                half3 L = SphericalToCartesian(phiL, NdotL);

                half LdotV = dot(L, V);
                // half LdotV = SphericalDot(NdotL, phiL, NdotV, 0);

                // Set up the ray...
                float  h = height;
                float3 O = r * N;

                // Determine the region of integration.
                float tMax;

                if (lookAboveHorizon)
                {
                    tMax = IntersectSphere(A, cosChi, r).y; // Max root
                }
                else
                {
                    tMax = IntersectSphere(R, cosChi, r).x; // Min root
                }

                // Integrate in-scattered radiance along -V.
                // Note that we have to evaluate the transmittance integral along -V as well.
                // The transmittance integral is pretty smooth (I plotted it in Mathematica).
                // However, using a non-linear distribution of samples is still a good idea both
                // when looking up (due to the exponential falloff of the coefficients)
                // and for horizontal rays (due to the exponential transmittance term).
                // It's easy enough to use a simple quadratic remap.

                half3 airTableEntry = 0;
                half3 aerosolTableEntry = 0;
                half3 msTableEntry = 0;
                half3 transmittance = 1.0;

                // Eye-balled number of samples.
            #ifdef ATMOSPHERIC_SCATTERING_LOW_RES
                const int numSamples = 4;
            #else
                const int numSamples = 16;
            #endif

                for (int i = 0; i < numSamples; i++)
                {
                    float t, dt;
                    GetSample(i, numSamples, tMax, t, dt);

                    float3 P = O + t * -V;

                    // Update these for the step along the ray...
                    r = max(length(P), R);
                    height = r - R;
                    NdotV = dot(normalize(P), V);
                    NdotL = dot(normalize(P), L);

                    const half3 sigmaE = AtmosphereExtinction(height);
                    const half3 transmittanceOverSegment = TransmittanceFromOpticalDepth(sigmaE * dt);

                    // Apply the phase function at runtime.
                    half3 sunTransmittance = EvaluateSunColorAttenuation(NdotL, r);
                    half3 airTerm = sunTransmittance * AirScatter(height);
                    half3 aerosolTerm = sunTransmittance * AerosolScatter(height);
                    half3 scatteringMS = AirScatter(height) + AerosolScatter(height);
                    half3 msTerm = EvaluateMultipleScattering(NdotL, height) * scatteringMS;

                    airTableEntry += IntegrateOverSegment(airTerm, transmittanceOverSegment, transmittance, sigmaE);
                    aerosolTableEntry += IntegrateOverSegment(aerosolTerm, transmittanceOverSegment, transmittance, sigmaE);
                    msTableEntry += IntegrateOverSegment(msTerm, transmittanceOverSegment, transmittance, sigmaE);

                    transmittance *= transmittanceOverSegment;
                }

                // TODO: deep compositing.
                // Note: ground reflection is computed at runtime.
                airSingleScattering = airTableEntry;                        // One order
                aerosolSingleScattering = aerosolTableEntry;                // One order
                multipleScattering = msTableEntry * MS_EXPOSURE;
            }
            ENDHLSL
        }

        Pass
        {
            Name "Ground Irradiance LUT"
            Tags { "PreviewType" = "None" "LightMode" = "Physically Based Sky" }

            HLSLPROGRAM
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Sampling/Hammersley.hlsl"

            #include "./PhysicallyBasedSkyRendering.hlsl"
            #include "./PhysicallyBasedSkyEvaluation.hlsl"

            #pragma vertex Vert
            #pragma fragment frag

            #pragma target 3.5

            #pragma multi_compile_local_fragment _ ATMOSPHERIC_SCATTERING_LOW_RES

            half3 frag(Varyings input) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
                float uv = input.texcoord.x;

                // As we look at the planet in the direction of the sun, the ground is rotationally invariant.
                half NdotL = UnmapCosineOfZenithAngle(uv.x);

                half3 groundIrradiance = 0.0;

                if (NdotL > 0)
                {
                    half3 oDepth = ComputeAtmosphericOpticalDepth(_PlanetaryRadius, NdotL, true);
                    half3 transm = TransmittanceFromOpticalDepth(oDepth);

                    groundIrradiance = transm * NdotL;
                }

                // Gather the volume contribution.
                // Arbitrary number of samples... (need a fibonacci number)
                //const int numVolumeSamples = 89; // number of samples used by HDRP
                const int numVolumeSamples = 8; // number of samples used by URP

                for (int i = 0; i < numVolumeSamples; i++)
                {
                    half2 f = Fibonacci2d(i, numVolumeSamples); // TODO: Cranley-Patterson Rotation
                    half3 L = SampleHemisphereCosine(f.x, f.y);

                    half cosChi = L.z;
                    half NdotV = -cosChi;
                    half phiL = TWO_PI * f.y;

                    TexCoord4D tc = ConvertPositionAndOrientationToTexCoords(0, NdotV, NdotL, phiL);

                    // Note: we switched the Y & Z of the LUT due to performance reason.
                    float3 uvw0 = float3(tc.u, tc.w0, tc.v);
                    float3 uvw1 = float3(tc.u, tc.w1, tc.v);

                    half3 radiance = 0;

                    // Single scattering does not contain the phase function.
                    half LdotV = SphericalDot(NdotV, 0, NdotL, phiL);

                    radiance += lerp(SAMPLE_TEXTURE3D_LOD(_AirSingleScatteringTexture, s_linear_clamp_sampler, uvw0, 0).rgb,
                        SAMPLE_TEXTURE3D_LOD(_AirSingleScatteringTexture, s_linear_clamp_sampler, uvw1, 0).rgb,
                        tc.a) * AirPhase(LdotV);

                    radiance += lerp(SAMPLE_TEXTURE3D_LOD(_AerosolSingleScatteringTexture, s_linear_clamp_sampler, uvw0, 0).rgb,
                        SAMPLE_TEXTURE3D_LOD(_AerosolSingleScatteringTexture, s_linear_clamp_sampler, uvw1, 0).rgb,
                        tc.a) * AerosolPhase(LdotV);

                    radiance += lerp(SAMPLE_TEXTURE3D_LOD(_MultipleScatteringTexture, s_linear_clamp_sampler, uvw0, 0).rgb,
                        SAMPLE_TEXTURE3D_LOD(_MultipleScatteringTexture, s_linear_clamp_sampler, uvw1, 0).rgb,
                        tc.a) * MS_EXPOSURE_INV;

                    half weight = PI * rcp(numVolumeSamples);

                    groundIrradiance += weight * radiance;
                }

                return groundIrradiance;
            }
            ENDHLSL
        }

        Pass
        {
            Name "Opaque Atmospheric Scattering"
            Tags { "PreviewType" = "None" "LightMode" = "Physically Based Sky" }

            Blend One SrcAlpha
            ZTest Less  // Required for XR occlusion mesh optimization

            HLSLPROGRAM
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Sampling/Hammersley.hlsl"

            #include "./PhysicallyBasedSkyRendering.hlsl"
            #include "./AtmosphericScattering.hlsl"

            #pragma vertex vert
            #pragma fragment frag

            #pragma target 3.5

            #pragma multi_compile_local_fragment _ LOCAL_SKY
            #pragma multi_compile_local_fragment _ ATMOSPHERIC_SCATTERING_LOW_RES

            #pragma multi_compile_fragment _ PHYSICALLY_BASED_SKY
            #pragma multi_compile_fragment _ DEBUG_DISPLAY

            #define OPAQUE_FOG_PASS

            // "_ScreenSize" that supports dynamic resolution
            float4 _ScreenResolution;

            SAMPLER(s_point_clamp_sampler);

            TEXTURE2D_X_FLOAT(_CameraDepthTexture);

            struct CustomVaryings
            {
                float4 positionCS : SV_POSITION;
                float2 texcoord : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                UNITY_VERTEX_OUTPUT_STEREO
            };

            CustomVaryings vert(Attributes input)
            {
                CustomVaryings output;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

                float4 pos = GetFullScreenTriangleVertexPosition(input.vertexID);
                float2 uv = GetFullScreenTriangleTexCoord(input.vertexID);

                output.positionCS = pos;
            #if UNITY_VERSION < 202320
                output.texcoord = uv * _BlitScaleBias.xy + _BlitScaleBias.zw;
            #else
                output.texcoord = DYNAMIC_SCALING_APPLY_SCALEBIAS(uv);
            #endif
                output.positionWS = ComputeWorldSpacePosition(output.texcoord, UNITY_RAW_FAR_CLIP_VALUE, UNITY_MATRIX_I_VP);

                return output;
            }

            half4 frag(CustomVaryings input) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
                float2 screenUV = input.texcoord.xy;
                int2 pixelCoords = int2(screenUV * _ScreenResolution.xy);

                float3 V = normalize(GetCameraPositionWS() - input.positionWS);
                float depth = LOAD_TEXTURE2D_X_LOD(_CameraDepthTexture, pixelCoords, 0).r;
                //float depth = SAMPLE_TEXTURE2D_X_LOD(_CameraDepthTexture, s_point_clamp_sampler, screenUV, 0).r;
                PositionInputs posInput = GetPositionInput(input.positionCS.xy, _ScreenResolution.zw, depth, UNITY_MATRIX_I_VP, UNITY_MATRIX_V);

                half3 volColor, volOpacity = 0.0;
                EvaluateAtmosphericScattering(posInput, V, volColor, volOpacity);

                // We use hardware blend options for better performance
                half atmosphericOpacity = 1.0 - Min3(volOpacity.x, volOpacity.y, volOpacity.z);
                return half4(volColor, atmosphericOpacity); // Note: output = volColor + sceneColor * (1 - volOpacity)
            }
            ENDHLSL
        }

        Pass
        {
            Name "Atmospheric Scattering LUT"
            Tags { "PreviewType" = "None" "LightMode" = "Physically Based Sky" }

            HLSLPROGRAM
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Sampling/Hammersley.hlsl"

            #include "./PhysicallyBasedSkyRendering.hlsl"
            #include "./PhysicallyBasedSkyEvaluation.hlsl"

            #pragma vertex vert
            #pragma fragment frag

            #pragma target 3.5

            TEXTURE2D(_AtmosphericScatteringSlice);
            TEXTURE2D(_SkyTransmittanceSlice);
            SAMPLER(s_point_clamp_sampler);

            #pragma multi_compile_fragment _ _LIGHT_COOKIES
            #pragma multi_compile_local_fragment _ LOCAL_SKY
            #pragma multi_compile_local_fragment _ ATMOSPHERIC_SCATTERING_LOW_RES

            #ifndef LOCAL_SKY
            #define CAMERA_SPACE
            #endif

            float4 _VolumetricCloudsShadowOriginToggle;
            float2 _VolumetricCloudsShadowScale;

            int PBSky_TableCoord_Z;

            struct CustomVaryings
            {
                float4 positionCS : SV_POSITION;
                float2 texcoord : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                UNITY_VERTEX_OUTPUT_STEREO
            };

            CustomVaryings vert(Attributes input)
            {
                CustomVaryings output;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

                float4 pos = GetFullScreenTriangleVertexPosition(input.vertexID);
                float2 uv = GetFullScreenTriangleTexCoord(input.vertexID);

                output.positionCS = pos;
            #if UNITY_VERSION < 202320
                output.texcoord = uv * _BlitScaleBias.xy + _BlitScaleBias.zw;
            #else
                output.texcoord = DYNAMIC_SCALING_APPLY_SCALEBIAS(uv);
            #endif
                output.positionWS = ComputeWorldSpacePosition(output.texcoord, UNITY_RAW_FAR_CLIP_VALUE, UNITY_MATRIX_I_VP);

                return output;
            }

            void frag(CustomVaryings input, out half3 skyColor : SV_Target0, out half3 skyTransmittance : SV_Target1)
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
                const float2 screenUV = input.texcoord.xy;
                const float2 res = float2(PBRSKYCONFIG_ATMOSPHERIC_SCATTERING_LUT_WIDTH, PBRSKYCONFIG_ATMOSPHERIC_SCATTERING_LUT_HEIGHT);
                const int2 pixelCoords = int2(screenUV * res);

                float3 O;
                float3 P;
                float  r;
                half3  N;
                float  height;
                float  t, dt;

                half3 sigmaE;
                half3 scatteringMS;
                half3 transmittanceOverSegment;

                skyColor = 0.0;
                skyTransmittance = 1.0;

                // Make sure first slice is all black. Looks better for bilinear at close range
                UNITY_BRANCH
                if (PBSky_TableCoord_Z == 0)
                    return;

                half3 V = normalize(input.positionWS - GetCameraPositionWS());

                // Accumulating results over multiple passes to simulate compute features (wave intrinsics)
                //skyTransmittance = SAMPLE_TEXTURE2D_LOD(_SkyTransmittanceSlice, s_point_clamp_sampler, screenUV, 0).xyz;
                skyTransmittance = LOAD_TEXTURE2D_LOD(_SkyTransmittanceSlice, pixelCoords, 0).xyz;

                // Following is the loop from EvaluateAtmosphericColor
                //for (int s = 0; s < PBSky_TableCoord_Z; s++)
                {
                    const int s = PBSky_TableCoord_Z - 1;
                    UnmapAtmosphericScattering(s, V, O, t, dt);

                    P = O + t * V;
                #ifndef CAMERA_SPACE
                    // When ray starts to intersect the planet, don't stop but move the point to the surface
                    // This is important because we bilinear sample the LUT and don't want garbage values anywhere
                    if (length(P) < _PlanetaryRadius)
                    {
                        P = normalize(P) * _PlanetaryRadius;
                        V = normalize(P - O);
                    }
                #endif

                    r = max(length(P), _PlanetaryRadius + 1);
                    N = P * rcp(r);
                    height = r - _PlanetaryRadius;

                    sigmaE         = AtmosphereExtinction(height);
                    scatteringMS   = AirScatter(height) + AerosolScatter(height);
                    transmittanceOverSegment = TransmittanceFromOpticalDepth(sigmaE * dt);

                    skyTransmittance *= transmittanceOverSegment;
                }

                //skyTransmittance = ParallelPrefixProduct(s, transmittanceOverSegment);

                half sunShadow = 1.0;

                // [HDRP Ver.] Keep as reference
                /*
                //if (_DirectionalShadowIndex >= 0)
                {
                    // See GetDirectionalShadowAttenuation
                    // Load shadowmap twice to get some form of smoothing
                    // We offset by one texel to not depend too much on the resolution of the shadow map
                    // Function call is inlined so share some computations between samples, which is not correct but faster
                    float3 V2 = -GetSkyViewDirWS((uv + 0.5 / res) * _ScreenSize.xy);
                    DirectionalLightData light = _DirectionalLightDatas[_DirectionalShadowIndex];
                    HDShadowContext shadowContext = InitShadowContext();

                    // Find if last cascade is usable, we only use this one as we don't need precise occlusion and it's faster
                    // See EvalShadow_GetSplitIndex
                    int shadowSplitIndex = _CascadeShadowCount - 1;
                    float4 sphere  = shadowContext.directionalShadowData.sphereCascades[shadowSplitIndex];
                    float3 wposDir = P + _PlanetCenterPosition - sphere.xyz;
                    float  distSq  = dot(wposDir, wposDir);
                    if (distSq <= sphere.w)
                    {
                        HDShadowData sd = shadowContext.shadowDatas[light.shadowIndex];
                        LoadDirectionalShadowDatas(sd, shadowContext, light.shadowIndex + shadowSplitIndex);

                        float3 posWS = O + _PlanetCenterPosition + sd.cacheTranslationDelta.xyz;
                        float3 posTC1 = EvalShadow_GetTexcoordsAtlas(sd, _CascadeShadowAtlasSize.zw, posWS + t*V, false);
                        float3 posTC2 = EvalShadow_GetTexcoordsAtlas(sd, _CascadeShadowAtlasSize.zw, posWS + t*V2, false);

                        sunShadow = (DIRECTIONAL_FILTER_ALGORITHM(sd, 0, posTC1, _ShadowmapCascadeAtlas, s_linear_clamp_compare_sampler, FIXED_UNIFORM_BIAS) +
                                DIRECTIONAL_FILTER_ALGORITHM(sd, 0, posTC2, _ShadowmapCascadeAtlas, s_linear_clamp_compare_sampler, FIXED_UNIFORM_BIAS)) / 2.0f;
                    }

                    if (_VolumetricCloudsShadowOriginToggle.w == 1.0)
                        sunShadow *= EvaluateVolumetricCloudsShadows(light, P + _PlanetCenterPosition);
                }
                */

                // See GetDirectionalShadowAttenuation
                // Load shadowmap twice to get some form of smoothing
                // We offset by one texel to not depend too much on the resolution of the shadow map
                // Function call is inlined so share some computations between samples, which is not correct but faster

                CelestialBodyData light = GetCelestialBody();

                float3 posWS = P + _PlanetCenterPosition;

            #if defined(_LIGHT_COOKIES)
                sunShadow = SampleMainLightCookie(posWS).r;
            #endif

                // TODO: Support multiple celestial bodies
                    
                //for (uint i = 0; i < _CelestialLightCount; i++)
                {
                    //CelestialBodyData light = _CelestialBodyDatas[i];
                    half3 L = -light.forward.xyz;

                    const half3 sunTransmittance = sunShadow * EvaluateSunColorAttenuation(dot(N, L), r);
                    const half3 phaseScatter = AirScatter(height) * AirPhase(-dot(L, V)) + AerosolScatter(height) * AerosolPhase(-dot(L, V));
                    const half3 multiScatteredLuminance = EvaluateMultipleScattering(dot(N, L), height);

                    // Compute color
                    half3 S = sunTransmittance * phaseScatter + multiScatteredLuminance * scatteringMS;
                    skyColor = IntegrateOverSegment(light.color * S, transmittanceOverSegment, skyTransmittance, sigmaE);
                }
                
                //skyColor = ParallelPostfixSum(s, skyColor);

                skyColor = Desaturate(skyColor, _ColorSaturation);
                skyColor *= _IntensityMultiplier;

                // Accumulating results over multiple passes to simulate compute features (wave intrinsics)
                //skyColor += SAMPLE_TEXTURE2D_LOD(_AtmosphericScatteringSlice, s_point_clamp_sampler, screenUV, 0).rgb;
                skyColor += LOAD_TEXTURE2D_LOD(_AtmosphericScatteringSlice, pixelCoords, 0).rgb;
                
                return;
            }
            ENDHLSL
        }
    }
}
