import Foundation

do {
    try E2EEProtocol.runSelfTest()
    print("e2ee-swift-selftest: passed")
} catch {
    fputs("e2ee-swift-selftest failed: \(error)\n", stderr)
    exit(1)
}
