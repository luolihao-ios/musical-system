import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct DocumentPickerView: UIViewControllerRepresentable {
    let onPick: ([ImportedFile]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let lrc = UTType(filenameExtension: "lrc") ?? .plainText
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.audio, lrc, .image, UTType(filenameExtension: "aiyuepack") ?? .data],
            asCopy: false
        )
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(
        _ uiViewController: UIDocumentPickerViewController,
        context: Context
    ) {
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([ImportedFile]) -> Void

        init(onPick: @escaping ([ImportedFile]) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            onPick(
                urls.map {
                    ImportedFile(
                        sourceURL: $0,
                        kind: $0.pathExtension.lowercased() == "aiyuepack" ? .package : $0.pathExtension.lowercased() == "lrc" ? .lyrics : ["jpg", "jpeg", "png", "webp"].contains($0.pathExtension.lowercased()) ? .cover : .audio
                    )
                }
            )
        }
    }
}
