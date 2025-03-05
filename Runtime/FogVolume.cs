using System;
using System.Diagnostics;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

/// <summary>
/// The Fog Volume Override lets you customize a global fog effect.
/// </summary>
#if UNITY_2023_1_OR_NEWER
[Serializable, VolumeComponentMenu("Sky/Fog (URP)"), SupportedOnRenderPipeline(typeof(UniversalRenderPipelineAsset))]
#else
[Serializable, VolumeComponentMenuForRenderPipeline("Sky/Fog (URP)", typeof(UniversalRenderPipeline))]
#endif
[HelpURL("https://github.com/jiaozi158/UnityPhysicallyBasedSkyURP/tree/main")]
public class Fog : VolumeComponent, IPostProcessComponent
{
    /// <summary>Enable fog.</summary>
    [Tooltip("Enables the fog.")]
    public BoolParameter enabled = new BoolParameter(false, BoolParameter.DisplayType.EnumPopup);
    /// <summary>Fog color mode.</summary>
    [Tooltip("Specifies the color mode of the fog.")]
    public FogColorParameter colorMode = new FogColorParameter(FogColorMode.SkyColor);
    /// <summary>Fog color.</summary>
    [Tooltip("Specifies the constant color of the fog.")]
    public ColorParameter color = new ColorParameter(Color.grey, hdr: true, showAlpha: false, showEyeDropper: true);
    /// <summary>Specifies the tint of the fog when using Sky Color.</summary>
    [Tooltip("Specifies the tint of the fog.")]
    public ColorParameter tint = new ColorParameter(Color.white, hdr: true, showAlpha: false, showEyeDropper: true);
    /// <summary>Maximum fog distance.</summary>
    [Tooltip("Sets the maximum fog distance URP uses when it shades the skybox or the Far Clipping Plane of the Camera.")]
    public MinFloatParameter maxFogDistance = new MinFloatParameter(5000.0f, 0.0f);
    /// <summary>Controls the maximum mip map URP uses for mip fog (0 is the lowest mip and 1 is the highest mip).</summary>
    [AdditionalProperty]
    [Tooltip("Controls the maximum mip map URP uses for mip fog (0 is the lowest mip and 1 is the highest mip).")]
    public ClampedFloatParameter mipFogMaxMip = new ClampedFloatParameter(0.5f, 0.0f, 1.0f);
    /// <summary>Sets the distance at which URP uses the minimum mip image of the blurred sky texture as the fog color.</summary>
    [AdditionalProperty]
    [Tooltip("Sets the distance at which URP uses the minimum mip image of the blurred sky texture as the fog color.")]
    public MinFloatParameter mipFogNear = new MinFloatParameter(0.0f, 0.0f);
    /// <summary>Sets the distance at which URP uses the maximum mip image of the blurred sky texture as the fog color.</summary>
    [AdditionalProperty]
    [Tooltip("Sets the distance at which URP uses the maximum mip image of the blurred sky texture as the fog color.")]
    public MinFloatParameter mipFogFar = new MinFloatParameter(1000.0f, 0.0f);

    // Volumetric Clouds
    /// <summary>Controls how much the multiple-scattering will affect the scene. Directly controls the amount of blur depending on the fog density.</summary>
    //[AdditionalProperty]
    //[Tooltip("Use this value to simulate multiple scattering when combining the fog with the scene color.")]
    //public ClampedFloatParameter multipleScatteringIntensity = new ClampedFloatParameter(0.0f, 0.0f, 2.0f);

    /// <summary>Enables or disables fog when the camera is underwater.</summary>
    [Tooltip("Enables or disables fog when the camera is underwater.")]
    public BoolParameter underWater = new BoolParameter(false);
    /// <summary>Sets the height at which the water surface is located, used to determine when URP disables fog.</summary>
    [Tooltip("Sets the height at which the water surface is located, used to determine when URP disables fog.")]
    public FloatParameter waterHeight = new FloatParameter(1.0f);

    // Height Fog
    /// <summary>Height fog base height.</summary>
    [Tooltip("Reference height (e.g. sea level). Sets the height of the boundary between the constant and exponential fog. Units: m.")]
    public FloatParameter baseHeight = new FloatParameter(0.0f);
    /// <summary>Height fog maximum height.</summary>
    [Tooltip("Max height of the fog layer. Controls the rate of height-based density falloff. Units: m.")]
    public FloatParameter maximumHeight = new FloatParameter(50.0f);
    /// <summary>Fog mean free path.</summary>
    [DisplayInfo(name = "Fog Attenuation Distance"), Tooltip("Controls the density at the base level (per color channel). Distance at which fog reduces background light intensity by 63%. Units: m.")]
    public MinFloatParameter meanFreePath = new MinFloatParameter(400.0f, 1.0f);

    // Volumetric Clouds
    // Limit parameters for the fog quality
    //const float minFogScreenResolutionPercentage = (1.0f / 16.0f) * 100;
    //const float optimalFogScreenResolutionPercentage = (1.0f / 8.0f) * 100;
    //const float maxFogScreenResolutionPercentage = 0.5f * 100;
    //const int maxFogSliceCount = 512;

    public bool IsActive()
    {
        return active && enabled.value;
    }

#if !UNITY_6000_0_OR_NEWER
    /// <summary>
    /// This is unused since 2023.1
    /// </summary>
    public bool IsTileCompatible() => false;
#endif

    /// <summary>
    /// Fog Color Mode.
    /// </summary>
    public enum FogColorMode
    {
        /// <summary>Fog is a constant color.</summary>
        ConstantColor,
        /// <summary>Fog uses the current sky to determine its color.</summary>
        SkyColor,
    }

    /// <summary>
    /// Fog Color parameter.
    /// </summary>
    [Serializable, DebuggerDisplay(k_DebuggerDisplay)]
    public sealed class FogColorParameter : VolumeParameter<FogColorMode>
    {
        /// <summary>
        /// Fog Color Parameter constructor.
        /// </summary>
        /// <param name="value">Fog Color Parameter.</param>
        /// <param name="overrideState">Initial override state.</param>
        public FogColorParameter(FogColorMode value, bool overrideState = false)
            : base(value, overrideState) { }
    }
}
