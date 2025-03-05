#ifndef URP_PHYSICALLY_BASED_SKY_DEFINES_INCLUDED
#define URP_PHYSICALLY_BASED_SKY_DEFINES_INCLUDED

#define PBRSKYCONFIG_GROUND_IRRADIANCE_TABLE_SIZE (256)
#ifdef ATMOSPHERIC_SCATTERING_LOW_RES
#define PBRSKYCONFIG_IN_SCATTERED_RADIANCE_TABLE_SIZE_X (64)
#define PBRSKYCONFIG_IN_SCATTERED_RADIANCE_TABLE_SIZE_Y (16)
#define PBRSKYCONFIG_IN_SCATTERED_RADIANCE_TABLE_SIZE_Z (8)
#define PBRSKYCONFIG_IN_SCATTERED_RADIANCE_TABLE_SIZE_W (64)
#else
#define PBRSKYCONFIG_IN_SCATTERED_RADIANCE_TABLE_SIZE_X (128)
#define PBRSKYCONFIG_IN_SCATTERED_RADIANCE_TABLE_SIZE_Y (32)
#define PBRSKYCONFIG_IN_SCATTERED_RADIANCE_TABLE_SIZE_Z (16)
#define PBRSKYCONFIG_IN_SCATTERED_RADIANCE_TABLE_SIZE_W (64)
#endif
#define PBRSKYCONFIG_MULTI_SCATTERING_LUT_WIDTH (32)
#define PBRSKYCONFIG_MULTI_SCATTERING_LUT_HEIGHT (32)
#define PBRSKYCONFIG_SKY_VIEW_LUT_WIDTH (256)
#define PBRSKYCONFIG_SKY_VIEW_LUT_HEIGHT (144)
#define PBRSKYCONFIG_ATMOSPHERIC_SCATTERING_LUT_WIDTH (32)
#define PBRSKYCONFIG_ATMOSPHERIC_SCATTERING_LUT_HEIGHT (32)
#define PBRSKYCONFIG_ATMOSPHERIC_SCATTERING_LUT_DEPTH (64)

#ifndef URP_VOLUMETRIC_CLOUDS_UTILITIES_HLSL
float _AirScaleHeight;
float _AerosolScaleHeight;
float _AirDensityFalloff;
float _AerosolDensityFalloff;
float3 _AirSeaLevelExtinction;
float _AerosolSeaLevelExtinction;
#endif

float _AtmosphericRadius;
float _AerosolAnisotropy;
float _AerosolPhasePartConstant;
//float _AerosolSeaLevelExtinction;
//float _AirDensityFalloff;
//float _AirScaleHeight;
//float _AerosolDensityFalloff;
//float _AerosolScaleHeight;
float2 _OzoneScaleOffset;
float _OzoneLayerStart;
float _OzoneLayerEnd;
//float4 _AirSeaLevelExtinction;
float4 _AirSeaLevelScattering;
float4 _AerosolSeaLevelScattering;
float4 _OzoneSeaLevelExtinction;
float4 _GroundAlbedo_PlanetRadius;
float4 _HorizonTint;
float4 _ZenithTint;
half _IntensityMultiplier;
half _ColorSaturation;
half _AlphaSaturation;
half _AlphaMultiplier;
half _HorizonZenithShiftPower;
half _HorizonZenithShiftScale;
uint _CelestialLightCount;
uint _CelestialBodyCount;
float _AtmosphericDepth;
float _RcpAtmosphericDepth;
float _CelestialLightExposure;
//float _PaddingPBS;

float3 _CelestialBody_Color;
float _CelestialBody_Radius;
float3 _CelestialBody_Forward;
float _CelestialBody_DistanceFromCamera;
half3 _CelestialBody_Right;
float _CelestialBody_AngularRadius;
half3 _CelestialBody_Up;
int _CelestialBody_Type;
float3 _CelestialBody_SurfaceColor;
float _CelestialBody_Earthshine;
float4 _CelestialBody_SurfaceTextureScaleOffset;
half3 _CelestialBody_SunDirection;
float _CelestialBody_FlareCosInner;
float _CelestialBody_FlareCosOuter;
float _CelestialBody_FlareSize;
float3 _CelestialBody_FlareColor;
float _CelestialBody_FlareFalloff;

#ifndef URP_VOLUMETRIC_CLOUDS_UTILITIES_HLSL
float4 _PlanetCenterRadius;
#endif
float4 _PlanetUpAltitude;

int _FogEnabled;
//int _PBRFogEnabled;
float _MaxFogDistance;
half4 _FogColor;
half _FogColorMode;
float4 _MipFogParameters;
float4 _HeightFogBaseScattering;
float _HeightFogBaseExtinction;
float _HeightFogBaseHeight;
float2 _HeightFogExponents;

half _UnderWaterEnabled;
float _FogWaterHeight;

half _EnableAtmosphericScattering;
//#define _MaxFogDistance 50000
#define _PBRFogEnabled (_EnableAtmosphericScattering == 1.0)

#define IsUnderWater(x) (_UnderWaterEnabled && x <= _FogWaterHeight)

#endif // URP_PHYSICALLY_BASED_SKY_DEFINES_INCLUDED