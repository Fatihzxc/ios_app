import CoreModels
import CoreGraphics
import Foundation
import ImageIO
@testable import ProgressPhotosKit
import UIKit
import UniformTypeIdentifiers
import XCTest

@MainActor
final class ProgressPhotoComparisonShareTests: XCTestCase {
    func testDescriptorOrdersChronologicallyAndUsesPoseThenImageBytesForEqualDates() throws {
        let earlier = ProgressPhotoShareItem(
            imageData: makeJPEG(color: .red),
            date: Date(timeIntervalSince1970: 100),
            pose: .side
        )
        let later = ProgressPhotoShareItem(
            imageData: makeJPEG(color: .blue),
            date: Date(timeIntervalSince1970: 200),
            pose: .front
        )

        let chronological = try ProgressPhotoComparisonShareDescriptor(
            first: later,
            second: earlier
        )

        XCTAssertEqual(chronological.before, earlier)
        XCTAssertEqual(chronological.after, later)

        let equalDate = Date(timeIntervalSince1970: 300)
        let front = ProgressPhotoShareItem(
            imageData: makeJPEG(color: .green),
            date: equalDate,
            pose: .front
        )
        let back = ProgressPhotoShareItem(
            imageData: makeJPEG(color: .yellow),
            date: equalDate,
            pose: .back
        )
        let poseForward = try ProgressPhotoComparisonShareDescriptor(
            first: back,
            second: front
        )
        let poseReverse = try ProgressPhotoComparisonShareDescriptor(
            first: front,
            second: back
        )

        XCTAssertEqual(poseForward, poseReverse)
        XCTAssertEqual(poseForward.before, front)
        XCTAssertEqual(poseForward.after, back)

        let samePoseA = ProgressPhotoShareItem(
            imageData: makeJPEG(color: .magenta),
            date: equalDate,
            pose: .side
        )
        let samePoseB = ProgressPhotoShareItem(
            imageData: makeJPEG(color: .cyan),
            date: equalDate,
            pose: .side
        )
        let byteForward = try ProgressPhotoComparisonShareDescriptor(
            first: samePoseA,
            second: samePoseB
        )
        let byteReverse = try ProgressPhotoComparisonShareDescriptor(
            first: samePoseB,
            second: samePoseA
        )

        XCTAssertEqual(byteForward, byteReverse)
        XCTAssertNotEqual(byteForward.before.imageData, byteForward.after.imageData)
    }

    func testDescriptorRejectsDuplicateItemsAndExposesOnlyImageDateAndPose() throws {
        let item = ProgressPhotoShareItem(
            imageData: makeJPEG(color: .orange),
            date: Date(timeIntervalSince1970: 400),
            pose: .front
        )

        XCTAssertThrowsError(
            try ProgressPhotoComparisonShareDescriptor(first: item, second: item)
        ) { error in
            XCTAssertEqual(
                error as? ProgressPhotoComparisonShareError,
                .duplicateItems
            )
        }

        let other = ProgressPhotoShareItem(
            imageData: makeJPEG(color: .purple),
            date: Date(timeIntervalSince1970: 500),
            pose: .back
        )
        let descriptor = try ProgressPhotoComparisonShareDescriptor(
            first: item,
            second: other
        )

        XCTAssertEqual(
            Set(Mirror(reflecting: descriptor).children.compactMap(\.label)),
            Set(["before", "after"])
        )
        for shareItem in [descriptor.before, descriptor.after] {
            XCTAssertEqual(
                Set(Mirror(reflecting: shareItem).children.compactMap(\.label)),
                Set(["imageData", "date", "pose"])
            )
        }
    }

    func testGalleryFailsClosedUntilTwoDistinctDecodableFullImagesAreReady() async throws {
        let first = shareSnapshot(
            id: "00000000-0000-0000-0000-000000000501",
            assetID: "00000000-0000-0000-0000-000000000601",
            date: Date(timeIntervalSince1970: 600),
            pose: .front,
            note: "private-note-never-shared"
        )
        let second = shareSnapshot(
            id: "00000000-0000-0000-0000-000000000502",
            assetID: "00000000-0000-0000-0000-000000000602",
            date: Date(timeIntervalSince1970: 700),
            pose: .side,
            note: "/private/source/path.jpg"
        )
        let firstJPEG = makeJPEG(color: .red)
        let secondJPEG = makeJPEG(color: .blue)
        let repository = ShareGalleryRepositoryFake(
            photos: [first, second],
            thumbnails: [
                first.imageRef: .available(Data([1])),
                second.imageRef: .available(Data([2])),
            ],
            fullImages: [
                first.imageRef: .available(firstJPEG),
                second.imageRef: .corrupt,
            ]
        )
        let viewModel = ProgressPhotoGalleryViewModel(repository: repository)

        await viewModel.load()
        await viewModel.loadThumbnail(id: first.id)
        await viewModel.loadThumbnail(id: second.id)
        _ = viewModel.toggleSelection(id: first.id)
        XCTAssertFalse(viewModel.canShareComparison)
        _ = viewModel.toggleSelection(id: second.id)
        XCTAssertFalse(viewModel.canShareComparison)
        XCTAssertThrowsError(try viewModel.makeComparisonShareDescriptor())

        await viewModel.loadComparisonImages()

        XCTAssertFalse(viewModel.canShareComparison)
        XCTAssertEqual(viewModel.selectedPhotoIDs, [first.id, second.id])
        XCTAssertThrowsError(try viewModel.makeComparisonShareDescriptor())

        repository.fullImages[second.imageRef] = .available(Data([0x00, 0x01]))
        await viewModel.reloadMissingAndCorruptAssets()
        XCTAssertFalse(viewModel.canShareComparison)
        XCTAssertEqual(viewModel.selectedPhotoIDs, [first.id, second.id])

        repository.fullImages[second.imageRef] = .available(secondJPEG)
        await viewModel.reloadMissingAndCorruptAssets()
        let descriptor = try viewModel.makeComparisonShareDescriptor()

        XCTAssertTrue(viewModel.canShareComparison)
        XCTAssertEqual(viewModel.selectedPhotoIDs, [first.id, second.id])
        XCTAssertEqual(descriptor.before.imageData, firstJPEG)
        XCTAssertEqual(descriptor.before.date, first.date)
        XCTAssertEqual(descriptor.before.pose, first.pose)
        XCTAssertEqual(descriptor.after.imageData, secondJPEG)
        XCTAssertEqual(descriptor.after.date, second.date)
        XCTAssertEqual(descriptor.after.pose, second.pose)
    }

