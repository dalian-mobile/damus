//
//  AttachMediaUtility.swift
//  damus
//
//  Created by Swift on 2/17/23.
//

import SwiftUI
import UIKit
import CoreGraphics
import UniformTypeIdentifiers

enum ImageUploadResult {
    case success(String)
    case failed(Error?)
}

fileprivate func create_upload_body(mediaData: Data, boundary: String, mediaUploader: MediaUploader, mediaIsImage: Bool) -> Data {
        let body = NSMutableData();
        let contentType = mediaIsImage ? "image/jpg" : "video/mp4"
        let genericFileName = mediaIsImage ? "damus_generic_filename.jpg" : "damus_generic_filename.mp4"
        body.appendString(string: "Content-Type: multipart/form-data; boundary=\(boundary)\r\n\r\n")
        body.appendString(string: "--\(boundary)\r\n")
        body.appendString(string: "Content-Disposition: form-data; name=\(mediaUploader.nameParam); filename=\(genericFileName)\r\n")
        body.appendString(string: "Content-Type: \(contentType)\r\n\r\n")
        body.append(mediaData as Data)
        body.appendString(string: "\r\n")
        body.appendString(string: "--\(boundary)--\r\n")
        return body as Data
    }

func create_upload_request(mediaToUpload: MediaUpload, mediaUploader: MediaUploader, progress: URLSessionTaskDelegate) async -> ImageUploadResult {
    var mediaData: Data?
    guard let url = URL(string: mediaUploader.postAPI) else {
        return .failed(nil)
    }
    
    var request = URLRequest(url: url)
    request.httpMethod = "POST";
    let boundary = "Boundary-\(UUID().description)"
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    
    switch mediaToUpload {
    case .image(let img):
        mediaData = img.jpegData(compressionQuality: 0.8)
    case .video(let url):
        do {
            mediaData = try Data(contentsOf: url)
        } catch {
            return .failed(error)
        }
    }

    guard let mediaData else {
        return .failed(nil)
    }

    request.httpBody = create_upload_body(mediaData: mediaData, boundary: boundary, mediaUploader: mediaUploader, mediaIsImage: mediaToUpload.is_image)
    
    do {
        let (data, _) = try await URLSession.shared.data(for: request, delegate: progress)
        
        guard let responseString = String(data: data, encoding: String.Encoding(rawValue: String.Encoding.utf8.rawValue)) else {
            print("Upload failed getting response string")
            return .failed(nil)
        }
        
        guard let url = mediaUploader.getMediaURL(from: responseString, mediaIsImage: mediaToUpload.is_image) else {
            print("Upload failed getting media url")
            return .failed(nil)
        }
        
        return .success(url)
        
    } catch {
        return .failed(error)
    }
}

extension PostView {
    struct ImagePicker: UIViewControllerRepresentable {

        @Environment(\.presentationMode)
        private var presentationMode

        let sourceType: UIImagePickerController.SourceType
        let damusState: DamusState
        let onImagePicked: (UIImage) -> Void
        let onVideoPicked: (URL) -> Void

        final class Coordinator: NSObject,
                                 UINavigationControllerDelegate,
                                 UIImagePickerControllerDelegate {

            @Binding
            private var presentationMode: PresentationMode
            private let sourceType: UIImagePickerController.SourceType
            private let onImagePicked: (UIImage) -> Void
            private let onVideoPicked: (URL) -> Void

            init(presentationMode: Binding<PresentationMode>,
                 sourceType: UIImagePickerController.SourceType,
                 onImagePicked: @escaping (UIImage) -> Void,
                 onVideoPicked: @escaping (URL) -> Void) {
                _presentationMode = presentationMode
                self.sourceType = sourceType
                self.onImagePicked = onImagePicked
                self.onVideoPicked = onVideoPicked
            }

            func imagePickerController(_ picker: UIImagePickerController,
                                       didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
                if let videoURL = info[UIImagePickerController.InfoKey.mediaURL] as? URL {
                    // Handle the selected video
                    onVideoPicked(videoURL)
                } else if let uiImage = info[UIImagePickerController.InfoKey.originalImage] as? UIImage {
                    // Handle the selected image
                    onImagePicked(uiImage)
                }
                presentationMode.dismiss()

            }

            func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
                presentationMode.dismiss()
            }

        }

