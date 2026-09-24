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

// Onda trocoidal (fase → altura para cima, média ≈ 0): cristas afiadas, vales achatados.
// A raiz suaviza a ponta da crista para não virar um bico.
static float crestWave(float phase) {
    float c = cos(phase);
    return 1.0 - sqrt(c * c + 0.04) - 0.30;
}

// Geometria da água num ponto: compartilhada entre o desenho (`water`) e a refração
// do conteúdo (`waterRefraction`), para as duas concordarem sobre onde está a superfície.
struct WaterGeometry {
    float d;          // > 0 dentro da água (distância à superfície, em pt)
    float h;          // profundidade no referencial da água
    float s;          // posição ao longo da superfície
    float u;          // s normalizado (0…1) de parede a parede
    float len;        // comprimento da superfície
    float halfExtent; // meia-extensão do retângulo ao longo da gravidade
    float surfaceH;   // profundidade da superfície neste ponto
};

static WaterGeometry waterGeometry(float2 position, float2 size, float time, float level,
                                   float2 down, float agitation,
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

    // Forma da superfície. Tudo aqui é "altura para cima" (up), subtraída de surfaceH,
    // que cresce a favor da gravidade.
    float eta = sampleField(field, count, u);

    // 1. Ondas ambiente trocoidais: cristas afiadas e vales achatados, como as ondas
    //    de verdade (uma senoide pura é simétrica e parece borracha). A fase é deformada
    //    por outra onda para não repetir de forma regular.
    float ambient = 2.2 * crestWave(s * 0.030 + time * 1.3 + 0.9 * sin(s * 0.013 - time * 0.7))
                  + 1.4 * crestWave(s * 0.055 - time * 1.7 + 1.3 + 0.7 * sin(s * 0.021 + time * 0.5));

    // 2. Marolas sobre o balanço: onde a superfície está inclinada ou a água agitada,
    //    surgem ondas curtas e rápidas por cima — a superfície deixa de ser uma reta.
    float du = 1.0 / float(count - 1);
    float slope = (sampleField(field, count, u + du) - sampleField(field, count, u - du)) / (2.0 * du * len);
    float chop = 4.5 * saturate(abs(slope) * 3.0 + 0.5 * agitation)
               * crestWave(s * 0.085 + time * 3.1 + 2.0 * sin(s * 0.030 - time * 1.2));

    // 3. Menisco: a água sobe um pouco ao encostar nas paredes laterais.
    float wallDist = min(position.x, size.x - position.x);
    float meniscus = 5.0 * exp(-wallDist / 9.0);

    float surfaceH = baseH + eta - ambient - chop - meniscus;

    float d = h - surfaceH;                        // > 0 dentro da água
    WaterGeometry g;
    g.d = d; g.h = h; g.s = s; g.u = u; g.len = len; g.halfExtent = halfExtent; g.surfaceH = surfaceH;
    return g;
}

