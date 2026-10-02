#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// ---------- Ajustes da água (valores para mexer à mão) ----------
// Superfície
constant float kSwellAmp        = 1.0;    // multiplica as 3 ondas longas (base: 1.9 / 1.1 / 0.55 pt)
constant float kCrestSharpness  = 0.012;  // arredondamento da crista: menor = mais afiada (antigo: 0.04)
constant float kChopAmp         = 1.6;    // marolas curtas que surgem com a água mexida (pt)
constant float kCapillaryAmp    = 0.22;   // ondulação capilar mais longa (pt); as outras são frações dela
constant float kMeniscusAmp     = 1.6;    // quanto a água sobe ao encostar na parede (pt; antigo: 5)
constant float kMeniscusWidth   = 3.5;    // alcance do menisco (pt; antigo: 9)
constant float kLineSharpness   = 2.0;    // nitidez do contorno: maior = linha mais fina
// Luz
constant float kSparkleSharp    = 260.0;  // expoente do brilho pontual: maior = pontos menores e mais raros
constant float kSparkleAlpha    = 0.95;
// Bolhas
constant float kBubbleRestPresence  = 0.60; // fração de bolhas ativas com a água parada
constant float kBubbleShakePresence = 0.85; // fração logo após uma sacudida forte
constant float kBubbleRiseSpeed     = 65.0; // pt/s de subida (as grandes sobem um pouco mais rápido)
// Refração do conteúdo
constant float kRefractAmp      = 3.45;    // deslocamento base (pt); cresce com a agitação e perto da superfície
constant float kRefractLens     = 6.0;    // quanto a imagem acompanha a inclinação das ondas logo abaixo da linha
constant float kRefractMax      = 9.5;    // limite do deslocamento (pt) — manter < maxSampleOffset no Swift
constant float3 kWaterTint      = float3(0.1098, 0.4627, 0.9922); // azul de destaque do app (#1C76FD)
constant float kTintSurface     = 0.18;   // quanto do azul cobre o conteúdo logo abaixo da superfície
constant float kTintDeep        = 0.45;   // …e no fundo do recipiente (cresce com a profundidade)
constant float kAccentAmount    = 0.5;    // 0 = tintura fria antiga, 1 = só o azul de destaque
// Gotas (a física fica no Swift, em `WaterTuning`)
constant int   kMaxDrops        = 32;     // igual a `WaterTuning.maxDroplets`
constant float kDropRimAlpha    = 0.55;   // aro branco fino
constant float kDropGlintAlpha  = 0.90;   // pontinho de reflexo no alto, à esquerda
constant float kDropDarkAlpha   = 0.16;   // fio escuro do lado oposto (aparece em fundo claro)
constant float kDropShadowAlpha = 0.06;   // sombra na camada de trás

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
// (y para baixo), `field` traz os deslocamentos da superfície, em pontos,
// ao longo dela (positivo = mais fundo), `fizz` a quantidade de bolhas e `drops`
// as gotas no ar (ver `shadeDrops`).
// Roda em duas camadas sobre o mesmo retângulo:
//   front = 0 → sombra suave (atrás do mascote), inclusive a das gotas
//   front = 1 → realces brancos, contorno, bolhas e gotas (na frente do mascote)
// Coordenadas em pontos, y para baixo.

static float sampleField(device const float *field, int count, float u) {
    float x = clamp(u, 0.0, 1.0) * float(count - 1);
    int i0 = int(floor(x));
    int i1 = min(i0 + 1, count - 1);
    return mix(field[i0], field[i1], x - float(i0));
}

// Onda trocoidal (fase → altura para cima, média ≈ 0): cristas afiadas, vales achatados.
// `sharp` arredonda a ponta da crista para não virar um bico. Devolve (altura, d/dfase).
static float2 crestWave(float phase, float sharp) {
    float c = cos(phase);
    float r = sqrt(c * c + sharp);
    return float2(1.0 - r - 0.35, c * sin(phase) / r);
}

// Onda longa com a fase deformada por outra onda (para não repetir de forma regular).
// Devolve (altura para cima, inclinação d/ds).
static float2 swell(float s, float time, float amp, float k, float w,
                    float warpAmp, float warpK, float warpW) {
    float warpPhase = s * warpK + time * warpW;
    float phase = s * k + time * w + warpAmp * sin(warpPhase);
    float dPhase = k + warpAmp * warpK * cos(warpPhase);
    float2 cw = crestWave(phase, kCrestSharpness);
    return amp * float2(cw.x, cw.y * dPhase);
}

