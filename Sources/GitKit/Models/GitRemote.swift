import Foundation

public struct GitRemote: Sendable, Equatable, Identifiable {
    public var id: String { name }

    public let name: String
    public let fetchURL: String?
    public let pushURL: String?

    public init(name: String, fetchURL: String? = nil, pushURL: String? = nil) {
        self.name = name
        self.fetchURL = fetchURL
        self.pushURL = pushURL
    }
}

public struct GitRemoteOperationResult: Sendable, Equatable {
    public let output: String

    public init(output: String) {
        self.output = output
    }

    public var isEmpty: Bool {
        output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
