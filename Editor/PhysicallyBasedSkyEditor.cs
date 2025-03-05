using System;
using UnityEditor;
using UnityEditor.Rendering;
using UnityEngine;

[CanEditMultipleObjects]
#if UNITY_2022_2_OR_NEWER
[CustomEditor(typeof(PhysicallyBasedSky))]
#else
[VolumeComponentEditor(typeof(PhysicallyBasedSky))]
#endif
class PhysicallyBasedSkyEditor : VolumeComponentEditor
{
    SerializedDataParameter m_Type;
    SerializedDataParameter m_AtmosphericScattering;
    //SerializedDataParameter m_Mode;
    //SerializedDataParameter m_Material;
    SerializedDataParameter m_PlanetRotation;
    SerializedDataParameter m_GroundColorTexture;
    SerializedDataParameter m_GroundTint;
    SerializedDataParameter m_GroundEmissionTexture;
    SerializedDataParameter m_GroundEmissionMultiplier;

    SerializedDataParameter m_SpaceRotation;
    SerializedDataParameter m_SpaceEmissionTexture;
    SerializedDataParameter m_SpaceEmissionMultiplier;

    SerializedDataParameter m_AirMaximumAltitude;
    SerializedDataParameter m_AirDensityR;
    SerializedDataParameter m_AirDensityG;
    SerializedDataParameter m_AirDensityB;
    SerializedDataParameter m_AirTint;

    SerializedDataParameter m_AerosolMaximumAltitude;
    SerializedDataParameter m_AerosolDensity;
    SerializedDataParameter m_AerosolTint;
    SerializedDataParameter m_AerosolAnisotropy;

    SerializedDataParameter m_OzoneDensity;
    SerializedDataParameter m_OzoneMinimumAltitude;
    SerializedDataParameter m_OzoneLayerWidth;

    SerializedDataParameter m_ColorSaturation;
    SerializedDataParameter m_AlphaSaturation;
    SerializedDataParameter m_AlphaMultiplier;
    SerializedDataParameter m_HorizonTint;
    SerializedDataParameter m_ZenithTint;
    SerializedDataParameter m_HorizonZenithShift;

    SerializedDataParameter m_SkyExposure;
    SerializedDataParameter m_SkyMultiplier;
    //SerializedDataParameter m_SkyRotation;
    //SerializedDataParameter m_EnvUpdateMode;
    //SerializedDataParameter m_EnvUpdatePeriod;
    //SerializedDataParameter m_IncludeSunInBaking;
    SerializedDataParameter m_DesiredLuxValue;
    SerializedDataParameter m_IntensityMode;
    SerializedDataParameter m_UpperHemisphereLuxValue;

    GUIContent[] m_ModelTypes = { new GUIContent("Earth (Simple)"), new GUIContent("Earth (Advanced)"), new GUIContent("Custom Planet") };
    int[] m_ModelTypeValues = { (int)PhysicallyBasedSky.PhysicallyBasedSkyModel.EarthSimple, (int)PhysicallyBasedSky.PhysicallyBasedSkyModel.EarthAdvanced, (int)PhysicallyBasedSky.PhysicallyBasedSkyModel.Custom };

    static public readonly GUIContent k_NewMaterialButtonText = EditorGUIUtility.TrTextContent("New", "Creates a new Physically Based Sky Material asset template.");
    static public readonly GUIContent k_CustomMaterial = EditorGUIUtility.TrTextContent("Material", "Sets a custom material that will be used to render the PBR Sky. If set to None, the default Rendering Mode is used.");

    /// <summary>
    /// Enum used to determine which comme sky UI elements needs to be displayed.
    /// </summary>
    [Flags]
    protected enum SkySettingsUIElement
    {
        /// <summary>Sky Intensity UI element.</summary>
        SkyIntensity = 1 << 0,
        /// <summary>Rotation UI element.</summary>
        Rotation = 1 << 1,
        /// <summary>Update Mode UI element.</summary>
        UpdateMode = 1 << 2,
        /// <summary>Include Sun in Baking UI element.</summary>
        IncludeSunInBaking = 1 << 3,
    }

    /// <summary>
    /// Mask of SkySettingsUIElement used to choose which common UI elements are displayed.
    /// </summary>
    protected uint m_CommonUIElementsMask = 0xFFFFFFFF;
    /// <summary>
    /// Set to true if your custom sky editor should enable the Lux Intensity mode.
    /// </summary>
    protected bool m_EnableLuxIntensityMode = false;

    GUIContent[] m_IntensityModes = { new GUIContent("Exposure"), new GUIContent("Multiplier"), new GUIContent("Lux") };
    int[] m_IntensityModeValues = { (int)PhysicallyBasedSky.SkyIntensityMode.Exposure, (int)PhysicallyBasedSky.SkyIntensityMode.Multiplier, (int)PhysicallyBasedSky.SkyIntensityMode.Lux };
    GUIContent[] m_IntensityModesNoLux = { new GUIContent("Exposure"), new GUIContent("Multiplier") };
    int[] m_IntensityModeValuesNoLux = { (int)PhysicallyBasedSky.SkyIntensityMode.Exposure, (int)PhysicallyBasedSky.SkyIntensityMode.Multiplier };

