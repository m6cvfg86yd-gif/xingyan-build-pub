#include <metal_stdlib>
using namespace metal;

static float sat(float value) {
    return clamp(value, 0.0, 1.0);
}

static float hash21(float2 point) {
    point = fract(point * float2(123.34, 456.21));
    point += dot(point, point + 45.32);
    return fract(point.x * point.y);
}

static float valueNoise(float2 point) {
    float2 cell = floor(point);
    float2 local = fract(point);
    float2 blend = local * local * (3.0 - 2.0 * local);
    float a = hash21(cell);
    float b = hash21(cell + float2(1.0, 0.0));
    float c = hash21(cell + float2(0.0, 1.0));
    float d = hash21(cell + float2(1.0, 1.0));
    return mix(mix(a, b, blend.x), mix(c, d, blend.x), blend.y);
}

static float fbm(float2 point) {
    float value = 0.0;
    float amplitude = 0.5;
    for (int index = 0; index < 4; ++index) {
        value += amplitude * valueNoise(point);
        point = point * 2.03 + float2(17.1, 9.7);
        amplitude *= 0.5;
    }
    return value;
}

static float3 blendAnchors(float position, float3 a, float3 b, float3 c, float3 d) {
    float section = fract(position) * 4.0;
    if (section < 1.0) return mix(a, b, section);
    if (section < 2.0) return mix(b, c, section - 1.0);
    if (section < 3.0) return mix(c, d, section - 2.0);
    return mix(d, a, section - 3.0);
}

