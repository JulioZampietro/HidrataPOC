import ObjectiveC
import UIKit
import SwiftUI

// MARK: - Global font replacement

/// Troca os métodos de fonte do sistema por Nunito via Objective-C runtime.
/// Deve ser chamado uma única vez antes de qualquer UI ser renderizada.
func applyNunitoGlobally() {
    swizzleClassMethod(UIFont.self,
        from: #selector(UIFont.systemFont(ofSize:)),
        to: #selector(UIFont.nunito_systemFont(ofSize:)))
    swizzleClassMethod(UIFont.self,
        from: #selector(UIFont.systemFont(ofSize:weight:)),
        to: #selector(UIFont.nunito_systemFont(ofSize:weight:)))
    swizzleClassMethod(UIFont.self,
        from: #selector(UIFont.boldSystemFont(ofSize:)),
        to: #selector(UIFont.nunito_boldSystemFont(ofSize:)))
    swizzleClassMethod(UIFont.self,
        from: #selector(UIFont.preferredFont(forTextStyle:)),
        to: #selector(UIFont.nunito_preferredFont(forTextStyle:)))
    swizzleClassMethod(UIFont.self,
        from: #selector(UIFont.preferredFont(forTextStyle:compatibleWith:)),
        to: #selector(UIFont.nunito_preferredFont(forTextStyle:compatibleWith:)))
}

/// Mantém a barra de navegação (título e botões como "Fechar", "Salvar") em SF Pro,
/// apesar da troca global por Nunito — é a barra dos sheets do app. As fontes vêm de
/// descritores do sistema, que não passam pelos métodos trocados acima.
@MainActor
func applySystemFontToNavigationBars() {
    let navigationBar = UINavigationBar.appearance()
    navigationBar.titleTextAttributes = [.font: sfPro(.headline)]
    navigationBar.largeTitleTextAttributes = [.font: sfPro(.largeTitle, traits: .traitBold)]

    let button = sfPro(.body)
    for state: UIControl.State in [.normal, .highlighted, .disabled, .focused] {
        UIBarButtonItem.appearance().setTitleTextAttributes([.font: button], for: state)
    }
}

private func sfPro(_ style: UIFont.TextStyle, traits: UIFontDescriptor.SymbolicTraits = []) -> UIFont {
    var descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: style)
    if !traits.isEmpty, let withTraits = descriptor.withSymbolicTraits(traits) {
        descriptor = withTraits
    }
    return UIFont(descriptor: descriptor, size: 0)
}

private func swizzleClassMethod(_ cls: AnyClass, from original: Selector, to replacement: Selector) {
    guard
        let originalMethod = class_getClassMethod(cls, original),
        let replacementMethod = class_getClassMethod(cls, replacement)
    else { return }
    method_exchangeImplementations(originalMethod, replacementMethod)
}

// MARK: - UIFont extension

extension UIFont {
    @objc class func nunito_systemFont(ofSize size: CGFloat) -> UIFont {
        UIFont(name: "Nunito", size: size) ?? nunito_systemFont(ofSize: size)
    }

    @objc class func nunito_systemFont(ofSize size: CGFloat, weight: UIFont.Weight) -> UIFont {
        nunitoFont(size: size, weight: weight)
    }

    @objc class func nunito_boldSystemFont(ofSize size: CGFloat) -> UIFont {
        nunitoFont(size: size, weight: .bold)
    }

    @objc class func nunito_preferredFont(forTextStyle style: UIFont.TextStyle) -> UIFont {
        nunitoMatching(nunito_preferredFont(forTextStyle: style))
    }

    @objc class func nunito_preferredFont(
        forTextStyle style: UIFont.TextStyle,
        compatibleWith traitCollection: UITraitCollection?
    ) -> UIFont {
        nunitoMatching(nunito_preferredFont(forTextStyle: style, compatibleWith: traitCollection))
    }

    /// Nunito no tamanho e no peso da fonte de sistema recebida — sem isso estilos
    /// como `.headline` (semibold) perdiam o peso e viravam regular.
    private class func nunitoMatching(_ base: UIFont) -> UIFont {
        let traits = base.fontDescriptor.object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any]
        let weight = (traits?[.weight] as? CGFloat).map(UIFont.Weight.init(rawValue:)) ?? .regular
        return nunitoFont(size: base.pointSize, weight: weight)
    }

    private class func nunitoFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let descriptor = UIFontDescriptor()
            .withFamily("Nunito")
            .addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight.rawValue]])
        return UIFont(descriptor: descriptor, size: size)
    }
}

// MARK: - Catálogo de fontes do app

/// Única porta de entrada para fontes no SwiftUI. As telas usam estes estilos em vez de
/// `.font(.custom("Nunito", size:))`, então trocar tamanho, peso ou família é mexer só aqui.
///
/// Todos os estilos escalam com o Dynamic Type seguindo a curva do `Font.TextStyle`
/// indicado em `relativeTo`. Só há três pesos — regular, bold e heavy; o Nunito é uma
/// fonte variável (`Nunito.ttf`), então qualquer peso sai dela sem arquivos estáticos.
///
/// Ícones (SF Symbols) continuam usando `.font(.system(...))`: ali a fonte só dimensiona
/// o símbolo, não é texto.
enum AppFont {
    private static let family = "Nunito"
    private static let displayFamily = "Baloo2-ExtraBold"

    // MARK: Títulos e números

    /// Números grandes (meta diária, estatísticas).
    static let metric = nunito(40, .heavy, relativeTo: .largeTitle)
    static let largeTitle = nunito(34, .heavy, relativeTo: .largeTitle)
    static let title = nunito(26, .heavy, relativeTo: .title)
    static let title2 = nunito(22, .heavy, relativeTo: .title2)
    static let title3 = nunito(18, .bold, relativeTo: .title3)
    /// Título de cartão e rótulo principal de botão grande.
    static let headline = nunito(17, .heavy, relativeTo: .headline)

    // MARK: Texto corrido

    static let body = nunito(17, .regular, relativeTo: .body)
    static let callout = nunito(16, .regular, relativeTo: .callout)
    /// Botões e valores de linhas de lista.
    static let calloutStrong = nunito(16, .bold, relativeTo: .callout)
    static let subheadline = nunito(15, .regular, relativeTo: .subheadline)
    static let subheadlineStrong = nunito(15, .bold, relativeTo: .subheadline)
    static let subheadlineHeavy = nunito(15, .heavy, relativeTo: .subheadline)
    static let footnote = nunito(13, .regular, relativeTo: .footnote)
    static let footnoteStrong = nunito(13, .bold, relativeTo: .footnote)
    static let caption = nunito(12, .regular, relativeTo: .caption)
    static let captionStrong = nunito(12, .bold, relativeTo: .caption)

    // MARK: Display (Baloo 2) — títulos do calendário

    static let displayTitle = Font.custom(displayFamily, size: 21, relativeTo: .title2)
    static let displayNumber = Font.custom(displayFamily, size: 14, relativeTo: .subheadline)

    // MARK: Tamanho fixo

    /// Para arte que não pode mudar com o Dynamic Type — o cartão de compartilhar é
    /// uma imagem 360×640 e tem que sair igual em qualquer configuração.
    static func fixed(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom(family, fixedSize: size).weight(weight)
    }

    private static func nunito(_ size: CGFloat, _ weight: Font.Weight, relativeTo style: Font.TextStyle) -> Font {
        .custom(family, size: size, relativeTo: style).weight(weight)
    }
}
