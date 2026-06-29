import Foundation

enum SearchPipelineStep: Int, CaseIterable, Identifiable, Hashable {
    case spotlight
    case filtering
    case enriching
    case checkingOllama
    case ranking

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .spotlight: return "Spotlight"
        case .filtering: return "Filtered"
        case .enriching: return "Reading metadata"
        case .checkingOllama: return "Connecting to Ollama"
        case .ranking: return "Ranking"
        }
    }
}

enum SearchStepStatus: Equatable {
    case pending
    case active(detail: String?)
    case completed(detail: String?)
}

struct SearchProgress: Equatable {
    private(set) var steps: [SearchPipelineStep: SearchStepStatus]

    static var initial: SearchProgress {
        var steps: [SearchPipelineStep: SearchStepStatus] = [:]
        for step in SearchPipelineStep.allCases {
            steps[step] = .pending
        }
        return SearchProgress(steps: steps)
    }

    init(steps: [SearchPipelineStep: SearchStepStatus]) {
        self.steps = steps
    }

    func status(for step: SearchPipelineStep) -> SearchStepStatus {
        steps[step] ?? .pending
    }

    mutating func activate(_ step: SearchPipelineStep, detail: String? = nil) {
        for prior in SearchPipelineStep.allCases where prior.rawValue < step.rawValue {
            switch steps[prior] ?? .pending {
            case .pending, .active:
                steps[prior] = .completed(detail: completedDetail(for: prior))
            case .completed:
                break
            }
        }
        steps[step] = .active(detail: detail)
    }

    mutating func updateActive(_ step: SearchPipelineStep, detail: String?) {
        steps[step] = .active(detail: detail)
    }

    mutating func complete(_ step: SearchPipelineStep, detail: String? = nil) {
        steps[step] = .completed(detail: detail)
    }

    mutating func completeRemaining(from step: SearchPipelineStep, detail: String? = nil) {
        for remaining in SearchPipelineStep.allCases where remaining.rawValue >= step.rawValue {
            if case .completed = steps[remaining] ?? .pending {
                continue
            }
            steps[remaining] = .completed(detail: remaining == step ? detail : nil)
        }
    }

    private func completedDetail(for step: SearchPipelineStep) -> String? {
        if case .completed(let detail) = steps[step] ?? .pending {
            return detail
        }
        if case .active(let detail) = steps[step] ?? .pending {
            return detail
        }
        return nil
    }
}