    func testSelectionAndLoadingNeverRenderWriteOrPresentBeforeExplicitShare() async throws {
        let fixture = await readyGalleryFixture()
        let renderer = ShareRendererSpy(result: makeJPEG(color: .brown))
        let store = ShareTemporaryStoreSpy()
        let coordinator = ProgressPhotoComparisonShareCoordinator(
            renderer: renderer,
            temporaryStore: store
        )

        XCTAssertTrue(fixture.viewModel.canShareComparison)
        XCTAssertEqual(renderer.renderCount, 0)
        XCTAssertEqual(store.writeCount, 0)
        XCTAssertNil(coordinator.artifact)
        XCTAssertEqual(coordinator.phase, .idle)

        await coordinator.share {
            try fixture.viewModel.makeComparisonShareDescriptor()
        }

        XCTAssertEqual(renderer.renderCount, 1)
        XCTAssertEqual(store.writeCount, 1)
        XCTAssertNotNil(coordinator.artifact)
        XCTAssertEqual(coordinator.phase, .ready)
    }

    func testUIKitRendererRejectsEitherCorruptInput() async throws {
        let valid = ProgressPhotoShareItem(
            imageData: makeJPEG(color: .red),
            date: Date(timeIntervalSince1970: 800),
            pose: .front
        )
        let corrupt = ProgressPhotoShareItem(
            imageData: Data([0x00, 0x01, 0x02]),
            date: Date(timeIntervalSince1970: 900),
            pose: .back
        )
        let renderer = UIKitProgressPhotoComparisonRenderer()

        for descriptor in [
            try ProgressPhotoComparisonShareDescriptor(first: corrupt, second: valid),
            try ProgressPhotoComparisonShareDescriptor(first: valid, second: corrupt),
        ] {
            do {
                _ = try await renderer.render(descriptor)
                XCTFail("Corrupt comparison input must fail closed.")
            } catch {
                XCTAssertEqual(
                    error as? ProgressPhotoComparisonShareError,
                    .corruptImage
                )
            }
        }
    }

    func testUIKitRendererCreatesMetadataFreeJPEGWithoutPrivateSourceBytes() async throws {
        let privateTokens = [
            "private-note-never-shared",
            "00000000-0000-0000-0000-000000000699",
            "/private/var/mobile/source.jpg",
            "caption-must-not-be-an-activity-item",
        ]
        let firstBytes = jpegWithTrailingTokens(
            color: .red,
            tokens: privateTokens
        )
        let secondBytes = jpegWithTrailingTokens(
            color: .blue,
            tokens: privateTokens.reversed()
        )
        let descriptor = try ProgressPhotoComparisonShareDescriptor(
            first: ProgressPhotoShareItem(
                imageData: firstBytes,
                date: Date(timeIntervalSince1970: 1_000),
                pose: .front
            ),
            second: ProgressPhotoShareItem(
                imageData: secondBytes,
                date: Date(timeIntervalSince1970: 2_000),
                pose: .back
            )
        )

        let output = try await UIKitProgressPhotoComparisonRenderer().render(descriptor)

        let source = try XCTUnwrap(CGImageSourceCreateWithData(output as CFData, nil))
        XCTAssertEqual(CGImageSourceGetType(source) as String?, UTType.jpeg.identifier)
        XCTAssertNotNil(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let properties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )
        let exif = properties[kCGImagePropertyExifDictionary]
            as? [CFString: Any] ?? [:]
        let allowedIntrinsicExifKeys: Set<CFString> = [
            kCGImagePropertyExifColorSpace,
            kCGImagePropertyExifPixelXDimension,
            kCGImagePropertyExifPixelYDimension,
        ]
        XCTAssertTrue(
            Set(exif.keys).isSubset(of: allowedIntrinsicExifKeys),
            "Fresh output may expose only decoder-derived color and dimensions."
        )
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
        XCTAssertNil(properties[kCGImagePropertyIPTCDictionary])
        XCTAssertNil(properties[kCGImagePropertyTIFFDictionary])
        let forbiddenPrivacyMetadataSignatures = [
            Data([0x45, 0x78, 0x69, 0x66, 0x00, 0x00]),
            Data("http://ns.adobe.com/xap/1.0/".utf8),
            Data("Photoshop 3.0".utf8),
        ]
        for signature in forbiddenPrivacyMetadataSignatures {
            XCTAssertNil(output.range(of: signature))
        }
        for token in privateTokens {
            XCTAssertNil(output.range(of: Data(token.utf8)), token)
        }
    }

    func testJPEGSanitizerRemovesPrivacySegmentsAndPreservesScanTail() throws {
        let app0 = jpegSegment(
            marker: 0xe0,
            payload: Data([0x4a, 0x46, 0x49, 0x46, 0x00])
        )
        let privatePayloads = [
            Data("Exif\0\0private-exif".utf8),
            Data("Photoshop 3.0private-iptc".utf8),
            Data("private-comment".utf8),
        ]
        let scanTail = Data([
            0xff, 0xda, 0x00, 0x02,
            0x11, 0xff, 0x00, 0x22, 0xff, 0xd0, 0x33,
            0xff, 0xd9,
        ])
        var input = Data([0xff, 0xd8])
        input.append(app0)
        input.append(jpegSegment(marker: 0xe1, payload: privatePayloads[0]))
        input.append(jpegSegment(marker: 0xed, payload: privatePayloads[1]))
        input.append(jpegSegment(marker: 0xfe, payload: privatePayloads[2]))
        input.append(jpegSegment(marker: 0xdb, payload: Data([0x00])))
        input.append(scanTail)

        let output = try JPEGPrivacySegmentSanitizer.sanitize(input)

        XCTAssertNotNil(output.range(of: Data("JFIF\0".utf8)))
        for payload in privatePayloads {
            XCTAssertNil(output.range(of: payload))
        }
        XCTAssertEqual(output.suffix(scanTail.count), scanTail)
    }

    func testJPEGSanitizerFailsClosedForMalformedOrTruncatedStreams() {
        let malformedStreams = [
            Data(),
            Data([0xff, 0xd8, 0xff, 0xe1, 0x00, 0x01]),
            Data([0xff, 0xd8, 0xff, 0xe1, 0x00, 0x08, 0x01]),
            Data([0xff, 0xd8, 0x00, 0xd9]),
            Data([0xff, 0xd8, 0xff, 0xda, 0x00, 0x02, 0x11]),
            Data([
                0xff, 0xd8, 0xff, 0xda, 0x00, 0x02,
                0x11, 0xff, 0xe1, 0x00, 0x02, 0xff, 0xd9,
            ]),
        ]

        for stream in malformedStreams {
            XCTAssertThrowsError(try JPEGPrivacySegmentSanitizer.sanitize(stream)) {
                error in
                XCTAssertEqual(
                    error as? ProgressPhotoComparisonShareError,
                    .renderingFailed
                )
            }
        }
    }

