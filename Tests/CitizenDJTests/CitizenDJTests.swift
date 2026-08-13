import XCTest
@testable import CitizenDJ

/// Smoke + resource-access tests. Behavior tests arrive with later chunks.
final class CitizenDJTests: XCTestCase {

    func testModuleLoads() {
        XCTAssertEqual(CitizenDJ.version, "0.1.0")
    }

    /// The package must bundle the TR-808 samples and the two drum-data JSONs so they're
    /// reachable through `Bundle.module`. SPM `.copy` preserves subdirectories, so we look
    /// under `audio` / `data` first and fall back to a flat lookup just in case the layout
    /// differs. Also prints the bundle's resource listing to aid debugging if this fails.
    func testBundledResourcesAreReachable() throws {
        // Sanity dump of where SPM put the resources.
        let bundle = Bundle.module
        let resourcesDir = bundle.resourcePath ?? ""
        if let names = try? FileManager.default.contentsOfDirectory(atPath: resourcesDir) {
            print("Bundle.module resources: \(names.sorted())")
        }

        // A known TR-808 one-shot that exists in the data set.
        let kick = locate("Roland_Tr-808_full__36kick_kg", "mp3", in: ["audio", "audio/drum_machines"])
        XCTAssertNotNil(kick, "TR-808 kick sample not found in bundle")

        // The two manifests the engine decodes.
        let machines = locate("drum_machines", "json", in: ["data"])
        XCTAssertNotNil(machines, "drum_machines.json not found in bundle")
        let patterns = locate("drum_patterns", "json", in: ["data"])
        XCTAssertNotNil(patterns, "drum_patterns.json not found in bundle")
    }

    /// Tries `Bundle.module` lookups with an optional subdirectory, then flat as a fallback.
    private func locate(_ name: String, _ ext: String, in subdirs: [String]) -> URL? {
        let bundle = Bundle.module
        for sub in subdirs {
            if let url = bundle.url(forResource: name, withExtension: ext, subdirectory: sub) {
                return url
            }
        }
        return bundle.url(forResource: name, withExtension: ext)
    }
}
