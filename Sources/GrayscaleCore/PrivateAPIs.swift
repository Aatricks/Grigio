import CPrivateAPIs
import Foundation
import ObjectiveC
import QuartzCore

public struct PrivateAPIStatus: Equatable, Sendable {
    public let backdropLayerAvailable: Bool
    public let colorFilterAvailable: Bool
    public let managedSpacesAvailable: Bool
}

public enum PrivateAPIError: Error, CustomStringConvertible {
    case classUnavailable(String)
    case selectorUnavailable(className: String, selector: String)
    case creationFailed(String)

    public var description: String {
        switch self {
        case let .classUnavailable(name):
            return "Private class \(name) is unavailable"
        case let .selectorUnavailable(className, selector):
            return "Private selector \(className).\(selector) is unavailable"
        case let .creationFailed(type):
            return "Private \(type) creation failed"
        }
    }
}

public enum PrivateAPIs {
    public static func probe() -> PrivateAPIStatus {
        PrivateAPIStatus(
            backdropLayerAvailable: NSClassFromString("CABackdropLayer") != nil,
            colorFilterAvailable: NSClassFromString("CAFilter") != nil,
            managedSpacesAvailable: GrayscaleManagedSpacesAPIAvailable()
        )
    }

    public static func makeColorSaturateFilter(amount: Double) throws -> NSObject {
        guard let filterClass = NSClassFromString("CAFilter") else {
            throw PrivateAPIError.classUnavailable("CAFilter")
        }

        let selector = NSSelectorFromString("filterWithType:")
        guard let method = class_getClassMethod(filterClass, selector) else {
            throw PrivateAPIError.selectorUnavailable(
                className: "CAFilter",
                selector: NSStringFromSelector(selector)
            )
        }

        typealias Factory = @convention(c) (AnyClass, Selector, NSString) -> AnyObject?
        let factory = unsafeBitCast(method_getImplementation(method), to: Factory.self)
        guard let filter = factory(filterClass, selector, "colorSaturate") as? NSObject else {
            throw PrivateAPIError.creationFailed("CAFilter")
        }

        filter.setValue(amount, forKey: "inputAmount")
        return filter
    }

    public static func makeBackdropLayer() throws -> CALayer {
        guard let layerType = NSClassFromString("CABackdropLayer") as? CALayer.Type else {
            throw PrivateAPIError.classUnavailable("CABackdropLayer")
        }

        let layer = layerType.init()
        setValue(true, forPrivateKey: "windowServerAware", on: layer)
        setValue(true, forPrivateKey: "allowsGroupBlending", on: layer)
        setValue(false, forPrivateKey: "allowsInPlaceFiltering", on: layer)
        setValue(true, forPrivateKey: "disablesOccludedBackdropBlurs", on: layer)
        setValue(true, forPrivateKey: "ignoresOffscreenGroups", on: layer)
        setValue(1.0, forPrivateKey: "scale", on: layer)
        setValue(0.0, forPrivateKey: "bleedAmount", on: layer)
        return layer
    }

    public static func setValue(_ value: Any, forPrivateKey key: String, on object: NSObject) {
        let first = key.prefix(1).uppercased()
        let remainder = key.dropFirst()
        let setter = NSSelectorFromString("set\(first)\(remainder):")
        guard object.responds(to: setter) else { return }
        object.setValue(value, forKey: key)
    }
}