// Ondulação capilar senoidal. Devolve (altura para cima, inclinação d/ds).
static float2 ripple(float s, float time, float amp, float k, float w) {
    float phase = s * k + time * w;
    return amp * float2(sin(phase), k * cos(phase));
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
    float baseH;      // profundidade da superfície em repouso (só o nível)
    float surfaceH;   // profundidade da superfície neste ponto
    float slope;      // d(surfaceH)/ds: positivo = a superfície afunda na direção +s
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

    // Forma da superfície. As ondas são "altura para cima" (x) com a inclinação d/ds (y),
    // subtraídas de surfaceH, que cresce a favor da gravidade. A inclinação é calculada
    // junto (derivada analítica), então quem desenha não precisa reavaliar a geometria.
    float eta = sampleField(field, count, u);
    float du = 1.0 / float(count - 1);
    float fieldSlope = (sampleField(field, count, u + du) - sampleField(field, count, u - du)) / (2.0 * du * len);

    // 1. Ondas longas trocoidais: cristas afiadas e vales achatados (uma senoide pura é
    //    simétrica e parece borracha). Quanto mais curta, mais rápida e mais baixa.
    float2 waves = swell(s, time, 1.90 * kSwellAmp, 0.024,  1.25, 0.8, 0.011, -0.6)
                 + swell(s, time, 1.10 * kSwellAmp, 0.043, -1.75, 0.6, 0.019,  0.45)
                 + swell(s, time, 0.55 * kSwellAmp, 0.071,  2.40, 0.4, 0.029, -0.9);

    // 2. Marolas: onde a superfície está inclinada ou a água agitada, surgem ondas curtas
    //    e rápidas por cima do balanço.
    float chopMask = saturate(abs(fieldSlope) * 3.0 + 0.6 * agitation);
    waves += chopMask * (swell(s, time, kChopAmp,       0.115,  4.3, 0.9, 0.037, -1.3)
                       + swell(s, time, 0.5 * kChopAmp, 0.200, -6.1, 0.5, 0.050,  1.7));

    // 3. Ondulação capilar: ondas finas (λ ≈ 6 a 18 pt), quanto mais curtas mais rápidas,
    //    em manchas que passeiam pela superfície e crescem com a agitação. Quase não mexem
    //    a linha, mas inclinam a superfície o bastante para cintilar.
    float capEnv = (0.3 + 0.7 * vnoise(float2(s * 0.017 - time * 0.4, time * 0.23))) * (1.0 + 2.0 * chopMask);
    waves += capEnv * (ripple(s, time, kCapillaryAmp,        0.36,   9.4)
                     + ripple(s, time, 0.55 * kCapillaryAmp, 0.63, -20.0)
                     + ripple(s, time, 0.30 * kCapillaryAmp, 1.08,  43.0));

    // 4. Menisco: a água sobe um pouco ao encostar nas paredes laterais (fino e curto).
    float wallDist = min(position.x, size.x - position.x);
    float meniscus = kMeniscusAmp * exp(-wallDist / kMeniscusWidth);
    float wallSign = position.x < 0.5 * size.x ? 1.0 : -1.0;          // d(wallDist)/dx
    float meniscusSlope = -meniscus / kMeniscusWidth * wallSign * t.x;  // d(meniscus)/ds

    float surfaceH = baseH + eta - waves.x - meniscus;

    WaterGeometry g;
    g.d = h - surfaceH;                            // > 0 dentro da água
    g.h = h; g.s = s; g.u = u; g.len = len; g.halfExtent = halfExtent;
    g.baseH = baseH; g.surfaceH = surfaceH;
    g.slope = fieldSlope - waves.y - meniscusSlope;
    return g;
}

// Gotas no ar. `drops` = [minX, minY, maxX, maxY] (área que contém todas, com folga)
// seguido de 6 floats por gota: x, y, raio, opacidade e o alongamento (vetor na direção
// da velocidade; o comprimento é quanto ela estica). Mesmo visual da água: miolo
// transparente, aro branco fino, um ponto de reflexo nítido no alto à esquerda e, do
// lado oposto, um fio escuro levíssimo. Na camada de trás, só uma sombra fraquíssima.
struct DropShade {
    float hi;    // realce branco (pré-multiplicado)
    float dark;  // fio escuro / sombra
};

