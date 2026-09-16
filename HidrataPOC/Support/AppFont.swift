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
        let base = nunito_preferredFont(forTextStyle: style)
        return UIFont(name: "Nunito", size: base.pointSize) ?? base
    }

    @objc class func nunito_preferredFont(
        forTextStyle style: UIFont.TextStyle,
        compatibleWith traitCollection: UITraitCollection?
    ) -> UIFont {
        let base = nunito_preferredFont(forTextStyle: style, compatibleWith: traitCollection)
        return UIFont(name: "Nunito", size: base.pointSize) ?? base
    }

    private class func nunitoFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let descriptor = UIFontDescriptor()
            .withFamily("Nunito")
            .addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight.rawValue]])
        return UIFont(descriptor: descriptor, size: size)
    }
}

// MARK: - SwiftUI convenience

extension Font {
    static func nunito(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .custom("Nunito", size: style.defaultSize, relativeTo: style).weight(weight)
    }
}

private extension Font.TextStyle {
    var defaultSize: CGFloat {
        switch self {
        case .largeTitle:  return 34
        case .title:       return 28
        case .title2:      return 22
        case .title3:      return 20
        case .headline:    return 17
        case .body:        return 17
        case .callout:     return 16
        case .subheadline: return 15
        case .footnote:    return 13
        case .caption:     return 12
        case .caption2:    return 11
        @unknown default:  return 17
        }
    }
}