    func testTemporaryStoreUsesIsolatedCompleteProtectedDirectoryAndOwnedCleanup() throws {
        let root = URL(fileURLWithPath: "/task-five-owned-root", isDirectory: true)
        let ownedID = UUID(uuidString: "00000000-0000-0000-0000-000000000701")!
        let fileSystem = ShareTemporaryFileSystemSpy()
        let store = ProgressPhotoComparisonTemporaryStore(
            rootDirectory: root,
            fileSystem: fileSystem,
            makeDirectoryID: { ownedID }
        )
        let renderedJPEG = makeJPEG(color: .green)

        let artifact = try store.writeOneUseJPEG(renderedJPEG)

        let ownedDirectory = root.appendingPathComponent(
            ownedID.uuidString.lowercased(),
            isDirectory: true
        )
        XCTAssertEqual(fileSystem.createdDirectories, [root, ownedDirectory])
        XCTAssertEqual(fileSystem.protectedURLs, [root, ownedDirectory])
        XCTAssertEqual(
            fileSystem.writes,
            [.init(data: renderedJPEG, url: ownedDirectory.appendingPathComponent("comparison.jpg"))]
        )
        XCTAssertEqual(artifact.fileURL, ownedDirectory.appendingPathComponent("comparison.jpg"))

        artifact.cleanup()
        artifact.cleanup()

        XCTAssertEqual(fileSystem.removedURLs, [ownedDirectory])
        XCTAssertFalse(
            fileSystem.removedURLs.contains(
                URL(fileURLWithPath: "/outside/not-owned.jpg")
            )
        )
    }

    func testTemporaryStoreCleansAllocatedDirectoryAfterPartialWriteFailure() throws {
        let root = URL(fileURLWithPath: "/task-five-failure-root", isDirectory: true)
        let ownedID = UUID(uuidString: "00000000-0000-0000-0000-000000000702")!
        let fileSystem = ShareTemporaryFileSystemSpy()
        fileSystem.writeError = ShareFixtureError.writeFailed
        let store = ProgressPhotoComparisonTemporaryStore(
            rootDirectory: root,
            fileSystem: fileSystem,
            makeDirectoryID: { ownedID }
        )

        XCTAssertThrowsError(try store.writeOneUseJPEG(makeJPEG(color: .yellow)))

        XCTAssertEqual(
            fileSystem.removedURLs,
            [
                root.appendingPathComponent(
                    ownedID.uuidString.lowercased(),
                    isDirectory: true
                )
            ]
        )
    }

    func testCoordinatorCleansAfterCompletedCancelledFailedAndPresentationFailure() async throws {
        let descriptor = try shareDescriptor()
        let renderer = ShareRendererSpy(result: makeJPEG(color: .blue))
        let store = ShareTemporaryStoreSpy()
        let coordinator = ProgressPhotoComparisonShareCoordinator(
            renderer: renderer,
            temporaryStore: store
        )

        await coordinator.share { descriptor }
        coordinator.activityDidFinish(
            artifactID: try XCTUnwrap(coordinator.artifact?.id),
            completed: true,
            error: nil
        )
        XCTAssertEqual(store.cleanupCount, 1)
        XCTAssertEqual(coordinator.phase, .idle)

        await coordinator.share { descriptor }
        coordinator.activityDidFinish(
            artifactID: try XCTUnwrap(coordinator.artifact?.id),
            completed: false,
            error: nil
        )
        XCTAssertEqual(store.cleanupCount, 2)
        XCTAssertEqual(coordinator.phase, .idle)

        await coordinator.share { descriptor }
        coordinator.activityDidFinish(
            artifactID: try XCTUnwrap(coordinator.artifact?.id),
            completed: false,
            error: ShareFixtureError.activityFailed
        )
        XCTAssertEqual(store.cleanupCount, 3)
        XCTAssertEqual(coordinator.phase, .failed)
        XCTAssertTrue(coordinator.hasRetryableError)

        await coordinator.share { descriptor }
        coordinator.presentationDidFail(
            artifactID: try XCTUnwrap(coordinator.artifact?.id)
        )
        XCTAssertEqual(store.cleanupCount, 4)
        XCTAssertEqual(coordinator.phase, .failed)
        XCTAssertTrue(coordinator.hasRetryableError)
    }

