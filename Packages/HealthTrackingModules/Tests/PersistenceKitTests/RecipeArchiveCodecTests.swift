import Foundation
@testable import PersistenceKit
import XCTest

final class RecipeArchiveCodecTests: XCTestCase {
    func testEncodeProducesVersionedCanonicalSortedUniquePayload() throws {
        let first = uuid("00000000-0000-4000-8000-000000000401")
        let second = uuid("00000000-0000-4000-8000-000000000402")

        let encoded = try RecipeArchiveCodec.encode([second, first])

        XCTAssertEqual(
            encoded,
            #"{"recipeIDs":["00000000-0000-4000-8000-000000000401","00000000-0000-4000-8000-000000000402"],"schemaVersion":1}"#
        )
        XCTAssertEqual(
            try RecipeArchiveCodec.decode(encoded),
            Set([first, second])
        )
        XCTAssertEqual(RecipeArchiveCodec.settingKey, "nutrition.recipe.archive")
        assertEquatableSendable(try RecipeArchiveCodec.decode(encoded))
    }

    func testDecodeRejectsMalformedPayloadAndUnexpectedKeys() {
        assertCodecError(.malformedPayload, json: "not-json")
        assertCodecError(.malformedPayload, json: #"[]"#)
        assertCodecError(
            .unexpectedKeys,
            json: #"{"recipeIDs":[],"schemaVersion":1,"unexpected":true}"#
        )
    }

    func testDecodeRejectsUnsupportedVersionAndInvalidIdentifiers() {
        assertCodecError(
            .unsupportedSchemaVersion(2),
            json: #"{"recipeIDs":[],"schemaVersion":2}"#
        )
        assertCodecError(
            .invalidRecipeID("not-a-uuid"),
            json: #"{"recipeIDs":["not-a-uuid"],"schemaVersion":1}"#
        )
    }

    func testDecodeRejectsDuplicateAndNonCanonicalIdentifierLists() {
        let first = uuid("00000000-0000-4000-8000-000000000401")
        let duplicate = first.uuidString
        assertCodecError(
            .duplicateRecipeID(first),
            json: #"{"recipeIDs":["\#(duplicate)","\#(duplicate)"],"schemaVersion":1}"#
        )
        assertCodecError(
            .nonCanonicalRecipeIDOrder,
            json: #"{"recipeIDs":["00000000-0000-4000-8000-000000000402","00000000-0000-4000-8000-000000000401"],"schemaVersion":1}"#
        )
    }

    private func assertCodecError(
        _ expected: RecipeArchiveCodecError,
        json: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try RecipeArchiveCodec.decode(json),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? RecipeArchiveCodecError,
                expected,
                file: file,
                line: line
            )
        }
    }

    private func uuid(_ value: String) -> UUID {
        UUID(uuidString: value)!
    }

    private func assertEquatableSendable<Value: Equatable & Sendable>(_: Value) {}
}