static DropShade shadeDrops(float2 p, bool shadowLayer, device const float *drops, int count) {
    DropShade o = { 0.0, 0.0 };
    if (count < 10) { return o; }
    if (p.x < drops[0] || p.y < drops[1] || p.x > drops[2] || p.y > drops[3]) { return o; }

    int n = min((count - 4) / 6, kMaxDrops);
    for (int i = 0; i < n; i++) {
        int b = 4 + i * 6;
        float2 center = float2(drops[b], drops[b + 1]);
        float r = drops[b + 2];
        float a = drops[b + 3];
        float2 stretch = float2(drops[b + 4], drops[b + 5]);
        float el = length(stretch);
        float reach = r * (1.0 + el) + 3.0;

        if (shadowLayer) {
            float2 rel = p - center - float2(1.2, 2.4);    // um pouco abaixo e à direita
            if (dot(rel, rel) > reach * reach) { continue; }
            o.dark += (1.0 - smoothstep(0.4 * r, 1.6 * r, length(rel))) * kDropShadowAlpha * a;
            continue;
        }

        float2 rel = p - center;
        if (dot(rel, rel) > reach * reach) { continue; }  // só olha gotas perto do pixel

        // Elipse esticada ao longo da velocidade (área mantida).
        float2 dir = el > 1e-3 ? stretch / el : float2(1.0, 0.0);
        float k = 1.0 + el;
        float2 q = float2(dot(rel, dir) / k, dot(rel, float2(-dir.y, dir.x)) * sqrt(k));
        float sd = length(q) - r;                        // < 0 dentro da gota
        float2 nrm = rel / max(length(rel), 1e-3);

        // Aro branco fino (~1 pt) por dentro do contorno, mais forte do lado da luz.
        float rim = 1.0 - smoothstep(0.35, 1.0, abs(sd + 0.5));
        float lit = saturate(dot(nrm, float2(-0.6, -0.8)));
        float gr = max(0.45, 0.28 * r);
        float glint = 1.0 - smoothstep(0.45 * gr, gr, length(rel - float2(-0.38, -0.45) * r));
        float hi = saturate(rim * kDropRimAlpha * (0.6 + 0.6 * lit) + glint * kDropGlintAlpha) * a;

        // Fio escuro levíssimo logo fora do contorno, do lado oposto à luz.
        float away = saturate(dot(nrm, float2(0.6, 0.8)));
        float dark = (1.0 - smoothstep(0.25, 0.9, abs(sd - 0.35))) * away * sqrt(away) * kDropDarkAlpha * a;

        o.hi = max(o.hi, hi);
        o.dark = max(o.dark, dark);
    }
    return o;
}