    GUIContent m_SkyIntensityModeLabel = new GUIContent("Intensity Mode");
    GUIContent m_ExposureCompensationLabel = new GUIContent("Exposure Compensation", "Sets the exposure compensation of the sky in EV.");

    static public readonly string k_NewSkyMaterialText = "Physically Based Sky";

    public override void OnEnable()
    {
        base.OnEnable();

        var o = new PropertyFetcher<PhysicallyBasedSky>(serializedObject);

        m_Type = Unpack(o.Find(x => x.type));
        m_AtmosphericScattering = Unpack(o.Find(x => x.atmosphericScattering));
        //m_Mode = Unpack(o.Find(x => x.renderingMode));
        //m_Material = Unpack(o.Find(x => x.material));
        m_PlanetRotation = Unpack(o.Find(x => x.planetRotation));
        m_GroundColorTexture = Unpack(o.Find(x => x.groundColorTexture));
        m_GroundTint = Unpack(o.Find(x => x.groundTint));
        m_GroundEmissionTexture = Unpack(o.Find(x => x.groundEmissionTexture));
        m_GroundEmissionMultiplier = Unpack(o.Find(x => x.groundEmissionMultiplier));

        m_SpaceRotation = Unpack(o.Find(x => x.spaceRotation));
        m_SpaceEmissionTexture = Unpack(o.Find(x => x.spaceEmissionTexture));
        m_SpaceEmissionMultiplier = Unpack(o.Find(x => x.spaceEmissionMultiplier));

        m_AirMaximumAltitude = Unpack(o.Find(x => x.airMaximumAltitude));
        m_AirDensityR = Unpack(o.Find(x => x.airDensityR));
        m_AirDensityG = Unpack(o.Find(x => x.airDensityG));
        m_AirDensityB = Unpack(o.Find(x => x.airDensityB));
        m_AirTint = Unpack(o.Find(x => x.airTint));

        m_AerosolMaximumAltitude = Unpack(o.Find(x => x.aerosolMaximumAltitude));
        m_AerosolDensity = Unpack(o.Find(x => x.aerosolDensity));
        m_AerosolTint = Unpack(o.Find(x => x.aerosolTint));
        m_AerosolAnisotropy = Unpack(o.Find(x => x.aerosolAnisotropy));

        m_OzoneDensity = Unpack(o.Find(x => x.ozoneDensityDimmer));
        m_OzoneMinimumAltitude = Unpack(o.Find(x => x.ozoneMinimumAltitude));
        m_OzoneLayerWidth = Unpack(o.Find(x => x.ozoneLayerWidth));

        m_ColorSaturation = Unpack(o.Find(x => x.colorSaturation));
        m_AlphaSaturation = Unpack(o.Find(x => x.alphaSaturation));
        m_AlphaMultiplier = Unpack(o.Find(x => x.alphaMultiplier));
        m_HorizonTint = Unpack(o.Find(x => x.horizonTint));
        m_ZenithTint = Unpack(o.Find(x => x.zenithTint));
        m_HorizonZenithShift = Unpack(o.Find(x => x.horizonZenithShift));

        m_SkyExposure = Unpack(o.Find(x => x.exposure));
        m_SkyMultiplier = Unpack(o.Find(x => x.multiplier));
        //m_SkyRotation = Unpack(o.Find(x => x.rotation));
        //m_EnvUpdateMode = Unpack(o.Find(x => x.updateMode));
        //m_EnvUpdatePeriod = Unpack(o.Find(x => x.updatePeriod));
        //m_IncludeSunInBaking = Unpack(o.Find(x => x.includeSunInBaking));
        m_DesiredLuxValue = Unpack(o.Find(x => x.desiredLuxValue));
        m_IntensityMode = Unpack(o.Find(x => x.skyIntensityMode));
        m_UpperHemisphereLuxValue = Unpack(o.Find(x => x.upperHemisphereLuxValue));
    }

    void ModelTypeField(SerializedDataParameter property)
    {
        var title = EditorGUIUtility.TrTextContent(property.displayName,
            property.GetAttribute<TooltipAttribute>()?.tooltip);

        using (var scope = new OverridablePropertyScope(property, title, this))
        {
            if (!scope.displayed)
                return;

            var rect = EditorGUILayout.GetControlRect();
            EditorGUI.BeginProperty(rect, title, property.value);

            EditorGUI.BeginChangeCheck();
            var value = EditorGUI.IntPopup(rect, title, property.value.intValue, m_ModelTypes, m_ModelTypeValues);
            if (EditorGUI.EndChangeCheck())
                property.value.intValue = value;

            EditorGUI.EndProperty();
        }
    }

