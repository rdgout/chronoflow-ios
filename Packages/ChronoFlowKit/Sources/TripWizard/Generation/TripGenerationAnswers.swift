import AppCore
import Foundation

extension TripGenerationService {
    public func answerPrompts(
        instance: String, input: ApiTripReviewInput, review: ApiTripReview, answers: [String: [String: JSONValue]],
        edit: TripEditContext? = nil
    ) async throws -> TripGenerationReviewResult {
        let answered = try Self.applyingAnswers(input: input, review: review, answers: answers)
        return try await self.review(instance: instance, input: answered, edit: edit)
    }

    public nonisolated static func applyingAnswers(
        input: ApiTripReviewInput, review: ApiTripReview, answers: [String: [String: JSONValue]]
    ) throws -> ApiTripReviewInput {
        var input = input
        var object = try JSONDecoder().decode(JSONObject.self, from: JSONEncoder().encode(input.input))
        for (id, values) in answers {
            guard let prompt = review.prompts.first(where: { $0.id == id }),
                ProfilePreferences.isSupported(prompt),
                Set(values.keys).isSubset(of: Set(prompt.fields))
            else {
                throw DataFailure.validation(
                    fields: ["review": FieldMessage(key: "Choose one of the available options.")], status: 422)
            }
            for (field, value) in values {
                switch prompt.target {
                case .profile:
                    if input.profile == nil { input.profile = JSONObject() }
                    input.profile?[field] = value
                case .trip:
                    var path = field.split(separator: ".").map(String.init)
                    if let index = prompt.scope.legIndex ?? prompt.scope.stayIndex, let journey = prompt.scope.journey {
                        path = [journey.rawValue, "legs", String(index)] + path
                    }
                    var root = JSONValue.object(object.fields)
                    try Self.set(value, path: path[...], in: &root)
                    object = JSONObject(root.object!)
                case .unknown:
                    throw DataFailure.validation(
                        fields: ["review": FieldMessage(key: "Choose one of the available options.")], status: 422)
                }
            }
        }
        input.input = try JSONDecoder().decode(ApiTripInput.self, from: JSONEncoder().encode(object))
        input.identity = review.identity
        return input
    }

    private static func set(_ value: JSONValue, path: ArraySlice<String>, in root: inout JSONValue) throws {
        guard let first = path.first else {
            root = value
            return
        }
        switch root {
        case .object(var object):
            var child = object[first] ?? .null
            try set(value, path: path.dropFirst(), in: &child)
            object[first] = child
            root = .object(object)
        case .array(var array):
            guard let index = Int(first), array.indices.contains(index) else { throw DataFailure.reviewExpired }
            try set(value, path: path.dropFirst(), in: &array[index])
            root = .array(array)
        default: throw DataFailure.reviewExpired
        }
    }
}
