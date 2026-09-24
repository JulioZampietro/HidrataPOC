#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// ---------- Ruído procedural ----------

static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

// Value noise: interpola valores aleatórios nos cantos de uma grade
static float vnoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);

    float a = hash21(i);
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));

    float2 u = f * f * (3.0 - 2.0 * f); // suaviza a interpolação
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// fBm: soma várias "oitavas" de ruído (cada uma com mais detalhe e menos força)
static float fbm(float2 p) {
    float value = 0.0;
    float amp = 0.5;
    for (int i = 0; i < 4; i++) {
        value += amp * vnoise(p);
        p = p * 2.0 + 17.0;
        amp *= 0.5;
    }
    return value;
}

// Raio da bolha em função do ângulo (a borda "viva")
static float bubbleRadius(float angle, float time) {
    float wobble = 0.045 * sin(angle * 3.0 + time * 1.3)
                 + 0.035 * sin(angle * 5.0 - time * 1.7)
                 + 0.025 * sin(angle * 2.0 + time * 0.9);
    return 0.68 + wobble;
}

[[ stitchable ]] half4 bubble(float2 position, half4 color, float2 size, float time) {

    // 1. Coordenadas
    float2 uv = (position - 0.5 * size) / (0.5 * min(size.x, size.y));
    float r = length(uv);
    float angle = atan2(uv.y, uv.x);

    // 2. Borda viva
    float radius = bubbleRadius(angle, time);
    float d = r - radius;                        // < 0 dentro, > 0 fora

    // 3. Silhueta com borda nítida
    float inside = 1.0 - smoothstep(0.0, 0.008, d);

    float band = smoothstep(-0.12, -0.005, d);
    float rimMask = band * inside;

    // 4. Linha fina no contorno
    float edgeLine = exp(-abs(d + 0.006) * 150.0) * inside;

    // 5. Dois arcos de luz que giram devagar
    float a1 = -2.35 + 0.25 * sin(time * 0.6);
    float a2 =  0.80 + 0.25 * sin(time * 0.5 + 1.0);
    float arc1 = pow(max(cos(angle - a1), 0.0), 8.0);
    float arc2 = pow(max(cos(angle - a2), 0.0), 12.0);
    float arcs = (arc1 * 0.85 + arc2 * 0.45) * rimMask;

    // 6. Sombra projetada no fundo
    //    A mesma forma da bolha, deslocada para baixo/direita
    float2 shadowUV = uv - float2(0.035, 0.055);
    float shadowAngle = atan2(shadowUV.y, shadowUV.x);
    float ds = length(shadowUV) - bubbleRadius(shadowAngle, time);

    // Forte colada na silhueta, some suavemente até ~0.16 de distância
    float outerShadow = pow(1.0 - smoothstep(-0.03, 0.16, ds), 2.0)
                      * 0.35
                      * (1.0 - inside);          // nunca aparece dentro da bolha

    // 7. Composição
    float highlightA = saturate(arcs + edgeLine * 0.5 + rimMask * 0.08);
    float shadowA = rimMask * 0.10 + outerShadow;

    float3 rgb = float3(highlightA);             // branco pré-multiplicado (a sombra é preta: rgb = 0)
    float alpha = saturate(highlightA + shadowA * (1.0 - highlightA));

    return half4(half3(rgb), half(alpha));
}

// ---------- Shader da água (recipiente da Home) ----------
// Mesmo visual da bolha: transparente, só realces brancos nas bordas e uma sombra
// levíssima. Sobe conforme `level` (0 = vazio, 1 = cheio).
//
// A superfície é um campo de alturas simulado no Swift (equação de onda com
// reflexão nas paredes, amortecimento e volume conservado — ver `WaterMotion`).
// Aqui só é desenhado: `down` é o vetor unitário "para baixo" no plano da tela
// (y para baixo) e `field` traz os deslocamentos da superfície, em pontos,
// ao longo dela (positivo = mais fundo).
// Roda em duas camadas sobre o mesmo retângulo:
//   front = 0 → sombra suave (atrás do mascote)
//   front = 1 → realces brancos, contorno e bolhas (na frente do mascote)
// Coordenadas em pontos, y para baixo.

static float sampleField(device const float *field, int count, float u) {
    float x = clamp(u, 0.0, 1.0) * float(count - 1);
    int i0 = int(floor(x));
    int i1 = min(i0 + 1, count - 1);
    return mix(field[i0], field[i1], x - float(i0));
}