    public override void OnInspectorGUI()
    {

        DrawHeader("Model");

        ModelTypeField(m_Type);
        PropertyField(m_AtmosphericScattering);

        //DrawHeader("Planet and Space");
        const bool hasMaterial = false;

        /*
        PropertyField(m_Mode);
        const bool hasMaterial = false;// m_Mode.value.intValue == 1;
        if (hasMaterial)
        {
            using (new IndentLevelScope())
            {
                MaterialFieldWithButton(m_Material, k_CustomMaterial);
            }

        }
        */

        DrawHeader("Planet");

        PhysicallyBasedSky.PhysicallyBasedSkyModel type = (PhysicallyBasedSky.PhysicallyBasedSkyModel)m_Type.value.intValue;
        if (type != PhysicallyBasedSky.PhysicallyBasedSkyModel.EarthSimple && !hasMaterial)
        {
            PropertyField(m_PlanetRotation);
            PropertyField(m_GroundColorTexture);
        }

        //ColorFieldLinear(m_GroundTint);
        PropertyField(m_GroundTint);

        if (type != PhysicallyBasedSky.PhysicallyBasedSkyModel.EarthSimple && !hasMaterial)
        {
            PropertyField(m_GroundEmissionTexture);
            PropertyField(m_GroundEmissionMultiplier);
        }

        if (type != PhysicallyBasedSky.PhysicallyBasedSkyModel.EarthSimple && !hasMaterial)
        {
            DrawHeader("Space");
            PropertyField(m_SpaceRotation);
            PropertyField(m_SpaceEmissionTexture);
            PropertyField(m_SpaceEmissionMultiplier);
        }

        if (type == PhysicallyBasedSky.PhysicallyBasedSkyModel.Custom)
        {
            DrawHeader("Air");
            PropertyField(m_AirMaximumAltitude);
            PropertyField(m_AirDensityR);
            PropertyField(m_AirDensityG);
            PropertyField(m_AirDensityB);
            PropertyField(m_AirTint);
        }

        DrawHeader("Aerosols");
        PropertyField(m_AerosolDensity);
        PropertyField(m_AerosolTint);
        PropertyField(m_AerosolAnisotropy);
        if (type != PhysicallyBasedSky.PhysicallyBasedSkyModel.EarthSimple)
            PropertyField(m_AerosolMaximumAltitude);

        if (type != PhysicallyBasedSky.PhysicallyBasedSkyModel.EarthSimple)
        {
            DrawHeader("Ozone");
            PropertyField(m_OzoneDensity);
            if (type == PhysicallyBasedSky.PhysicallyBasedSkyModel.Custom)
            {
                PropertyField(m_OzoneMinimumAltitude);
                PropertyField(m_OzoneLayerWidth);
            }
        }

        EditorGUILayout.Space();
        DrawHeader("Artistic Overrides");
        PropertyField(m_ColorSaturation);
        PropertyField(m_AlphaSaturation);
        PropertyField(m_AlphaMultiplier);
        PropertyField(m_HorizonTint);
        PropertyField(m_HorizonZenithShift);
        PropertyField(m_ZenithTint);

        EditorGUILayout.Space();
        DrawHeader("Miscellaneous");

        using (var scope = new OverridablePropertyScope(m_IntensityMode, m_SkyIntensityModeLabel, this))
        {
            if (scope.displayed)
            {
                var rect = EditorGUILayout.GetControlRect();
                EditorGUI.BeginProperty(rect, m_SkyIntensityModeLabel, m_IntensityMode.value);
                if (m_EnableLuxIntensityMode)
                    m_IntensityMode.value.intValue = EditorGUI.IntPopup(rect, m_SkyIntensityModeLabel, (int)m_IntensityMode.value.intValue, m_IntensityModes, m_IntensityModeValues);
                else
                    m_IntensityMode.value.intValue = EditorGUI.IntPopup(rect, m_SkyIntensityModeLabel, (int)m_IntensityMode.value.intValue, m_IntensityModesNoLux, m_IntensityModeValuesNoLux);
                EditorGUI.EndProperty();
            }
        }

        using (new IndentLevelScope())
        {
            if (m_IntensityMode.value.GetEnumValue<PhysicallyBasedSky.SkyIntensityMode>() == PhysicallyBasedSky.SkyIntensityMode.Exposure)
                PropertyField(m_SkyExposure, m_ExposureCompensationLabel);
            else if (m_IntensityMode.value.GetEnumValue<PhysicallyBasedSky.SkyIntensityMode>() == PhysicallyBasedSky.SkyIntensityMode.Multiplier)
                PropertyField(m_SkyMultiplier);
            else if (m_IntensityMode.value.GetEnumValue<PhysicallyBasedSky.SkyIntensityMode>() == PhysicallyBasedSky.SkyIntensityMode.Lux)
            {
                PropertyField(m_DesiredLuxValue);

                // Show the multiplier
                EditorGUILayout.HelpBox(String.Format(
                    "Upper hemisphere lux value: {0}\nAbsolute multiplier: {1}",
                    m_UpperHemisphereLuxValue.value.floatValue,
                    (m_DesiredLuxValue.value.floatValue / m_UpperHemisphereLuxValue.value.floatValue)
                    ), MessageType.Info);
            }
        }
    }
}
