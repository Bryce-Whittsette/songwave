// No Core Audio, system consent, app preferences, speakers or motors are used.
@main struct AccessRegression {
    static func main() {
        var health = AudioAccessHealth()
        precondition(!health.permitsAutomaticListening(setupSaved: false),
                     "A first launch must not assume setup was completed.")
        precondition(health.permitsAutomaticListening(setupSaved: true),
                     "Saved setup must permit normal launch listening without another app prompt.")

        health.finishCheck(failure: nil)
        precondition(health.status == .unchecked, "A stale callback must not verify unchecked access.")
        precondition(health.beginCheck())
        precondition(!health.beginCheck(), "Concurrent checks must not restart the state machine.")
        precondition(!health.permitsAutomaticListening(setupSaved: true),
                     "Dismissing a pending check must not start listening.")

        health.finishCheck(failure: "System audio access is off.")
        precondition(health.failure == "System audio access is off.")
        precondition(health.requiresRecovery)
        precondition(!health.permitsAutomaticListening(setupSaved: true),
                     "Saved setup must not override a failed runtime recheck on Done or wake.")
        health.finishCheck(failure: nil)
        precondition(health.failure != nil, "An unsolicited success must not clear a known failure.")

        precondition(health.beginCheck())
        health.finishCheck(failure: nil)
        precondition(health.failure == nil && !health.requiresRecovery)
        precondition(health.permitsAutomaticListening(setupSaved: true),
                     "An explicit successful retry must allow listening to resume.")
        precondition(!health.permitsAutomaticListening(setupSaved: false),
                     "Runtime health is not a substitute for persisted setup completion.")

        let relaunched = AudioAccessHealth()
        precondition(relaunched.status == .unchecked && relaunched.permitsAutomaticListening(setupSaved: true),
                     "Last-session check status must not masquerade as current OS authorization.")
        print("Saved setup, failed/pending check suppression, explicit recovery, and relaunch semantics passed.")
    }
}