[[ stitchable ]] half4 water(float2 position, half4 color, float2 size, float time,
                             float level, float2 down, float agitation, float fizz, float front,
                             device const float *field, int count,
                             device const float *drops, int dropCount) {

    WaterGeometry g = waterGeometry(position, size, time, level, down, agitation, field, count);
    float d = g.d, h = g.h, s = g.s, u = g.u;
    float halfExtent = g.halfExtent, surfaceH = g.surfaceH;
    float inside = 1.0 - smoothstep(-0.5, 0.5, -d); // silhueta com borda nítida (~1 pt)

    // Gotas: ficam no ar, fora da água, então são desenhadas antes do retorno abaixo.
    // Uma gota some ao voltar a cruzar a superfície: pixels já fundos nem olham a lista.
    DropShade drop = { 0.0, 0.0 };
    if (d < 6.0) { drop = shadeDrops(position, front < 0.5, drops, dropCount); }

    if (inside <= 0.0) {
        float dropA = drop.hi + drop.dark * (1.0 - drop.hi);
        return half4(half3(drop.hi), half(saturate(dropA)));
    }

    if (front < 0.5) {
        // Sombra levíssima junto da superfície (e a das gotas logo acima dela)
        float shadowA = saturate(exp(-max(d, 0.0) / 4.0) * 0.06 * inside + drop.dark);
        return half4(0.0h, 0.0h, 0.0h, half(shadowA));
    }

    float slope = g.slope;
    float steep = saturate(abs(slope) * 3.0);

    // Reflexo especular: a luz vem de cima e da esquerda, então só as faces das ondas
    // viradas para ela brilham. `sheen` é o brilho largo e suave; `sparkle` são pontos
    // nítidos que acendem e apagam conforme as ondulações capilares passam.
    float2 normal = normalize(float2(slope, 1.0));           // y = "para cima" da água
    float2 lightDir = normalize(float2(-0.6, 1.0));
    float2 halfVec = normalize(lightDir + float2(0.0, 1.0)); // vista de frente
    float nh = saturate(dot(normal, halfVec));
    float sheen = saturate((pow(nh, 40.0) - 0.15) / 0.85);
    float sparkle = pow(nh, kSparkleSharp);

    // Linha fina e nítida no contorno da superfície; engrossa um pouco onde a onda é íngreme.
    float edgeLine = exp(-abs(d - 0.7) * (kLineSharpness - 0.8 * steep)) * inside;
    float lineA = edgeLine * (0.22 + 0.40 * sheen);
    float glint = sparkle * exp(-abs(d - 0.8) * 1.2) * kSparkleAlpha;

    // Espessura da superfície: faixa translúcida bem estreita logo abaixo da linha, com um
    // fio tênue marcando onde ela termina.
    float lip = smoothstep(0.4, 1.2, d) * (1.0 - smoothstep(2.0, 4.5, d)) * (0.03 + 0.08 * sheen);
    float lipEdge = exp(-abs(d - 4.0) * 1.2) * 0.025;

    // Dois reflexos largos e fracos que deslizam devagar, colados na superfície
    float near = exp(-max(d, 0.0) / 4.0);
    float a1 = 0.25 + 0.10 * sin(time * 0.6);
    float a2 = 0.75 + 0.10 * sin(time * 0.5 + 1.0);
    float arc1 = pow(max(cos((u - a1) * 6.2832 * 0.9), 0.0), 8.0);
    float arc2 = pow(max(cos((u - a2) * 6.2832 * 0.9), 0.0), 12.0);
    float arcs = (arc1 * 0.22 + arc2 * 0.12) * near;

    // Contorno fino nas paredes do recipiente (só onde há água)
    float wallDist = min(position.x, size.x - position.x);
    float bottomDist = size.y - position.y;
    float walls = (exp(-wallDist * 1.8) + exp(-bottomDist * 1.8)) * 0.24 * inside;

    // Bolhas: sobem sempre, mesmo com a água parada; depois de uma sacudida (`fizz`) surgem mais pelo corpo
    // da água e sobem rápido, contra a gravidade. Tamanhos variados (muitas pequenas,
    // poucas grandes); as grandes sobem mais rápido e em zigue-zague, as pequenas quase
    // retas. Somem com um anel que abre ao chegar na superfície.
    float bubbles = 0.0;
    float presence = kBubbleRestPresence + (kBubbleShakePresence - kBubbleRestPresence) * saturate(fizz);
    const float cellW = 40.0;
    float bottomH = halfExtent - 20.0;           // fundo do recipiente ao longo da gravidade
    // Ciclo fixo (não depende da inclinação): com `time` grande, qualquer variação aqui
    // faria as bolhas saltarem de lugar a cada frame enquanto o celular se mexe.
    float cycleLen = max(size.x + size.y, 1.0);
    float cell = floor(s / cellW);
    for (int k = -1; k <= 1; k++) {
        float cc = cell + float(k);
        float baseS = (cc + 0.15 + 0.7 * hash21(float2(cc, 7.3))) * cellW;
        for (int j = 0; j < 3; j++) {
            float id = cc * 3.0 + float(j);
            // Aparece/some suavemente conforme `fizz` sobe e desce.
            float vis = 1.0 - smoothstep(presence - 0.06, presence, hash21(float2(id, 9.1)));
            if (vis <= 0.0) { continue; }
            float rad = 0.7 + 3.2 * pow(hash21(float2(id, 3.1)), 2.5);
            float riseSpeed = kBubbleRiseSpeed * (0.7 + 0.5 * hash21(float2(id, 1.7))) + 12.0 * rad; // pt/s
            // Percorre a altura toda do recipiente; acima da superfície já estourou.
            float p = fract(time * riseSpeed / cycleLen + hash21(float2(id, 4.9)));
            float bh = bottomH - p * cycleLen;
            float above = bh - surfaceH;               // > 0 enquanto está abaixo da superfície
            if (above <= 0.0) { continue; }
            float zig = (0.3 + 0.5 * rad) * sin(time * (1.8 + 1.2 * hash21(float2(id, 2.3))) + id * 1.9);
            float bs = baseS + 5.0 * hash21(float2(id, 6.6)) + zig;
            float2 rel = float2(s - bs, h - bh);
            float pop = 1.0 - smoothstep(0.0, 4.0, above);       // estoura nos últimos 4 pt
            float r = rad * (1.0 + 0.8 * pop);
            float dist = length(rel);
            if (dist > r + 4.0) { continue; }
            float ring = exp(-abs(dist - r) * 3.0) * 0.55;
            float glint = exp(-length(rel - float2(-0.35 * r, -0.35 * r)) * 3.0) * 0.45;
            bubbles += (ring + glint) * vis * (1.0 - pop);
        }
    }

    float highlightA = saturate(saturate(arcs + lineA + glint + lip + near * 0.012 + walls + bubbles) * inside
                                + drop.hi);
    float darkA = max(lipEdge * inside, drop.dark);

    // branco pré-multiplicado, com o fio escuro por baixo
    float alpha = highlightA + darkA * (1.0 - highlightA);
    return half4(half3(highlightA), half(alpha));
}

