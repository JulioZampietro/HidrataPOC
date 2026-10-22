import SwiftData
import SwiftUI

/// Mantém um `@State` array sincronizado com um fetch filtrado, sem usar `@Query` com
/// predicado — e por isso sem o `init` customizado que causou a regressão do A-2 (ver
/// CORRECOES.md "Regressão encontrada depois da entrega inicial"): configurar um
/// `@Query` novo dentro do `init` de uma view construída pela primeira vez no meio de
/// uma transição do `NavigationStack` (ex. `.navigationDestination(isPresented:)`)
/// travava a transição para sempre, sem crash e sem erro.
///
/// Em vez disso, o fetch roda só dentro de `.task` — que o SwiftUI garante rodar
/// depois de a view já estar na hierarquia, nunca durante a construção — e é
/// atualizado de novo sempre que o `ModelContext` salva algo (`ModelContext.didSave`),
/// o que mantém a mesma reatividade que um `@Query` com predicado teria, sem o custo
/// de materializar a tabela inteira a cada render nem o risco que causou o travamento.
extension View {
    func syncedFetch<Model: PersistentModel>(
        _ state: Binding<[Model]>,
        context: ModelContext,
        descriptor: @escaping () -> FetchDescriptor<Model>
    ) -> some View {
        self
            .task {
                state.wrappedValue = (try? context.fetch(descriptor())) ?? []
            }
            .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
                state.wrappedValue = (try? context.fetch(descriptor())) ?? []
            }
    }
}
