using System;
using System.Diagnostics;
using Unity.Mathematics;
using static Unity.Mathematics.math;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

/// <summary>
/// The Physically Based Sky Volume Override lets you configure how the Universal Render Pipeline (URP) renders physically based sky.
/// </summary>
#if UNITY_2023_1_OR_NEWER
[Serializable, VolumeComponentMenu("Sky/Physically Based Sky (URP)"), SupportedOnRenderPipeline(typeof(UniversalRenderPipelineAsset))]
#else
[Serializable, VolumeComponentMenuForRenderPipeline("Sky/Physically Based Sky (URP)", typeof(UniversalRenderPipeline))]
#endif
[HelpURL("https://github.com/jiaozi158/UnityPhysicallyBasedSkyURP/tree/main")]
public class PhysicallyBasedSky : VolumeComponent, IPostProcessComponent
{
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
    /// The model used to control the complexity of the simulation.
    /// </summary>
    public enum PhysicallyBasedSkyModel
    {
        /// <summary>Suitable to simulate Earth</summary>
        EarthSimple,
        /// <summary>Suitable to simulate Earth</summary>
        EarthAdvanced,
        /// <summary>Suitable to simulate any planet</summary>
        Custom
    };

    /// <summary>
    /// Environment lighting update mode.
    /// </summary>
    public enum EnvironmentUpdateMode
    {
        /// <summary>Environment lighting is updated when the sky has changed.</summary>
        OnChanged = 0,
        /// <summary>Environment lighting is updated on demand.</summary>
        OnDemand,
        /// <summary>Environment lighting is updated in real time.</summary>
        Realtime
    }

    /// <summary>
    /// Sky Intensity Mode.
    /// </summary>
    public enum SkyIntensityMode
    {
        /// <summary>Intensity is expressed as an exposure.</summary>
        Exposure,
        /// <summary>Intensity is expressed in lux.</summary>
        Lux,
        /// <summary>Intensity is expressed as a multiplier.</summary>
        Multiplier,
    }

    /* We use the measurements from Earth as the defaults. */
    const float k_DefaultEarthRadius = 6.3781f * 1000000;
    const float k_DefaultAirScatteringR = 5.8f / 1000000; // at 680 nm, without ozone
    const float k_DefaultAirScatteringG = 13.5f / 1000000; // at 550 nm, without ozone
    const float k_DefaultAirScatteringB = 33.1f / 1000000; // at 440 nm, without ozone
    const float k_DefaultAirScaleHeight = 8000;
    const float k_DefaultAerosolScaleHeight = 1200;
    static readonly float k_DefaultAerosolMaximumAltitude = LayerDepthFromScaleHeight(k_DefaultAerosolScaleHeight);
    static readonly float k_DefaultOzoneMinimumAltitude = 20.0f * 1000.0f; // 20km
    static readonly float k_DefaultOzoneLayerWidth = 20.0f * 1000.0f; // 20km

    //internal static Material s_DefaultMaterial = null;

    /// <summary> Indicates a preset URP uses to simplify the Inspector. </summary>
    [Tooltip("Indicates a preset URP uses to simplify the Inspector.")]
    public PhysicallyBasedSkyModelParameter type = new(PhysicallyBasedSkyModel.EarthAdvanced);

    /// <summary> Enable atmopsheric scattering on opaque objects.</summary>
    [Tooltip("Enables atmospheric attenuation on opaque objects when viewed from a distance. This is responsible for the blue tint on distant montains or clouds.")]
    public BoolParameter atmosphericScattering = new BoolParameter(true);

    /// <summary> The material used for sky rendering. </summary>
    //[Tooltip("The material used to render the sky. It is recommended to use the **Physically Based Sky** Material type of ShaderGraph.")]
    //public MaterialParameter material = new MaterialParameter(s_DefaultMaterial);

    /// <summary> Opacity (per color channel) of air as measured by an observer on the ground looking towards the zenith. </summary>
    [Tooltip("Controls the red color channel opacity of air at the point in the sky directly above the observer (zenith).")]
    public ClampedFloatParameter airDensityR = new ClampedFloatParameter(ZenithOpacityFromExtinctionAndScaleHeight(k_DefaultAirScatteringR, k_DefaultAirScaleHeight), 0, 1);

    /// <summary> Opacity (per color channel) of air as measured by an observer on the ground looking towards the zenith. </summary>
    [Tooltip("Controls the green color channel opacity of air at the point in the sky directly above the observer (zenith).")]
    public ClampedFloatParameter airDensityG = new ClampedFloatParameter(ZenithOpacityFromExtinctionAndScaleHeight(k_DefaultAirScatteringG, k_DefaultAirScaleHeight), 0, 1);

    /// <summary> Opacity (per color channel) of air as measured by an observer on the ground looking towards the zenith. </summary>
    [Tooltip("Controls the blue color channel opacity of air at the point in the sky directly above the observer (zenith).")]
    public ClampedFloatParameter airDensityB = new ClampedFloatParameter(ZenithOpacityFromExtinctionAndScaleHeight(k_DefaultAirScatteringB, k_DefaultAirScaleHeight), 0, 1);

    /// <summary> Single scattering albedo of air molecules (per color channel). The value of 0 results in absorbing molecules, and the value of 1 results in scattering ones. </summary>
    [Tooltip("Specifies the color that URP tints the air to. This controls the single scattering albedo of air molecules (per color channel). A value of 0 results in absorbing molecules, and a value of 1 results in scattering ones.")]
    public ColorParameter airTint = new ColorParameter(Color.white, hdr: false, showAlpha: false, showEyeDropper: true);

    /// <summary> Depth of the atmospheric layer (from the sea level) composed of air particles. Controls the rate of height-based density falloff. Units: meters. </summary>
    [Tooltip("Sets the depth, in meters, of the atmospheric layer, from sea level, composed of air particles. Controls the rate of height-based density falloff.")]
    // We assume the exponential falloff of density w.r.t. the height.
    // We can interpret the depth as the height at which the density drops to 0.1% of the initial (sea level) value.
    public MinFloatParameter airMaximumAltitude = new MinFloatParameter(LayerDepthFromScaleHeight(k_DefaultAirScaleHeight), 0);

    /// <summary> Opacity of aerosols as measured by an observer on the ground looking towards the zenith. </summary>
    [Tooltip("Controls the opacity of aerosols at the point in the sky directly above the observer (zenith).")]
    // Note: aerosols are (fairly large) solid or liquid particles suspended in the air.
    public ClampedFloatParameter aerosolDensity = new ClampedFloatParameter(ZenithOpacityFromExtinctionAndScaleHeight(10.0f / 1000000, k_DefaultAerosolScaleHeight), 0, 1);