[[ stitchable ]] half4 water(float2 position, half4 color, float2 size, float time,
                             float level, float2 down, float agitation, float front,
                             device const float *field, int count) {

    WaterGeometry g = waterGeometry(position, size, time, level, down, agitation, field, count);
    float d = g.d, h = g.h, s = g.s, u = g.u, len = g.len;
    float halfExtent = g.halfExtent, surfaceH = g.surfaceH;
    float inside = 1.0 - smoothstep(-0.5, 1.0, -d); // silhueta com borda nítida
    if (inside <= 0.0) { return half4(0.0h); }

    // Faixa perto da superfície: 1 na superfície, 0 a ~24pt abaixo
    float band = exp(-max(d, 0.0) / 10.0);

    if (front < 0.5) {
        // Sombra levíssima junto da superfície
        float shadowA = band * 0.10 * inside;
        return half4(0.0h, 0.0h, 0.0h, half(shadowA));
    }

    // Inclinação da superfície inteira neste ponto (ondas, marolas, menisco…), medida
    // por diferença entre dois pontos vizinhos ao longo dela. Positivo = a superfície
    // afunda (a favor da gravidade) na direção +s.
    float2 tangent = float2(normalize(down).y, -normalize(down).x);
    float ds = 2.0;
    float slope = (waterGeometry(position + tangent * ds, size, time, level, down, agitation, field, count).surfaceH
                 - waterGeometry(position - tangent * ds, size, time, level, down, agitation, field, count).surfaceH)
                / (2.0 * ds);

    // Reflexo especular: a luz vem de cima e da esquerda, então as faces das ondas
    // viradas para ela brilham forte e as demais quase nada. O brilho anda junto com as
    // ondas em vez de ser uniforme ao longo da linha.
    float2 normal = normalize(float2(slope, 1.0));           // y = "para cima" da água
    float2 lightDir = normalize(float2(-0.6, 1.0));
    float2 halfVec = normalize(lightDir + float2(0.0, 1.0)); // vista de frente
    float spec = saturate((pow(saturate(dot(normal, halfVec)), 40.0) - 0.15) / 0.85);

    // Linha fina no contorno da superfície: intensidade segue o reflexo e fica um pouco
    // mais grossa onde a onda é íngreme.
    float edgeLine = exp(-abs(d - 1.0) * (1.2 - 0.5 * saturate(abs(slope) * 3.0))) * inside;
    float lineA = edgeLine * (0.30 + 0.55 * spec);

    // Espessura da superfície: faixa translúcida logo abaixo da linha (a "borda" da
    // água), com um fio bem tênue mais fundo marcando onde ela termina.
    float lip = smoothstep(0.5, 2.0, d) * (1.0 - smoothstep(4.0, 9.0, d)) * (0.07 + 0.10 * spec);
    float lipEdge = exp(-abs(d - 10.0) * 0.5) * 0.05;

    // Dois arcos de luz que deslizam devagar pela superfície
    float a1 = 0.25 + 0.10 * sin(time * 0.6);
    float a2 = 0.75 + 0.10 * sin(time * 0.5 + 1.0);
    float arc1 = pow(max(cos((u - a1) * 6.2832 * 0.9), 0.0), 8.0);
    float arc2 = pow(max(cos((u - a2) * 6.2832 * 0.9), 0.0), 12.0);
    float arcs = (arc1 * 0.50 + arc2 * 0.27) * band;

    // Contorno branco nas paredes do recipiente (só onde há água)
    float wallDist = min(position.x, size.x - position.x);
    float bottomDist = size.y - position.y;
    float walls = (exp(-wallDist * 0.9) + exp(-bottomDist * 0.9)) * 0.35 * inside;

    // Bolhas: sobem em fios a partir do fundo, contra a gravidade, e estouram ao chegar
    // na superfície. Pequenas, com um vai-e-vem lateral que cresce na subida, um leve
    // crescimento e um brilho pontual; ficam mais numerosas com a água agitada.
    float bubbles = 0.0;
    const float cellW = 46.0;
    float bottomH = halfExtent - 20.0;           // fundo do recipiente ao longo da gravidade
    float cell = floor(s / cellW);
    float presence = 0.30 + 0.45 * saturate(agitation);
    for (int k = -1; k <= 1; k++) {
        float cc = cell + float(k);
        float baseS = (cc + 0.15 + 0.7 * hash21(float2(cc, 7.3))) * cellW;
        for (int j = 0; j < 3; j++) {
            float id = cc * 3.0 + float(j);
            if (hash21(float2(id, 9.1)) > presence) { continue; }
            float speed = 0.16 + 0.14 * hash21(float2(id, 1.7));        // subidas de ~3 a 6 s
            float p = fract(time * speed + hash21(float2(id, 4.9)));    // 0 = fundo, 1 = superfície
            float bh = mix(bottomH, surfaceH, p);
            float wobble = (2.0 + 3.0 * p) * sin(time * (1.6 + 1.4 * hash21(float2(id, 2.3))) + id * 1.9);
            float bs = baseS + 5.0 * hash21(float2(id, 6.6)) + wobble;
            float rad = (1.2 + 1.6 * hash21(float2(id, 3.1))) * (1.0 + 0.25 * p);
            // Estoura no último trecho: o anel abre e some.
            float pop = smoothstep(0.93, 1.0, p);
            rad *= 1.0 + 0.9 * pop;
            float2 rel = float2(s - bs, h - bh);
            float dist = length(rel);
            float ring = exp(-abs(dist - rad) * 2.0) * 0.50;
            float glint = exp(-length(rel - float2(-0.35 * rad, -0.35 * rad)) * 2.5) * 0.45;
            float below = smoothstep(0.0, 4.0, bh - surfaceH);          // só existe abaixo da linha
            bubbles += (ring + glint) * below * (1.0 - pop);
        }
    }

    float highlightA = saturate(arcs + lineA + lip + band * 0.08 + walls + bubbles) * inside;
    float darkA = lipEdge * inside;

    // branco pré-multiplicado, com o fio escuro por baixo
    float alpha = highlightA + darkA * (1.0 - highlightA);
    return half4(half3(highlightA), half(alpha));
}

// ---------- Refração do conteúdo sob a água ----------
// Roda como `layerEffect` no conteúdo do recipiente (mascote, cabeçalho…). Abaixo da
// superfície a imagem é deslocada por uma ondulação suave, que aumenta com a agitação
// da água, e ganha uma tintura fria leve — como se fosse vista através do líquido.
// `origin` é o canto do conteúdo dentro do retângulo da água (o recipiente pode se
// estender sob a status bar).

[[ stitchable ]] half4 waterRefraction(float2 position, SwiftUI::Layer layer,
                                       float2 size, float2 origin, float time, float level,
                                       float2 down, float agitation,
                                       device const float *field, int count) {
    float2 p = position + origin;
    WaterGeometry g = waterGeometry(p, size, time, level, down, agitation, field, count);

    // Entra aos poucos abaixo da superfície, sem emenda visível na linha d'água.
    float inside = smoothstep(0.0, 10.0, g.d);
    if (inside <= 0.0) { return layer.sample(position); }

    float amp = (2.0 + 1.5 * min(agitation, 1.5)) * inside;
    float2 offset = amp * float2(
        sin(p.y * 0.045 + time * 1.6 + 1.5 * sin(p.x * 0.020 + time * 0.7))
          + 0.4 * sin(p.y * 0.110 - time * 2.3),
        cos(p.x * 0.038 - time * 1.3 + 1.5 * sin(p.y * 0.030 - time * 0.5))
          + 0.4 * cos(p.x * 0.100 + time * 2.0));

    half4 c = layer.sample(position + offset);

    // Tintura fria e leve perda de brilho com a profundidade (pré-multiplicado).
    float depth = saturate(g.d / max(size.y, 1.0));
    float3 cool = float3(0.90, 0.97, 1.05);
    float3 rgb = float3(c.rgb) * mix(float3(1.0), cool, inside * 0.7) * (1.0 - 0.12 * depth * inside);
    rgb = min(rgb, float3(c.a));
    return half4(half3(rgb), c.a);
}
