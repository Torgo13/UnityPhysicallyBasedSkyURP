Shader "Hidden/Skybox/PhysicallyBasedSky"
{
    Properties
    {
        [MainTexture][NoScaleOffset] _BaseMap("Texture", 2D) = "black" {}
        [HideInInspector] _SnapshotData ("SnapshotData", Vector) = (0,0,0)
        _ShadowIntensity ("Shadow Intensity", Float) = 0.2
    }

    SubShader
    {
        Cull Off ZWrite Off
        ZTest LEqual

        // Optimized version of PBSky for Unity built-in skybox rendering using a sphere mesh (5040 vertices).
        Pass
        {
            Name "Physically Based Sky"
            Tags { "RenderType" = "Background" "Queue" = "Background" "PreviewType" = "None" }
            
            HLSLPROGRAM
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            #include "./PhysicallyBasedSkyRendering.hlsl"
            #include "./PhysicallyBasedSkyEvaluation.hlsl"
            #include "./AtmosphericScattering.hlsl"

            #pragma multi_compile_fragment _ _TERRAIN _SHADOWS
            
            float4 _SnapshotData; // x: boundsMin.x, y: boundsMin.z, z: 1 / TEXTURE_SIZE (1 / 4096), w: FogFactor
            half4 _TerrainData; // x: _TerrainMinDistance, y: _TerrainMaxAltitude, z: _FadeIn, w: _Quality

#if defined(_TERRAIN) || defined(_SHADOWS)
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Macros.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            
            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);
            
#if defined(_SHADOWS)
            half _ShadowIntensity;
#endif // defined(_SHADOWS)

            half _VPDaylightShadowAtten;
            half _VPAmbientLight;
            half _VPFogData;            

            half4 FarChunks(const float3 temp, const float2 position, const half3 rayDir)
            {
                half4 color = half4(0, 0, 0, 0);
                //if (rayDir.y > atan2(_TerrainData.y - _WorldSpaceCameraPos.y, _TerrainData.x))
                //    return color;

                // sample the terrain texture
                //float maxDistManhattan = temp.z; // half(2) / _SnapshotData.z;
                //float2 bounds = temp.xy; // _SnapshotData.xy;

                float3 wpos;
                float t = _TerrainData.x + frac(dot(float2(2.4084507, 3.2535211), position));
                const float incr = 1.015;
                for (; t < temp.z; t = t * incr + incr) {
                    wpos = _WorldSpaceCameraPos.xyz + rayDir * t;
                    if (wpos.y > _TerrainData.y) {
                        return color; // Above max terrain height
                    }

                    wpos = floor(wpos) + half(0.5);
                    float2 tpos = wpos.xz * _SnapshotData.z - temp.xy;
                    float4 terrain = SAMPLE_TEXTURE2D_LOD(_BaseMap, sampler_BaseMap, tpos, 0);
                    float terrainAltitude = terrain.a * _TerrainData.y;
                    if (wpos.y < terrainAltitude + half(0.5)) {
                        color = half4(terrain.rgb, 1.0);
                        break;
                    }
                }

                if (color.a == 0) {
                    return color;
                }

                // refine hit position using binary search                
                float t1 = t;
                float t0 = (t / incr) - 1;
                float3 hpos = wpos;
                half ao = half(0.9999);
                for (int i = 0; i < _TerrainData.w; i++) {
                    t = (t1 + t0) * half(0.5);
                    hpos = _WorldSpaceCameraPos.xyz + rayDir * t;
                    wpos = floor(hpos) + half(0.5);
                    float2 tpos = wpos.xz * _SnapshotData.z - temp.xy;
                    float4 terrain = SAMPLE_TEXTURE2D_LOD(_BaseMap, sampler_BaseMap, tpos, 0);
                    float terrainAltitude = terrain.a * _TerrainData.y;
                    if (wpos.y < terrainAltitude + half(0.5)) {
                        t1 = t;
                        color = half4(terrain.rgb, 1.0);
                        ao = hpos.y;
                    } else {
                        t0 = t;
                    }
                }

                ao = frac(ao);
                ao = half(0.25) + ao * half(0.75);
                ao = half(1.05) - (half(1.0) - ao) * (half(1.0) - ao);
                half aoFade = max(half(0), (t - half(256)) * half(0.03125));
                ao = saturate(ao + aoFade);

                // compute if pixel is under shadow by casting a ray from pixel to the Sun
                half atten = half(1.0);
#if defined(_SHADOWS)
                for (float j = 2.0; j < temp.z; j = j * incr + incr) {
                    float3 rpos = hpos + _MainLightPosition.xyz * j;
                    if (rpos.y > _TerrainData.y) {
                        break; // Above terrain max altitude so in direct light
                    }
                    
                    float2 tpos = rpos.xz * _SnapshotData.z - temp.xy;
                    float terrain = SAMPLE_TEXTURE2D_LOD(_BaseMap, sampler_BaseMap, tpos, 0).a;
                    float terrainAltitude = terrain * _TerrainData.y;
                    if (rpos.y < terrainAltitude) {
                        atten = _ShadowIntensity;
                        break;
                    }
                }
#endif // defined(_SHADOWS)
              
                // compute normal
                half3 dc = abs(hpos - wpos);
                dc.y *= half(1.05); // avoid artifacts at the edges
                half3 signs = -sign(rayDir);
                half3 norm = half3(0, signs.y, 0);
                if (dc.z > dc.x && dc.z > dc.y) norm = half3(0, 0, signs.z);
                if (dc.x > dc.z && dc.x > dc.y) norm = half3(signs.x, 0, 0);

                // day/night cycle matching regular VP shader lighting
                half NdotL = saturate(dot(_MainLightPosition.xyz, norm) * half(0.5) + half(0.5));
                half lightAtten = saturate( (atten * NdotL + _MainLightPosition.y * _VPDaylightShadowAtten) + _VPAmbientLight);
                //color.rgb *= min((lightAtten * ao) * _MainLightColor.rgb + _VPAmbientLight, 1.2);
                color.rgb *= saturate((lightAtten * ao) * _MainLightColor.rgb + _VPAmbientLight);

                // add fog
                half fogFactor = (_TerrainData.z * 512.0) * (_SnapshotData.w / t);
                half heightFog = hpos.y / _TerrainData.y;
                heightFog *= heightFog;
                half fog = saturate(fogFactor * fogFactor);

                return half4(color.rgb * fog, fog + fogFactor * heightFog);
            }
#endif // defined(_TERRAIN)

            #pragma vertex vert
            #pragma fragment frag

            #pragma editor_sync_compilation
            #pragma target 3.5

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 viewDir    : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float3 viewDir    : TEXCOORD1;
                float4 temp       : TEXCOORD2;
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings vert(Attributes input)
            {
                Varyings output;

                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                // Calculate the virtual position of skybox for view direction calculation
                output.positionWS = TransformObjectToWorld(input.positionOS.xyz);
                
                float maxDistManhattan = 2.0 / _SnapshotData.z;
                float2 bounds = _SnapshotData.xy;
                float view = atan2(_TerrainData.y - _WorldSpaceCameraPos.y, _TerrainData.x);
                output.temp = float4(bounds, maxDistManhattan, view);
                output.viewDir = normalize(output.positionWS - _WorldSpaceCameraPos);

                return output;
            }

            int _HasGroundAlbedoTexture;    // bool...
            int _HasGroundEmissionTexture;  // bool...
            int _HasSpaceEmissionTexture;   // bool...

            half _GroundEmissionMultiplier;
            half _SpaceEmissionMultiplier;

            // 3x3, but Unity can only set 4x4...
            half4x4 _PlanetRotation;
            half4x4 _SpaceRotation;

            #pragma multi_compile_local_fragment _ LOCAL_SKY
            #pragma multi_compile_local_fragment _ ATMOSPHERIC_SCATTERING_LOW_RES

            #pragma multi_compile_fragment _ SKY_NOT_BAKING

            TEXTURECUBE(_GroundAlbedoTexture);
            TEXTURECUBE(_GroundEmissionTexture);
            TEXTURECUBE(_SpaceEmissionTexture);

            float4 RenderSky(float2 screenUV, float3 positionWS)
            {
                const float R = _PlanetaryRadius;

            #ifdef SKY_NOT_BAKING
                const half3 V = normalize(GetCameraPositionWS() - positionWS);
                const bool renderSunDisk = _RenderSunDisk != 0;
            #else
                const half3 V = normalize(-positionWS);
                const bool renderSunDisk = false;
            #endif
                
                half3 N; float r; // These params correspond to the entry point

            #ifdef LOCAL_SKY
                const float3 O = _PBRSkyCameraPosPS;

                float tEntry = IntersectAtmosphere(O, V, N, r).x;
                float tExit  = IntersectAtmosphere(O, V, N, r).y;

                half cosChi = -dot(N, V);
                half cosHor = ComputeCosineOfHorizonAngle(r);
            #else
                N = half3(0, 1, 0);
                r = _PlanetaryRadius;
                half cosChi = -dot(N, V);
                half cosHor = 0.0;
                const float3 O = N * r;

                float tEntry = 0.0;
                float tExit  = IntersectSphere(_AtmosphericRadius, -dot(N, V), r).y;
            #endif

                bool rayIntersectsAtmosphere = (tEntry >= 0);
                bool lookAboveHorizon        = (cosChi >= cosHor);

                float tFrag    = FLT_INF;
                float3 radiance = 0;

                if (renderSunDisk)
                    radiance = RenderSunDisk(tFrag, tExit, V);

                if (rayIntersectsAtmosphere && !lookAboveHorizon) // See the ground?
                {
                    float tGround = tEntry + IntersectSphere(R, cosChi, r).x;

                    if (tGround < tFrag)
                    {
                        // Closest so far.
                        // Make it negative to communicate to EvaluatePbrAtmosphere that we intersected the ground.
                        tFrag = -tGround;

                        radiance = 0;

                        float3 gP = O + tGround * -V;
                        half3 gN = normalize(gP);

                        UNITY_BRANCH
                        if (_HasGroundEmissionTexture)
                        {
                            half4 ts = SAMPLE_TEXTURECUBE(_GroundEmissionTexture, s_trilinear_clamp_sampler, mul(gN, (half3x3)_PlanetRotation));
                            radiance += _GroundEmissionMultiplier * ts.rgb;
                        }

                        half3 albedo = _GroundAlbedo.xyz;

                        UNITY_BRANCH
                        if (_HasGroundAlbedoTexture)
                        {
                            albedo *= SAMPLE_TEXTURECUBE(_GroundAlbedoTexture, s_trilinear_clamp_sampler, mul(gN, (half3x3)_PlanetRotation)).rgb;
                        }

                        half3 gBrdf = INV_PI * albedo;

                        {
                            CelestialBodyData light = GetCelestialBody();
                            half3 L         = -light.forward.xyz;
                            half3 intensity = light.color.rgb;

                        #ifdef LOCAL_SKY
                            intensity *= SampleGroundIrradianceTexture(dot(gN, L));
                        #else
                            half3 opticalDepth = ComputeAtmosphericOpticalDepth(r, dot(N, L), true);
                            intensity *= TransmittanceFromOpticalDepth(opticalDepth) * saturate(dot(N, L));
                        #endif

                            radiance += gBrdf * intensity;
                        }

                        // TODO: Multiple Celestial Bodies
                        /*
                        // Shade the ground.
                        for (uint i = 0; i < _CelestialLightCount; i++)
                        {
                            CelestialBodyData light = _CelestialBodyDatas[i];

                            half3 L          = -light.forward.xyz;
                            half3 intensity  = light.color.rgb;

                        #ifdef LOCAL_SKY
                            intensity *= SampleGroundIrradianceTexture(dot(gN, L));
                        #else
                            half3 opticalDepth = ComputeAtmosphericOpticalDepth(r, dot(N, L), true);
                            intensity *= TransmittanceFromOpticalDepth(opticalDepth) * saturate(dot(N, L));
                        #endif

                            radiance += gBrdf * intensity;
                        }
                        */
                    }
                }
                /*
                else if (tFrag == FLT_INF) // See the stars?
                {
                    UNITY_BRANCH
                    if (_HasSpaceEmissionTexture)
                    {
                        // V points towards the camera.
                        half4 ts = SAMPLE_TEXTURECUBE(_SpaceEmissionTexture, s_trilinear_clamp_sampler, mul(-V, (half3x3)_SpaceRotation));
                        radiance += _SpaceEmissionMultiplier * ts.rgb;
                    }
                }
                */

                float3 skyColor = 0, skyOpacity = 0;

                #ifdef LOCAL_SKY
                if (rayIntersectsAtmosphere)
                    EvaluatePbrAtmosphere(_PBRSkyCameraPosPS, V, tFrag, renderSunDisk, skyColor, skyOpacity);
                #else
                if (lookAboveHorizon)
                    EvaluateDistantAtmosphere(-V, skyColor, skyOpacity);
                #endif

                skyColor += radiance * (1 - skyOpacity);
                skyColor *= _IntensityMultiplier;

                return float4(skyColor, 1.0);
            }

            float4 frag(Varyings input) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

#if defined(_TERRAIN) || defined(_SHADOWS)
                float4 farChunks = float4(0, 0, 0, 0);
                if (input.viewDir.y <= input.temp.w)
                {
                    farChunks = FarChunks(input.temp.xyz, input.positionCS.xy, input.viewDir);

                    // Skip PBR Sky if terrain is fully opaque
                    if (farChunks.a >= half(1.0))
                        return farChunks;
                }
#endif // defined(_TERRAIN) || defined(_SHADOWS)

                float2 screenUV = GetNormalizedScreenSpaceUV(input.positionCS);

                float4 color = RenderSky(screenUV, input.positionWS);
                
#if defined(_TERRAIN) || defined(_SHADOWS)
                color = lerp(color, farChunks, farChunks.a);
#endif // defined(_TERRAIN) || defined(_SHADOWS)
                
#if REAL_IS_HALF
                // Clamp any half.inf+ to HALF_MAX
                return min(color, HALF_MAX);
#else
                return color;
#endif // REAL_IS_HALF
            }
            ENDHLSL
        }

        // For Blit() using a fullscreen triangle mesh (3 vertices), we can switch to an optimized version for better performance.
        Pass
        {
            Name "Physically Based Sky Fullscreen Triangle"
            Tags { "PreviewType" = "None" "LightMode" = "Physically Based Sky" }
            
            HLSLPROGRAM
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            #include "./PhysicallyBasedSkyRendering.hlsl"
            #include "./PhysicallyBasedSkyEvaluation.hlsl"
            #include "./AtmosphericScattering.hlsl"

            #pragma vertex vert
            #pragma fragment frag

            #pragma target 3.5

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

                // Calculate the virtual position of skybox for view direction calculation
                output.positionWS = ComputeWorldSpacePosition(output.texcoord, UNITY_RAW_FAR_CLIP_VALUE, UNITY_MATRIX_I_VP);

                return output;
            }

            int _HasGroundAlbedoTexture;    // bool...
            int _HasGroundEmissionTexture;  // bool...
            int _HasSpaceEmissionTexture;   // bool...

            half _GroundEmissionMultiplier;
            half _SpaceEmissionMultiplier;

            // 3x3, but Unity can only set 4x4...
            half4x4 _PlanetRotation;
            half4x4 _SpaceRotation;

            #pragma multi_compile_local_fragment _ LOCAL_SKY
            #pragma multi_compile_local_fragment _ ATMOSPHERIC_SCATTERING_LOW_RES

            TEXTURECUBE(_GroundAlbedoTexture);
            TEXTURECUBE(_GroundEmissionTexture);
            TEXTURECUBE(_SpaceEmissionTexture);

            float4 RenderSky(float2 screenUV, float3 positionWS)
            {
                const float R = _PlanetaryRadius;
                const half3 V = normalize(GetCameraPositionWS() - positionWS);
                const bool renderSunDisk = _RenderSunDisk != 0;
                half3 N; float r; // These params correspond to the entry point

            #ifdef LOCAL_SKY
                const float3 O = _PBRSkyCameraPosPS;

                float tEntry = IntersectAtmosphere(O, V, N, r).x;
                float tExit  = IntersectAtmosphere(O, V, N, r).y;

                half cosChi = -dot(N, V);
                half cosHor = ComputeCosineOfHorizonAngle(r);
            #else
                N = half3(0, 1, 0);
                r = _PlanetaryRadius;
                half cosChi = -dot(N, V);
                half cosHor = 0.0;
                const float3 O = N * r;

                float tEntry = 0.0;
                float tExit  = IntersectSphere(_AtmosphericRadius, -dot(N, V), r).y;
            #endif

                bool rayIntersectsAtmosphere = (tEntry >= 0);
                bool lookAboveHorizon        = (cosChi >= cosHor);

                float tFrag    = FLT_INF;
                float3 radiance = 0;

                if (renderSunDisk)
                    radiance = RenderSunDisk(tFrag, tExit, V);

                if (rayIntersectsAtmosphere && !lookAboveHorizon) // See the ground?
                {
                    float tGround = tEntry + IntersectSphere(R, cosChi, r).x;

                    if (tGround < tFrag)
                    {
                        // Closest so far.
                        // Make it negative to communicate to EvaluatePbrAtmosphere that we intersected the ground.
                        tFrag = -tGround;

                        radiance = 0;

                        float3 gP = O + tGround * -V;
                        half3 gN = normalize(gP);

                        UNITY_BRANCH
                        if (_HasGroundEmissionTexture)
                        {
                            half4 ts = SAMPLE_TEXTURECUBE(_GroundEmissionTexture, s_trilinear_clamp_sampler, mul(gN, (half3x3)_PlanetRotation));
                            radiance += _GroundEmissionMultiplier * ts.rgb;
                        }

                        half3 albedo = _GroundAlbedo.xyz;

                        UNITY_BRANCH
                        if (_HasGroundAlbedoTexture)
                        {
                            albedo *= SAMPLE_TEXTURECUBE(_GroundAlbedoTexture, s_trilinear_clamp_sampler, mul(gN, (half3x3)_PlanetRotation)).rgb;
                        }

                        half3 gBrdf = INV_PI * albedo;

                        {
                            CelestialBodyData light = GetCelestialBody();
                            half3 L         = -light.forward.xyz;
                            half3 intensity = light.color.rgb;

                        #ifdef LOCAL_SKY
                            intensity *= SampleGroundIrradianceTexture(dot(gN, L));
                        #else
                            half3 opticalDepth = ComputeAtmosphericOpticalDepth(r, dot(N, L), true);
                            intensity *= TransmittanceFromOpticalDepth(opticalDepth) * saturate(dot(N, L));
                        #endif

                            radiance += gBrdf * intensity;
                        }

                        // TODO: Multiple Celestial Bodies
                        /*
                        // Shade the ground.
                        for (uint i = 0; i < _CelestialLightCount; i++)
                        {
                            CelestialBodyData light = _CelestialBodyDatas[i];

                            half3 L          = -light.forward.xyz;
                            half3 intensity  = light.color.rgb;

                        #ifdef LOCAL_SKY
                            intensity *= SampleGroundIrradianceTexture(dot(gN, L));
                        #else
                            half3 opticalDepth = ComputeAtmosphericOpticalDepth(r, dot(N, L), true);
                            intensity *= TransmittanceFromOpticalDepth(opticalDepth) * saturate(dot(N, L));
                        #endif

                            radiance += gBrdf * intensity;
                        }
                        */
                    }
                }
                /*
                else if (tFrag == FLT_INF) // See the stars?
                {
                    UNITY_BRANCH
                    if (_HasSpaceEmissionTexture)
                    {
                        // V points towards the camera.
                        half4 ts = SAMPLE_TEXTURECUBE(_SpaceEmissionTexture, s_trilinear_clamp_sampler, mul(-V, (half3x3)_SpaceRotation));
                        radiance += _SpaceEmissionMultiplier * ts.rgb;
                    }
                }
                */

                float3 skyColor = 0, skyOpacity = 0;

                #ifdef LOCAL_SKY
                if (rayIntersectsAtmosphere)
                    EvaluatePbrAtmosphere(_PBRSkyCameraPosPS, V, tFrag, renderSunDisk, skyColor, skyOpacity);
                #else
                if (lookAboveHorizon)
                    EvaluateDistantAtmosphere(-V, skyColor, skyOpacity);
                #endif

                skyColor += radiance * (1 - skyOpacity);
                skyColor *= _IntensityMultiplier;

                return float4(skyColor, 1.0);
            }

            float4 frag(CustomVaryings input) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
                float2 screenUV = input.texcoord;

                float4 color = RenderSky(screenUV, input.positionWS);
                return color;
            }
            ENDHLSL
        }
    }
}