    /// <summary> Single scattering albedo of aerosol molecules (per color channel). The value of 0 results in absorbing molecules, and the value of 1 results in scattering ones. </summary>
    [Tooltip("Specifies the color that URP tints aerosols to. This controls the single scattering albedo of aerosol molecules (per color channel). A value of 0 results in absorbing molecules, and a value of 1 results in scattering ones.")]
    public ColorParameter aerosolTint = new ColorParameter(new Color(0.9f, 0.9f, 0.9f), hdr: false, showAlpha: false, showEyeDropper: true);

    /// <summary> Depth of the atmospheric layer (from the sea level) composed of aerosol particles. Controls the rate of height-based density falloff. Units: meters. </summary>
    [Tooltip("Sets the depth, in meters, of the atmospheric layer, from sea level, composed of aerosol particles. Controls the rate of height-based density falloff.")]
    // We assume the exponential falloff of density w.r.t. the height.
    // We can interpret the depth as the height at which the density drops to 0.1% of the initial (sea level) value.
    public MinFloatParameter aerosolMaximumAltitude = new MinFloatParameter(k_DefaultAerosolMaximumAltitude, 0);

    /// <summary> Positive values for forward scattering, 0 for isotropic scattering. negative values for backward scattering. </summary>
    [Tooltip("Controls the direction of anisotropy. Set this to a positive value for forward scattering, a negative value for backward scattering, or 0 for isotropic scattering.")]
    public ClampedFloatParameter aerosolAnisotropy = new ClampedFloatParameter(0.8f, -1, 1);

    /// <summary> Controls the ozone density in the atmosphere. </summary>
    [Tooltip("Controls the ozone density in the atmosphere.")]
    public ClampedFloatParameter ozoneDensityDimmer = new ClampedFloatParameter(1.0f, 0, 1);

    /// <summary>Controls the minimum altitude of ozone in the atmosphere. </summary>
    [Tooltip("Controls the minimum altitude of ozone in the atmosphere.")]
    public MinFloatParameter ozoneMinimumAltitude = new MinFloatParameter(k_DefaultOzoneMinimumAltitude, 0);

    /// <summary> Controls the width of the ozone layer in the atmosphere. </summary>
    [Tooltip("Controls the width of the ozone layer in the atmosphere.")]
    public MinFloatParameter ozoneLayerWidth = new MinFloatParameter(k_DefaultOzoneLayerWidth, 0);

    /// <summary> Ground tint. </summary>
    [Tooltip("Specifies a color that URP uses to tint the Ground Color Texture.")]
    public ColorParameter groundTint = new ColorParameter(new Color(0.12f, 0.10f, 0.09f), hdr: false, showAlpha: false, showEyeDropper: false);

    /// <summary> Ground color texture. Does not affect the precomputation. </summary>
    [Tooltip("Specifies a Texture that represents the planet's surface. Does not affect the precomputation.")]
    public CubemapParameter groundColorTexture = new CubemapParameter(null);

    /// <summary> Ground emission texture. Does not affect the precomputation. </summary>
    [Tooltip("Specifies a Texture that represents the emissive areas of the planet's surface. Does not affect the precomputation.")]
    public CubemapParameter groundEmissionTexture = new CubemapParameter(null);

    /// <summary> Ground emission multiplier. Does not affect the precomputation. </summary>
    [Tooltip("Sets the multiplier that URP applies to the Ground Emission Texture. Does not affect the precomputation.")]
    public MinFloatParameter groundEmissionMultiplier = new MinFloatParameter(1, 0);

    /// <summary> Rotation of the planet. Does not affect the precomputation. </summary>
    [Tooltip("Sets the orientation of the planet. Does not affect the precomputation.")]
    public Vector3Parameter planetRotation = new Vector3Parameter(Vector3.zero);

    /// <summary> Space emission texture. Does not affect the precomputation. </summary>
    [Tooltip("Specifies a Texture that represents the emissive areas of space. Does not affect the precomputation.")]
    public CubemapParameter spaceEmissionTexture = new CubemapParameter(null);

    /// <summary> Space emission multiplier. Does not affect the precomputation. </summary>
    [Tooltip("Sets the multiplier that URP applies to the Space Emission Texture. Does not affect the precomputation.")]
    public MinFloatParameter spaceEmissionMultiplier = new MinFloatParameter(1, 0);

    /// <summary> Rotation of space. Does not affect the precomputation. </summary>
    [Tooltip("Sets the orientation of space. Does not affect the precomputation.")]
    public Vector3Parameter spaceRotation = new Vector3Parameter(Vector3.zero);

    /// <summary> Color saturation. Does not affect the precomputation. </summary>
    [Tooltip("Controls the saturation of the sky color. Does not affect the precomputation.")]
    public ClampedFloatParameter colorSaturation = new ClampedFloatParameter(1, 0, 1);

    /// <summary> Opacity saturation. Does not affect the precomputation. </summary>
    [Tooltip("Controls the saturation of the sky opacity. Does not affect the precomputation.")]
    public ClampedFloatParameter alphaSaturation = new ClampedFloatParameter(1, 0, 1);

    /// <summary> Opacity multiplier. Does not affect the precomputation. </summary>
    [Tooltip("Sets the multiplier that URP applies to the opacity of the sky. Does not affect the precomputation.")]
    public ClampedFloatParameter alphaMultiplier = new ClampedFloatParameter(1, 0, 1);

    /// <summary> Horizon tint. Does not affect the precomputation. </summary>
    [Tooltip("Specifies a color that URP uses to tint the sky at the horizon. Does not affect the precomputation.")]
    public ColorParameter horizonTint = new ColorParameter(Color.white, hdr: false, showAlpha: false, showEyeDropper: true);

    /// <summary> Zenith tint. Does not affect the precomputation. </summary>
    [Tooltip("Specifies a color that URP uses to tint the point in the sky directly above the observer (the zenith). Does not affect the precomputation.")]
    public ColorParameter zenithTint = new ColorParameter(Color.white, hdr: false, showAlpha: false, showEyeDropper: true);

    /// <summary> Horizon-zenith shift. Does not affect the precomputation. </summary>
    [Tooltip("Controls how URP blends between the Horizon Tint and Zenith Tint. Does not affect the precomputation.")]
    public ClampedFloatParameter horizonZenithShift = new ClampedFloatParameter(0, -1, 1);