[[ stitchable ]] half4 water(float2 position, half4 color, float2 size, float time,
                             float level, float2 down, float agitation, float front,
                             device const float *field, int count) {

    float2 n = normalize(down);                    // direção da gravidade
    float2 t = float2(n.y, -n.x);                  // direção ao longo da superfície
    float2 c = 0.5 * size;

    // Coordenadas no referencial da água: h = profundidade (cresce a favor da gravidade),
    // s = posição ao longo da superfície.
    float2 rel = position - c;
    float h = dot(rel, n);
    float s = dot(rel, t) + 0.5 * size.x;

    // Extensão da superfície: o campo de alturas cobre toda ela, de parede a parede.
    float len = abs(t.x) * size.x + abs(t.y) * size.y;
    float u = dot(rel, t) / len + 0.5;

    // Meia-extensão do retângulo ao longo de n: level 0 esvazia e level 1 enche por
    // completo em qualquer inclinação; em 0.5 a superfície passa pelo centro.
    const float margin = 20.0;
    float halfExtent = 0.5 * (abs(n.x) * size.x + abs(n.y) * size.y) + margin;
    float baseH = mix(halfExtent, -halfExtent, saturate(level));

    // Ondas ambiente, pequenas, para a água nunca ficar parada; a agitação (energia
    // da simulação) acrescenta marolas curtas.
    float ambient = 1.6 * sin(s * 0.030 + time * 1.3 + 0.9 * sin(s * 0.013 - time * 0.7))
                  + 1.1 * sin(s * 0.055 - time * 1.7 + 1.3)
                  + agitation * 1.0 * sin(s * 0.16 + time * 4.0) * sin(s * 0.047 - time * 1.9);

    float eta = sampleField(field, count, u);
    float surfaceH = baseH + eta + ambient;

    float d = h - surfaceH;                        // > 0 dentro da água
    float inside = 1.0 - smoothstep(-0.5, 1.0, -d); // silhueta com borda nítida
    if (inside <= 0.0) { return half4(0.0h); }

    // Faixa perto da superfície: 1 na superfície, 0 a ~24pt abaixo
    float band = exp(-max(d, 0.0) / 10.0);

    if (front < 0.5) {
        // Sombra levíssima junto da superfície
        float shadowA = band * 0.10 * inside;
        return half4(0.0h, 0.0h, 0.0h, half(shadowA));
    }

    // Inclinação local da superfície: onde a onda é íngreme o brilho aumenta,
    // como o reflexo da luz numa água real.
    float du = 1.0 / float(count - 1);
    float slope = (sampleField(field, count, u + du) - sampleField(field, count, u - du)) / (2.0 * du * len);
    float glint = smoothstep(0.03, 0.40, abs(slope)) * band;

    // Linha fina no contorno da superfície (mais grossa onde a onda é íngreme)
    float edgeLine = exp(-abs(d - 1.0) * (1.2 - 0.5 * saturate(abs(slope) * 3.0))) * inside;

    // Dois arcos de luz que deslizam devagar pela superfície
    float a1 = 0.25 + 0.10 * sin(time * 0.6);
    float a2 = 0.75 + 0.10 * sin(time * 0.5 + 1.0);
    float arc1 = pow(max(cos((u - a1) * 6.2832 * 0.9), 0.0), 8.0);
    float arc2 = pow(max(cos((u - a2) * 6.2832 * 0.9), 0.0), 12.0);
    float arcs = (arc1 * 0.85 + arc2 * 0.45) * band;

    // Contorno branco nas paredes do recipiente (só onde há água)
    float wallDist = min(position.x, size.x - position.x);
    float bottomDist = size.y - position.y;
    float walls = (exp(-wallDist * 0.9) + exp(-bottomDist * 0.9)) * 0.35 * inside;

    // Bolhas subindo contra a gravidade (anéis brancos discretos)
    float bubbles = 0.0;
    const float cellW = 38.0;
    float cell = floor(s / cellW);
    for (int k = -1; k <= 1; k++) {
        float cc = cell + float(k);
        float r = hash21(float2(cc, 1.7));
        float bs = (cc + 0.2 + 0.6 * hash21(float2(cc, 7.3))) * cellW
                 + sin(time * 0.8 + r * 6.0) * 4.0;
        float bh = mix(-halfExtent, halfExtent, fract(time * (0.04 + 0.05 * r) + r));
        float rad = 2.0 + 3.0 * hash21(float2(cc, 3.1));
        float dist = length(float2(s - bs, h - bh));
        float ring = exp(-abs(dist - rad) * 1.6) * 0.45;
        float below = smoothstep(0.0, 6.0, bh - surfaceH);
        bubbles += ring * below;
    }

    float highlightA = saturate(arcs + glint * 0.3 + edgeLine * 0.5 + band * 0.08 + walls + bubbles) * inside;

    // branco pré-multiplicado
    return half4(half3(highlightA), half(highlightA));
}
