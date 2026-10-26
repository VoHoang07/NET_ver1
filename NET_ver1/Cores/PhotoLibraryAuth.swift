import Photos

enum PhotoLibraryAuth {
    nonisolated static var currentStatus: PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .addOnly)
    }

    nonisolated static var isReadAuthorized: Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return status == .authorized || status == .limited
    }

    nonisolated static func request(_ completion: @escaping @Sendable (PHAuthorizationStatus) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { completion($0) }
    }

    nonisolated static func requestReadAccess(_ completion: @escaping @Sendable (Bool) -> Void) {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized, .limited:
            completion(true)
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { completion($0 == .authorized || $0 == .limited) }
        case .denied, .restricted:
            completion(false)
        @unknown default:
            completion(false)
        }
    }
}
