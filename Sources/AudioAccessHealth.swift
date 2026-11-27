// Saved setup and a runtime access check are different facts. An unchecked
// session may use previously configured access without repeating onboarding;
// a failed explicit check must not silently restart listening when dismissed.
struct AudioAccessHealth: Equatable {
    enum Status: Equatable {
        case unchecked
        case checking
        case checked
        case failed(String)
    }

    private(set) var status: Status = .unchecked

    mutating func beginCheck() -> Bool {
        guard status != .checking else { return false }
        status = .checking
        return true
    }

    mutating func finishCheck(failure: String?) {
        guard status == .checking else { return }
        status = failure.map(Status.failed) ?? .checked
    }

    var failure: String? {
        if case .failed(let message) = status { return message }
        return nil
    }

    var requiresRecovery: Bool {
        switch status {
        case .checking, .failed: return true
        case .unchecked, .checked: return false
        }
    }

    func permitsAutomaticListening(setupSaved: Bool) -> Bool {
        setupSaved && !requiresRecovery
    }

    func summary(setupSaved: Bool) -> String {
        switch status {
        case .unchecked:
            return setupSaved ? "Setup saved. Open Listening help to verify audio access." : "Audio access has not been set up."
        case .checking: return "Checking audio access…"
        case .checked: return "Audio access checked this session."
        case .failed: return "Audio access needs attention."
        }
    }
}