    func testCoordinatorCleansOnDismissalReplacementAndRepeatedTerminalCallbacks() async throws {
        let descriptor = try shareDescriptor()
        let renderer = ShareRendererSpy(result: makeJPEG(color: .cyan))
        let store = ShareTemporaryStoreSpy()
        let coordinator = ProgressPhotoComparisonShareCoordinator(
            renderer: renderer,
            temporaryStore: store
        )

        await coordinator.share { descriptor }
        await coordinator.share { descriptor }
        XCTAssertEqual(store.cleanupCount, 1)
        let dismissedArtifactID = try XCTUnwrap(coordinator.artifact?.id)

        coordinator.dismiss()
        coordinator.dismiss()
        coordinator.activityDidFinish(
            artifactID: dismissedArtifactID,
            completed: false,
            error: nil
        )

        XCTAssertEqual(store.cleanupCount, 2)
        XCTAssertNil(coordinator.artifact)
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testCoordinatorPreservesSelectionAndOffersRetryAfterRenderOrWriteFailure() async throws {
        let fixture = await readyGalleryFixture()
        let selectedIDs = fixture.viewModel.selectedPhotoIDs
        let renderer = ShareRendererSpy(error: ShareFixtureError.renderFailed)
        let store = ShareTemporaryStoreSpy()
        let coordinator = ProgressPhotoComparisonShareCoordinator(
            renderer: renderer,
            temporaryStore: store
        )

        await coordinator.share {
            try fixture.viewModel.makeComparisonShareDescriptor()
        }

        XCTAssertEqual(coordinator.phase, .failed)
        XCTAssertTrue(coordinator.hasRetryableError)
        XCTAssertEqual(fixture.viewModel.selectedPhotoIDs, selectedIDs)
        XCTAssertEqual(store.writeCount, 0)

        renderer.error = nil
        store.writeError = ShareFixtureError.writeFailed
        await coordinator.share {
            try fixture.viewModel.makeComparisonShareDescriptor()
        }
        XCTAssertEqual(coordinator.phase, .failed)
        XCTAssertTrue(coordinator.hasRetryableError)
        XCTAssertEqual(fixture.viewModel.selectedPhotoIDs, selectedIDs)

        store.writeError = nil
        await coordinator.share {
            try fixture.viewModel.makeComparisonShareDescriptor()
        }
        XCTAssertEqual(coordinator.phase, .ready)
        XCTAssertFalse(coordinator.hasRetryableError)
        XCTAssertEqual(fixture.viewModel.selectedPhotoIDs, selectedIDs)
    }

    func testDismissDuringSuspendedRenderInvalidatesOperationWithoutWritingOrPublishing() async throws {
        let descriptor = try shareDescriptor()
        let renderer = ShareSuspendingRenderer(
            results: [makeJPEG(color: .red)],
            suspendedCalls: [1]
        )
        let store = ShareTemporaryStoreSpy()
        let coordinator = ProgressPhotoComparisonShareCoordinator(
            renderer: renderer,
            temporaryStore: store
        )
        let operation = Task {
            await coordinator.share { descriptor }
        }
        await renderer.waitUntilSuspended(call: 1)

        coordinator.dismiss()
        renderer.resume(call: 1)
        await operation.value

        XCTAssertEqual(renderer.renderCount, 1)
        XCTAssertEqual(store.writeCount, 0)
        XCTAssertTrue(store.writtenData.isEmpty)
        XCTAssertNil(coordinator.artifact)
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testNewerShareWinsWhenOlderSuspendedRenderResumes() async throws {
        let descriptor = try shareDescriptor()
        let olderJPEG = makeJPEG(color: .red)
        let newerJPEG = makeJPEG(color: .blue)
        let renderer = ShareSuspendingRenderer(
            results: [olderJPEG, newerJPEG],
            suspendedCalls: [1]
        )
        let store = ShareTemporaryStoreSpy()
        let coordinator = ProgressPhotoComparisonShareCoordinator(
            renderer: renderer,
            temporaryStore: store
        )
        let olderOperation = Task {
            await coordinator.share { descriptor }
        }
        await renderer.waitUntilSuspended(call: 1)

        await coordinator.share { descriptor }
        let newerArtifactID = try XCTUnwrap(coordinator.artifact?.id)
        renderer.resume(call: 1)
        await olderOperation.value

        XCTAssertEqual(renderer.renderCount, 2)
        XCTAssertEqual(store.writtenData, [newerJPEG])
        XCTAssertEqual(store.writeCount, 1)
        XCTAssertEqual(store.cleanupCount, 0)
        XCTAssertNotNil(coordinator.artifact)
        XCTAssertEqual(coordinator.artifact?.id, newerArtifactID)
        XCTAssertEqual(coordinator.phase, .ready)
    }

    func testExternalTaskCancellationDuringSuspendedRenderNeverWritesArtifact() async throws {
        let descriptor = try shareDescriptor()
        let renderer = ShareSuspendingRenderer(
            results: [makeJPEG(color: .green)],
            suspendedCalls: [1]
        )
        let store = ShareTemporaryStoreSpy()
        let coordinator = ProgressPhotoComparisonShareCoordinator(
            renderer: renderer,
            temporaryStore: store
        )
        let operation = Task {
            await coordinator.share { descriptor }
        }
        await renderer.waitUntilSuspended(call: 1)

        operation.cancel()
        renderer.resume(call: 1)
        await operation.value

        XCTAssertEqual(store.writeCount, 0)
        XCTAssertNil(coordinator.artifact)
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testQueuedCancelledShareCannotEnterAfterDismissalOrCallDescriptor() async throws {
        let descriptor = try shareDescriptor()
        let renderer = ShareRendererSpy(result: makeJPEG(color: .green))
        let store = ShareTemporaryStoreSpy()
        let coordinator = ProgressPhotoComparisonShareCoordinator(
            renderer: renderer,
            temporaryStore: store
        )
        await coordinator.share { descriptor }
        let gate = ShareEntryGate()
        var descriptorCallCount = 0
        let queuedShare = Task {
            await gate.wait()
            await coordinator.share { (descriptorCallCount += 1, descriptor).1 }
        }
        await gate.waitUntilEntered()

        queuedShare.cancel()
        coordinator.dismiss()
        gate.open()
        await queuedShare.value

        XCTAssertEqual(descriptorCallCount, 0)
        XCTAssertEqual(renderer.renderCount, 1)
        XCTAssertEqual(store.writeCount, 1)
        XCTAssertEqual(store.cleanupCount, 1)
        XCTAssertNil(coordinator.artifact)
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testStaleActivityAndPresentationCallbacksCannotCleanNewerArtifact() async throws {
        let descriptor = try shareDescriptor()

        let activityStore = ShareTemporaryStoreSpy()
        let activityCoordinator = ProgressPhotoComparisonShareCoordinator(
            renderer: ShareRendererSpy(result: makeJPEG(color: .red)),
            temporaryStore: activityStore
        )
        await activityCoordinator.share { descriptor }
        let activityArtifactA = try XCTUnwrap(activityCoordinator.artifact)
        await activityCoordinator.share { descriptor }
        let activityArtifactB = try XCTUnwrap(activityCoordinator.artifact)
        XCTAssertNotEqual(activityArtifactA.id, activityArtifactB.id)

        activityCoordinator.activityDidFinish(
            artifactID: activityArtifactA.id,
            completed: false,
            error: nil
        )

        XCTAssertEqual(activityCoordinator.artifact?.id, activityArtifactB.id)
        XCTAssertEqual(activityStore.cleanupCount, 1)
        XCTAssertEqual(activityCoordinator.phase, .ready)

        let presentationStore = ShareTemporaryStoreSpy()
        let presentationCoordinator = ProgressPhotoComparisonShareCoordinator(
            renderer: ShareRendererSpy(result: makeJPEG(color: .blue)),
            temporaryStore: presentationStore
        )
        await presentationCoordinator.share { descriptor }
        let presentationArtifactA = try XCTUnwrap(presentationCoordinator.artifact)
        await presentationCoordinator.share { descriptor }
        let presentationArtifactB = try XCTUnwrap(presentationCoordinator.artifact)
        XCTAssertNotEqual(presentationArtifactA.id, presentationArtifactB.id)

        presentationCoordinator.presentationDidFail(
            artifactID: presentationArtifactA.id
        )

        XCTAssertEqual(presentationCoordinator.artifact?.id, presentationArtifactB.id)
        XCTAssertEqual(presentationStore.cleanupCount, 1)
        XCTAssertEqual(presentationCoordinator.phase, .ready)
    }

    func testArtifactCleanupRetriesAfterTransientRemovalFailure() throws {
        let root = URL(fileURLWithPath: "/task-five-cleanup-retry", isDirectory: true)
        let ownedID = UUID(uuidString: "00000000-0000-0000-0000-000000000703")!
        let ownedDirectory = root.appendingPathComponent(
            ownedID.uuidString.lowercased(),
            isDirectory: true
        )
        let fileSystem = ShareTemporaryFileSystemSpy()
        let store = ProgressPhotoComparisonTemporaryStore(
            rootDirectory: root,
            fileSystem: fileSystem,
            makeDirectoryID: { ownedID }
        )
        let artifact = try store.writeOneUseJPEG(makeJPEG(color: .orange))
        fileSystem.removeError = ShareFixtureError.cleanupFailed

        artifact.cleanup()
        artifact.cleanup()

        XCTAssertEqual(fileSystem.removalAttempts, [ownedDirectory, ownedDirectory])
        XCTAssertEqual(fileSystem.removedURLs, [ownedDirectory])
        XCTAssertFalse(fileSystem.removedURLs.isEmpty)
    }

    func testCoordinatorRetainsFailedCleanupAndRetriesWithoutRepublishingArtifact() async throws {
        let root = URL(fileURLWithPath: "/task-five-coordinator-cleanup", isDirectory: true)
        let ownedID = UUID(uuidString: "00000000-0000-0000-0000-000000000704")!
        let ownedDirectory = root.appendingPathComponent(
            ownedID.uuidString.lowercased(),
            isDirectory: true
        )
        let fileSystem = ShareTemporaryFileSystemSpy()
        let store = ProgressPhotoComparisonTemporaryStore(
            rootDirectory: root,
            fileSystem: fileSystem,
            makeDirectoryID: { ownedID }
        )
        let coordinator = ProgressPhotoComparisonShareCoordinator(
            renderer: ShareRendererSpy(result: makeJPEG(color: .purple)),
            temporaryStore: store
        )
        await coordinator.share { try shareDescriptor() }
        XCTAssertNotNil(coordinator.artifact)
        XCTAssertEqual(fileSystem.writes.count, 1)
        fileSystem.removeError = ShareFixtureError.cleanupFailed

        coordinator.dismiss()

        XCTAssertNil(coordinator.artifact)
        XCTAssertEqual(coordinator.phase, .failed)
        XCTAssertTrue(coordinator.hasRetryableError)
        XCTAssertEqual(fileSystem.removalAttempts, [ownedDirectory])

        coordinator.dismiss()

        XCTAssertNil(coordinator.artifact)
        XCTAssertEqual(fileSystem.writes.count, 1)
        XCTAssertEqual(fileSystem.removalAttempts, [ownedDirectory, ownedDirectory])
        XCTAssertEqual(fileSystem.removedURLs, [ownedDirectory])
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testPartialWriteCleanupFailureIsRetriedBeforeNextAllocation() throws {
        let root = URL(fileURLWithPath: "/task-five-partial-retry", isDirectory: true)
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000705")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000706")!
        var directoryIDs = [firstID, secondID]
        let firstDirectory = root.appendingPathComponent(
            firstID.uuidString.lowercased(),
            isDirectory: true
        )
        let secondDirectory = root.appendingPathComponent(
            secondID.uuidString.lowercased(),
            isDirectory: true
        )
        let fileSystem = ShareTemporaryFileSystemSpy()
        fileSystem.writeError = ShareFixtureError.writeFailed
        fileSystem.removeError = ShareFixtureError.cleanupFailed
        let store = ProgressPhotoComparisonTemporaryStore(
            rootDirectory: root,
            fileSystem: fileSystem,
            makeDirectoryID: { directoryIDs.removeFirst() }
        )

        XCTAssertThrowsError(try store.writeOneUseJPEG(makeJPEG(color: .yellow)))
        fileSystem.writeError = nil
        let artifact = try store.writeOneUseJPEG(makeJPEG(color: .green))

        XCTAssertEqual(
            fileSystem.removalAttempts,
            [firstDirectory, firstDirectory]
        )
        XCTAssertEqual(fileSystem.removedURLs, [firstDirectory])
        XCTAssertEqual(
            artifact.fileURL,
            secondDirectory.appendingPathComponent("comparison.jpg")
        )
        let retryIndex = try XCTUnwrap(
            fileSystem.events.firstIndex(of: .removeSucceeded(firstDirectory))
        )
        let allocationIndex = try XCTUnwrap(
            fileSystem.events.firstIndex(of: .create(secondDirectory))
        )
        XCTAssertLessThan(retryIndex, allocationIndex)
    }

    func testPartialWriteCleanupOutlivesReleasedStoreWithoutAnotherWrite() async throws {
        let root = URL(fileURLWithPath: "/task-five-partial-lifetime", isDirectory: true)
        let ownedID = UUID(uuidString: "00000000-0000-0000-0000-000000000709")!
        let ownedDirectory = root.appendingPathComponent(
            ownedID.uuidString.lowercased(),
            isDirectory: true
        )
        let fileSystem = ShareTemporaryFileSystemSpy()
        fileSystem.writeError = ShareFixtureError.writeFailed
        fileSystem.removeError = ShareFixtureError.cleanupFailed
        var store: ProgressPhotoComparisonTemporaryStore? =
            ProgressPhotoComparisonTemporaryStore(
                rootDirectory: root,
                fileSystem: fileSystem,
                makeDirectoryID: { ownedID }
            )
        weak var releasedStore = store

        XCTAssertThrowsError(
            try XCTUnwrap(store).writeOneUseJPEG(makeJPEG(color: .yellow))
        )
        store = nil

        XCTAssertNil(releasedStore)
        let didCleanUp = await waitUntil {
            fileSystem.removedURLs == [ownedDirectory]
        }
        XCTAssertTrue(didCleanUp)
        XCTAssertEqual(fileSystem.removalAttempts, [ownedDirectory, ownedDirectory])
        XCTAssertEqual(fileSystem.removedURLs, [ownedDirectory])
        XCTAssertEqual(fileSystem.writes.count, 1)
    }

    func testTerminalCleanupOutlivesReleasedCoordinatorAndStore() async throws {
        let root = URL(fileURLWithPath: "/task-five-terminal-lifetime", isDirectory: true)
        let ownedID = UUID(uuidString: "00000000-0000-0000-0000-000000000719")!
        let ownedDirectory = root.appendingPathComponent(
            ownedID.uuidString.lowercased(),
            isDirectory: true
        )
        let fileSystem = ShareTemporaryFileSystemSpy()
        var store: ProgressPhotoComparisonTemporaryStore? =
            ProgressPhotoComparisonTemporaryStore(
                rootDirectory: root,
                fileSystem: fileSystem,
                makeDirectoryID: { ownedID }
            )
        weak var releasedStore = store
        var coordinator: ProgressPhotoComparisonShareCoordinator? =
            ProgressPhotoComparisonShareCoordinator(
                renderer: ShareRendererSpy(result: makeJPEG(color: .purple)),
                temporaryStore: try XCTUnwrap(store)
            )
        weak var releasedCoordinator = coordinator
        await coordinator?.share { try shareDescriptor() }
        fileSystem.removeError = ShareFixtureError.cleanupFailed

        coordinator?.dismiss()
        XCTAssertEqual(coordinator?.phase, .failed)
        XCTAssertNil(coordinator?.artifact)
        coordinator = nil
        store = nil

        XCTAssertNil(releasedCoordinator)
        XCTAssertNil(releasedStore)
        let didCleanUp = await waitUntil {
            fileSystem.removedURLs == [ownedDirectory]
        }
        XCTAssertTrue(didCleanUp)
        XCTAssertEqual(fileSystem.removalAttempts, [ownedDirectory, ownedDirectory])
        XCTAssertEqual(fileSystem.removedURLs, [ownedDirectory])
        XCTAssertEqual(fileSystem.writes.count, 1)
    }

    func testStaleLifetimeRetryCannotDeleteNewArtifactAtReusedOwnedURL() throws {
        let root = URL(fileURLWithPath: "/task-five-stale-lifetime", isDirectory: true)
        let ownedID = UUID(uuidString: "00000000-0000-0000-0000-000000000729")!
        let ownedDirectory = root.appendingPathComponent(
            ownedID.uuidString.lowercased(),
            isDirectory: true
        )
        let scheduler = ShareCleanupSchedulerFake()
        let registry = ProgressPhotoComparisonLifetimeCleanupRegistry(
            scheduler: scheduler
        )
        let nonOwnedDirectory = root.appendingPathComponent(
            "not-an-owned-uuid",
            isDirectory: true
        )
        var nonOwnedCleanupCount = 0
        var retiredArtifactCleanupCount = 0
        var newArtifactCleanupCount = 0

        registry.retainOwnedDirectory(nonOwnedDirectory, under: root) {
            nonOwnedCleanupCount += 1
        }
        XCTAssertFalse(scheduler.hasScheduledOperation)
        registry.retainOwnedDirectory(ownedDirectory, under: root) {
            retiredArtifactCleanupCount += 1
        }
        registry.didCleanOwnedDirectory(ownedDirectory, under: root)
        registry.retainOwnedDirectory(ownedDirectory, under: root) {
            newArtifactCleanupCount += 1
        }

        XCTAssertTrue(scheduler.hasScheduledOperation)
        XCTAssertEqual(scheduler.pendingOperationCount, 2)
        scheduler.runNext()
        XCTAssertEqual(nonOwnedCleanupCount, 0)
        XCTAssertEqual(retiredArtifactCleanupCount, 0)
        XCTAssertEqual(newArtifactCleanupCount, 0)
        XCTAssertEqual(scheduler.pendingOperationCount, 1)

        scheduler.runNext()
        XCTAssertEqual(retiredArtifactCleanupCount, 0)
        XCTAssertEqual(newArtifactCleanupCount, 1)
        XCTAssertFalse(scheduler.hasScheduledOperation)
    }

    func testStoreSkipsCollidingDirectoryWithoutTouchingPreexistingContent() throws {
        let root = URL(fileURLWithPath: "/task-five-collision", isDirectory: true)
        let collisionID = UUID(uuidString: "00000000-0000-0000-0000-000000000707")!
        let ownedID = UUID(uuidString: "00000000-0000-0000-0000-000000000708")!
        var directoryIDs = [collisionID, ownedID]
        let collisionDirectory = root.appendingPathComponent(
            collisionID.uuidString.lowercased(),
            isDirectory: true
        )
        let ownedDirectory = root.appendingPathComponent(
            ownedID.uuidString.lowercased(),
            isDirectory: true
        )
        let sentinel = Data("non-owned-sentinel".utf8)
        let fileSystem = ShareTemporaryFileSystemSpy()
        fileSystem.collisionDirectories = [collisionDirectory]
        fileSystem.sentinelContents[collisionDirectory] = sentinel
        let store = ProgressPhotoComparisonTemporaryStore(
            rootDirectory: root,
            fileSystem: fileSystem,
            makeDirectoryID: { directoryIDs.removeFirst() }
        )

        let artifact = try store.writeOneUseJPEG(makeJPEG(color: .brown))

        XCTAssertEqual(
            artifact.fileURL,
            ownedDirectory.appendingPathComponent("comparison.jpg")
        )
        XCTAssertEqual(
            fileSystem.createdDirectories.filter { $0 != root },
            [collisionDirectory, ownedDirectory]
        )
        XCTAssertEqual(fileSystem.sentinelContents[collisionDirectory], sentinel)
        XCTAssertFalse(fileSystem.protectedURLs.contains(collisionDirectory))
        XCTAssertFalse(fileSystem.removalAttempts.contains(collisionDirectory))
        XCTAssertFalse(fileSystem.writes.contains { $0.url.deletingLastPathComponent() == collisionDirectory })
    }

    func testStoreFailsClosedAfterBoundedDirectoryCollisionsWithoutDeletingAny() throws {
        let root = URL(fileURLWithPath: "/task-five-collision-exhaust", isDirectory: true)
        let ids = (710..<718).map { value in
            UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
        }
        var remainingIDs = ids
        let collisionDirectories = ids.map {
            root.appendingPathComponent($0.uuidString.lowercased(), isDirectory: true)
        }
        let fileSystem = ShareTemporaryFileSystemSpy()
        fileSystem.collisionDirectories = Set(collisionDirectories)
        let store = ProgressPhotoComparisonTemporaryStore(
            rootDirectory: root,
            fileSystem: fileSystem,
            makeDirectoryID: { remainingIDs.removeFirst() }
        )

        XCTAssertThrowsError(try store.writeOneUseJPEG(makeJPEG(color: .cyan)))

        XCTAssertEqual(
            fileSystem.createdDirectories.filter { $0 != root },
            collisionDirectories
        )
        XCTAssertTrue(fileSystem.writes.isEmpty)
        XCTAssertTrue(fileSystem.removalAttempts.isEmpty)
    }

    func testRendererUsesFixedDarkInkAndWrapsSupportedCaptionsOnWhiteInDarkAppearance() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let longDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 8_888, month: 9, day: 30))
        )
        let descriptor = try ProgressPhotoComparisonShareDescriptor(
            first: ProgressPhotoShareItem(
                imageData: makeJPEG(color: .red),
                date: longDate,
                pose: .front
            ),
            second: ProgressPhotoShareItem(
                imageData: makeJPEG(color: .blue),
                date: longDate.addingTimeInterval(86_400),
                pose: .back
            )
        )
        let previousTraits = UITraitCollection.current
        defer { UITraitCollection.current = previousTraits }

        UITraitCollection.current = UITraitCollection(
            preferredContentSizeCategory: .large
        )
        let baselineOutput = try await UIKitProgressPhotoComparisonRenderer(
            outputWidth: 420,
            maximumImageHeight: 120
        ).render(descriptor)
        let baselineRaster = try rgbaRaster(baselineOutput)

        UITraitCollection.current = UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: .dark),
            UITraitCollection(
                preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge
            ),
        ])

        let output = try await UIKitProgressPhotoComparisonRenderer(
            outputWidth: 420,
            maximumImageHeight: 120
        ).render(descriptor)
        let raster = try rgbaRaster(output)

        XCTAssertEqual(raster.width, 420)
        XCTAssertGreaterThan(raster.height, baselineRaster.height + 80)
        XCTAssertGreaterThanOrEqual(raster.height, 300)
        XCTAssertTrue(raster.isNearlyWhite(x: 8, y: 8))
        let sourceRows = raster.rowsContainingSaturatedRedOrBlue()
        let firstSourceRow = try XCTUnwrap(sourceRows.min())
        let lastSourceRow = try XCTUnwrap(sourceRows.max())
        for horizontalRange in [48..<178, 242..<372] {
            let ink = raster.darkPixels(
                xRange: horizontalRange,
                excludingYRange: firstSourceRow...lastSourceRow
            )
            XCTAssertGreaterThan(ink.count, 250)
            XCTAssertGreaterThanOrEqual(Set(ink.map(\.y)).count, 56)
            XCTAssertTrue(ink.contains { abs($0.y - firstSourceRow) > 110 })
            XCTAssertGreaterThan(try XCTUnwrap(ink.map(\.x).min()), horizontalRange.lowerBound)
            XCTAssertLessThan(try XCTUnwrap(ink.map(\.x).max()), horizontalRange.upperBound - 1)
        }
    }

    private func readyGalleryFixture() async -> (
        viewModel: ProgressPhotoGalleryViewModel,
        repository: ShareGalleryRepositoryFake
    ) {
        let first = shareSnapshot(
            id: "00000000-0000-0000-0000-000000000511",
            assetID: "00000000-0000-0000-0000-000000000611",
            date: Date(timeIntervalSince1970: 1_100),
            pose: .front
        )
        let second = shareSnapshot(
            id: "00000000-0000-0000-0000-000000000512",
            assetID: "00000000-0000-0000-0000-000000000612",
            date: Date(timeIntervalSince1970: 1_200),
            pose: .back
        )
        let repository = ShareGalleryRepositoryFake(
            photos: [first, second],
            thumbnails: [
                first.imageRef: .available(Data([1])),
                second.imageRef: .available(Data([2])),
            ],
            fullImages: [
                first.imageRef: .available(makeJPEG(color: .red)),
                second.imageRef: .available(makeJPEG(color: .blue)),
            ]
        )
        let viewModel = ProgressPhotoGalleryViewModel(repository: repository)
        await viewModel.load()
        await viewModel.loadThumbnail(id: first.id)
        await viewModel.loadThumbnail(id: second.id)
        _ = viewModel.toggleSelection(id: first.id)
        _ = viewModel.toggleSelection(id: second.id)
        await viewModel.loadComparisonImages()
        return (viewModel, repository)
    }

    private func shareDescriptor() throws -> ProgressPhotoComparisonShareDescriptor {
        try ProgressPhotoComparisonShareDescriptor(
            first: ProgressPhotoShareItem(
                imageData: makeJPEG(color: .red),
                date: Date(timeIntervalSince1970: 1_300),
                pose: .front
            ),
            second: ProgressPhotoShareItem(
                imageData: makeJPEG(color: .blue),
                date: Date(timeIntervalSince1970: 1_400),
                pose: .back
            )
        )
    }

    private func makeJPEG(color: UIColor) -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 12, height: 12)).jpegData(
            withCompressionQuality: 0.9
        ) { context in
            color.setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 12, height: 12))
        }
    }

    private func waitUntil(
        attempts: Int = 100,
        condition: @MainActor () -> Bool
    ) async -> Bool {
        for _ in 0..<attempts {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return condition()
    }

    private func jpegWithTrailingTokens<S: Sequence>(
        color: UIColor,
        tokens: S
    ) -> Data where S.Element == String {
        var bytes = makeJPEG(color: color)
        for token in tokens {
            bytes.append(Data(token.utf8))
        }
        return bytes
    }

    private func jpegSegment(marker: UInt8, payload: Data) -> Data {
        let length = payload.count + 2
        precondition(length <= Int(UInt16.max))
        var segment = Data([
            0xff,
            marker,
            UInt8((length >> 8) & 0xff),
            UInt8(length & 0xff),
        ])
        segment.append(payload)
        return segment
    }

    private func rgbaRaster(_ data: Data) throws -> ShareRGBARaster {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let rendered = pixels.withUnsafeMutableBytes { storage -> Bool in
            guard let context = CGContext(
                data: storage.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return false }
            context.draw(
                image,
                in: CGRect(x: 0, y: 0, width: image.width, height: image.height)
            )
            return true
        }
        XCTAssertTrue(rendered)
        return ShareRGBARaster(width: image.width, height: image.height, pixels: pixels)
    }
}