    /// <summary>
    /// Sky Intensity volume parameter.
    /// </summary>
    [Serializable, DebuggerDisplay(k_DebuggerDisplay)]
    public sealed class SkyIntensityParameter : VolumeParameter<SkyIntensityMode>
    {
        /// <summary>
        /// Sky Intensity volume parameter constructor.
        /// </summary>
        /// <param name="value">Sky Intensity parameter.</param>
        /// <param name="overrideState">Initial override state.</param>
        public SkyIntensityParameter(SkyIntensityMode value, bool overrideState = false)
            : base(value, overrideState) { }
    }

    /// <summary>
    /// Environment Update volume parameter.
    /// </summary>
    [Serializable, DebuggerDisplay(k_DebuggerDisplay)]
    public sealed class EnvUpdateParameter : VolumeParameter<EnvironmentUpdateMode>
    {
        /// <summary>
        /// Environment Update parameter constructor.
        /// </summary>
        /// <param name="value">Environment Update Mode parameter.</param>
        /// <param name="overrideState">Initial override state.</param>
        public EnvUpdateParameter(EnvironmentUpdateMode value, bool overrideState = false)
            : base(value, overrideState) { }
    }

    /// <summary>
    /// A <see cref="VolumeParameter"/> that holds a <see cref="PhysicallyBasedSkyModel"/> value.
    /// </summary>
    [Serializable, DebuggerDisplay(k_DebuggerDisplay)]
    public sealed class PhysicallyBasedSkyModelParameter : VolumeParameter<PhysicallyBasedSkyModel>
    {
        /// <summary>
        /// Creates a new <see cref="PhysicallyBasedSkyModelParameter"/> instance.
        /// </summary>
        /// <param name="value">The initial value to store in the parameter.</param>
        /// <param name="overrideState">The initial override state for the parameter.</param>
        public PhysicallyBasedSkyModelParameter(PhysicallyBasedSkyModel value, bool overrideState = false) : base(value, overrideState) { }
    }

    /// <summary>Intensity mode of the sky.</summary>
    [Tooltip("Specifies the intensity mode URP uses for the sky.")]
    public SkyIntensityParameter skyIntensityMode = new SkyIntensityParameter(SkyIntensityMode.Exposure);

    /// <summary>Exposure of the sky.</summary>
    [Tooltip("Sets the exposure of the sky in EV.")]
    public FloatParameter exposure = new FloatParameter(0.0f);

    /// <summary>Intensity Multipler of the sky.</summary>
    [Tooltip("Sets the intensity multiplier for the sky.")]
    public MinFloatParameter multiplier = new MinFloatParameter(1.0f, 0.0f);

    /// <summary>Informative helper that displays the relative intensity (in Lux) for the current HDR texture set in HDRI Sky.</summary>
    [Tooltip("Informative helper that displays the relative intensity (in Lux) for the current HDR texture set in HDRI Sky.")]
    public MinFloatParameter upperHemisphereLuxValue = new MinFloatParameter(1.0f, 0.0f);

    /// <summary>Informative helper that displays Show the color of Shadow.</summary>
    [Tooltip("Informative helper that displays Show the color of Shadow.")]
    public Vector3Parameter upperHemisphereLuxColor = new Vector3Parameter(new Vector3(0, 0, 0));

    /// <summary>Absolute intensity (in lux) of the sky.</summary>
    [Tooltip("Sets the absolute intensity (in Lux) of the current HDR texture set in HDRI Sky. Functions as a Lux intensity multiplier for the sky.")]
    public FloatParameter desiredLuxValue = new FloatParameter(20000);

    /// <summary>Update mode of the sky.</summary>
    [Tooltip("Specifies when URP updates the environment lighting. When set to OnDemand, use HDRenderPipeline.RequestSkyEnvironmentUpdate() to request an update.")]
    public EnvUpdateParameter updateMode = new EnvUpdateParameter(EnvironmentUpdateMode.OnChanged);

    /// <summary>In case of real-time update mode, time between updates. 0 means every frame.</summary>
    [Tooltip("Sets the period, in seconds, at which URP updates the environment ligting (0 means URP updates it every frame).")]
    public MinFloatParameter updatePeriod = new MinFloatParameter(0.0f, 0.0f);

    /// <summary>True if the sun disk should be included in the baking information (where available).</summary>
    [Tooltip("When enabled, URP uses the Sun Disk in baked lighting.")]
    public BoolParameter includeSunInBaking = new BoolParameter(false);

    static public float ScaleHeightFromLayerDepth(float d)
    {
        // Exp[-d / H] = 0.001
        // -d / H = Log[0.001]
        // H = d / -Log[0.001]
        return d * 0.144765f;
    }

    static public float LayerDepthFromScaleHeight(float H)
    {
        return H / 0.144765f;
    }

    static public float ExtinctionFromZenithOpacityAndScaleHeight(float alpha, float H)
    {
        float opacity = Mathf.Min(alpha, 0.999999f);
        float optDepth = -Mathf.Log(1 - opacity, 2.71828183f); // product of extinction and H

        return optDepth / H;
    }

    static public float ZenithOpacityFromExtinctionAndScaleHeight(float ext, float H)
    {
        float optDepth = ext * H;

        return 1 - Mathf.Exp(-optDepth);
    }

    // TODO: Get the actual user-defined planet radius
    static float GetPlanetaryRadius()
    {
        return k_DefaultEarthRadius;
    }

    static Vector3 GetPlanetaryCenter()
    {
        return new Vector3(0.0f, -GetPlanetaryRadius(), 0.0f);
    }

    public float GetAirScaleHeight()
    {
        if (type.value != PhysicallyBasedSkyModel.Custom)
        {
            return k_DefaultAirScaleHeight;
        }
        else
        {
            return ScaleHeightFromLayerDepth(airMaximumAltitude.value);
        }
    }

    public float GetMaximumAltitude()
    {
        if (type.value == PhysicallyBasedSkyModel.Custom)
            return Mathf.Max(airMaximumAltitude.value, aerosolMaximumAltitude.value);

        float aerosolMaxAltitude = (type.value == PhysicallyBasedSkyModel.EarthSimple) ? k_DefaultAerosolMaximumAltitude : aerosolMaximumAltitude.value;
        return Mathf.Max(LayerDepthFromScaleHeight(k_DefaultAirScaleHeight), aerosolMaxAltitude);
    }

    public Vector3 GetAirExtinctionCoefficient()
    {
        Vector3 airExt = new Vector3();

        if (type.value != PhysicallyBasedSkyModel.Custom)
        {
            airExt.x = k_DefaultAirScatteringR;
            airExt.y = k_DefaultAirScatteringG;
            airExt.z = k_DefaultAirScatteringB;
        }
        else
        {
            airExt.x = ExtinctionFromZenithOpacityAndScaleHeight(airDensityR.value, GetAirScaleHeight());
            airExt.y = ExtinctionFromZenithOpacityAndScaleHeight(airDensityG.value, GetAirScaleHeight());
            airExt.z = ExtinctionFromZenithOpacityAndScaleHeight(airDensityB.value, GetAirScaleHeight());
        }

        return airExt;
    }

