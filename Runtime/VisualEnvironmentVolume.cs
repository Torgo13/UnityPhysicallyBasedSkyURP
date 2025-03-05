using System;
using Unity.Mathematics;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

/// <summary>
/// The Visual Environment Volume component override specifies the Sky Type that URP renders in the Volume.
/// </summary>
#if UNITY_2023_1_OR_NEWER
[Serializable, VolumeComponentMenu("Sky/Visual Environment (URP)"), SupportedOnRenderPipeline(typeof(UniversalRenderPipelineAsset))]
#else
[Serializable, VolumeComponentMenuForRenderPipeline("Sky/Visual Environment (URP)", typeof(UniversalRenderPipeline))]
#endif
[HelpURL("https://github.com/jiaozi158/UnityPhysicallyBasedSkyURP/tree/main")]
public class VisualEnvironment : VolumeComponent, IPostProcessComponent
{
    const float k_DefaultEarthRadius = 6.3781f * 1000000;

    //static Material s_DefaultMaterial = null;

    /// <summary>
    /// Specifies how the planet center is computed
    /// </summary>
    public enum PlanetMode
    {
        /// <summary>
        /// Top of the planet is located at the world origin.
        /// </summary>
        Automatic,
        /// <summary>
        /// Arbitrary position in space.
        /// </summary>
        Manual,
    };

    /// <summary>
    /// Rendering space used for planetary effects
    /// </summary>
    public enum RenderingSpace
    {
        /// <summary>
        /// Always centered around the camera
        /// </summary>
        Camera,
        /// <summary>
        /// Rendered in world space
        /// </summary>
        World,
    };

    // WIP feature
    /// <summary>
    /// Resolution of the sky reflection cubemap.
    /// </summary>
    private enum SkyResolution
    {
        /// <summary>128x128 per face.</summary>
        SkyResolution128 = 128,
        /// <summary>256x256 per face.</summary>
        SkyResolution256 = 256,
        /// <summary>512x512 per face.</summary>
        SkyResolution512 = 512,
        /// <summary>1024x1024 per face.</summary>
        SkyResolution1024 = 1024,
        /// <summary>2048x2048 per face.</summary>
        //SkyResolution2048 = 2048,
        /// <summary>4096x4096 per face.</summary>
        //SkyResolution4096 = 4096
    }

    /// <summary>Type of sky that should be used for rendering.</summary>
    [Header("Sky")]
    public NoInterpIntParameter skyType = new NoInterpIntParameter(0);
    
    /// <summary>Type of clouds that should be used for rendering.</summary>
    //public NoInterpIntParameter cloudType = new NoInterpIntParameter(0);
    
    /// <summary>Defines the way the ambient probe should be computed.</summary>
    public SkyAmbientModeParameter skyAmbientMode = new SkyAmbientModeParameter(SkyAmbientMode.Dynamic);

    /// <summary> Radius of the planet (distance from the center of the planet to the sea level). Units: kilometers. </summary>
    [Header("Planet")]
    public MinFloatParameter planetRadius = new MinFloatParameter(k_DefaultEarthRadius / 1000.0f, 0);
    
    /// <summary>When in Camera Space, sky and clouds will be centered on the camera. When in World Space, the camera can navigate through the atmosphere and the clouds.</summary>
    [Tooltip("When in Camera Space, sky and clouds will be centered on the camera.\nWhen in World Space, the camera can navigate through the atmosphere and the clouds.")]
    public RenderingSpaceParameter renderingSpace = new(RenderingSpace.World);
    
    /// <summary>The center is used when defining where the planets surface is. In automatic mode, the surface is at the world's origin and the center is derived from the planet radius. </summary>
    [AdditionalProperty]
    public PlanetModeParameter centerMode = new(PlanetMode.Automatic);

    /// <summary> Position of the center of the planet in world space. Units: kilometers. </summary>
    [AdditionalProperty]
    public Vector3Parameter planetCenter = new Vector3Parameter(new Vector3(0, -k_DefaultEarthRadius / 1000.0f, 0));

    /// <summary>Controls the global orientation of the wind relative to the X world vector.</summary>
    //[Header("Wind")]
    //public ClampedFloatParameter windOrientation = new ClampedFloatParameter(0.0f, 0.0f, 360.0f);

    /// <summary>Controls the global wind speed in kilometers per hour.</summary>
    //public FloatParameter windSpeed = new FloatParameter(0.0f);

