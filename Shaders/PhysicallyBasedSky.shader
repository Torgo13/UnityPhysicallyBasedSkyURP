Shader "Hidden/Skybox/PhysicallyBasedSky"
{
    Properties
    {

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

            #pragma vertex vert
            #pragma fragment frag

            #pragma editor_sync_compilation
            #pragma target 3.5

            struct Attributes
            {
                float4 positionOS : POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
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
                float2 screenUV = GetNormalizedScreenSpaceUV(input.positionCS);

                float4 color = RenderSky(screenUV, input.positionWS);
                return color;
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