    public Vector3 GetAirAlbedo()
    {
        Vector3 airAlb = Vector3.one;

        if (type.value == PhysicallyBasedSkyModel.Custom)
        {
            airAlb.x = airTint.value.r;
            airAlb.y = airTint.value.g;
            airAlb.z = airTint.value.b;
        }

        return airAlb;
    }

    public Vector3 GetAirScatteringCoefficient()
    {
        Vector3 airExt = GetAirExtinctionCoefficient();
        Vector3 airAlb = GetAirAlbedo();

        return new Vector3(airExt.x * airAlb.x,
            airExt.y * airAlb.y,
            airExt.z * airAlb.z);
    }

    public float GetAerosolScaleHeight()
    {
        if (type.value == PhysicallyBasedSkyModel.EarthSimple)
        {
            return k_DefaultAerosolScaleHeight;
        }
        else
        {
            return ScaleHeightFromLayerDepth(aerosolMaximumAltitude.value);
        }
    }

    public float GetAerosolExtinctionCoefficient()
    {
        return ExtinctionFromZenithOpacityAndScaleHeight(aerosolDensity.value, GetAerosolScaleHeight());
    }

    public Vector3 GetAerosolScatteringCoefficient()
    {
        float aerExt = GetAerosolExtinctionCoefficient();

        return new Vector3(aerExt * aerosolTint.value.r,
            aerExt * aerosolTint.value.g,
            aerExt * aerosolTint.value.b);
    }

    public Vector3 GetOzoneExtinctionCoefficient()
    {
        Vector3 absorption = new Vector3(0.00065f, 0.00188f, 0.00008f) / 1000.0f;
        if (type.value != PhysicallyBasedSkyModel.EarthSimple)
            absorption *= ozoneDensityDimmer.value;
        return absorption;
    }

    public float GetOzoneLayerWidth()
    {
        if (type.value == PhysicallyBasedSkyModel.Custom)
            return ozoneLayerWidth.value;
        return k_DefaultOzoneLayerWidth;
    }

    public float GetOzoneLayerMinimumAltitude()
    {
        if (type.value == PhysicallyBasedSkyModel.Custom)
            return ozoneMinimumAltitude.value;
        return k_DefaultOzoneMinimumAltitude;
    }

    /// <summary>
    /// Returns the sky intensity of this PBR Sky.
    /// </summary>
    /// <returns>The sky intensity.</returns>
    public float GetIntensityFromSettings()
    {
        float skyIntensity = 1.0f;
        switch (skyIntensityMode.value)
        {
            case SkyIntensityMode.Exposure:
                // Note: Here we use EV100 of sky as a multiplier, so it is the opposite of when use with a Camera
                // because for sky/light, higher EV mean brighter, but for camera higher EV mean darker scene
                skyIntensity *= ColorUtils.ConvertEV100ToExposure(-exposure.value);
                break;
            case SkyIntensityMode.Multiplier:
                skyIntensity *= multiplier.value;
                break;
            case SkyIntensityMode.Lux:
                skyIntensity *= desiredLuxValue.value / Mathf.Max(upperHemisphereLuxValue.value, 1e-5f);
                break;
        }
        return skyIntensity;
    }

    /// <summary> Returns the hash code of the precomputation related parameters of the sky. </summary>
    /// <returns> The hash code of the parameters of the sky. </returns>
    public int GetPrecomputationHashCode()
    {
        int hash = base.GetHashCode();

        unchecked
        {
            // These parameters affect precomputation.
            hash = hash * 23 + type.GetHashCode();
            hash = hash * 23 + atmosphericScattering.GetHashCode();
            hash = hash * 23 + groundTint.GetHashCode();

            hash = hash * 23 + airMaximumAltitude.GetHashCode();
            hash = hash * 23 + airDensityR.GetHashCode();
            hash = hash * 23 + airDensityG.GetHashCode();
            hash = hash * 23 + airDensityB.GetHashCode();
            hash = hash * 23 + airTint.GetHashCode();

            hash = hash * 23 + aerosolMaximumAltitude.GetHashCode();
            hash = hash * 23 + aerosolDensity.GetHashCode();
            hash = hash * 23 + aerosolTint.GetHashCode();
            hash = hash * 23 + aerosolAnisotropy.GetHashCode();

            hash = hash * 23 + ozoneDensityDimmer.GetHashCode();
            hash = hash * 23 + ozoneMinimumAltitude.GetHashCode();
            hash = hash * 23 + ozoneLayerWidth.GetHashCode();
        }

        return hash;
    }

    /// <summary> Returns the hash code of the parameters of the sky. </summary>
    /// <returns> The hash code of the parameters of the sky. </returns>
    public override int GetHashCode()
    {
        int hash = GetPrecomputationHashCode();

        unchecked
        {
            // These parameters do NOT affect precomputation.
            //hash = hash * 23 + renderingSpace.GetHashCode();
            //hash = hash * 23 + material.GetHashCode();
            hash = hash * 23 + planetRotation.GetHashCode();

            if (groundColorTexture.value != null)
                hash = hash * 23 + groundColorTexture.GetHashCode();

            if (groundEmissionTexture.value != null)
                hash = hash * 23 + groundEmissionTexture.GetHashCode();

            hash = hash * 23 + groundEmissionMultiplier.GetHashCode();

            hash = hash * 23 + spaceRotation.GetHashCode();

            if (spaceEmissionTexture.value != null)
                hash = hash * 23 + spaceEmissionTexture.GetHashCode();

            hash = hash * 23 + spaceEmissionMultiplier.GetHashCode();
            hash = hash * 23 + colorSaturation.GetHashCode();
            hash = hash * 23 + alphaSaturation.GetHashCode();
            hash = hash * 23 + alphaMultiplier.GetHashCode();
            hash = hash * 23 + horizonTint.GetHashCode();
            hash = hash * 23 + zenithTint.GetHashCode();
            hash = hash * 23 + horizonZenithShift.GetHashCode();
        }

        return hash;
    }

    static float Saturate(float x)
    {
        return Mathf.Max(0, Mathf.Min(x, 1));
    }

    static float Rcp(float x)
    {
        return 1.0f / x;
    }

    static float Rsqrt(float x)
    {
        return Rcp(Mathf.Sqrt(x));
    }

