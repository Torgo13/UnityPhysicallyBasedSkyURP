using System;
using System.Reflection;
using System.Collections.Generic;
using UnityEditor;
using UnityEditor.Rendering;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

[CanEditMultipleObjects]
#if UNITY_2022_2_OR_NEWER
[CustomEditor(typeof(VisualEnvironment))]
#else
[VolumeComponentEditor(typeof(VisualEnvironment))]
#endif
class VisualEnvironmentEditor : VolumeComponentEditor
{
    SerializedDataParameter m_SkyType;
    //SerializedDataParameter m_CloudType;
    SerializedDataParameter m_SkyAmbientMode;

    SerializedDataParameter m_PlanetRadius;
    SerializedDataParameter m_RenderingSpace;
    SerializedDataParameter m_CenterMode;
    SerializedDataParameter m_PlanetCenter;

    //SerializedDataParameter m_WindOrientation;
    //SerializedDataParameter m_WindSpeed;

    SerializedDataParameter m_CustomSkyMaterial;

    const string k_UniversalForward = "Universal Forward";

    const string k_CustomSkyShaderGraphMessage = "It looks like the \"Sky Material\" is using a shader graph. Please ensure that the \"Render Face\" setting is set to \"Both\".";

    const string k_EmptyCustomSkyMessage = "The \"Sky Material\" property is empty, URP will use the \"Fallback Sky Material\" in the renderer feature instead.";

    // TODO: Verify if HDR Color Grading is truly necessary
    //const string k_HDRColorGradingMessage = "It is recommended to switch the \"Color Grading Mode\" to \"High Dynamic Range\" when using Physically Based Sky.";

    const string k_NoRendererFeatureMessage = "\"Physically Based Sky\" renderer feature does not exist in the active URP renderer.";

    const string k_RendererFeatureOffMessage = "\"Physically Based Sky\" is disabled in the active URP renderer.";

    const string k_RendererDataList = "m_RendererDataList";

    const string k_PhysicallyBasedSkyRendererFeature = "PhysicallyBasedSkyURP";

    const string k_FixButtonName = "Fix";

    static List<GUIContent> m_SkyClassNames = null;
    static List<int> m_SkyUniqueIDs = null;

    public static List<GUIContent> skyClassNames
    {
        get
        {
            UpdateSkyAndFogIntPopupData();
            return m_SkyClassNames;
        }
    }

    public static List<int> skyUniqueIDs
    {
        get
        {
            UpdateSkyAndFogIntPopupData();
            return m_SkyUniqueIDs;
        }
    }

    public override void OnEnable()
    {
        base.OnEnable();
        var o = new PropertyFetcher<VisualEnvironment>(serializedObject);

        RenderDataListFieldInfo = typeof(UniversalRenderPipelineAsset).GetField(k_RendererDataList, BindingFlags.Instance | BindingFlags.NonPublic);

        m_SkyType = Unpack(o.Find(x => x.skyType));
        //m_CloudType = Unpack(o.Find(x => x.cloudType));
        m_SkyAmbientMode = Unpack(o.Find(x => x.skyAmbientMode));

        m_PlanetRadius = Unpack(o.Find(x => x.planetRadius));
        m_RenderingSpace = Unpack(o.Find(x => x.renderingSpace));
        m_CenterMode = Unpack(o.Find(x => x.centerMode));
        m_PlanetCenter = Unpack(o.Find(x => x.planetCenter));

        //m_WindOrientation = Unpack(o.Find(x => x.windOrientation));
        //m_WindSpeed = Unpack(o.Find(x => x.windSpeed));

        m_CustomSkyMaterial = Unpack(o.Find(x => x.customSkyMaterial));
    }

    /*
    static Dictionary<int, Type> m_SkyTypesDict = null;
    static void UpdateSkyTypes()
    {
        if (m_SkyTypesDict == null)
        {
            m_SkyTypesDict = new Dictionary<int, Type>();

            var skyTypes = CoreUtils.GetAllTypesDerivedFrom<VisualEnvironment.SkyType>().Where(t => !t.IsAbstract);
            foreach (Type skyType in skyTypes)
            {
                var uniqueIDs = skyType.GetCustomAttributes(typeof(int), false);
                if (uniqueIDs.Length == 0)
                {
                    Debug.LogWarningFormat("Missing attribute SkyUniqueID on class {0}. Class won't be registered as an available sky.", skyType);
                }
                else
                {
                    int uniqueID = ((int)uniqueIDs[0]);
                    if (uniqueID == 0)
                    {
                        Debug.LogWarningFormat("0 is a reserved SkyUniqueID and is used in class {0}. Class won't be registered as an available sky.", skyType);
                        continue;
                    }

                    Type value;
                    if (m_SkyTypesDict.TryGetValue(uniqueID, out value))
                    {
                        Debug.LogWarningFormat("SkyUniqueID {0} used in class {1} is already used in class {2}. Class won't be registered as an available sky.", uniqueID, skyType, value);
                        continue;
                    }

                    m_SkyTypesDict.Add(uniqueID, skyType);
                }
            }
        }
    }
    */

