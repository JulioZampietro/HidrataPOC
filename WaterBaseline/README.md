# Estado-base da água (giroscópio + mola)

Ponto de retorno guardado antes de tornar a água mais fluida:
recipiente com água transparente que acompanha o giroscópio (gravidade passa por uma mola amortecida).

Para voltar a este estado:

    cp WaterBaseline/Bubble.metal.base Bubble.metal
    cp WaterBaseline/HomeView.swift.base HidrataPOC/Views/Home/HomeView.swift

(Os arquivos ficam com extensão `.base` para não entrarem no build.) Pode apagar esta pasta quando não precisar mais.