    public static float ComputeCosineOfHorizonAngle(float r, float R)
    {
        float sinHoriz = R * Rcp(r);
        return -Mathf.Sqrt(Saturate(1 - sinHoriz * sinHoriz));
    }

    public static float ChapmanUpperApprox(float z, float cosTheta)
    {
        float c = cosTheta;
        float n = 0.761643f * ((1 + 2 * z) - (c * c * z));
        float d = c * z + Mathf.Sqrt(z * (1.47721f + 0.273828f * (c * c * z)));

        return 0.5f * c + (n * Rcp(d));
    }

    public static float ChapmanHorizontal(float z)
    {
        float r = Rsqrt(z);
        float s = z * r; // sqrt(z)

        return 0.626657f * (r + 2 * s);
    }

    public static float OzoneDensity(float height, Vector2 ozoneScaleOffset)
    {
        return Mathf.Clamp01(1 - Mathf.Abs(height * ozoneScaleOffset.x + ozoneScaleOffset.y));
    }

    // See IntersectSphere in PhysicallyBasedSkyCommon.hlsl
    public static Vector2 IntersectSphere(float sphereRadius, float cosChi, float radialDistance, float rcpRadialDistance)
    {
        float d = Mathf.Pow(sphereRadius * rcpRadialDistance, 2.0f) - Mathf.Clamp01(1.0f - cosChi * cosChi);
        return (d < 0.0f) ? new Vector2(d, d) : (radialDistance * new Vector2(-cosChi - Mathf.Sqrt(d), -cosChi + Mathf.Sqrt(d)));
    }

    public static float ComputeOzoneOpticalDepth(float R, float r, float cosTheta, float ozoneMinimumAltitude, float ozoneLayerWidth)
    {
        float ozoneOD = 0.0f;

        Vector2 tInner = IntersectSphere(R + ozoneMinimumAltitude, cosTheta, r, 1.0f / r);
        Vector2 tOuter = IntersectSphere(R + ozoneMinimumAltitude + ozoneLayerWidth, cosTheta, r, 1.0f / r);
        float tEntry, tEntry2, tExit, tExit2;

        if (tInner.x < 0.0 && tInner.y >= 0.0) // Below the lower bound
        {
            // The ray starts at the intersection with the lower bound and ends at the intersection with the outer bound
            tEntry = tInner.y;
            tExit2 = tOuter.y;
            tEntry2 = tExit = (tExit2 - tEntry) * 0.5f;
        }
        else // Inside or above the volume
        {
            // The ray starts at the intersection with the outer bound, or at 0 if we are inside
            // The ray ends at the lower bound if we hit it, at the outer bound otherwise
            tEntry = Mathf.Max(tOuter.x, 0.0f);
            tExit = tInner.x >= 0.0 ? tInner.x : tOuter.y;

            // If we hit the lower bound, we may intersect the volume a second time
            if (tInner.x >= 0.0)
            {
                tEntry2 = tInner.y;
                tExit2 = tOuter.y;
            }
            else
            {
                tExit2 = tExit;
                tEntry2 = tExit = (tExit2 - tEntry) * 0.5f;
            }
        }

        uint count = 2;
        float rcpCount = 1.0f / count;
        float dt = (tExit - tEntry) * rcpCount;
        float dt2 = (tExit2 - tEntry2) * rcpCount;
        Vector2 ozoneScaleOffset = new Vector2(2.0f / ozoneLayerWidth, -2.0f * ozoneMinimumAltitude / ozoneLayerWidth - 1.0f);

        for (uint i = 0; i < count; i++)
        {
            float t = Mathf.Lerp(tEntry, tExit, (i + 0.5f) * rcpCount);
            float t2 = Mathf.Lerp(tEntry2, tExit2, (i + 0.5f) * rcpCount);
            float h = Mathf.Sqrt(r * r + t * (2 * r * cosTheta + t)) - R;
            float h2 = Mathf.Sqrt(r * r + t2 * (2 * r * cosTheta + t2)) - R;

            ozoneOD += OzoneDensity(h, ozoneScaleOffset) * dt;
            ozoneOD += OzoneDensity(h2, ozoneScaleOffset) * dt2;
        }

        return ozoneOD * 0.6f;
    }


    public static Vector3 ComputeAtmosphericOpticalDepth(
        float airScaleHeight, float aerosolScaleHeight, in Vector3 airExtinctionCoefficient, float aerosolExtinctionCoefficient,
        float ozoneMinimumAltitude, float ozoneLayerWidth, Vector3 ozoneExtinctionCoefficient,
        float R, float r, float cosTheta, bool alwaysAboveHorizon = false)
    {
        Vector2 H = new Vector2(airScaleHeight, aerosolScaleHeight);
        Vector2 rcpH = new Vector2(Rcp(H.x), Rcp(H.y));

        Vector2 z = r * rcpH;
        Vector2 Z = R * rcpH;

        float cosHoriz = ComputeCosineOfHorizonAngle(r, R);
        float sinTheta = Mathf.Sqrt(Saturate(1 - cosTheta * cosTheta));

        Vector2 ch;
        ch.x = ChapmanUpperApprox(z.x, Mathf.Abs(cosTheta)) * Mathf.Exp(Z.x - z.x); // Rescaling adds 'exp'
        ch.y = ChapmanUpperApprox(z.y, Mathf.Abs(cosTheta)) * Mathf.Exp(Z.y - z.y); // Rescaling adds 'exp'

        if ((!alwaysAboveHorizon) && (cosTheta < cosHoriz)) // Below horizon, intersect sphere
        {
            float sinGamma = (r / R) * sinTheta;
            float cosGamma = Mathf.Sqrt(Saturate(1 - sinGamma * sinGamma));

            Vector2 ch_2;
            ch_2.x = ChapmanUpperApprox(Z.x, cosGamma); // No need to rescale
            ch_2.y = ChapmanUpperApprox(Z.y, cosGamma); // No need to rescale

            ch = ch_2 - ch;
        }
        else if (cosTheta < 0)   // Above horizon, lower hemisphere
        {
            // z_0 = n * r_0 = (n * r) * sin(theta) = z * sin(theta).
            // Ch(z, theta) = 2 * exp(z - z_0) * Ch(z_0, Pi/2) - Ch(z, Pi - theta).
            Vector2 z_0 = z * sinTheta;
            Vector2 b = new Vector2(Mathf.Exp(Z.x - z_0.x), Mathf.Exp(Z.x - z_0.x)); // Rescaling cancels out 'z' and adds 'Z'
            Vector2 a;
            a.x = 2 * ChapmanHorizontal(z_0.x);
            a.y = 2 * ChapmanHorizontal(z_0.y);
            Vector2 ch_2 = a * b;

            ch = ch_2 - ch;
        }

        Vector2 optDepth = ch * H;

        float ozoneOD = alwaysAboveHorizon ? ComputeOzoneOpticalDepth(R, r, cosTheta, ozoneMinimumAltitude, ozoneLayerWidth) : 0.0f;

        Vector3 airExtinction = airExtinctionCoefficient;
        float aerosolExtinction = aerosolExtinctionCoefficient;
        Vector3 ozoneExtinction = ozoneExtinctionCoefficient;

        return new Vector3(optDepth.x * airExtinction.x + optDepth.y * aerosolExtinction + ozoneOD * ozoneExtinction.x,
            optDepth.x * airExtinction.y + optDepth.y * aerosolExtinction + ozoneOD * ozoneExtinction.y,
            optDepth.x * airExtinction.z + optDepth.y * aerosolExtinction + ozoneOD * ozoneExtinction.z);
    }