    static void UpdateSkyAndFogIntPopupData()
    {
        if (m_SkyClassNames == null)
        {
            m_SkyClassNames = new List<GUIContent>();
            m_SkyUniqueIDs = new List<int>();

            // Add special "None" case.
            m_SkyClassNames.Add(new GUIContent("None"));
            m_SkyUniqueIDs.Add(0);

            foreach (VisualEnvironment.SkyType skyType in Enum.GetValues(typeof(VisualEnvironment.SkyType)))
            {
                string name = ObjectNames.NicifyVariableName(skyType.ToString());
                name = name.Replace("Settings", ""); // remove Settings if it was in the class name
                //m_SkyClassNames.Add(new GUIContent(name));
                m_SkyClassNames.Add(new GUIContent(string.Concat(name, " Sky")));
                m_SkyUniqueIDs.Add((int)skyType);
            }

            /*
            UpdateSkyTypes();
            var skyTypesDict = m_SkyTypesDict;
            foreach (KeyValuePair<int, Type> kvp in skyTypesDict)
            //foreach (KeyValuePair<VisualEnvironment.SkyType, Type> kvp in VisualEnvironment)
            {
                string name = ObjectNames.NicifyVariableName(kvp.Value.Name);
                name = name.Replace("Settings", ""); // remove Settings if it was in the class name
                m_SkyClassNames.Add(new GUIContent(name));
                m_SkyUniqueIDs.Add(kvp.Key);
            }
            */
        }
        /*
        if (m_CloudClassNames == null)
        {
            m_CloudClassNames = new List<GUIContent>();
            m_CloudUniqueIDs = new List<int>();

            // Add special "None" case.
            m_CloudClassNames.Add(new GUIContent("None"));
            m_CloudUniqueIDs.Add(0);

            var typesDict = SkyManager.cloudTypesDict;

            foreach (KeyValuePair<int, Type> kvp in typesDict)
            {
                string name = ObjectNames.NicifyVariableName(kvp.Value.Name);
                name = name.Replace("Settings", ""); // remove Settings if it was in the class name
                m_CloudClassNames.Add(new GUIContent(name));
                m_CloudUniqueIDs.Add(kvp.Key);
            }
        }
        */
    }

