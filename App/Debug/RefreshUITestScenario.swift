#if DEBUG
    actor RefreshUITestScenario {
        private var pending = false
        func arm() { pending = true }
        func consume() -> Bool {
            defer { pending = false }
            return pending
        }
    }
#endif