    // Computes transmittance along the light path segment.
    public static Vector3 EvaluateAtmosphericAttenuation(
        float airScaleHeight, float aerosolScaleHeight, in Vector3 airExtinctionCoefficient, float aerosolExtinctionCoefficient,
        float ozoneMinimumAltitude, float ozoneLayerWidth, Vector3 ozoneExtinctionCoefficient,
        in Vector3 C, float R, in Vector3 L, in Vector3 X)
    {
        float r = Vector3.Distance(X, C);
        float cosHoriz = ComputeCosineOfHorizonAngle(r, R);
        float cosTheta = Vector3.Dot(X - C, L) * Rcp(r);

        if (cosTheta > cosHoriz) // Above horizon
        {
            Vector3 oDepth = ComputeAtmosphericOpticalDepth(
                airScaleHeight, aerosolScaleHeight, airExtinctionCoefficient, aerosolExtinctionCoefficient,
                ozoneMinimumAltitude, ozoneLayerWidth, ozoneExtinctionCoefficient,
                R, r, cosTheta, true);

            Vector3 transm;

            transm.x = Mathf.Exp(-oDepth.x);
            transm.y = Mathf.Exp(-oDepth.y);
            transm.z = Mathf.Exp(-oDepth.z);

            return transm;
        }
        else
        {
            return Vector3.zero;
        }
    }

    #region PBSkyUtils
    float3 AirScatter(float height)
    {
        return GetAirScatteringCoefficient() * exp(-height * rcp(GetAirScaleHeight()));
    }

    static float AirPhase(float LdotV)
    {
        return RayleighPhaseFunction(-LdotV);
    }

    float3 AerosolScatter(float height)
    {
        return GetAerosolScatteringCoefficient() * exp(-height * rcp(GetAerosolScaleHeight()));
    }

    float AerosolPhase(float LdotV)
    {
        return CornetteShanksPhasePartConstant(aerosolAnisotropy.value) * CornetteShanksPhasePartVarying(aerosolAnisotropy.value, -LdotV);
    }

    float OzoneDensity(float height)
    {
        float2 ozoneScaleOffset = float2(2.0f / GetOzoneLayerWidth(), -2.0f * GetOzoneLayerMinimumAltitude() / GetOzoneLayerWidth() - 1.0f);
        return saturate(1 - abs(height * ozoneScaleOffset.x + ozoneScaleOffset.y));
    }

    // This is a very crude approximation, should be reworked
    // It estimates the result by integrating with 4 samples
    float ComputeOzoneOpticalDepth(float r, float cosTheta, float distAlongRay)
    {
        float R = PlanetaryRadius();
        float rcpR = rcp(R);

        float2 tInner = IntersectSphere(R + GetOzoneLayerMinimumAltitude(), cosTheta, r, rcpR);
        float2 tOuter = IntersectSphere(R + GetOzoneLayerMinimumAltitude() + GetOzoneLayerWidth(), cosTheta, r, rcpR);
        float tEntry, tEntry2, tExit, tExit2;

        if (tInner.x < 0.0 && tInner.y >= 0.0) // Below the lower bound
        {
            // The ray starts at the intersection with the lower bound and ends at the intersection with the outer bound
            tEntry = tInner.y;
            tExit2 = tOuter.y;
            tEntry2 = tExit = (tExit2 - tEntry) * 0.5f;
        }
        else // Inside or above the volume
        {
            // The ray starts at the intersection with the outer bound, or at 0 if we are inside
            // The ray ends at the lower bound if we hit it, at the outer bound otherwise
            tEntry = max(tOuter.x, 0.0f);
            tExit = tInner.x >= 0.0 ? tInner.x : tOuter.y;

            // If we hit the lower bound, we may intersect the volume a second time
            if (tInner.x >= 0.0 && distAlongRay > tInner.y)
            {
                tEntry2 = tInner.y;
                tExit2 = tOuter.y;
            }
            else
            {
                tExit2 = tExit;
                tEntry2 = tExit = (tExit2 - tEntry) * 0.5f;
            }
        }

        tExit = min(tExit, distAlongRay);
        tExit2 = min(tExit2, distAlongRay);

        float ozoneOD = 0.0f;
        const uint count = 2;
        float dt = max(tExit - tEntry, 0) * rcp(count);
        float dt2 = max(tExit2 - tEntry2, 0) * rcp(count);

        for (uint i = 0; i < count; i++)
        {
            float t = lerp(tEntry, tExit, (i + 0.5f) * rcp(count));
            float t2 = lerp(tEntry2, tExit2, (i + 0.5f) * rcp(count));
            float h = sqrt(r * r + t * (2 * r * cosTheta + t)) - R;
            float h2 = sqrt(r * r + t2 * (2 * r * cosTheta + t2)) - R;

            ozoneOD += OzoneDensity(h) * dt;
            ozoneOD += OzoneDensity(h2) * dt2;
        }

        return ozoneOD * 0.6f;
    }

