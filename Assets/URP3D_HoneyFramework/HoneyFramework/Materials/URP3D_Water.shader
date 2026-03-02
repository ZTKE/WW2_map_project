Shader "HoneyFramework/URP3D/Water" {
    Properties {
        _WaveScale ("Wave scale", Range (0.02, 0.15)) = 0.063
        _ReflDistort ("Reflection distort", Range (0,1.5)) = 0.44
        _WaveSpeed ("Wave speed (map1 x,y; map2 x,y)", Vector) = (2, 0.5, -2, -1.5)
        _BumpMap ("Normalmap ", 2D) = "bump" {}
        _ReflectiveColor ("Reflective color (RGB) fresnel (A) ", 2D) = "" {}
        _WaterTone ("Water tone", COLOR)  = (0, 0.17, 0.29, 0)
    }

    SubShader {
        Tags {
            "WaterMode" = "Refractive"
            "RenderType" = "Transparent"
            "RenderPipeline" = "UniversalPipeline"
        }

        Pass {
            Name "ForwardLit"
            Tags {
                "LightMode" = "UniversalForward"
            }
            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            Cull Off

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _SHADOWS_SOFT

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
            };

            struct Varyings {
                float4 pos : SV_POSITION;
                float4 ref : TEXCOORD0;
                float2 bumpuv0 : TEXCOORD1;
                float2 bumpuv1 : TEXCOORD2;
                float3 viewDir : TEXCOORD3;
                float3 worldPos : TEXCOORD4;
            };

            TEXTURE2D(_ReflectionTex);
            SAMPLER(sampler_ReflectionTex);

            TEXTURE2D(_ReflectiveColor);
            SAMPLER(sampler_ReflectiveColor);

            TEXTURE2D(_RefractionTex);
            SAMPLER(sampler_RefractionTex);

            TEXTURE2D(_BumpMap);
            SAMPLER(sampler_BumpMap);

            TEXTURE2D(_CameraDepthTexture);
            SAMPLER(sampler_CameraDepthTexture);

            CBUFFER_START(UnityPerMaterial)
                float4 _ReflectiveColor_ST;
                float _ReflDistort;
                float _WaveScale;
                half4 _WaterTone;
                half4 _WaveSpeed;
            CBUFFER_END

            Varyings vert(Attributes i) {
                Varyings o;
                o.pos = TransformObjectToHClip(i.vertex.xyz);
                float4 waveScale = float4(_WaveScale, _WaveScale, _WaveScale * 0.4, _WaveScale * 0.45);
                float4 waveOffset = float4(fmod(_WaveSpeed.x * waveScale.x * _Time.x, 1),
                                           fmod(_WaveSpeed.y * waveScale.y * _Time.x, 1),
                                           fmod(_WaveSpeed.z * waveScale.z * _Time.x, 1),
                                           fmod(_WaveSpeed.w * waveScale.w * _Time.x, 1));

                // scroll bump waves
                float4 temp;
                temp.xyzw = i.vertex.xzxz * waveScale + waveOffset;
                o.bumpuv0 = temp.xy;
                o.bumpuv1 = temp.wz;

                // object space view direction (will normalize per pixel)
                o.viewDir.xzy = GetObjectSpaceNormalizeViewDir(i.vertex.xyz);
                o.ref = GetVertexPositionInputs(o.pos.xyz).positionNDC;
                o.worldPos = TransformObjectToWorld(i.vertex.xyz).xyz;
                return o;
            }

            half4 frag(Varyings i) : SV_Target {
                // Water depth
                // Get the distance to the camera from the depth buffer for this point
                float2 screenUV = i.ref.xy / i.ref.w;
                float4 cam = SAMPLE_TEXTURE2D_X(_CameraDepthTexture, sampler_CameraDepthTexture, screenUV);
                float sceneZ = LinearEyeDepth(cam.r, _ZBufferParams);
                float4x4 mvMatrixIT = transpose(mul(UNITY_MATRIX_I_M, UNITY_MATRIX_I_V));
                float3 viewDir = mvMatrixIT[2].xyz;
                // sceneZ = LinearEyeDepth(tex2D(_CameraDepthTexture, i.ref).r);
                float3 cameraDist = i.worldPos - GetCameraPositionWS();
                float partZ = -dot(viewDir, cameraDist);
                // If the two are similar, then there is an object intersecting with our object
                half diff = sceneZ.x - partZ;
                diff = pow(max(0.0, diff), 0.3);
                half minDepthBorder = 0.32;
                half midDepth = 0.4;
                half depthBorder = 0.5;
                half waterDepth = 0;
                // low intensity on border to smoothen it.
                if (diff > minDepthBorder && diff <= midDepth) {
                    half shalowBrackets = midDepth - minDepthBorder;
                    waterDepth = 0.5 * (diff - minDepthBorder) / shalowBrackets;
                } else if (diff > midDepth && diff <= depthBorder) {
                    half deepBrackets = depthBorder - midDepth;
                    waterDepth = 0.5 + 0.4 * (diff - midDepth) / deepBrackets;
                } else if (diff > depthBorder) {
                    // higher intensity when depth is entered
                    waterDepth = 0.9 + (diff - depthBorder)*10; 
                }
                // waterDepth = diff * 5;
                // Water reflection adn refraction
                i.viewDir = normalize(i.viewDir);
                half3 bump1 = UnpackNormal(SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, i.bumpuv0)).rgb;
                half3 bump2 = UnpackNormal(SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, i.bumpuv1)).rgb;
                half3 bump = (bump1 + bump2) * 0.5;
                // fresnel factor
                half fresnelFac = dot(i.viewDir, bump * waterDepth);
                // perturb reflection/refraction UVs by bumpmap, and lookup colors
                float4 uv1 = i.ref;
                uv1.xy += (bump * _ReflDistort).xy;
                // final color is between refracted and reflected based on fresnel
                half4 color;
                float2 tmpUV = float2(i.worldPos.x, i.worldPos.z) / 10.0;
                tmpUV += (bump * waterDepth * _ReflDistort).xy;
                tmpUV.xy += _Time.x / 3.0;
                half4 sky = SAMPLE_TEXTURE2D(_ReflectiveColor, sampler_ReflectiveColor, tmpUV);
                color.rgb = (sky * 0.25 + _WaterTone * 0.75).rgb;
                color.a = waterDepth;
                return color;
            }
            ENDHLSL
        }

        Pass {
            Name "ShadowCaster"
            Tags {
                "LightMode" = "ShadowCaster"
            }

            ZWrite On
            ZTest LEqual
            ColorMask 0

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
                float2 uv : TEXCOORD0;
            };

            struct Varyings {
                float4 vertex : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            Varyings vert(Attributes i) {
                Varyings o;
                VertexPositionInputs v = GetVertexPositionInputs(i.vertex.xyz);
                o.vertex = v.positionCS;
                float3 n = TransformObjectToWorldNormal(i.normal);
                Light mainLight = GetMainLight();
                float3 l = mainLight.direction;
                float3 p = v.positionWS;
                ApplyShadowBias(p, n, l);
                o.uv = i.uv;
                return o;
            }

            half4 frag(Varyings i) : SV_TARGET {
                return 0;
            }
            ENDHLSL
        }

        Pass {
            Name "DepthOnly"
            Tags {
                "LightMode" = "DepthOnly"
            }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes {
                float4 vertex : POSITION;
            };

            struct Varyings {
                float4 vertex : SV_POSITION;
            };

            Varyings vert(Attributes i) {
                Varyings o;
                o.vertex = TransformObjectToHClip(i.vertex.xyz);
                return o;
            }

            half4 frag(Varyings i) : SV_Target {
                return 0;
            }
            ENDHLSL
        }
    }
}
