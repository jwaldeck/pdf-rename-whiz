import Foundation
import FoundationModels

/// The maximum number of characters of document text to include in a prompt.
/// Apple's on-device model has a much smaller context window than a larger local LLM.
private let maxDocumentExcerptLength = 12000

/// The maximum length of a macOS filename in UTF-8 bytes.
private let maxFilenameLength: Int = 255

private let isoDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter
}()

private let displayDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy.MM.dd"
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter
}()

private let notFoundSentinel = "unknown"

/// Extracts receipt fields (date, patient, amount, provider, plus any custom variables) from a
/// document's text using a single structured, on-device model call.
///
/// - Parameters:
///    - document: The extracted (or OCR'd) text of the document.
///    - variables: The built-in and custom variables the active naming template may reference.
///    - client: The Apple Intelligence client to use.
///
/// - Returns: A dictionary from variable key to its formatted string value (empty if not found).
func extractVariables(
    from document: String, variables: [TemplateVariable], using client: AppleIntelligenceClient
) async throws -> [String: String] {
    let confidenceSchema = DynamicGenerationSchema(
        name: "Confidence", anyOf: ["high", "medium", "low"])

    // Fields are required (not isOptional) with a "\(notFoundSentinel)"/0 sentinel for missing
    // data: on-device guided generation tends to omit isOptional fields entirely rather than
    // attempt them and fall back to null, so a required field + sentinel is far more reliable.
    var properties = [
        DynamicGenerationSchema.Property(
            name: "date",
            description:
                "Date of service in YYYY-MM-DD format, or payment date if there's no service date. \"\(notFoundSentinel)\" if not found.",
            schema: DynamicGenerationSchema(type: String.self)),
        DynamicGenerationSchema.Property(
            name: "patient",
            description:
                "Full name of the patient, or the guarantor if no patient is listed. \"\(notFoundSentinel)\" if not found.",
            schema: DynamicGenerationSchema(type: String.self)),
        DynamicGenerationSchema.Property(
            name: "amount",
            description: "The amount actually paid, as a plain number. 0 if not found.",
            schema: DynamicGenerationSchema(type: Double.self)),
        DynamicGenerationSchema.Property(
            name: "provider",
            description:
                "Short name of the doctor, clinic, lab, hospital, or pharmacy. \"\(notFoundSentinel)\" if not found.",
            schema: DynamicGenerationSchema(type: String.self)),
        DynamicGenerationSchema.Property(
            name: "confidence",
            description: "Confidence in this extraction.",
            schema: DynamicGenerationSchema(referenceTo: "Confidence")),
    ]

    let customVariables = variables.filter { !$0.isBuiltIn }
    for variable in customVariables {
        properties.append(
            DynamicGenerationSchema.Property(
                name: variable.key,
                description: "\(variable.description) \"\(notFoundSentinel)\" if not found.",
                schema: DynamicGenerationSchema(type: String.self)))
    }

    let root = DynamicGenerationSchema(name: "ReceiptExtraction", properties: properties)
    let schema = try GenerationSchema(root: root, dependencies: [confidenceSchema])

    var customVariableInstructions = ""
    if !customVariables.isEmpty {
        customVariableInstructions =
            "\n" + customVariables.map { "- \($0.key): \($0.description)" }.joined(separator: "\n")
    }

    let prompt = """
        You are reading a medical receipt, bill, or payment confirmation.
        Extract: date (YYYY-MM-DD, service date or payment date if none), \
        patient (full name, or guarantor if no patient listed), \
        amount (amount actually paid, number only), provider (short name), \
        confidence (high/medium/low). Use "\(notFoundSentinel)" (or 0 for amount) for anything \
        you cannot find. Do not guess.\(customVariableInstructions)

        Document content:
        \(document.prefix(maxDocumentExcerptLength))
        """

    let content = try await client.respond(to: prompt, schema: schema, temperature: 0)

    let date = nonSentinel(try? content.value(String.self, forProperty: "date"))
    let patient = nonSentinel(try? content.value(String.self, forProperty: "patient"))
    let amount = try? content.value(Double.self, forProperty: "amount")
    let provider = nonSentinel(try? content.value(String.self, forProperty: "provider"))

    var values: [String: String] = [
        "date": formattedDate(from: date),
        "initials": initials(from: patient),
        "amount": formattedAmount(from: amount),
        "provider": sanitizedForFilename(provider ?? ""),
    ]

    for variable in customVariables {
        let value = nonSentinel(try? content.value(String.self, forProperty: variable.key))
        values[variable.key] = sanitizedForFilename(value ?? "")
    }

    return values
}

/// Renders a naming template's format string by substituting each `{key}` token with its
/// extracted value, then clamps the result to a safe filename length.
func renderFilename(template: NamingTemplate, values: [String: String], extension: String?) -> String {
    var result = template.format
    for (key, value) in values {
        result = result.replacingOccurrences(of: "{\(key)}", with: value)
    }
    result = result.trimmingCharacters(in: .whitespacesAndNewlines)

    let extensionSuffix = `extension`.map { "." + $0 } ?? ""
    let maxLengthWithoutExtension = maxFilenameLength - extensionSuffix.utf8.count
    if result.utf8.count > maxLengthWithoutExtension {
        result = String(result.prefix(maxLengthWithoutExtension))
    }

    return result + extensionSuffix
}

private func formattedDate(from string: String?) -> String {
    guard let string, !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return ""
    }
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)

    if let date = isoDateFormatter.date(from: trimmed) {
        return displayDateFormatter.string(from: date)
    }

    let types: NSTextCheckingResult.CheckingType = [.date]
    guard let detector = try? NSDataDetector(types: types.rawValue) else { return "" }
    let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
    guard let match = detector.matches(in: trimmed, options: [], range: range).first?.date else {
        return ""
    }
    return displayDateFormatter.string(from: match)
}

/// Derives initials from a full name, e.g. "WALDECK, JAN" -> "JW", "Jan Waldeck" -> "JW".
private func initials(from name: String?) -> String {
    guard let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return ""
    }

    let parts: [String]
    if name.contains(",") {
        parts = name.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.reversed()
    } else {
        parts = name.split(separator: " ").map(String.init)
    }

    let letters = parts.compactMap { $0.first }.map { String($0).uppercased() }
    guard let first = letters.first else { return "" }
    guard letters.count > 1, let last = letters.last else { return first }
    return first + last
}

private func formattedAmount(from value: Double?) -> String {
    guard let value, value != 0 else { return "" }
    return String(format: "$%.2f", value)
}

private func sanitizedForFilename(_ value: String) -> String {
    value
        .replacingOccurrences(of: "/", with: "-")
        .replacingOccurrences(of: ":", with: "-")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Converts the model's "\(notFoundSentinel)" (or blank) sentinel back to nil.
private func nonSentinel(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed.caseInsensitiveCompare(notFoundSentinel) != .orderedSame else {
        return nil
    }
    return trimmed
}