@MainActor
private final class ShareRendererSpy: ProgressPhotoComparisonRendering {
    var result: Data
    var error: Error?
    private(set) var renderCount = 0

    init(result: Data = Data([0xff, 0xd8, 0xff, 0xd9]), error: Error? = nil) {
        self.result = result
        self.error = error
    }

    func render(_ descriptor: ProgressPhotoComparisonShareDescriptor) async throws -> Data {
        _ = descriptor
        renderCount += 1
        if let error { throw error }
        return result
    }
}

@MainActor
private final class ShareSuspendingRenderer: ProgressPhotoComparisonRendering {
    private let results: [Data]
    private let suspendedCalls: Set<Int>
    private var startedCalls: Set<Int> = []
    private var startWaiters: [Int: [CheckedContinuation<Void, Never>]] = [:]
    private var resumeContinuations: [Int: CheckedContinuation<Void, Never>] = [:]
    private(set) var renderCount = 0

    init(results: [Data], suspendedCalls: Set<Int>) {
        self.results = results
        self.suspendedCalls = suspendedCalls
    }

    func waitUntilSuspended(call: Int) async {
        if startedCalls.contains(call) { return }
        await withCheckedContinuation { continuation in
            startWaiters[call, default: []].append(continuation)
        }
    }

    func resume(call: Int) {
        resumeContinuations.removeValue(forKey: call)?.resume()
    }

