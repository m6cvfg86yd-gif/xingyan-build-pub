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

static float2 rotate2(float2 point, float angle) {
    float sine = sin(angle);
    float cosine = cos(angle);
    return float2(cosine * point.x - sine * point.y,
                  sine * point.x + cosine * point.y);
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
    float t = time * (0.72 + low * 0.30 + high * 0.08);

    float2 drift = float2(sin(t * 0.28), cos(t * 0.24)) * (0.008 + low * 0.018);
    float2 sphereUV = (uv - drift) / max(radius, 0.001);
    float radial = length(sphereUV);
    float radialSquared = dot(sphereUV, sphereUV);
    float sphereZ = sqrt(max(0.0, 1.0 - radialSquared));

    float3 sphereNormal = normalize(float3(sphereUV.x,
                                          sphereUV.y,
                                          max(0.035, sphereZ)));
    float facing = sat(sphereNormal.z);
    float fresnel = pow(saturate(1.0 - facing), 3.35);

    float2 tube = sphereNormal.xy / (1.16 + sphereNormal.z);
    float spin = t * (0.12 + low * 0.065);
    float2 primaryPoint = rotate2(tube * 2.15, spin);
    float2 secondaryPoint = rotate2(tube * 4.90, -spin * 1.43 + 0.8);

    float plume = fbm(primaryPoint + float2(0.0, t * 0.043));
    float detail = fbm(secondaryPoint + float2(t * 0.082, -t * 0.061));
    float curl = fbm(primaryPoint * 0.67 +
                     (float2(plume, detail) - 0.5) * 1.18 +
                     float2(t * 0.027, -t * 0.032));
    float pressure = smoothstep(0.15, 0.89, curl);

    float longitude = atan2(sphereNormal.y, sphereNormal.x) / 6.2831853 + 0.5;
    float hue = longitude + plume * 0.46 + curl * 0.24 +
                high * 0.055 + state * 0.035 + t * 0.007;
    float3 first = blendAnchors(hue,
                                float3(colorA.rgb), float3(colorB.rgb),
                                float3(colorC.rgb), float3(colorD.rgb));
    float3 second = blendAnchors(hue + 0.31,
                                 float3(colorD.rgb), float3(colorA.rgb),
                                 float3(colorB.rgb), float3(colorC.rgb));
    float3 color = mix(first, second, 0.24 + 0.16 * sin(t * 0.54 + low * 1.1));

    float sphereMask = 1.0 - smoothstep(0.94, 1.025, radial);
    float halo = exp(-max(0.0, radial - 0.88) * 3.2);
    float innerCore = exp(-radialSquared * (5.2 - low * 0.7));
    float rim = exp(-pow((radial - 0.955) / 0.052, 2.0));

    float rollingBand = smoothstep(0.58, 0.95,
                                   sin(curl * 13.0 + t * 1.15) * 0.5 + 0.5);
    float filaments = pow(saturate(1.0 - abs(detail * 2.0 - 1.0)), 10.0);
    float filamentMask = (1.0 - smoothstep(0.22, 0.92, radial)) *
                          smoothstep(0.08, 0.72, pressure);

    float3 keyDirection = normalize(float3(-0.48, -0.62, 0.62));
    float3 keyHalf = normalize(keyDirection + float3(0.0, 0.0, 1.0));
    float keyDiffuse = sat(dot(sphereNormal, keyDirection));
    float keySpecular = pow(saturate(dot(sphereNormal, keyHalf)), 145.0);

    float3 fillDirection = normalize(float3(0.62, 0.46, 0.54));
    float3 fillHalf = normalize(fillDirection + float3(0.0, 0.0, 1.0));
    float fillSpecular = pow(saturate(dot(sphereNormal, fillHalf)), 52.0);

    float2 keyPoint = (sphereUV - float2(-0.34, -0.40)) / float2(0.20, 0.10);
    float softWindow = exp(-dot(keyPoint, keyPoint) * 2.8);
    float2 lowerReflection = (sphereUV - float2(0.35, 0.43)) / float2(0.48, 0.26);
    float reflectedWindow = exp(-dot(lowerReflection, lowerReflection) * 1.75);

    float3 darkGlass = float3(0.010, 0.014, 0.030);
    float3 innerVolume = mix(darkGlass, color * 0.64, pressure * 0.78);
    float3 reflectedEnvironment = mix(float3(1.0, 1.0, 1.0),
                                      color * 1.24 + 0.035,
                                      sat(0.34 - sphereNormal.y * 0.21));

    float3 output = innerVolume * (0.20 + keyDiffuse * 0.17 + facing * 0.18);
    output += color * pressure * sphereMask * (0.34 + energy * 0.34);
    output += mix(color, reflectedEnvironment, 0.62) *
              rollingBand * filamentMask * (0.035 + high * 0.12);
    output += mix(color, float3(1.0), 0.46) *
              filaments * filamentMask * (0.045 + high * 0.17);
    output += reflectedEnvironment * fresnel * (0.36 + glass * 0.20);
    output += color * rim * (0.20 + energy * 0.12);
    output += color * innerCore * (0.10 + energy * 0.10);
    output += mix(float3(1.0), float3(colorC.rgb), 0.48) *
              keySpecular * (0.90 + energy * 0.44);
    output += mix(float3(1.0), reflectedEnvironment, 0.70) *
              fillSpecular * (0.16 + high * 0.14);
    output += float3(1.0, 0.995, 1.0) * softWindow * 0.30;
    output += reflectedEnvironment * reflectedWindow * 0.035;
    output += color * halo * (0.080 + energy * 0.12);
    output *= 0.94 + sphereZ * 0.08;

    float dispersion = (radial - 0.93) * 0.052 * clamp(glass, 0.0, 1.5);
    output.r *= 1.0 + dispersion;
    output.b *= 1.0 - dispersion;

    float alpha = sat(sphereMask * 0.96 + halo * 0.20 + fresnel * 0.10) *
                  (1.0 - smoothstep(0.70, 1.26, radial));
    return half4(half3(max(output, 0.0)), half(alpha));
}
