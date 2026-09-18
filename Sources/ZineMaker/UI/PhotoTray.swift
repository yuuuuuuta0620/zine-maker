import AppKit
import UniformTypeIdentifiers
import SwiftUI

/// 下部の写真トレイ。取り込んだ写真がここに並び、キャンバスへドラッグして配置する。
struct PhotoTray: View {
    @ObservedObject var state: AppState
    @State private var reloadTick = 0

    private var placedIDs: Set<UUID> {
        Set(state.boards.flatMap { $0.imageFrames.compactMap(\.assetID) })
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if state.assets.isEmpty {
                emptyState
            } else {
                strip
            }
        }
        .glassBar()
        .onReceive(NotificationCenter.default.publisher(for: ImageStore.didLoad)) { _ in
            reloadTick &+= 1
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "photo.stack").font(.system(size: 10, weight: .semibold))
            Text("写真トレイ").font(.system(size: 11, weight: .semibold))
            Text("\(state.assets.count) 枚")
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.secondary)
            if !state.unplacedAssets.isEmpty {
                Text("未配置 \(state.unplacedAssets.count)")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.orange)
            }
            Spacer()
            if !state.traySelection.isEmpty {
                Text("\(state.traySelection.count) 枚選択")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.secondary)
                Button("選択解除") { state.traySelection.removeAll() }
                    .buttonStyle(.link).font(.system(size: 10))
            }
            Button {
                state.presentImportPhotos()
            } label: {
                Label("写真を追加", systemImage: "plus").font(.system(size: 10))
            }
            .controlSize(.small)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    private var emptyState: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.doc").foregroundStyle(.tertiary)
            Text("写真をここへドラッグするか「写真を追加」から読み込みます　—　JPEG / PNG / TIFF / AVIF / JPEG XL / HEIC")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: DS.thumbSize.height + DS.thumbPadding * 2)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
    }

    private var strip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 6) {
                ForEach(state.assets) { asset in
                    PhotoThumb(asset: asset,
                               isSelected: state.traySelection.contains(asset.id),
                               isPlaced: placedIDs.contains(asset.id),
                               tick: reloadTick)
                        .onTapGesture {
                            if NSEvent.modifierFlags.contains(.command) || NSEvent.modifierFlags.contains(.shift) {
                                if state.traySelection.contains(asset.id) { state.traySelection.remove(asset.id) }
                                else { state.traySelection.insert(asset.id) }
                            } else {
                                state.traySelection = [asset.id]
                            }
                        }
                        .onTapGesture(count: 2) { state.assign(assetID: asset.id) }
                        .onDrag {
                            let ids = state.traySelection.contains(asset.id) && state.traySelection.count > 1
                                ? state.assets.filter { state.traySelection.contains($0.id) }.map(\.id)
                                : [asset.id]
                            let payload = ids.map(\.uuidString).joined(separator: "\n")
                            let provider = NSItemProvider()
                            provider.registerDataRepresentation(forTypeIdentifier: "com.zinemaker.asset",
                                                                visibility: .all) { completion in
                                completion(payload.data(using: .utf8), nil)
                                return nil
                            }
                            return provider
                        }
                        .contextMenu {
                            Button("選択中の枠に入れる") { state.assign(assetID: asset.id) }
                            Button("新しい枠として置く") { state.addImageFrame(assetID: asset.id) }
                            Divider()
                            Button("Finder で表示") {
                                NSWorkspace.shared.activateFileViewerSelecting([asset.url])
                            }
                            Divider()
                            Button("トレイから外す", role: .destructive) {
                                state.removeAssets(state.traySelection.contains(asset.id)
                                                   ? state.traySelection : [asset.id])
                            }
                        }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, DS.thumbPadding)
        }
        .frame(height: DS.thumbSize.height + DS.thumbPadding * 2)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in handleDrop(providers) }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let group = DispatchGroup()
        var urls: [URL] = []
        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { urls.append(url) }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            let readable = Set(ImageStore.readableTypes.map(\.identifier))
            let images = urls.filter { url in
                (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType?.identifier)
                    .flatMap { readable.contains($0) } ?? false
            }
            state.importPhotos(urls: images.sorted { $0.lastPathComponent < $1.lastPathComponent })
        }
        return true
    }
}

private struct PhotoThumb: View {
    let asset: PhotoAsset
    let isSelected: Bool
    let isPlaced: Bool
    let tick: Int

    var body: some View {
        let image = ImageStore.shared.thumbnail(at: asset.url, maxPixel: 256)
        ZStack(alignment: .topTrailing) {
            CGImageView(image: image, contentMode: .fill)
                .frame(width: DS.thumbSize.width, height: DS.thumbSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(isSelected ? Color.accentColor : Color.black.opacity(0.15),
                                      lineWidth: isSelected ? 2.5 : 1)
                )
                .opacity(isPlaced ? 0.55 : 1)

            if isPlaced {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.white, Color.accentColor)
                    .padding(3)
            }
        }
        .help(asset.name)
    }
}