    public override void OnInspectorGUI()
    {
        var pbrSky = GetRendererFeature(k_PhysicallyBasedSkyRendererFeature) as PhysicallyBasedSkyURP;
        if (pbrSky == null)
        {
            EditorGUILayout.Space();
            EditorGUILayout.HelpBox(k_NoRendererFeatureMessage, MessageType.Error, wide: true);
            return;
        }
        else if (!pbrSky.isActive)
        {
            EditorGUILayout.Space();
            CoreEditorUtils.DrawFixMeBox(k_RendererFeatureOffMessage, MessageType.Warning, k_FixButtonName, () =>
            {
                pbrSky.SetActive(true);
                GUIUtility.ExitGUI();
            });
            EditorGUILayout.Space();
        }

        // TODO: Verify if HDR Color Grading is truly necessary
        /*
        var urpAsset = GraphicsSettings.currentRenderPipeline as UniversalRenderPipelineAsset;
        if (urpAsset != null)
        {
            bool isPbrSky = m_SkyType.value.intValue == (int)VisualEnvironment.SkyType.PhysicallyBased;
            bool isLDRColorGrading = urpAsset.colorGradingMode == ColorGradingMode.LowDynamicRange;
            if (isLDRColorGrading && isPbrSky) { EditorGUILayout.HelpBox(k_HDRColorGradingMessage, MessageType.Info, wide: true); }
        }
        */

        // Sky
        UpdateSkyAndFogIntPopupData();

        using (var scope = new OverridablePropertyScope(m_SkyType, EditorGUIUtility.TrTextContent("Sky Type", "Specifies the type of sky this Volume uses."), this))
        {
            if (scope.displayed)
                EditorGUILayout.IntPopup(m_SkyType.value, m_SkyClassNames.ToArray(), m_SkyUniqueIDs.ToArray(), scope.label);
        }

        if (m_SkyType.value.intValue == (int)VisualEnvironment.SkyType.Custom)
        {
            Material customSkyMaterial = (Material)m_CustomSkyMaterial.value.objectReferenceValue;
            if (customSkyMaterial == null)
            {
                EditorGUILayout.HelpBox(k_EmptyCustomSkyMessage, MessageType.Info, wide: true);
            }
            else if (customSkyMaterial.GetPassName(0) == k_UniversalForward)
            {
                EditorGUILayout.HelpBox(k_CustomSkyShaderGraphMessage, MessageType.Info, wide: true);
            }
            using (new IndentLevelScope())
            {
                PropertyField(m_CustomSkyMaterial, EditorGUIUtility.TrTextContent("Sky Material", "Specifies the custom sky material used by this visual environment override."));
            }
        }

        /*
        using (var scope = new OverridablePropertyScope(m_CloudType, EditorGUIUtility.TrTextContent("Background Clouds", "Specifies the type of background cloud this Volume uses."), this))
        {
            if (scope.displayed)
                EditorGUILayout.IntPopup(m_CloudType.value, m_CloudClassNames.ToArray(), m_CloudUniqueIDs.ToArray(), scope.label);
        }
        */

        PropertyField(m_SkyAmbientMode, EditorGUIUtility.TrTextContent("Ambient Mode", "Specifies how the global ambient probe is computed. Dynamic will use the currently displayed sky and static will use the sky setup in the environment lighting panel."));

        /*
        var staticLightingSky = SkyManager.GetStaticLightingSky();
        if (m_SkyAmbientMode.value.GetEnumValue<SkyAmbientMode>() == SkyAmbientMode.Static)
        {
            if (staticLightingSky == null)
                EditorGUILayout.HelpBox("No Static Lighting Sky is assigned in the Environment settings.", MessageType.Info);
            else
            {
                var skyType = staticLightingSky.staticLightingSkyUniqueID == 0 ? "no Sky" : SkyManager.skyTypesDict[staticLightingSky.staticLightingSkyUniqueID].Name;
                var cloudType = staticLightingSky.staticLightingCloudsUniqueID == 0 ? "no Clouds" : SkyManager.cloudTypesDict[staticLightingSky.staticLightingCloudsUniqueID].Name;
                var staticLightingSkyProfileName = staticLightingSky.profile != null ? staticLightingSky.profile.name : "None";
                EditorGUILayout.HelpBox($"Current Static Lighting Sky uses {skyType} and {cloudType} of profile {staticLightingSkyProfileName}.", MessageType.Info);
            }
        }
        */

        // Planet
        PropertyField(m_PlanetRadius, EditorGUIUtility.TrTextContent("Radius", "Sets the radius of the planet in kilometers. This is distance from the center of the planet to the sea level."));
        PropertyField(m_RenderingSpace);

        if (m_RenderingSpace.value.intValue == (int)VisualEnvironment.RenderingSpace.World && BeginAdditionalPropertiesScope())
        {
            PropertyField(m_CenterMode, EditorGUIUtility.TrTextContent("Center", "The center is used when defining where the planets surface is. In automatic mode, the surface is at the world's origin and the center is derived from the planet radius."));
            if (m_CenterMode.value.intValue == (int)VisualEnvironment.PlanetMode.Manual)
            {
                using (new IndentLevelScope())
                    PropertyField(m_PlanetCenter, EditorGUIUtility.TrTextContent("Position", "Sets the world-space position of the planet's center in kilometers."));
            }
            EndAdditionalPropertiesScope();
        }
    }

    /// <summary>
    /// Check if the Physically Based Sky renderer feature has been added.
    /// From "https://forum.unity.com/threads/enable-or-disable-render-features-at-runtime.932571/"
    /// </summary>
    #region Reflection
    private static FieldInfo RenderDataListFieldInfo;

    private static ScriptableRendererData[] GetRendererDataList(UniversalRenderPipelineAsset asset = null)
    {
        try
        {
            if (asset == null)
                asset = (UniversalRenderPipelineAsset)GraphicsSettings.currentRenderPipeline;

            if (asset == null)
                return null;

            if (RenderDataListFieldInfo == null)
                return null;

            var renderDataList = (ScriptableRendererData[])RenderDataListFieldInfo.GetValue(asset);
            return renderDataList;
        }
        catch
        {
            // Fail silently if reflection failed.
            return null;
        }
    }

    private static ScriptableRendererFeature GetRendererFeature(string typeName)
    {
        var renderDataList = GetRendererDataList();
        if (renderDataList == null || renderDataList.Length == 0)
            return null;

        foreach (var renderData in renderDataList)
        {
            foreach (var rendererFeature in renderData.rendererFeatures)
            {
                if (rendererFeature == null)
                    continue;

                if (rendererFeature.GetType().Name.Contains(typeName))
                {
                    return rendererFeature;
                }
            }
        }

        return null;
    }
    #endregion
}
