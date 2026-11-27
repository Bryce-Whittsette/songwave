import SwiftUI

private struct AdditionalMotionReduction: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    // May request more reduction (including in tests), never negate the OS setting.
    var songWaveAdditionalMotionReduction: Bool {
        get { self[AdditionalMotionReduction.self] }
        set { self[AdditionalMotionReduction.self] = newValue }
    }
}
enum AccessibleMotion {
    static func reduced(system: Bool, additional: Bool) -> Bool { system || additional }
    static func apply(to transaction: inout Transaction, reduced: Bool) {
        if reduced { transaction.animation = nil; transaction.disablesAnimations = true }
    }
}
