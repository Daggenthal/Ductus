import Testing
@testable import DuctusEngine

@Suite struct AppVersionTests {
    @Test func parses() {
        #expect(AppVersion("v0.1.0")?.parts == [0, 1, 0])
        #expect(AppVersion("1.2")?.parts == [1, 2])
        #expect(AppVersion("2.0.1-beta.3")?.parts == [2, 0, 1])
        #expect(AppVersion("latest") == nil)
        #expect(AppVersion("") == nil)
    }

    @Test func compares() {
        #expect(AppVersion("0.1.0")! < AppVersion("0.2.0")!)
        #expect(AppVersion("0.9.0")! < AppVersion("0.10.0")!)  // numbers, not text
        #expect(AppVersion("1.2")! == AppVersion("1.2.0")!)
        #expect(!(AppVersion("1.0.0")! < AppVersion("v1.0")!))
        #expect(AppVersion("1.0.1")! > AppVersion("1.0")!)
    }

    @Test func readsChecksums() {
        let text = """
        6f1d2c0a9b8e7d6c5b4a3f2e1d0c9b8a7f6e5d4c3b2a1f0e9d8c7b6a5f4e3d2c  Ductus-0.1.0.zip
        A1B2C3D4E5F60718293A4B5C6D7E8F90A1B2C3D4E5F60718293A4B5C6D7E8F90 *Ductus-0.1.0.dmg
        not a checksum line
        """
        let sums = Checksums.parse(text)
        #expect(sums.count == 2)
        #expect(sums["Ductus-0.1.0.dmg"] == "a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90")
    }
}
