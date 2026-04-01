import AppKit
import SwiftUI

struct AboutView: View {
    private var shortVersion: String {
        AppMetadata.shortVersion
    }

    private var buildVersion: String {
        AppMetadata.buildVersion
    }

    private var iconImage: NSImage {
        AppMetadata.applicationIconImage
    }

    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: iconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 12, y: 4)

            VStack(spacing: 6) {
                Text("Porti")
                    .font(.system(size: 28, weight: .semibold))
                Text("Version \(shortVersion) • Build \(buildVersion)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Link(destination: AppMetadata.repositoryURL) {
                Label("github.com/kysz/porti", systemImage: "link")
                    .font(.body)
            }
            .buttonStyle(.link)

            Text("Save Dock profiles and switch between them from the menu bar.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }
}
