import Foundation
import os
import SwiftData

private let logger = Logger(subsystem: "com.hidratapoc", category: "Persistence")

/// Compilado nos dois targets, como `IntakeLogService` — o caminho de registrar água
/// é compartilhado com a extensão do widget.
extension ModelContext {
    /// Salva registrando a falha, em vez de `try? save()`.
    ///
    /// O projeto tinha cerca de cem `try? save()`/`try? fetch()`, o que torna uma falha
    /// de persistência indistinguível de "nada a fazer": um registro de água que não
    /// chega ao disco desaparece sem deixar rastro em lugar nenhum. Aqui o erro vai
    /// para o log com o lugar de origem, e o retorno permite ao chamador reagir.
    ///
    /// `operation` é um rótulo curto do que estava sendo salvo ("registro de água",
    /// "meta do dia") — é o que aparece no log.
    @discardableResult
    func saveLogging(
        _ operation: String,
        file: StaticString = #fileID,
        line: UInt = #line
    ) -> Bool {
        guard hasChanges else { return true }
        do {
            try save()
            return true
        } catch {
            logger.error("Falha ao salvar \(operation, privacy: .public) em \(String(describing: file), privacy: .public):\(line, privacy: .public): \(String(describing: error), privacy: .public)")
            return false
        }
    }
}
