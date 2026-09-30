import PDFKit
import QuickLookUI
import SwiftUI
import UniformTypeIdentifiers
import Vision

struct PDFFile: Identifiable {
    let id = UUID()
    var url: URL
    var generatedFilename: String?
    var isProcessed = false
    var isLoading = false
    var progress: Double = 0
}

struct ContentView: View {
    @StateObject private var templateStore: TemplateStore
    @StateObject private var viewModel: ContentViewModel
    @State private var isTargeted = false
    @State private var showingTemplateEditor = false

    init() {
        let store = TemplateStore()
        _templateStore = StateObject(wrappedValue: store)
        _viewModel = StateObject(wrappedValue: ContentViewModel(templateStore: store))
    }

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.pdfFiles.isEmpty {
                dropZone
            } else {
                fileList
            }
            namingSection
            bottomBar
        }
        .frame(minWidth: 400, minHeight: 300)
        .onDrop(of: [UTType.pdf], isTargeted: $isTargeted) { providers in
            viewModel.handleDrop(providers: providers)
        }
        .overlay(
            Group {
                if isTargeted {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.blue, lineWidth: 3)
                        .padding(8)
                }
            }
        )
        .alert(item: $viewModel.alertItem) { alertItem in
            Alert(
                title: Text(alertItem.title),
                message: Text(alertItem.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .sheet(isPresented: $showingTemplateEditor) {
            TemplateEditorView(store: templateStore)
        }
    }

    private var namingSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Filename format")
                    .foregroundColor(.secondary)
                Picker("", selection: $templateStore.selectedTemplateID) {
                    ForEach(templateStore.templates) { template in
                        Text(template.name).tag(template.id)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 200)

                Button(action: { showingTemplateEditor = true }) {
                    Image(systemName: "gearshape.fill")
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)

                Spacer()
            }

            Text(
                "e.g. "
                    + renderedExample(
                        format: templateStore.selectedTemplate.format,
                        customVariables: templateStore.customVariables) + ".pdf"
            )
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.windowBackgroundColor))

            VStack {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 50))
                    .foregroundColor(.secondary)
                Text("Drag and drop PDF files onto the area above")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var fileList: some View {
        List {
            ForEach(viewModel.pdfFiles) { file in
                fileRow(for: file)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
        )
        .padding(.horizontal)
    }

    private func fileRow(for file: PDFFile) -> some View {
        HStack {
            Group {
                if file.isLoading {
                    ProgressView(value: file.progress)
                        .progressViewStyle(CircularProgressViewStyle())
                        .controlSize(.small)
                } else if file.isProcessed {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .frame(width: 20, height: 20)

            VStack(alignment: .leading) {
                Text(file.url.lastPathComponent)
                    .font(.headline)
                if let generatedFilename = file.generatedFilename {
                    Text(generatedFilename)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if file.generatedFilename != nil {
                HStack {
                    Button("Apply") { viewModel.applyFilename(for: file) }
                        .buttonStyle(.borderedProminent)
                }
            }

            Button(action: { viewModel.openQuickLook(for: file) }) {
                Image(systemName: "eye")
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)

            Button(action: { viewModel.openInFinder(file) }) {
                Image(systemName: "folder")
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
        }
    }

    private var bottomBar: some View {
        HStack {
            Button(action: { viewModel.addFiles() }) {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)

            Spacer()
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
    }
}

class ContentViewModel: ObservableObject {
    @Published var pdfFiles: [PDFFile] = []
    private let client: AppleIntelligenceClient = .default
    private let templateStore: TemplateStore
    private var processingQueue: [PDFFile] = []
    private var isProcessing = false
    @Published var alertItem: AlertItem?
    private var quickLookDataSource: QuickLookDataSource?

    init(templateStore: TemplateStore) {
        self.templateStore = templateStore
    }

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.pdf.identifier, options: nil) {
                    item, error in
                    guard let url = item as? URL else { return }
                    DispatchQueue.main.async {
                        let newFile = PDFFile(url: url)
                        self.pdfFiles.append(newFile)
                        self.queueFileForProcessing(newFile)
                    }
                }
            }
        }
        return true
    }

    private func queueFileForProcessing(_ file: PDFFile) {
        processingQueue.append(file)
        processNextFileIfNeeded()
    }

    private func processNextFileIfNeeded() {
        guard !isProcessing, let nextFile = processingQueue.first else { return }
        isProcessing = true
        processingQueue.removeFirst()
        generate(for: nextFile)
    }

    func generate(for file: PDFFile) {
        Task { @MainActor in
            guard let index = pdfFiles.firstIndex(where: { $0.id == file.id }) else {
                self.isProcessing = false
                self.processNextFileIfNeeded()
                return
            }
            pdfFiles[index].isLoading = true
            pdfFiles[index].generatedFilename = nil
            pdfFiles[index].progress = 0

            do {
                let contents = try await extractPDFContents(from: file.url)
                pdfFiles[index].progress = 0.3

                let values = try await extractVariables(
                    from: contents, variables: templateStore.allVariables, using: client)
                pdfFiles[index].progress = 0.8

                let filename = renderFilename(
                    template: templateStore.selectedTemplate, values: values,
                    extension: file.url.pathExtension)
                pdfFiles[index].generatedFilename = filename
                pdfFiles[index].isProcessed = true
                pdfFiles[index].progress = 1.0
            } catch {
                print("Error generating filename: \(error)")
                pdfFiles[index].progress = 0
            }

            pdfFiles[index].isLoading = false
            self.isProcessing = false
            self.processNextFileIfNeeded()
        }
    }

    func applyFilename(for file: PDFFile) {
        guard let index = pdfFiles.firstIndex(where: { $0.id == file.id }),
            let newFilename = pdfFiles[index].generatedFilename
        else { return }

        let originalURL = file.url
        let directory = originalURL.deletingLastPathComponent()
        var newURL = directory.appendingPathComponent(newFilename)
        if newURL.pathExtension.isEmpty {
            newURL.appendPathExtension(originalURL.pathExtension)
        }

        do {
            try FileManager.default.moveItem(at: originalURL, to: newURL)
            pdfFiles[index].url = newURL
            pdfFiles[index].generatedFilename = nil
            pdfFiles[index].isProcessed = true
        } catch {
            print("Failed to rename file: \(error)")
            alertItem = AlertItem(
                title: "Failed to rename file",
                message: error.localizedDescription
            )
        }
    }

    func rejectFilename(for file: PDFFile) {
        guard let index = pdfFiles.firstIndex(where: { $0.id == file.id }) else { return }
        pdfFiles[index].generatedFilename = nil
        pdfFiles[index].isProcessed = false
    }

    func addFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [UTType.pdf]

        if panel.runModal() == .OK {
            for url in panel.urls {
                let newFile = PDFFile(url: url)
                pdfFiles.append(newFile)
                queueFileForProcessing(newFile)
            }
        }
    }

    func openInFinder(_ file: PDFFile) {
        NSWorkspace.shared.selectFile(file.url.path, inFileViewerRootedAtPath: "")
    }

    func openQuickLook(for file: PDFFile) {
        guard let panel = QLPreviewPanel.shared() else { return }

        let previewItem = file.url as NSURL
        quickLookDataSource = QuickLookDataSource(item: previewItem)
        panel.dataSource = quickLookDataSource

        if !panel.isVisible {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    /// Extracts text from a PDF, falling back to on-device OCR for scanned pages
    /// (e.g. phone photos or faxes) that have no embedded text layer.
    private func extractPDFContents(from url: URL) async throws -> String {
        guard let pdfDocument = PDFDocument(url: url) else {
            throw NSError(
                domain: "PDFError", code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Unable to open PDF document."])
        }

        return await Task.detached(priority: .userInitiated) {
            (0..<pdfDocument.pageCount).compactMap { pageIndex -> String? in
                guard let page = pdfDocument.page(at: pageIndex) else { return nil }

                // Always OCR in addition to any embedded text layer: some PDFs (e.g. an
                // exported photo) carry a scanned page's real content purely as an image,
                // but still have a trivial bit of embedded text (like a caption or
                // timestamp annotation) that would otherwise make us skip OCR entirely.
                var pieces: [String] = []
                if let text = page.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                    !text.isEmpty
                {
                    pieces.append(text)
                }
                if let ocrText = try? Self.recognizedText(from: page),
                    !ocrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                {
                    pieces.append(ocrText)
                }

                return pieces.isEmpty ? nil : pieces.joined(separator: "\n")
            }.joined()
        }.value
    }

    private static func recognizedText(from page: PDFPage) throws -> String {
        let bounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 3
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let image = page.thumbnail(of: size, for: .mediaBox)

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return ""
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])

        return (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }
}

class QuickLookDataSource: NSObject, QLPreviewPanelDataSource {
    let item: NSURL

    init(item: NSURL) {
        self.item = item
        super.init()
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        return 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        return item
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

struct AlertItem: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
