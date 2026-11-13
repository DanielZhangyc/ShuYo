// AppFeedback.swift — an in-app feedback form. What the person writes,
// plus up to four photos, goes to this application's independent platform environment.
//
// Copy this file and AirDeviceProof.swift into the app target, unchanged
// except for `FeedbackConfig.endpoint`, `FeedbackConfig.appKey` and
// `FeedbackConfig.teamID`. Requires no packages, no Info.plist entries, and
// no account: a public ingestion key authorizes submission only. iOS 15 or later.
//
// With the App Attest capability and `teamID` set, each entry carries the
// device's proof (AirDeviceProof.swift). Without them — and always on the
// Simulator — feedback is still sent and stored, marked unverified.
//
// Usage — present the form from anywhere:
//   .sheet(isPresented: $showFeedback) { FeedbackView() }
// or send without the form:
//   try await FeedbackClient.send(message: "…", images: [uiImage])
//
// The form's strings are plain English; localize them like the rest of the
// app if the app is localized.

import PhotosUI
import SwiftUI
import UIKit

enum FeedbackConfig {
    /// The `feedbackEndpoint` and public `key` returned by `workers app-key`.
    static let endpoint = URL(string: "https://apps.air.build/v1/ingest/feedback")!
    static let appKey = "ak_production_jdSzo3xlhYz1sMiJ3mxI6VFdq13OYClx97IS4HLPJ3s"
    /// The Apple team id (DEVELOPMENT_TEAM) for App Attest; nil sends no proof.
    static let teamID: String? = nil
    static let maximumImages = 4
}

enum FeedbackClient {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Sends one piece of feedback. Images are downscaled to 2048 px on the
    /// long side and sent as JPEG, so a report with four screenshots stays
    /// small enough for cellular. Main actor because the device strings come
    /// from `UIDevice`; the network wait does not block anything.
    @MainActor
    static func send(message: String, images: [UIImage]) async throws {
        let info = Bundle.main.infoDictionary ?? [:]
        let body: [String: Any] = [
            "message": message,
            "appVersion": info["CFBundleShortVersionString"] as? String ?? "",
            "appBuild": info["CFBundleVersion"] as? String ?? "",
            "deviceModel": deviceModel,
            "osVersion": "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
            "locale": Locale.current.identifier,
            "images": images.prefix(FeedbackConfig.maximumImages).compactMap { image -> [String: String]? in
                guard let data = jpegData(image) else { return nil }
                return ["mediaType": "image/jpeg", "data": data.base64EncodedString()]
            },
        ]

        var request = URLRequest(url: FeedbackConfig.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(FeedbackConfig.appKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let bytes = try JSONSerialization.data(withJSONObject: body)
        request.httpBody = bytes
        request.timeoutInterval = 60
        // The proof signs these exact bytes; none is fine (stored unverified).
        let proof = await AirDeviceProof.headers(
            for: bytes, endpoint: FeedbackConfig.endpoint, appKey: FeedbackConfig.appKey, teamID: FeedbackConfig.teamID
        )
        for (name, value) in proof {
            request.setValue(value, forHTTPHeaderField: name)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw Failure(message: "No response from the server.")
        }
        if !proof.isEmpty {
            await AirDeviceProof.handle(status: http.value(forHTTPHeaderField: "X-Attest-Status"))
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            let reason = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["reason"] as? String
            throw Failure(message: reason ?? "The server answered \(http.statusCode).")
        }
    }

    private static func jpegData(_ image: UIImage) -> Data? {
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, 2048 / max(longest, 1))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let scaled = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return scaled.jpegData(compressionQuality: 0.8)
    }

    /// The hardware identifier (`iPhone17,2`), which is what a bug report needs;
    /// `UIDevice.model` only says "iPhone".
    private static var deviceModel: String {
        var system = utsname()
        uname(&system)
        return withUnsafeBytes(of: &system.machine) { buffer in
            String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}

struct FeedbackView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    @State private var images: [UIImage] = []
    @State private var showingImagePicker = false
    @State private var sending = false
    @State private var failure: String?
    @State private var sent = false

    private var canSend: Bool {
        !sending && (!message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !images.isEmpty)
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextEditor(text: $message)
                        .frame(minHeight: 110)
                } header: {
                    Text("What happened, or what would you like to see?")
                }
                Section {
                    if !images.isEmpty {
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                ForEach(images.indices, id: \.self) { index in
                                    Image(uiImage: images[index])
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 72, height: 72)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(alignment: .topTrailing) {
                                            Button {
                                                images.remove(at: index)
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .symbolRenderingMode(.palette)
                                                    .foregroundStyle(.white, .black.opacity(0.6))
                                            }
                                            .padding(4)
                                        }
                                }
                            }
                        }
                    }
                    Button {
                        showingImagePicker = true
                    } label: {
                        Label("Add Screenshots", systemImage: "photo.on.rectangle")
                    }
                    .disabled(images.count >= FeedbackConfig.maximumImages)
                } footer: {
                    Text("Up to \(FeedbackConfig.maximumImages) images. The app version and device model are sent along.")
                }
                if let failure {
                    Section {
                        Text(failure).foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Send Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }.disabled(sending)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if sending {
                        ProgressView()
                    } else {
                        Button("Send") { send() }.disabled(!canSend)
                    }
                }
            }
            .sheet(isPresented: $showingImagePicker) {
                FeedbackImagePicker(maxSelectionCount: FeedbackConfig.maximumImages - images.count) { pickedImages in
                    let remaining = FeedbackConfig.maximumImages - images.count
                    images.append(contentsOf: pickedImages.prefix(remaining))
                }
            }
            .alert("Thank you", isPresented: $sent) {
                Button("Done") { dismiss() }
            } message: {
                Text("Your feedback was sent.")
            }
            .interactiveDismissDisabled(sending)
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private func send() {
        sending = true
        failure = nil
        Task {
            do {
                try await FeedbackClient.send(message: message, images: images)
                sent = true
            } catch {
                failure = error.localizedDescription
            }
            sending = false
        }
    }
}

private struct FeedbackImagePicker: UIViewControllerRepresentable {
    let maxSelectionCount: Int
    let onImages: ([UIImage]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onImages: onImages)
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = maxSelectionCount
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let onImages: ([UIImage]) -> Void

        init(onImages: @escaping ([UIImage]) -> Void) {
            self.onImages = onImages
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard !results.isEmpty else { return }

            let group = DispatchGroup()
            let lock = NSLock()
            var loadedImages: [UIImage] = []
            for result in results {
                guard result.itemProvider.canLoadObject(ofClass: UIImage.self) else { continue }
                group.enter()
                result.itemProvider.loadObject(ofClass: UIImage.self) { object, _ in
                    if let image = object as? UIImage {
                        lock.lock()
                        loadedImages.append(image)
                        lock.unlock()
                    }
                    group.leave()
                }
            }
            group.notify(queue: .main) {
                self.onImages(loadedImages)
            }
        }
    }
}