// ---------- Refração do conteúdo sob a água ----------
// Roda como `layerEffect` no conteúdo do recipiente (mascote, cabeçalho…). Abaixo da
// superfície a imagem é deslocada (sem blur: só muda de onde cada pixel é lido) por
// ondulações rápidas e finas, mais fortes perto da superfície e com a água agitada;
// logo abaixo da linha ela acompanha a inclinação das ondas, como uma lente. Ganha
// ainda uma tintura azulada (ver `kAccentAmount`) — como se fosse vista através do líquido.
// `origin` é o canto do conteúdo dentro do retângulo da água (o recipiente pode se
// estender sob a status bar).

[[ stitchable ]] half4 waterRefraction(float2 position, SwiftUI::Layer layer,
                                       float2 size, float2 origin, float time, float level,
                                       float2 down, float agitation,
                                       device const float *field, int count) {
    float2 p = position + origin;
    WaterGeometry g = waterGeometry(p, size, time, level, down, agitation, field, count);

    // Entra aos poucos abaixo da superfície, sem emenda visível na linha d'água.
    float inside = smoothstep(0.0, 6.0, g.d);
    if (inside <= 0.0) { return layer.sample(position); }

    // Mais forte perto da superfície, menor em profundidade.
    float nearSurface = exp(-g.d / 22.0);
    float amp = kRefractAmp * (1.0 + 0.9 * min(agitation, 1.5)) * (0.35 + 1.0 * nearSurface) * inside;
    float2 offset = amp * float2(
        sin(p.y * 0.052 + time * 2.1 + 1.4 * sin(p.x * 0.024 + time * 0.9))
          + 0.45 * sin(p.y * 0.130 + p.x * 0.030 - time * 3.4),
        cos(p.x * 0.047 - time * 1.8 + 1.4 * sin(p.y * 0.035 - time * 0.7))
          + 0.45 * cos(p.x * 0.120 - p.y * 0.020 + time * 3.0));

    // Lente da superfície: logo abaixo da linha, a imagem é empurrada ao longo da
    // gravidade conforme a inclinação da onda que passa por cima.
    float lens = exp(-g.d / 9.0) * inside;
    offset += normalize(down) * (clamp(g.slope, -0.4, 0.4) * kRefractLens * lens);
    offset = clamp(offset, -kRefractMax, kRefractMax);

    half4 c = layer.sample(position + offset);

    // Duas tinturas misturadas por `kAccentAmount` (pré-multiplicado): a fria antiga, com
    // leve perda de brilho no fundo, e a no azul de destaque, mais forte com a profundidade.
    float depth = saturate(g.d / max(size.y, 1.0));
    float3 base = float3(c.rgb);
    float3 cool = base * mix(float3(1.0), float3(0.90, 0.97, 1.05), inside * 0.7) * (1.0 - 0.12 * depth * inside);
    cool = min(cool, float3(c.a));
    float3 accent = mix(base, kWaterTint * float(c.a), inside * mix(kTintSurface, kTintDeep, depth));
    float3 rgb = mix(cool, accent, kAccentAmount);
    return half4(half3(rgb), c.a);
}
