#ifndef HEXASPHERE_URP_COMMON
#define HEXASPHERE_URP_COMMON

//#define USE_FORWARD_PLUS_ADDITIONAL_DIRECTIONAL_LIGHTS
#define _NativeLightsMultiplier 1.0

half3 GetNativeLightsColor(float3 wpos, float2 uv) {
    half3 color = 0;
            #if USE_FORWARD_PLUS
                // additional directional lights
                #if defined(USE_FORWARD_PLUS_ADDITIONAL_DIRECTIONAL_LIGHTS)
                    for (uint lightIndex = 0; lightIndex < URP_FP_DIRECTIONAL_LIGHTS_COUNT; lightIndex++) {
                        Light light = GetAdditionalLight(lightIndex, wpos, 1.0.xxxx);
                        color += light.color * (light.distanceAttenuation * light.shadowAttenuation * _NativeLightsMultiplier);
                    }
                #endif
                // clustered lights
                {
                    uint lightIndex;
                    ClusterIterator _urp_internal_clusterIterator = ClusterInit(uv, wpos, 0);
                    [loop] while (ClusterNext(_urp_internal_clusterIterator, lightIndex)) { 
                        lightIndex += URP_FP_DIRECTIONAL_LIGHTS_COUNT;
                        Light light = GetAdditionalLight(lightIndex, wpos, 1.0.xxxx);
                        color += light.color * (light.distanceAttenuation * light.shadowAttenuation * _NativeLightsMultiplier);
                    }
                }
            #else
                #if USE_FORWARD_PLUS
                    uint additionalLightCount = min(URP_FP_PROBES_BEGIN, 8); // more than 8 lights is too slow for raymarching
                #else
                    uint additionalLightCount = GetAdditionalLightsCount();
                #endif
                for (uint i = 0; i < additionalLightCount; ++i) {
                    #if UNITY_VERSION >= 202030
                        Light light = GetAdditionalLight(i, wpos, 1.0.xxxx);
                    #else
                        Light light = GetAdditionalLight(i, wpos);
                    #endif
                    color += light.color * (light.distanceAttenuation * light.shadowAttenuation * _NativeLightsMultiplier);
                }
            #endif
        return color;
}

#endif