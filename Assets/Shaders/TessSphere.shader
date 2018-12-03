Shader "TessSphere"
{
	Properties
	{
		// Properties accessible and editable in Unity editor
		_MainTex ("Texture", 2D) = "white" {}
		_MatCap ("MatCap", 2D) = "white" {}
		_Color ("Color", Color) = (1, 1, 1, 1)

		_RockAlbedo ("Rock Albedo", Color) = (1, 1, 1, 1)				// Colour of the rock 
		_RockBaseAlbedo ("Rock Base Albedo", Color) = (1, 1, 1, 1)		// Base colour of the rock

		_LavaBaseAlbedo ("Lava Base Albedo", Color) = (1, 1, 1, 1)		// Base colour of the lava
		_LavaAlbedo ("Lava Albedo", Color) = (1, 1, 1, 1)				// Colour of the lava
		_LavaLightAlbedo ("Lava Light Albedo", Color) = (1, 1, 1, 1)	// Colour of the light emitted by the lava
		_LavaMin ("Lava Min", Range(0, 1)) = 0.1
		_LavaMax ("Lava Max", Range(0, 1)) = 0.5
		_LavaLightMin ("Lava Light Min", Range(0, 1)) = 0.1
		_LavaLightMax ("Lava Light Max", Range(0, 1)) = 0.5

		_Frequency("Frequency", float) = 10.0
		_Lacunarity("Lacunarity", float) = 2.0
		_Gain("Gain", float) = 0.5
		_Jitter("Jitter", Range(0,1)) = 1.0
	}
	SubShader
	{
		Tags { "RenderType"="Opaque" }

		Pass
		{
			CGPROGRAM
				#pragma vertex vert					// Define vertex shader
				#pragma fragment frag				// Define fragment shader
				#pragma multi_compile_instancing
				
				// Include necessary libraries
				#include "UnityCG.cginc"			// Shader library
				#include "Lighting.cginc"			// Lighting stuff
				#include "NoiseLib.cginc"			// Simplex noise
				#include "Voronoise.cginc"			// Worley noise

				#define OCTAVES 4
				
				// The struct passed from the vertex shader to the fragment shader
				struct v2f
				{
					float4 vertex 		: SV_POSITION;
					float2 texcoord		: TEXCOORD0;
					float3 worldPos		: TEXCOORD1;
					float3 normal		: TEXCOORD2;
					float3 viewNormal	: TEXCOORD3;
					float  height		: TEXCOORD4;

					UNITY_VERTEX_INPUT_INSTANCE_ID
					UNITY_VERTEX_OUTPUT_STEREO
				};
				
				// Define the properties so the shaders can use them
				sampler2D 	_MainTex;
				sampler2D	_MatCap;
				fixed4		_Color;
				fixed4		_RockAlbedo;
				fixed4		_RockBaseAlbedo;
				fixed4		_LavaBaseAlbedo;
				fixed4		_LavaAlbedo;
				fixed4		_LavaLightAlbedo;
				float		_LavaMin;
				float		_LavaMax;
				float		_LavaLightMin;
				float		_LavaLightMax;


				// ???
				float Height (float2 uv)
				{
					return fBm_F1_F0(uv, OCTAVES);
				}

				v2f vert (appdata_full v)
				{
					UNITY_SETUP_INSTANCE_ID(v);
					v2f o;
					UNITY_INITIALIZE_OUTPUT(v2f, o);
					UNITY_TRANSFER_INSTANCE_ID(v, o);
					UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

					o.height 		= Height(v.texcoord.xy);

					// ???
					float dispIntensity = 0.02;

					float offset 	= 0.0005;												// How far from the actual position we want the offset positions to be
					float3 v0		= float3(v.texcoord.xy, 0);								// The actual position we want to calculate the normal for
					float3 v1		= float3(v.texcoord.xy + float2(1, 0) * offset, 0);		// The first offset position we use to calculate the normal
					float3 v2		= float3(v.texcoord.xy + float2(0, 1) * offset, 0);		// The second offest position we use to calculate the normal
					v0.z = Height(v0.xy) * dispIntensity;
					v1.z = Height(v1.xy) * dispIntensity;
					v2.z = Height(v2.xy) * dispIntensity;
					float3 vn 		= cross( normalize(v2-v0), normalize(v1-v0) );

					// Calculate tangent space etc.
					fixed3 worldNormal = UnityObjectToWorldNormal(v.normal);
					fixed3 worldTangent = UnityObjectToWorldDir(v.tangent.xyz);
					fixed tangentSign = v.tangent.w * unity_WorldTransformParams.w;
					fixed3 worldBinormal = cross(worldNormal, worldTangent) * tangentSign;
					float3 tSpace0 = float3(worldTangent.x, worldBinormal.x, worldNormal.x);
					float3 tSpace1 = float3(worldTangent.y, worldBinormal.y, worldNormal.y);
					float3 tSpace2 = float3(worldTangent.z, worldBinormal.z, worldNormal.z);
					
					worldNormal.x = dot(tSpace0.xyz, vn);
					worldNormal.y = dot(tSpace1.xyz, vn);
					worldNormal.z = dot(tSpace2.xyz, vn);

					float3 disp  	= v.normal * o.height * dispIntensity;
					v.vertex.xyz 	+= disp;

					o.worldPos 		= mul(unity_ObjectToWorld, v.vertex);

					o.vertex 		= UnityObjectToClipPos(v.vertex);
					o.texcoord 		= v.texcoord;
					o.normal 		= -worldNormal;
					o.viewNormal 	= mul(UNITY_MATRIX_V, float4(o.normal, 0));

					return o;
				}

				fixed4 frag (v2f i) : SV_Target
				{
					UNITY_SETUP_INSTANCE_ID(i);

					float3 viewDir = normalize(i.worldPos - _WorldSpaceCameraPos);

					//	Fresnel-reflection, calculates the reflection of the surface depending on the view direction
					float fresnel = pow(1-saturate(dot(i.normal, -viewDir)), 5);

					fixed4 albedo = tex2D(_MainTex, i.texcoord);

					fixed4 col = albedo *_Color;

					// Diffuse color
					col.rgb = lerp(_RockBaseAlbedo, _RockAlbedo, i.height);

					// Apply lighting
					float3 light = 0;
					light += max(dot(_WorldSpaceLightPos0.xyz, i.normal), 0) * _LightColor0.rgb;
					light += lerp(unity_AmbientGround, unity_AmbientSky, i.normal.y*0.5+0.5);

					col.rgb *= light;

					// Test mat cap
					// col.rgb *= tex2D(_MatCap, i.viewNormal.xy*0.5+0.5);

					col.rgb += pow(max(dot(viewDir, normalize(reflect(_WorldSpaceLightPos0.xyz, i.normal))), 0), 2) * _LightColor0.rgb * 0.1;

					col.rgb += unity_AmbientSky * fresnel * 0.2;

					float lavaNoise = fBm_F1_F0(i.texcoord.xy * 2 + float2(_Time.x, 0), OCTAVES);

					// Apply lava
					col.rgb += smoothstep(_LavaMax, _LavaMin, i.height) * lerp(_LavaBaseAlbedo, _LavaAlbedo, lavaNoise) * 1.5;
					col.rgb += smoothstep(_LavaLightMax, _LavaLightMin, i.height) * _LavaLightAlbedo;
					
					return col;
				}
			ENDCG
		}
	}
}