    float3 ComputeAtmosphericOpticalDepth(float r, float cosTheta, bool aboveHorizon)
    {
        float2 n = float2(rcp(GetAirScaleHeight()), rcp(GetAerosolScaleHeight()));
        float2 H = float2(GetAirScaleHeight(), GetAerosolScaleHeight());
        float R = PlanetaryRadius();

        float2 z = n * r;
        float2 Z = n * R;

        float sinTheta = sqrt(saturate(1 - cosTheta * cosTheta));

        float2 ch;
        ch.x = ChapmanUpperApprox(z.x, abs(cosTheta)) * exp(Z.x - z.x); // Rescaling adds 'exp'
        ch.y = ChapmanUpperApprox(z.y, abs(cosTheta)) * exp(Z.y - z.y); // Rescaling adds 'exp'

        if (!aboveHorizon) // Below horizon, intersect sphere
        {
            float sinGamma = (r / R) * sinTheta;
            float cosGamma = sqrt(saturate(1 - sinGamma * sinGamma));

            float2 ch_2;
            ch_2.x = ChapmanUpperApprox(Z.x, cosGamma); // No need to rescale
            ch_2.y = ChapmanUpperApprox(Z.y, cosGamma); // No need to rescale

            ch = ch_2 - ch;
        }
        else if (cosTheta < 0)   // Above horizon, lower hemisphere
        {
            // z_0 = n * r_0 = (n * r) * sin(theta) = z * sin(theta).
            // Ch(z, theta) = 2 * exp(z - z_0) * Ch(z_0, Pi/2) - Ch(z, Pi - theta).
            float2 z_0 = z * sinTheta;
            float2 b = exp(Z - z_0); // Rescaling cancels out 'z' and adds 'Z'
            float2 a;
            a.x = 2 * ChapmanHorizontal(z_0.x);
            a.y = 2 * ChapmanHorizontal(z_0.y);
            float2 ch_2 = a * b;

            ch = ch_2 - ch;
        }

        float ozone = aboveHorizon ? ComputeOzoneOpticalDepth(r, cosTheta, float.MaxValue) : 0.0f;
        float3 optDepth = float3(ch * H, ozone);

        return optDepth.x * float3(GetAirExtinctionCoefficient())
            + optDepth.y * GetAerosolExtinctionCoefficient()
            + optDepth.z * float3(GetOzoneExtinctionCoefficient());
    }

    static float RayleighPhaseFunction(float cosTheta)
    {
        float k = 3 / (16 * PI);
        return k * (1 + cosTheta * cosTheta);
    }

    // Similar to the RayleighPhaseFunction.
    static float CornetteShanksPhasePartSymmetrical(float cosTheta)
    {
        float h = 1 + cosTheta * cosTheta;
        return h;
    }

    static float CornetteShanksPhasePartAsymmetrical(float anisotropy, float cosTheta)
    {
        float g = anisotropy;
        float x = 1 + g * g - 2 * g * cosTheta;
        float f = rsqrt(max(x, EPSILON)); // x^(-1/2)
        return f * f * f;                 // x^(-3/2)
    }

    static float CornetteShanksPhasePartVarying(float anisotropy, float cosTheta)
    {
        return CornetteShanksPhasePartSymmetrical(cosTheta) *
               CornetteShanksPhasePartAsymmetrical(anisotropy, cosTheta); // h * x^(-3/2)
    }

    static float CornetteShanksPhasePartConstant(float anisotropy)
    {
        float g = anisotropy;

        return (3.0f / (8.0f * Mathf.PI)) * (1.0f - g * g) / (2.0f + g * g);
    }

    static float2 ComputeExponentialInterpolationParams(float k)
    {
        if (k == 0) k = 1e-6f; // Avoid the numerical explosion around 0

        // Remap t: (exp(10 k t) - 1) / (exp(10 k) - 1) = exp(x t) y - y.
        float x = 10 * k;
        float y = 1 / (exp(x) - 1);

        return float2(x, y);
    }

    float3 IntegrateOverSegment(float3 S, float3 transmittanceOverSegment, float3 transmittance, float3 sigmaE)
    {
        // https://www.shadertoy.com/view/XlBSRz

        // See slide 28 at http://www.frostbite.com/2015/08/physically-based-unified-volumetric-rendering-in-frostbite
        // Assumes homogeneous medium along the interval

        float3 Sint = (S - S * transmittanceOverSegment) / sigmaE;    // integrate along the current step segment
        return transmittance * Sint; // accumulate and also take into account the transmittance from previous steps
    }

    static void GetSample(uint s, uint sampleCount, float tExit, out float t, out float dt)
    {
        //dt = tMax / sampleCount;
        //t += dt;

        float t0 = (s) / (float)sampleCount;
        float t1 = (s + 1.0f) / (float)sampleCount;

        // Non linear distribution of sample within the range.
        t0 = t0 * t0 * tExit;
        t1 = t1 * t1 * tExit;

        t = lerp(t0, t1, 0.5f); // 0.5 gives the closest result to reference
        dt = t1 - t0;
    }

    static float PlanetaryRadius()
    {
        return 6378100.0f;
    }

    static float3 PlanetaryRadiusCenter()
    {
        return float3(0.0f, -PlanetaryRadius(), 0.0f);
    }

    float3 AtmosphereExtinction(float height)
    {
        float densityMie = exp(-height * rcp(GetAerosolScaleHeight()));
        float densityRayleigh = exp(-height * rcp(GetAirScaleHeight()));

        float2 ozoneScaleOffset = float2(2.0f / GetOzoneLayerWidth(), -2.0f * GetOzoneLayerMinimumAltitude() / GetOzoneLayerWidth() - 1.0f);
        float densityOzone = OzoneDensity(height, ozoneScaleOffset);

        float3 extinction = densityMie * GetAerosolExtinctionCoefficient()
                          + densityRayleigh * float3(GetAirExtinctionCoefficient())
                          + densityOzone * float3(GetOzoneExtinctionCoefficient());

        return max(extinction, FLT_MIN_NORMAL);
    }

    float3 TransmittanceFromOpticalDepth(float3 opticalDepth)
    {
        return exp(-opticalDepth);
    }

    static float Avg3(float a, float b, float c)
    {
        return (a + b + c) * 0.33333333f;
    }

    static float3 Desaturate(float3 value, float3 saturation)
    {
        // Saturation = Colorfulness / Brightness.
        // https://munsell.com/color-blog/difference-chroma-saturation/
        float mean = Avg3(value.x, value.y, value.z);
        float3 dev = value - mean;

        return mean + dev * saturation;
    }

    float3 EvaluateSunColorAttenuation(float3 positionPS, float3 sunDirection, bool estimatePenumbra = false)
    {
        float r = length(positionPS);
        float cosTheta = dot(positionPS, sunDirection) * rcp(r); // Normalize

        // Point can be below horizon due to precision issues
        float R = PlanetaryRadius();
        r = max(r, R);
        float cosHoriz = ComputeCosineOfHorizonAngle(r, R);

        if (cosTheta >= cosHoriz) // Above horizon
        {
            float3 oDepth = ComputeAtmosphericOpticalDepth(r, cosTheta, true);
            float3 opacity = 1 - TransmittanceFromOpticalDepth(oDepth);
            float penumbra = saturate((cosTheta - cosHoriz) / 0.0019f); // very scientific value
            float3 attenuation = 1 - (Desaturate(opacity, alphaSaturation.value) * alphaMultiplier.value);
            return estimatePenumbra ? attenuation * penumbra : attenuation;
        }
        else
        {
            return 0;
        }
    }