    func render(
        _ descriptor: ProgressPhotoComparisonShareDescriptor
    ) async throws -> Data {
        _ = descriptor
        renderCount += 1
        let call = renderCount
        if suspendedCalls.contains(call) {
            startedCalls.insert(call)
            let waiters = startWaiters.removeValue(forKey: call) ?? []
            waiters.forEach { $0.resume() }
            await withCheckedContinuation { continuation in
                resumeContinuations[call] = continuation
            }
        }
        return results[call - 1]
    }
}

@MainActor
private final class ShareEntryGate {
    private var didEnter = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var continuation: CheckedContinuation<Void, Never>?

    func waitUntilEntered() async {
        if didEnter { return }
        await withCheckedContinuation { continuation in
            entryWaiters.append(continuation)
        }
    }

    func wait() async {
        didEnter = true
        let waiters = entryWaiters
        entryWaiters.removeAll(keepingCapacity: true)
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func open() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class ShareTemporaryStoreSpy: ProgressPhotoComparisonTemporaryStoring {
    private(set) var writeCount = 0
    private(set) var cleanupCount = 0
    private(set) var writtenData: [Data] = []
    var writeError: Error?

    func writeOneUseJPEG(_ data: Data) throws -> ProgressPhotoOneUseArtifact {
        writeCount += 1
        writtenData.append(data)
        if let writeError { throw writeError }
        let sequence = writeCount
        let artifactID = UUID(
            uuidString: String(
                format: "00000000-0000-0000-0000-%012d",
                800 + sequence
            )
        )!
        return ProgressPhotoOneUseArtifact(
            id: artifactID,
            fileURL: URL(fileURLWithPath: "/owned/share-\(sequence)/comparison.jpg")
        ) { [weak self] in
            self?.cleanupCount += 1
        }
    }
}

@MainActor
private final class ShareTemporaryFileSystemSpy:
    ProgressPhotoComparisonTemporaryFileSystem {
    enum Event: Equatable {
        case create(URL)
        case protect(URL)
        case write(URL)
        case removeAttempt(URL)
        case removeSucceeded(URL)
    }

    struct Write: Equatable {
        let data: Data
        let url: URL
    }

    private(set) var createdDirectories: [URL] = []
    private(set) var protectedURLs: [URL] = []
    private(set) var writes: [Write] = []
    private(set) var removedURLs: [URL] = []
    private(set) var removalAttempts: [URL] = []
    private(set) var events: [Event] = []
    var collisionDirectories: Set<URL> = []
    var sentinelContents: [URL: Data] = [:]
    var writeError: Error?
    var removeError: Error?

    func createDirectory(at url: URL) throws {
        createdDirectories.append(url)
        events.append(.create(url))
    }

    func createExclusiveDirectory(at url: URL) throws {
        createdDirectories.append(url)
        events.append(.create(url))
        if collisionDirectories.contains(url) {
            throw NSError(
                domain: NSCocoaErrorDomain,
                code: CocoaError.fileWriteFileExists.rawValue,
                userInfo: [NSFilePathErrorKey: url.path]
            )
        }
    }

    func applyCompleteFileProtection(at url: URL) throws {
        protectedURLs.append(url)
        events.append(.protect(url))
    }

    func writeAtomically(_ data: Data, to url: URL) throws {
        writes.append(Write(data: data, url: url))
        events.append(.write(url))
        if let writeError { throw writeError }
    }

    func removeItemIfExists(at url: URL) throws {
        removalAttempts.append(url)
        events.append(.removeAttempt(url))
        if let removeError {
            self.removeError = nil
            throw removeError
        }
        removedURLs.append(url)
        sentinelContents.removeValue(forKey: url)
        events.append(.removeSucceeded(url))
    }
}

@MainActor
private final class ShareCleanupSchedulerFake:
    ProgressPhotoComparisonCleanupScheduling {
    private var operations: [@MainActor () -> Void] = []

    var hasScheduledOperation: Bool { !operations.isEmpty }
    var pendingOperationCount: Int { operations.count }

    func schedule(
        afterNanoseconds delay: UInt64,
        operation: @escaping @MainActor () -> Void
    ) {
        _ = delay
        operations.append(operation)
    }

    func runNext() {
        operations.removeFirst()()
    }
}

@MainActor
private final class ShareGalleryRepositoryFake: ProgressPhotoRepository {
    var photos: [ProgressPhotoSnapshot]
    var thumbnails: [String: PhotoAssetLoadResult]
    var fullImages: [String: PhotoAssetLoadResult]
    var pendingAssetCleanupIDs: [String] { [] }

    init(
        photos: [ProgressPhotoSnapshot],
        thumbnails: [String: PhotoAssetLoadResult],
        fullImages: [String: PhotoAssetLoadResult]
    ) {
        self.photos = photos
        self.thumbnails = thumbnails
        self.fullImages = fullImages
    }

    func fetchPhotos() async throws -> [ProgressPhotoSnapshot] { photos }

    func importPhoto(
        _ input: ProgressPhotoInput,
        bytes: Data
    ) async throws -> ProgressPhotoSnapshot {
        _ = input
        _ = bytes
        throw ShareFixtureError.unsupported
    }

    func thumbnail(assetID: String) async throws -> PhotoAssetLoadResult {
        thumbnails[assetID] ?? .missing
    }

    func fullImage(assetID: String) async throws -> PhotoAssetLoadResult {
        fullImages[assetID] ?? .missing
    }

    func deletePhoto(id: UUID, expectedUpdatedAt: Date) async throws {}
    func retryPendingAssetCleanup() async throws {}
}

private enum ShareFixtureError: Error {
    case unsupported
    case renderFailed
    case writeFailed
    case activityFailed
    case cleanupFailed
}

private struct ShareRGBARaster {
    struct Point {
        let x: Int
        let y: Int
    }

    let width: Int
    let height: Int
    let pixels: [UInt8]

    func isNearlyWhite(x: Int, y: Int) -> Bool {
        let pixel = rgba(x: x, y: y)
        return pixel.red >= 245 && pixel.green >= 245 && pixel.blue >= 245
    }

    func rowsContainingSaturatedRedOrBlue() -> [Int] {
        var rows: [Int] = []
        for y in 0..<height {
            var containsSource = false
            for x in 0..<width where !containsSource {
                let pixel = rgba(x: x, y: y)
                containsSource = (
                    pixel.red >= 120
                        && Int(pixel.red) >= Int(pixel.green) + 45
                        && Int(pixel.red) >= Int(pixel.blue) + 45
                ) || (
                    pixel.blue >= 120
                        && Int(pixel.blue) >= Int(pixel.red) + 45
                        && Int(pixel.blue) >= Int(pixel.green) + 45
                )
            }
            if containsSource { rows.append(y) }
        }
        return rows
    }

    func darkPixels(
        xRange: Range<Int>,
        excludingYRange: ClosedRange<Int>
    ) -> [Point] {
        var result: [Point] = []
        for y in 0..<height where !excludingYRange.contains(y) {
            for x in xRange {
                let pixel = rgba(x: x, y: y)
                if pixel.red < 100 && pixel.green < 100 && pixel.blue < 100 {
                    result.append(Point(x: x, y: y))
                }
            }
        }
        return result
    }

    private func rgba(x: Int, y: Int) -> (red: UInt8, green: UInt8, blue: UInt8) {
        let offset = ((y * width) + x) * 4
        return (pixels[offset], pixels[offset + 1], pixels[offset + 2])
    }
}

private func shareSnapshot(
    id: String,
    assetID: String,
    date: Date,
    pose: ProgressPhotoPose,
    note: String? = nil
) -> ProgressPhotoSnapshot {
    ProgressPhotoSnapshot(
        id: UUID(uuidString: id)!,
        createdAt: date,
        updatedAt: date,
        date: date,
        imageRef: assetID,
        pose: pose,
        note: note
    )
}
