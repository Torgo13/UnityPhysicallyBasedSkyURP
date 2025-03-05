using UnityEditor;
using UnityEditor.Rendering;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

[CanEditMultipleObjects]
#if UNITY_2022_2_OR_NEWER
[CustomEditor(typeof(Fog))]
#else
[VolumeComponentEditor(typeof(Fog))]
#endif
class FogEditor : VolumeComponentEditor
{
    SerializedDataParameter m_Enabled;
    SerializedDataParameter m_MaxFogDistance;
    SerializedDataParameter m_ColorMode;
    SerializedDataParameter m_Color;
    SerializedDataParameter m_Tint;
    SerializedDataParameter m_MipFogNear;
    SerializedDataParameter m_MipFogFar;
    SerializedDataParameter m_MipFogMaxMip;
    //SerializedDataParameter m_Albedo;
    SerializedDataParameter m_MeanFreePath;
    SerializedDataParameter m_BaseHeight;
    SerializedDataParameter m_MaximumHeight;

    //SerializedDataParameter m_Anisotropy;
    //SerializedDataParameter m_MultipleScatteringIntensity;
    
    SerializedDataParameter m_UnderWater;
    SerializedDataParameter m_WaterHeight;

    static GUIContent s_Enabled = new GUIContent("State", "When set to Enabled, URP renders fog in your scene.");
    //static GUIContent s_AlbedoLabel = new GUIContent("Albedo", "Specifies the color this fog scatters light to.");
    static GUIContent s_MeanFreePathLabel = new GUIContent("Fog Attenuation Distance", "Controls the density at the base level (per color channel). Distance at which fog reduces background light intensity by 63%. Units: m.");
    static GUIContent s_BaseHeightLabel = new GUIContent("Base Height", "Reference height (e.g. sea level). Sets the height of the boundary between the constant and exponential fog. Units: m.");
    static GUIContent s_MaximumHeightLabel = new GUIContent("Maximum Height", "Max height of the fog layer. Controls the rate of height-based density falloff. Units: m.");

    public override void OnEnable()
    {
        var o = new PropertyFetcher<Fog>(serializedObject);

        m_Enabled = Unpack(o.Find(x => x.enabled));
        m_MaxFogDistance = Unpack(o.Find(x => x.maxFogDistance));

        // Fog Color
        m_ColorMode = Unpack(o.Find(x => x.colorMode));
        m_Color = Unpack(o.Find(x => x.color));
        m_Tint = Unpack(o.Find(x => x.tint));
        m_MipFogNear = Unpack(o.Find(x => x.mipFogNear));
        m_MipFogFar = Unpack(o.Find(x => x.mipFogFar));
        m_MipFogMaxMip = Unpack(o.Find(x => x.mipFogMaxMip));
        //m_Albedo = Unpack(o.Find(x => x.albedo));
        m_MeanFreePath = Unpack(o.Find(x => x.meanFreePath));
        m_BaseHeight = Unpack(o.Find(x => x.baseHeight));
        m_MaximumHeight = Unpack(o.Find(x => x.maximumHeight));
        //m_Anisotropy = Unpack(o.Find(x => x.anisotropy));
        //m_MultipleScatteringIntensity = Unpack(o.Find(x => x.multipleScatteringIntensity));

        m_UnderWater = Unpack(o.Find(x => x.underWater));
        m_WaterHeight = Unpack(o.Find(x => x.waterHeight));

        base.OnEnable();

    }

    public override void OnInspectorGUI()
    {
        //var urpAsset = GraphicsSettings.currentRenderPipeline as UniversalRenderPipelineAsset;

        PropertyField(m_Enabled, s_Enabled);

        PropertyField(m_MeanFreePath, s_MeanFreePathLabel);
        PropertyField(m_BaseHeight, s_BaseHeightLabel);
        PropertyField(m_MaximumHeight, s_MaximumHeightLabel);
        PropertyField(m_MaxFogDistance);

        if (m_MaximumHeight.value.floatValue < m_BaseHeight.value.floatValue)
        {
            m_MaximumHeight.value.floatValue = m_BaseHeight.value.floatValue;
            serializedObject.ApplyModifiedProperties();
        }

        PropertyField(m_ColorMode);

        using (new IndentLevelScope())
        {
            if (!m_ColorMode.value.hasMultipleDifferentValues &&
                (Fog.FogColorMode)m_ColorMode.value.intValue == Fog.FogColorMode.ConstantColor)
            {
                PropertyField(m_Color);
            }
            else
            {
                PropertyField(m_Tint);
                PropertyField(m_MipFogNear);
                PropertyField(m_MipFogFar);
                PropertyField(m_MipFogMaxMip);
            }
        }

        //PropertyField(m_MultipleScatteringIntensity);

        PropertyField(m_UnderWater);
        using (new EditorGUI.DisabledScope(!m_UnderWater.overrideState.boolValue))
        {
            using (new IndentLevelScope())
            {
                if (m_UnderWater.value.boolValue)
                    PropertyField(m_WaterHeight);
            }
        }
    }
}