    void EvaluateAtmosphericColor(float3 L, float3 lightColor, float3 O, float3 V, float tExit,
                out float3 skyColor, out float3 skyTransmittance)
    {
        skyColor = 0.0f;
        skyTransmittance = 1.0f;

        const uint sampleCount = 4;

        for (uint s = 0; s < sampleCount; s++)
        {
            GetSample(s, sampleCount, tExit, out float t, out float dt);

            float3 P = O + t * V;
            float  r = max(length(P), PlanetaryRadius());
            float3 N = P * rcp(r);
            float  height = r - PlanetaryRadius();

            float3 sigmaE       = AtmosphereExtinction(height);
            //float3 scatteringMS = AirScatter(height) + AerosolScatter(height);
            float3 transmittanceOverSegment = TransmittanceFromOpticalDepth(sigmaE * dt);

            /*
            for (uint i = 0; i < _CelestialLightCount; i++)
            {
                CelestialBodyData light = _CelestialBodyDatas[i];
                float3 L = -light.forward.xyz;

                const float3 sunTransmittance = EvaluateSunColorAttenuation(dot(N, L), r);
                const float3 phaseScatter = AirScatter(height) * AirPhase(-dot(L, V)) + AerosolScatter(height) * AerosolPhase(-dot(L, V));
                const float3 multiScatteredLuminance = EvaluateMultipleScattering(dot(N, L), height);

                float3 S = sunTransmittance * phaseScatter + multiScatteredLuminance * scatteringMS;
                skyColor += IntegrateOverSegment(light.color * S, transmittanceOverSegment, skyTransmittance, sigmaE);
            }
            */

            {
                //CelestialBodyData light = GetCelestialBody();
                //float3 L          = -light.forward.xyz;

                float3 sunTransmittance = EvaluateSunColorAttenuation(dot(N, L), r);
                float3 phaseScatter = AirScatter(height) * AirPhase(-dot(L, V)) + AerosolScatter(height) * AerosolPhase(-dot(L, V));
                //float3 multiScatteredLuminance = EvaluateMultipleScattering(dot(N, L), height);

                float3 S = sunTransmittance * phaseScatter;// + multiScatteredLuminance * scatteringMS;
                skyColor += IntegrateOverSegment(lightColor * S, transmittanceOverSegment, skyTransmittance, sigmaE);
            }

            skyTransmittance *= transmittanceOverSegment;
        }
    }

    float3 ExpLerp(float3 A, float3 B, float t, float x, float y)
    {
        // Remap t: (exp(10 k t) - 1) / (exp(10 k) - 1) = exp(x t) y - y.
        t = exp(x * t) * y - y;
        // Perform linear interpolation using the new value of t.
        return lerp(A, B, t);
    }

    void AtmosphereArtisticOverride(float cosHor, float cosChi, ref float3 skyColor, ref float3 skyOpacity, bool precomputedColorDesaturate = false)
    {
        if (!precomputedColorDesaturate)
            skyColor = Desaturate(skyColor, colorSaturation.value);
        skyOpacity = Desaturate(skyOpacity, alphaSaturation.value) * alphaMultiplier.value;

        float horAngle = acos(cosHor);
        float chiAngle = acos(cosChi);

        // [start, end] -> [0, 1] : (x - start) / (end - start) = x * rcpLength - (start * rcpLength)
        // TEMPLATE_3_REAL(Remap01, x, rcpLength, startTimesRcpLength, return saturate(x * rcpLength - startTimesRcpLength))
        float start = horAngle;
        float end = 0;
        //float rcpLen = rcp(end - start);
        //float nrmAngle = Remap01(chiAngle, rcpLen, start * rcpLen);
        float nrmAngle = remap(start, end, 0, 1, chiAngle);
        // float angle = saturate((0.5 * PI) - acos(cosChi) * rcp(0.5 * PI));

        float2 expParams = ComputeExponentialInterpolationParams(horizonZenithShift.value);

        skyColor *= ExpLerp(float3(horizonTint.value.r, horizonTint.value.g, horizonTint.value.b), float3(zenithTint.value.r, zenithTint.value.g, zenithTint.value.b), nrmAngle, expParams.x, expParams.y);
    }

    /// <summary>
    /// Evaluates the simplified camera space version of physically based sky on the CPU.
    /// </summary>
    /// <param name="lightDirection">The normalized direction of the sun in world space.</param>
    /// <param name="lightColor">The color and intensity of the sun.</param>
    /// <param name="viewDirection">The view direction in world space.</param>
    /// <param name="skyColor">The color of physically based sky.</param>
    /// <param name="skyOpacity">The opacity of physically based sky.</param>
    public void RenderSky(float3 lightDirection, float3 lightColor, float3 viewDirection, out float3 skyColor, out float3 skyOpacity)
    {
        float3 positionPS = -PlanetaryRadiusCenter();
        float cosHor = ComputeCosineOfHorizonAngle(length(positionPS), PlanetaryRadius());
        float cosChi = viewDirection.y;

        bool lookAboveHorizon = (cosChi >= cosHor);

        float3 optDepth = ComputeAtmosphericOpticalDepth(
                GetAirScaleHeight(), GetAerosolScaleHeight(), GetAirExtinctionCoefficient(), GetAerosolExtinctionCoefficient(),
                GetOzoneLayerMinimumAltitude(), GetOzoneLayerWidth(), GetOzoneExtinctionCoefficient(),
                PlanetaryRadius(), PlanetaryRadius(), cosChi, true);
        skyOpacity = 1.0f - TransmittanceFromOpticalDepth(optDepth);

        float3 N = float3(0.0f, 1.0f, 0.0f);
        float r = PlanetaryRadius();
        float3 O = r * N;

        if (lookAboveHorizon)
        {
            float tExit = IntersectSphere(r + GetMaximumAltitude(), dot(N, viewDirection), r, rcp(r)).y;
            EvaluateAtmosphericColor(lightDirection, lightColor, O, viewDirection, tExit,
                    out skyColor, out _);

            AtmosphereArtisticOverride(cosHor, cosChi, ref skyColor, ref skyOpacity);
        }
        else
        {
            float3 gBrdf = rcp(PI) * float3(groundTint.value.r, groundTint.value.g, groundTint.value.b);
            skyColor = gBrdf * saturate(dot(N, lightDirection)) * lightColor;
        }

        skyColor *= GetIntensityFromSettings();
    }

    #endregion
}