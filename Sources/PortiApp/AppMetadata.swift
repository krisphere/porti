import AppKit
import Foundation

@MainActor
enum AppMetadata {
    static let fallbackShortVersion = "0.1.6"
    static let fallbackBuildVersion = "0001006"
    static let repositoryURL = URL(string: "https://github.com/kysz/porti")!

    static var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? fallbackShortVersion
    }

    static var buildVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? fallbackBuildVersion
    }

    static var bundledIconImage: NSImage? {
        loadImage(named: "AppIcon", withExtension: "icns") ?? loadImage(named: "porti", withExtension: "png")
    }

    static var applicationIconImage: NSImage {
        if let appIcon = NSApp.applicationIconImage, appIcon.size.width > 0, appIcon.size.height > 0 {
            return appIcon
        }

        if let bundledIconImage {
            return bundledIconImage
        }

        return NSImage(size: NSSize(width: 128, height: 128))
    }

    private static func loadImage(named name: String, withExtension fileExtension: String) -> NSImage? {
        for bundle in candidateBundles() {
            guard let url = bundle.url(forResource: name, withExtension: fileExtension),
                  let image = NSImage(contentsOf: url) else {
                continue
            }
            return image
        }

        return nil
    }

    private static func candidateBundles() -> [Bundle] {
        var bundles: [Bundle] = []
        var seenURLs = Set<URL>()

        func add(_ bundle: Bundle?) {
            guard let bundle else {
                return
            }

            let bundleURL = bundle.bundleURL.standardizedFileURL
            guard seenURLs.insert(bundleURL).inserted else {
                return
            }

            bundles.append(bundle)
        }

        add(Bundle.main)
        Bundle.allBundles.forEach(add)
        Bundle.allFrameworks.forEach(add)

        let fileManager = FileManager.default
        let searchDirectories = [
            Bundle.main.resourceURL,
            Bundle.main.bundleURL,
            Bundle.main.executableURL?.deletingLastPathComponent(),
            URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true),
        ]

        for directory in searchDirectories.compactMap({ $0?.standardizedFileURL }) {
            guard let childURLs = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for childURL in childURLs where childURL.pathExtension == "bundle" {
                add(Bundle(url: childURL))
            }
        }

        return bundles
    }
}
