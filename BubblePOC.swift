//
//  BubblePOC.swift
//  HidrataPOC
//
//  Created by Gabriel Amaral on 24/09/26.
//

import SwiftUI

struct BubbleView: View {
    // Guardamos o instante inicial para o "time" começar em 0 (evita floats gigantes)
    @State private var start = Date()

    var body: some View {
        // TimelineView(.animation) re-renderiza a cada frame da tela
        TimelineView(.animation) { context in
            let time = Float(start.distance(to: context.date))

            GeometryReader { geo in
                ZStack {
                    Image("mascote4")
                    Rectangle()
                        .fill(Color.white) // conteúdo de base; o shader ignora essa cor
                        .colorEffect(
                            ShaderLibrary.bubble(          // nome da função no .metal
                                .float2(geo.size),         // parâmetro `size`
                                .float(time)               // parâmetro `time`
                            )
                        )
                }
            }
        }
        .aspectRatio(1, contentMode: .fit) // o shader assume um quadrado
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        BubbleView()
            .frame(width: 300, height: 300)
    }
}
