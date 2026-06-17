import CoreGraphics
import Foundation

public final class GammaBrightnessController: BrightnessControlling, BrightnessControlResetting {
    private struct TransferFormula {
        var redMin: Float
        var redMax: Float
        var redGamma: Float
        var greenMin: Float
        var greenMax: Float
        var greenGamma: Float
        var blueMin: Float
        var blueMax: Float
        var blueGamma: Float
    }

    private var originalFormulas: [DisplayID: TransferFormula] = [:]
    private var values: [DisplayID: Float] = [:]

    public init() {}

    public func brightness(for displayID: DisplayID) -> Float? {
        values[displayID] ?? 1
    }

    @discardableResult
    public func setBrightness(_ brightness: Float, for displayID: DisplayID) -> Bool {
        let value = min(max(brightness, 0), 1)
        let original = originalFormula(for: displayID)

        if value >= 0.995 {
            let restored = restoreOriginalFormula(for: displayID)
            if restored {
                values[displayID] = 1
            }
            return restored
        }

        let adjusted = CGSetDisplayTransferByFormula(
            displayID,
            original.redMin,
            original.redMax * value,
            original.redGamma,
            original.greenMin,
            original.greenMax * value,
            original.greenGamma,
            original.blueMin,
            original.blueMax * value,
            original.blueGamma
        ) == .success
        if adjusted {
            values[displayID] = value
        }
        return adjusted
    }

    public func reset() {
        for displayID in Array(originalFormulas.keys) {
            _ = restoreOriginalFormula(for: displayID)
        }
        originalFormulas.removeAll()
        values.removeAll()
    }

    public func reset(displayID: DisplayID) {
        _ = restoreOriginalFormula(for: displayID)
        originalFormulas.removeValue(forKey: displayID)
        values.removeValue(forKey: displayID)
    }

    private func restoreOriginalFormula(for displayID: DisplayID) -> Bool {
        guard let original = originalFormulas[displayID] else {
            return true
        }

        return CGSetDisplayTransferByFormula(
            displayID,
            original.redMin,
            original.redMax,
            original.redGamma,
            original.greenMin,
            original.greenMax,
            original.greenGamma,
            original.blueMin,
            original.blueMax,
            original.blueGamma
        ) == .success
    }

    private func originalFormula(for displayID: DisplayID) -> TransferFormula {
        if let formula = originalFormulas[displayID] {
            return formula
        }

        var formula = TransferFormula(
            redMin: 0,
            redMax: 1,
            redGamma: 1,
            greenMin: 0,
            greenMax: 1,
            greenGamma: 1,
            blueMin: 0,
            blueMax: 1,
            blueGamma: 1
        )

        var redMin = formula.redMin
        var redMax = formula.redMax
        var redGamma = formula.redGamma
        var greenMin = formula.greenMin
        var greenMax = formula.greenMax
        var greenGamma = formula.greenGamma
        var blueMin = formula.blueMin
        var blueMax = formula.blueMax
        var blueGamma = formula.blueGamma

        if CGGetDisplayTransferByFormula(
            displayID,
            &redMin,
            &redMax,
            &redGamma,
            &greenMin,
            &greenMax,
            &greenGamma,
            &blueMin,
            &blueMax,
            &blueGamma
        ) == .success {
            formula = TransferFormula(
                redMin: redMin,
                redMax: redMax,
                redGamma: redGamma,
                greenMin: greenMin,
                greenMax: greenMax,
                greenGamma: greenGamma,
                blueMin: blueMin,
                blueMax: blueMax,
                blueGamma: blueGamma
            )
        }

        originalFormulas[displayID] = formula
        return formula
    }
}