        func makeCoordinator() -> Coordinator {
            return Coordinator(presentationMode: presentationMode,
                               sourceType: sourceType,
                               onImagePicked: onImagePicked, onVideoPicked: onVideoPicked)
        }

        func makeUIViewController(context: UIViewControllerRepresentableContext<ImagePicker>) -> UIImagePickerController {
            let picker = UIImagePickerController()
            picker.sourceType = sourceType
            let mediaUploader = get_media_uploader(damusState.keypair.pubkey)
            picker.mediaTypes = ["public.image"]
            if mediaUploader.supportsVideo {
                picker.mediaTypes.append("public.movie")
            }
            picker.delegate = context.coordinator
            return picker
        }

        func updateUIViewController(_ uiViewController: UIImagePickerController,
                                    context: UIViewControllerRepresentableContext<ImagePicker>) {

        }
    }
}

extension NSMutableData {
    func appendString(string: String) {
        guard let data = string.data(using: String.Encoding.utf8, allowLossyConversion: true) else {
            return
        }
        append(data)
    }
}

enum MediaUploader: String, CaseIterable, Identifiable {
    var id: String { self.rawValue }
    case nostrBuild
    case nostrImg

    var nameParam: String {
        switch self {
        case .nostrBuild:
            return "\"fileToUpload\""
        case .nostrImg:
            return "\"image\""
        }
    }

    var supportsVideo: Bool {
        switch self {
        case .nostrBuild:
            return true
        case .nostrImg:
            return false
        }
    }

    struct Model: Identifiable, Hashable {
        var id: String { self.tag }
        var index: Int
        var tag: String
        var displayName : String
    }

    var model: Model {
        switch self {
        case .nostrBuild:
            return .init(index: -1, tag: "nostrBuild", displayName: NSLocalizedString("NostrBuild", comment: "Dropdown option label for system default for NostrBuild image uploader."))
        case .nostrImg:
            return .init(index: 0, tag: "nostrImg", displayName: NSLocalizedString("NostrImg", comment: "Dropdown option label for system default for NostrImg image uploader."))
        }
    }


    var postAPI: String {
        switch self {
        case .nostrBuild:
            return "https://nostr.build/upload.php"
        case .nostrImg:
            return "https://nostrimg.com/api/upload"
        }
    }

    func getMediaURL(from responseString: String, mediaIsImage: Bool) -> String? {
        switch self {
        case .nostrBuild:
            guard let startIndex = responseString.range(of: "nostr.build_")?.lowerBound else {
                return nil
            }
            
            let stringContainingName = responseString[startIndex..<responseString.endIndex]
            guard let endIndex = stringContainingName.range(of: "<")?.lowerBound else {
                return nil
            }
            let nostrBuildImageName = responseString[startIndex..<endIndex]
            let nostrBuildURL = mediaIsImage ? "https://nostr.build/i/\(nostrBuildImageName)" : "https://nostr.build/av/\(nostrBuildImageName)"
            return nostrBuildURL
                
        case .nostrImg:
            guard let startIndex = responseString.range(of: "https://i.nostrimg.com/")?.lowerBound else {
                    return nil
                }
            let stringContainingName = responseString[startIndex..<responseString.endIndex]
            guard let endIndex = stringContainingName.range(of: "\"")?.lowerBound else {
                return nil
            }
            let nostrBuildImageName = responseString[startIndex..<endIndex]
            let nostrBuildURL = "\(nostrBuildImageName)"
            return nostrBuildURL
        }
    }
}
