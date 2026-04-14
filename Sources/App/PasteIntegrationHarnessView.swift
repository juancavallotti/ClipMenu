import SwiftUI
import SwiftData

struct PasteIntegrationHarnessView: View {
    private let sampleText = "ClipMenu UI test paste"
    private let runtime = AppRuntime.shared

    @Environment(\.modelContext) private var modelContext
    @FocusState private var isFieldFocused: Bool
    @State private var text = ""
    @State private var accessibilityStatus = PasteService.accessibilityStatus()
    @State private var simulatedPasteCount = 0
    @State private var lastSimulatedPaste = ""
    @State private var stepStatus = "Idle"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Paste Integration Harness")
                .font(.headline)

            TextField("Paste target", text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($isFieldFocused)
                .accessibilityIdentifier("pasteTargetField")

            Button("Open Popup") {
                Task { @MainActor in openPopup() }
            }
            .accessibilityIdentifier("openPopupButton")

            Text(accessibilityTrustText)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(accessibilityStatus.isTrusted ? .green : .red)
                .accessibilityIdentifier("accessibilityTrustLabel")
                .accessibilityLabel(accessibilityTrustText)

            Text(accessibilityStatus.bundleIdentifier)
                .font(.caption)
                .textSelection(.enabled)
                .accessibilityIdentifier("bundleIdentifierLabel")
                .accessibilityLabel(accessibilityStatus.bundleIdentifier)

            Text(accessibilityStatus.executablePath)
                .font(.caption2)
                .textSelection(.enabled)
                .lineLimit(3)
                .accessibilityIdentifier("executablePathLabel")
                .accessibilityLabel(accessibilityStatus.executablePath)

            Text(menuSeedStatusText)
                .font(.caption)
                .accessibilityIdentifier("menuSeedStatusLabel")
                .accessibilityLabel(menuSeedStatusText)

            Text(stepStatusText)
                .font(.caption)
                .accessibilityIdentifier("stepStatusLabel")
                .accessibilityLabel(stepStatusText)

            Text(simulatedPasteCountText)
                .font(.caption)
                .accessibilityIdentifier("simulatedPasteCountLabel")
                .accessibilityLabel(simulatedPasteCountText)

            Text(simulatedPastePayloadText)
                .font(.caption2)
                .lineLimit(2)
                .accessibilityIdentifier("simulatedPastePayloadLabel")
                .accessibilityLabel(simulatedPastePayloadText)

            Text(resultText)
                .accessibilityIdentifier("pasteResultLabel")
                .accessibilityLabel(resultText)
        }
        .padding(20)
        .frame(width: 520)
        .onReceive(NotificationCenter.default.publisher(for: PasteService.simulatedPasteNotification)) { notification in
            let pasted = notification.userInfo?["string"] as? String ?? ""
            simulatedPasteCount += 1
            lastSimulatedPaste = pasted
            text = pasted
        }
        .onAppear {
            configureRuntimeForPopupTest()
            seedSampleClip()
            refreshAccessibilityStatus()
            NSApp.activate(ignoringOtherApps: true)
            isFieldFocused = true
        }
    }

    @MainActor
    private func openPopup() {
        isFieldFocused = true
        stepStatus = "Showing popup"
        runtime.hotkeyService.presentMainMenuForTesting()
        stepStatus = "Popup dismissed"
        refreshAccessibilityStatus()
    }

    private func refreshAccessibilityStatus() {
        accessibilityStatus = PasteService.accessibilityStatus()
    }

    private var accessibilityTrustText: String {
        accessibilityStatus.isTrusted ? "Accessibility: granted" : "Accessibility: missing"
    }

    private var menuSeedStatusText: String {
        "Seeded menu clip: \(sampleText)"
    }

    private var stepStatusText: String {
        "Step status: \(stepStatus)"
    }

    private var simulatedPasteCountText: String {
        "Paste callback count: \(simulatedPasteCount)"
    }

    private var simulatedPastePayloadText: String {
        "Last callback payload: \(lastSimulatedPaste)"
    }

    private var resultText: String {
        "Rendered result: \(text)"
    }

    @MainActor
    private func configureRuntimeForPopupTest() {
        runtime.settings.autoPasteAfterSelection = true
        runtime.settings.enableAction = false
        runtime.settings.showLabelsInMenu = false
        runtime.settings.showClearHistoryItem = false
        runtime.settings.numberOfItemsInline = 1
        runtime.settings.numberOfItemsInsideFolder = 10
        runtime.settings.numberedMenuItems = false
        runtime.settings.numericKeyEquivalents = false
        runtime.settings.maxMenuItemTitleLength = 200
    }

    @MainActor
    private func seedSampleClip() {
        stepStatus = "Seeding popup clip"

        do {
            let descriptor = FetchDescriptor<ClipEntry>(
                predicate: #Predicate<ClipEntry> { entry in
                    entry.stringValue == sampleText
                }
            )

            if try modelContext.fetchCount(descriptor) == 0 {
                let entry = ClipEntry()
                entry.stringValue = sampleText
                entry.types = [NSPasteboard.PasteboardType.string.rawValue]
                modelContext.insert(entry)
                try modelContext.save()
            }
            stepStatus = "Popup clip ready"
        } catch {
            stepStatus = "Failed to seed popup clip"
        }
    }
}