    /// <summary> The custom sky material for this visual environment. </summary>
    [InspectorName("Sky Material"), Tooltip("The custom sky material for this visual environment.")]
    public MaterialParameter customSkyMaterial = new MaterialParameter(null);

    public bool IsActive()
    {
        return active;
    }

#if !UNITY_6000_0_OR_NEWER
    /// <summary>
    /// This is unused since 2023.1
    /// </summary>
    public bool IsTileCompatible() => false;
#endif

    /// <summary>
    /// Get the center position and radius of the current planet in meters.
    /// </summary>
    public float4 GetPlanetCenterRadius(float3 cameraPositionWS)
    {
        float4 center;
        float radius = planetRadius.value * 1000.0f;
        if (renderingSpace.value == RenderingSpace.Camera)
            center = new float4(cameraPositionWS.x, cameraPositionWS.y - radius, cameraPositionWS.z, radius);
        else if (centerMode.value == PlanetMode.Automatic)
            center = new float4(0, -radius, 0, radius);
        else
            center = new float4(planetCenter.value * 1000.0f, radius);

        return center;
    }

    /// <summary>
    /// Get the radius of the current planet in meters.
    /// </summary>
    public float GetPlanetRadius()
    {
        return planetRadius.value * 1000.0f;
    }

    /// <summary>
    /// Informative enumeration containing SkyUniqueIDs already used by URP.
    /// When users write their own sky type, they can use any ID not present in this enumeration or in their project.
    /// </summary>
    public enum SkyType
    {
        // To simplify this package, please assign a custom sky material for other sky types.

        /// <summary>HDRI Sky Unique ID.</summary>
        //HDRI = 1,
        /// <summary>Procedural Sky Unique ID.</summary>
        //Procedural = 2,
        /// <summary>Gradient Sky Unique ID.</summary>
        //Gradient = 3,
        /// <summary>Physically Based Sky Unique ID.</summary>
        PhysicallyBased = 4,
        /// <summary>Custom Sky Unique ID.</summary>
        Custom = 5,
    }

    /// <summary>
    /// Informative enumeration containing CloudUniqueIDs already used by URP.
    /// When users write their own cloud type, they can use any ID not present in this enumeration or in their project.
    /// </summary>
    //public enum CloudType
    //{
        /// <summary>Cloud Layer Unique ID.</summary>
        //CloudLayer = 1,
    //}

    /// <summary>
    /// Sky Ambient Mode.
    /// </summary>
    public enum SkyAmbientMode
    {
        /// <summary>URP will use the baked global ambient probe setup in the lighting panel.</summary>
        Static,
        /// <summary>URP will use the current sky used for lighting to compute the global ambient probe.</summary>
        Dynamic,
    }

    /// <summary>
    /// Sky Ambient Mode volume parameter.
    /// </summary>
    [Serializable]
    public sealed class SkyAmbientModeParameter : VolumeParameter<SkyAmbientMode>
    {
        /// <summary>
        /// Sky Ambient Mode volume parameter constructor.
        /// </summary>
        /// <param name="value">Sky Ambient Mode parameter.</param>
        /// <param name="overrideState">Initial override value.</param>
        public SkyAmbientModeParameter(SkyAmbientMode value, bool overrideState = false)
            : base(value, overrideState) { }
    }

    /// <summary>
    /// A <see cref="VolumeParameter"/> that holds a <see cref="PlanetMode"/> value.
    /// </summary>
    [Serializable]
    public sealed class PlanetModeParameter : VolumeParameter<PlanetMode>
    {
        /// <summary>
        /// Creates a new <see cref="PlanetModeParameter"/> instance.
        /// </summary>
        /// <param name="value">The initial value to store in the parameter.</param>
        /// <param name="overrideState">The initial override state for the parameter.</param>
        public PlanetModeParameter(PlanetMode value, bool overrideState = false) : base(value, overrideState) { }
    }

    /// <summary>
    /// A <see cref="VolumeParameter"/> that holds a <see cref="RenderingSpace"/> value.
    /// </summary>
    [Serializable]
    public sealed class RenderingSpaceParameter : VolumeParameter<RenderingSpace>
    {
        /// <summary>
        /// Creates a new <see cref="RenderingSpaceParameter"/> instance.
        /// </summary>
        /// <param name="value">The initial value to store in the parameter.</param>
        /// <param name="overrideState">The initial override state for the parameter.</param>
        public RenderingSpaceParameter(RenderingSpace value, bool overrideState = false) : base(value, overrideState) { }
    }
}