[[ stitchable ]] half4 voiceOrb(float2 position, half4 inputColor,
                                float time, float width, float height,
                                half4 colorA, half4 colorB, half4 colorC, half4 colorD,
                                float amplitude, float glass, float radius,
                                float lowDrive, float highDrive, float mode)
{
    float2 size = float2(width, height);
    float2 uv = (position - size * 0.5) / (size.x * 0.5);
    float energy = sat(amplitude);
    float low = sat(lowDrive);
    float high = sat(highDrive);
    float state = sat(mode / 6.0);
    float timeScale = 0.88 + low * 0.52 + high * 0.08;
    float t = time * timeScale;

    float2 drift = float2(sin(t * 0.31), cos(t * 0.27)) * low * 0.045;
    float angle = atan2(uv.y, uv.x);
    float edge = fbm(float2(cos(angle) * 1.35, sin(angle) * 1.35) + float2(0.0, t * 0.10));
    float edgeAmount = (0.11 + energy * 0.18 + low * 0.12);
    float orbRadius = radius * (1.0 + (edge - 0.5) * edgeAmount);
    float distanceFromCore = length(uv - drift) / max(orbRadius, 0.001);

    float2 flowPoint = (uv - drift) * 1.5;
    float2 warp = float2(fbm(flowPoint + float2(0.0, t * 0.11)),
                         fbm(flowPoint + float2(3.7, -t * 0.09)));
    float flow = fbm(flowPoint * 1.18 + (warp - 0.5) * 1.02 +
                     float2(t * 0.052, -t * 0.043));

    float2 sphereUV = (uv - drift) / max(orbRadius, 0.001);
    float sphereR2 = dot(sphereUV, sphereUV);
    float sphereZ = sqrt(max(0.0, 1.0 - sphereR2));
    float3 surfaceNormal = normalize(float3(
        sphereUV + (warp - 0.5) * (0.045 + low * 0.035),
        max(0.02, sphereZ)
    ));
    float3 viewDirection = float3(0.0, 0.0, 1.0);
    float normalView = sat(dot(surfaceNormal, viewDirection));
    float fresnel = pow(saturate(1.0 - normalView), 3.15);

    float3 keyDirection = normalize(float3(-0.46, -0.60, 0.66));
    float3 keyHalf = normalize(keyDirection + viewDirection);
    float keySpecular = pow(saturate(dot(surfaceNormal, keyHalf)), 118.0);

    float3 fillDirection = normalize(float3(0.58, 0.42, 0.58));
    float3 fillHalf = normalize(fillDirection + viewDirection);
    float fillSpecular = pow(saturate(dot(surfaceNormal, fillHalf)), 42.0);
    float keyDiffuse = sat(dot(surfaceNormal, keyDirection));

    float2 keyPoint = (sphereUV - float2(-0.34, -0.40)) / float2(0.23, 0.14);
    float softKey = exp(-dot(keyPoint, keyPoint) * 2.1);
    float2 reflectionPoint = (sphereUV - float2(0.34, 0.40)) / float2(0.45, 0.28);
    float softReflection = exp(-dot(reflectionPoint, reflectionPoint) * 1.55);
    float glassEdge = smoothstep(0.72, 0.98, length(sphereUV)) *
                      (1.0 - smoothstep(1.0, 1.08, length(sphereUV)));

    float hue = flow * 1.18 + t * 0.045 + distanceFromCore * 0.22 +
                high * 0.08 + state * 0.035;
    float3 first = blendAnchors(hue,
                                float3(colorA.rgb), float3(colorB.rgb),
                                float3(colorC.rgb), float3(colorD.rgb));
    float3 second = blendAnchors(hue + 0.36,
                                 float3(colorD.rgb), float3(colorA.rgb),
                                 float3(colorB.rgb), float3(colorC.rgb));
    float3 color = mix(first, second, 0.5 + 0.24 * sin(t * 0.72 + low * 1.4));

    float core = exp(-distanceFromCore * distanceFromCore * (2.35 - low * 0.30));
    float body = smoothstep(1.46, 0.04, distanceFromCore);
    float halo = exp(-max(0.0, distanceFromCore - 0.80) * 2.15);
    float rim = exp(-pow((distanceFromCore - 0.94 - low * 0.04) / 0.11, 2.0));
    float luminance = 0.30 + energy * 0.52 + low * 0.12;

    float filamentPattern = pow(sat(1.0 - abs(flow * 2.0 - 1.0)), 16.0);
    float filamentBand = smoothstep(0.16, 0.72, distanceFromCore) *
                         (1.0 - smoothstep(1.02, 1.28, distanceFromCore));
    float filaments = filamentPattern * filamentBand * (0.018 + high * 0.30);

    float sphereShade = 0.50 + normalView * 0.40 + keyDiffuse * 0.20;
    float3 reflectedEnvironment = mix(float3(1.0), color * 1.28,
                                      sat(0.34 - surfaceNormal.y * 0.16));
    float3 output = color * (core * 0.82 + body * 0.46) * sphereShade
                  + color * halo * (0.20 + energy * 0.30)
                  + reflectedEnvironment * fresnel * (0.26 + glass * 0.18)
                  + reflectedEnvironment * glassEdge * (0.08 + low * 0.08)
                  + color * rim * (0.045 + low * 0.08)
                  + mix(color, float3(1.0), 0.38) * filaments;
    output += float3(1.0, 0.995, 1.0) * keySpecular * (0.72 + energy * 0.42);
    output += mix(float3(1.0), float3(colorC.rgb), 0.45) *
              fillSpecular * (0.18 + high * 0.24);
    output += float3(1.0, 0.995, 1.0) * softKey * 0.36;
    output += reflectedEnvironment * softReflection * 0.055;
    output += float3(1.0, 0.99, 1.0) * core * (0.12 + energy * 0.18);
    output *= 1.0 - sat((sphereUV.x * 0.25 + sphereUV.y * 0.62 + 0.18) *
                        (1.0 - normalView) * 0.24);

    float dispersion = (distanceFromCore - 1.0) * 0.055 * clamp(glass, 0.0, 1.4);
    output.r *= 1.0 + dispersion;
    output.b *= 1.0 - dispersion;

    float alpha = sat(body * 0.94 + halo * 0.42 + rim * 0.12 +
                      fresnel * 0.12 + glassEdge * 0.08) *
                  smoothstep(1.34, 0.54, distanceFromCore);
    return half4(half3(max(output, 0.0)), half(alpha));
}
