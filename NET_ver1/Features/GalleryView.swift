import Photos
import SwiftUI

struct GalleryItem: Identifiable {
    let id: String
    let asset: PHAsset
    var thumbnail: UIImage?
}

struct GalleryView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var items: [GalleryItem] = []
    @State private var selectedItem: GalleryItem?
    @State private var isAuthorized = false
    @State private var didRequestAuthorization = false

    private let columnCount = 3

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if !isAuthorized {
                    permissionView
                } else if items.isEmpty {
                    ContentUnavailableView(
                        "Chưa có ảnh nào",
                        systemImage: "photo.stack",
                        description: Text("Ảnh bạn chụp bằng NÉT sẽ xuất hiện tại đây.")
                    )
                } else {
                    grid
                }
            }
            .navigationTitle("Bộ Sưu Tập")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .refreshable { await loadItems() }
            .task { await loadItems() }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    Task { await loadItems() }
                }
            }
            .sheet(item: $selectedItem) { item in
                GalleryDetailView(asset: item.asset, thumbnail: item.thumbnail)
            }
        }
    }

    // MARK: - Subviews

    private var grid: some View {
        ScrollView {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: columnCount),
                spacing: 2
            ) {
                ForEach(items) { item in
                    Color.black
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            if let thumbnail = item.thumbnail {
                                Image(uiImage: thumbnail)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                ProgressView().tint(.white)
                            }
                        }
                        .clipped()
                        .contentShape(.rect)
                        .onTapGesture { selectedItem = item }
                }
            }
        }
    }

    private var permissionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 44))
                .foregroundStyle(.gray)
            Text("Cần quyền truy cập Thư viện ảnh")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            Text("Ứng dụng cần quyền truy cập Thư viện ảnh để lưu và hiển thị những bức ảnh bạn vừa chụp trên thiết bị.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button("Mở Cài đặt") {
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsURL)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(28)
        .frame(maxWidth: 420)
    }

    // MARK: - Loading

    private func loadItems() async {
        if !didRequestAuthorization {
            didRequestAuthorization = true
            isAuthorized = await withCheckedContinuation { continuation in
                PhotoLibraryAuth.requestReadAccess { continuation.resume(returning: $0) }
            }
        } else {
            isAuthorized = PhotoLibraryAuth.isReadAuthorized
        }
        guard isAuthorized else { return }

        // Gán placeholder trước để grid hiện ngay, ảnh thật sẽ điền vào sau.
        let assets = Self.recentAssets()
        items = assets.map { GalleryItem(id: $0.localIdentifier, asset: $0, thumbnail: nil) }

        let loaded = await withTaskGroup(of: GalleryItem?.self) { group in
            for item in items {
                group.addTask {
                    let image = await Self.thumbnail(for: item.asset)
                    return GalleryItem(id: item.id, asset: item.asset, thumbnail: image)
                }
            }
            var results: [GalleryItem?] = []
            for await result in group {
                results.append(result)
            }
            return results
        }

        for item in loaded {
            guard let item, let index = items.firstIndex(where: { $0.id == item.id }) else { continue }
            items[index] = item
        }
        }

    private static func recentAssets(limit: Int = 60) -> [PHAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = limit

        let result = PHAsset.fetchAssets(with: .image, options: options)
        guard result.count > 0 else { return [] }
        return result.objects(at: IndexSet(0..<result.count))
    }

    private static func thumbnail(for asset: PHAsset) async -> UIImage? {
        let manager = PHCachingImageManager()
        let scale = await MainActor.run { UIScreen.main.scale }
        let target = CGSize(width: 200 * scale, height: 200 * scale)

        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast

        return await withCheckedContinuation { continuation in
            var resumed = false
            manager.requestImage(for: asset, targetSize: target, contentMode: .aspectFill, options: options) { image, info in
                guard !resumed else { return }
                // `opportunistic` có thể gọi lại nhiều lần; chỉ lấy lần đầu có ảnh thật.
                guard image != nil, (info?[PHImageResultIsDegradedKey] as? Bool) != true else { return }
                resumed = true
                continuation.resume(returning: image)
            }
        }
    }
}

struct GalleryDetailView: View {
    let asset: PHAsset
    let thumbnail: UIImage?

    @State private var fullImage: UIImage?
    @State private var didFailLoading = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if let image = fullImage ?? thumbnail {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    ProgressView().tint(.white)
                }

                if didFailLoading && fullImage == nil {
                    ContentUnavailableView(
                        "Không tải được ảnh",
                        systemImage: "exclamationmark.triangle",
                        description: Text("Ảnh này có thể đã bị xóa khỏi thư viện.")
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Đóng") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) { actionBar }
            .task { await loadFullImage() }
            }
            }

            private var actionBar: some View {
            Group {
            if let image = fullImage ?? thumbnail {
                ShareLink(
                    item: Image(uiImage: image),
                    preview: SharePreview("Ảnh chụp từ NÉT", image: Image(uiImage: image))
                ) {
                    Label("Chia sẻ", systemImage: "square.and.arrow.up")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial, in: .capsule)
                        .foregroundStyle(.white)
                }
            }
            }
            .padding(.bottom, 8)
            }

            // MARK: - Loading

    private func loadFullImage() async {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .none

        let image: UIImage? = await withCheckedContinuation { continuation in
            var hasResumed = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                // Callback có thể được gọi lại nhiều lần; chỉ resume một lần.
                guard !hasResumed else { return }
                let failed = (info?[PHImageCancelledKey] as? Bool) == true || info?[PHImageErrorKey] != nil
                guard !failed else {
                    hasResumed = true
                    continuation.resume(returning: nil)
                    return
                }
                guard image != nil else { return }
                hasResumed = true
                continuation.resume(returning: image)
            }
        }

        if let image {
            fullImage = image
        } else {
            didFailLoading = true
        }
        }
        }
