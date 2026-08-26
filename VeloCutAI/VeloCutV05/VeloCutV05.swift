import SwiftUI
import AVKit
import AVFoundation
import PhotosUI
import CoreTransferable
import UniformTypeIdentifiers
import UIKit

struct SpeedPoint: Identifiable, Equatable {
    var id = UUID()
    var t: Double
    var speed: Double
}

struct V5Clip: Equatable {
    let url: URL
    var name: String
    var duration: Double
    var trimStart: Double
    var trimEnd: Double
    var baseSpeed: Double = 1
    var curveEnabled = false
    var points: [SpeedPoint] = [SpeedPoint(t: 0, speed: 1), SpeedPoint(t: 1, speed: 1)]

    var sourceDuration: Double { max(0.05, trimEnd - trimStart) }
    var sortedPoints: [SpeedPoint] { points.sorted { $0.t < $1.t } }
}

struct PickedMovieV5: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let dst = FileManager.default.temporaryDirectory.appendingPathComponent("VeloCutV5-\(UUID().uuidString).\(ext)")
            try? FileManager.default.removeItem(at: dst)
            try FileManager.default.copyItem(at: received.file, to: dst)
            return PickedMovieV5(url: dst)
        }
    }
}

@MainActor
final class V5Model: ObservableObject {
    @Published var clip: V5Clip?
    @Published var player = AVPlayer()
    @Published var playhead = 0.0
    @Published var isPlaying = false
    @Published var zoom: CGFloat = 1.6
    @Published var pan: CGFloat = 0
    @Published var selectedPointID: UUID?
    @Published var showCurveEditor = false
    @Published var isFileImporting = false
    @Published var isExporting = false
    @Published var exportedURL: URL?
    @Published var error: String?

    private var observer: Any?

    init() {
        player.automaticallyWaitsToMinimizeStalling = false
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.033, preferredTimescale: 600), queue: .main) { [weak self] time in
            guard let self else { return }
            Task { @MainActor in
                guard self.player.rate != 0 else { return }
                self.playhead = CMTimeGetSeconds(time)
                self.isPlaying = true
                if let clip = self.clip, self.playhead >= clip.trimEnd - 0.02 {
                    self.player.pause()
                    self.isPlaying = false
                    self.seek(clip.trimStart)
                }
            }
        }
    }

    func importVideo(_ url: URL) {
        Task {
            do {
                let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
                let d = max(0.1, CMTimeGetSeconds(try await asset.load(.duration)))
                clip = V5Clip(url: url, name: url.deletingPathExtension().lastPathComponent, duration: d, trimStart: 0, trimEnd: d)
                player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
                seek(0)
            } catch { self.error = "Не удалось открыть видео: \(error.localizedDescription)" }
        }
    }

    func seek(_ seconds: Double) {
        guard let clip else { return }
        let safe = min(max(seconds, clip.trimStart), clip.trimEnd)
        playhead = safe
        player.seek(to: CMTime(seconds: safe, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func playPause() {
        guard let clip else { return }
        if player.rate != 0 { player.pause(); isPlaying = false; return }
        if playhead >= clip.trimEnd - 0.03 { seek(clip.trimStart) }
        player.play(); isPlaying = true
    }

    func setTrimStart(_ value: Double) {
        guard var c = clip else { return }
        c.trimStart = min(max(0, value), c.trimEnd - 0.05)
        clip = c
        if playhead < c.trimStart { seek(c.trimStart) }
    }

    func setTrimEnd(_ value: Double) {
        guard var c = clip else { return }
        c.trimEnd = max(min(c.duration, value), c.trimStart + 0.05)
        clip = c
        if playhead > c.trimEnd { seek(c.trimEnd) }
    }

    func setCurveEnabled(_ on: Bool) {
        guard var c = clip else { return }
        c.curveEnabled = on
        if c.points.count < 2 { c.points = [SpeedPoint(t: 0, speed: 1), SpeedPoint(t: 1, speed: 1)] }
        clip = c
    }

    func setBaseSpeed(_ value: Double) {
        guard var c = clip else { return }
        c.baseSpeed = min(max(value, 0.05), 20)
        clip = c
    }

    func normalizedPlayhead() -> Double {
        guard let c = clip else { return 0 }
        return min(max((playhead - c.trimStart) / max(c.sourceDuration, 0.0001), 0), 1)
    }

    func speedAt(_ t: Double) -> Double {
        guard let c = clip else { return 1 }
        let p = c.sortedPoints
        guard p.count >= 2 else { return 1 }
        let x = min(max(t, 0), 1)
        for i in 0..<(p.count - 1) {
            let a = p[i], b = p[i + 1]
            if x >= a.t && x <= b.t {
                let u = (x - a.t) / max(0.0001, b.t - a.t)
                return max(0.05, a.speed + (b.speed - a.speed) * u)
            }
        }
        return p.last?.speed ?? 1
    }

    func addPoint(at t: Double? = nil) {
        guard var c = clip else { return }
        let x = min(max(t ?? normalizedPlayhead(), 0.001), 0.999)
        let point = SpeedPoint(t: x, speed: speedAt(x))
        c.points.append(point)
        c.points.sort { $0.t < $1.t }
        c.curveEnabled = true
        selectedPointID = point.id
        clip = c
    }

    func movePoint(id: UUID, t: Double, speed: Double) {
        guard var c = clip, let i = c.points.firstIndex(where: { $0.id == id }) else { return }
        let endpoint = c.points[i].t <= 0.0001 || c.points[i].t >= 0.9999
        if !endpoint { c.points[i].t = min(max(t, 0.001), 0.999) }
        c.points[i].speed = min(max(speed, 0.05), 20)
        c.points.sort { $0.t < $1.t }
        c.curveEnabled = true
        clip = c
    }

    func deleteSelectedPoint() {
        guard var c = clip, let id = selectedPointID, let p = c.points.first(where: { $0.id == id }) else { return }
        guard p.t > 0.0001 && p.t < 0.9999 else { return }
        c.points.removeAll { $0.id == id }
        clip = c
        selectedPointID = nil
    }

    func applyPreset(_ preset: Int) {
        guard var c = clip else { return }
        switch preset {
        case 0: c.points = [SpeedPoint(t:0,speed:1),SpeedPoint(t:0.28,speed:0.25),SpeedPoint(t:0.52,speed:5),SpeedPoint(t:0.74,speed:0.35),SpeedPoint(t:1,speed:1)]
        case 1: c.points = [SpeedPoint(t:0,speed:1),SpeedPoint(t:0.35,speed:0.15),SpeedPoint(t:0.5,speed:8),SpeedPoint(t:0.66,speed:0.3),SpeedPoint(t:1,speed:1)]
        case 2: c.points = [SpeedPoint(t:0,speed:1),SpeedPoint(t:0.42,speed:0.2),SpeedPoint(t:0.55,speed:10),SpeedPoint(t:0.7,speed:1),SpeedPoint(t:1,speed:1)]
        default: c.points = [SpeedPoint(t:0,speed:1),SpeedPoint(t:0.3,speed:0.5),SpeedPoint(t:0.5,speed:3),SpeedPoint(t:0.7,speed:0.5),SpeedPoint(t:1,speed:1)]
        }
        c.curveEnabled = true
        clip = c
    }

    func export() {
        guard let c = clip else { return }
        isExporting = true; exportedURL = nil
        Task {
            do { exportedURL = try await exportClip(c) }
            catch { self.error = "Ошибка экспорта: \(error.localizedDescription)" }
            isExporting = false
        }
    }

    private func exportClip(_ c: V5Clip) async throws -> URL {
        let asset = AVURLAsset(url: c.url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        guard let sourceVideo = try await asset.loadTracks(withMediaType: .video).first else { throw NSError(domain:"VeloCut", code:1) }
        let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first
        let composition = AVMutableComposition()
        guard let video = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw NSError(domain:"VeloCut", code:2) }
        video.preferredTransform = try await sourceVideo.load(.preferredTransform)
        let audio = sourceAudio == nil ? nil : composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        let segments = c.curveEnabled ? 80 : 1
        let ds = c.sourceDuration / Double(segments)
        var cursor = CMTime.zero
        for i in 0..<segments {
            let n = (Double(i) + 0.5) / Double(segments)
            let factor = c.curveEnabled ? speedAtCurve(c.sortedPoints, n) : 1
            let speed = min(max(c.baseSpeed * factor, 0.05), 20)
            let range = CMTimeRange(start: CMTime(seconds:c.trimStart + Double(i)*ds, preferredTimescale:6000), duration: CMTime(seconds:ds, preferredTimescale:6000))
            try video.insertTimeRange(range, of: sourceVideo, at: cursor)
            if let sourceAudio, let audio { try? audio.insertTimeRange(range, of: sourceAudio, at: cursor) }
            let inserted = CMTimeRange(start: cursor, duration: CMTime(seconds:ds, preferredTimescale:6000))
            let out = CMTime(seconds:ds/speed, preferredTimescale:6000)
            video.scaleTimeRange(inserted, toDuration: out)
            audio?.scaleTimeRange(inserted, toDuration: out)
            cursor = cursor + out
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("VeloCut-v0.5-\(UUID().uuidString).mp4")
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else { throw NSError(domain:"VeloCut",code:3) }
        session.outputURL = url; session.outputFileType = .mp4; session.shouldOptimizeForNetworkUse = true
        await withCheckedContinuation { continuation in session.exportAsynchronously { continuation.resume() } }
        guard session.status == .completed else { throw session.error ?? NSError(domain:"VeloCut",code:4) }
        return url
    }

    nonisolated private func speedAtCurve(_ points: [SpeedPoint], _ t: Double) -> Double {
        let p = points.sorted { $0.t < $1.t }
        guard p.count >= 2 else { return 1 }
        for i in 0..<(p.count - 1) {
            let a = p[i], b = p[i + 1]
            if t >= a.t && t <= b.t {
                let u = (t-a.t)/max(0.0001,b.t-a.t)
                return max(0.05,a.speed+(b.speed-a.speed)*u)
            }
        }
        return p.last?.speed ?? 1
    }
}

struct PlayerBoxV5: UIViewControllerRepresentable {
    let player: AVPlayer
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let c = AVPlayerViewController(); c.player = player; c.showsPlaybackControls = false; c.videoGravity = .resizeAspect; return c
    }
    func updateUIViewController(_ ui: AVPlayerViewController, context: Context) { if ui.player !== player { ui.player = player } }
}

struct FilePickerV5: UIViewControllerRepresentable {
    let onPick: (URL)->Void
    func makeCoordinator() -> Coordinator { Coordinator(onPick) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let p = UIDocumentPickerViewController(forOpeningContentTypes:[.movie,.mpeg4Movie,.quickTimeMovie],asCopy:true); p.delegate = context.coordinator; return p
    }
    func updateUIViewController(_ ui: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick:(URL)->Void; init(_ onPick:@escaping(URL)->Void){self.onPick=onPick}
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls:[URL]){if let u=urls.first{onPick(u)}}
    }
}

struct ShareV5: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context:Context)->UIActivityViewController{UIActivityViewController(activityItems:[url],applicationActivities:nil)}
    func updateUIViewController(_ ui:UIActivityViewController,context:Context){}
}

struct CurveGraphV5: View {
    let points:[SpeedPoint]
    @Binding var selected:UUID?
    let onMove:(UUID,Double,Double)->Void
    let onAdd:(Double)->Void

    var body: some View {
        GeometryReader { g in
            ZStack {
                RoundedRectangle(cornerRadius:10).fill(Color.white.opacity(0.06))
                Path { path in
                    let p=points.sorted{$0.t<$1.t}; guard let first=p.first else{return}
                    path.move(to:CGPoint(x:first.t*g.size.width,y:y(first.speed,g.size.height)))
                    for point in p.dropFirst(){path.addLine(to:CGPoint(x:point.t*g.size.width,y:y(point.speed,g.size.height)))}
                }.stroke(Color.yellow,lineWidth:2)
                ForEach(points){point in
                    Circle().fill(selected==point.id ? Color.orange:Color.white).frame(width:selected==point.id ? 16:12,height:selected==point.id ? 16:12)
                        .position(x:point.t*g.size.width,y:y(point.speed,g.size.height))
                        .highPriorityGesture(DragGesture(minimumDistance:0).onChanged{v in
                            selected=point.id
                            let t=min(max(Double(v.location.x/max(g.size.width,1)),0),1)
                            let s=speed(v.location.y,g.size.height)
                            onMove(point.id,t,s)
                        })
                        .onTapGesture{selected=point.id}
                }
            }.contentShape(Rectangle()).gesture(SpatialTapGesture().onEnded{v in onAdd(min(max(Double(v.location.x/max(g.size.width,1)),0),1))})
        }
    }
    private func y(_ speed:Double,_ h:CGFloat)->CGFloat{let n=(min(max(speed,0.05),20)-0.05)/(20-0.05);return h-CGFloat(n)*(h-14)-7}
    private func speed(_ y:CGFloat,_ h:CGFloat)->Double{let n=1-min(max((y-7)/max(h-14,1),0),1);return 0.05+Double(n)*(20-0.05)}
}

struct ContentViewV5: View {
    @StateObject var model = V5Model()
    @State var photoItem: PhotosPickerItem?
    @State var showShare=false
    @GestureState var pinch:CGFloat=1
    @State var panAnchor:CGFloat?
    @State var leftAnchor:Double?
    @State var rightAnchor:Double?

    var body: some View {
        ZStack { Color.black.ignoresSafeArea(); VStack(spacing:0){top;preview;playback;timeline;if model.showCurveEditor{curveEditor};speedBar} }
        .sheet(isPresented:$model.isFileImporting){FilePickerV5{u in model.isFileImporting=false;model.importVideo(u)}}
        .sheet(isPresented:$showShare){if let u=model.exportedURL{ShareV5(url:u)}}
        .onChange(of:model.exportedURL){_,u in if u != nil{showShare=true}}
        .onChange(of:photoItem){_,item in guard let item else{return};Task{do{if let m=try await item.loadTransferable(type:PickedMovieV5.self){await MainActor.run{model.importVideo(m.url);photoItem=nil}}}catch{await MainActor.run{model.error="Фото: \(error.localizedDescription)"}}}}
        .alert("VeloCut",isPresented:Binding(get:{model.error != nil},set:{if !$0{model.error=nil}})){Button("OK",role:.cancel){}}message:{Text(model.error ?? "")}
    }

    var top: some View { HStack{VStack(alignment:.leading){Text("VeloCut").font(.headline);Text("v0.5 • Curve Timeline").font(.caption2).foregroundStyle(.secondary)};Spacer();PhotosPicker(selection:$photoItem,matching:.videos){Image(systemName:"photo.on.rectangle")}.buttonStyle(.bordered);Button{model.isFileImporting=true}label:{Image(systemName:"folder")}.buttonStyle(.bordered);Button{model.export()}label:{model.isExporting ? AnyView(ProgressView()):AnyView(Text("Экспорт").font(.caption.weight(.bold)))}.buttonStyle(.borderedProminent).disabled(model.clip==nil||model.isExporting)}.padding(12).background(.ultraThinMaterial) }

    var preview: some View { ZStack{RoundedRectangle(cornerRadius:18).fill(Color.black);if model.clip != nil{PlayerBoxV5(player:model.player)}else{VStack{Image(systemName:"film.stack").font(.largeTitle);Text("Добавьте видео");Text("Фото или Файлы").font(.caption).foregroundStyle(.secondary)}}}.clipShape(RoundedRectangle(cornerRadius:18)).padding(.horizontal,10).padding(.top,8).frame(maxHeight:.infinity) }

    var playback: some View { HStack{Text(format(model.playhead)).font(.caption.monospacedDigit()).foregroundStyle(.secondary);Spacer();Button{model.seek(model.playhead-1)}label:{Image(systemName:"backward.frame")};Button{model.playPause()}label:{Image(systemName:model.isPlaying ? "pause.fill":"play.fill").frame(width:44,height:34).background(.thinMaterial,in:Capsule())};Button{model.seek(model.playhead+1)}label:{Image(systemName:"forward.frame")};Spacer();Button{model.showCurveEditor.toggle()}label:{Image(systemName:"point.topleft.down.to.point.bottomright.curvepath")}.disabled(!(model.clip?.curveEnabled ?? false))}.padding(.horizontal,14).padding(.vertical,7) }

    var timeline: some View {
        VStack(spacing:6){HStack{Text("Таймлайн").font(.caption.weight(.semibold));Spacer();Text("Pinch zoom • drag pan • края = trim").font(.caption2).foregroundStyle(.secondary)}.padding(.horizontal,14)
            GeometryReader{g in
                let visible=g.size.width
                let width=max(visible,visible*model.zoom*pinch)
                ZStack(alignment:.topLeading){RoundedRectangle(cornerRadius:12).fill(Color.white.opacity(0.05))
                    if let c=model.clip{
                        let start=model.pan+CGFloat(c.trimStart/max(c.duration,0.001))*width
                        let w=max(34,CGFloat(c.sourceDuration/max(c.duration,0.001))*width)
                        RoundedRectangle(cornerRadius:9).fill(Color.accentColor.opacity(0.3)).frame(width:w,height:46).offset(x:start,y:8)
                        Rectangle().fill(.white).frame(width:14,height:46).offset(x:start-7,y:8).highPriorityGesture(trimGesture(true,width))
                        Rectangle().fill(.white).frame(width:14,height:46).offset(x:start+w-7,y:8).highPriorityGesture(trimGesture(false,width))
                        if c.curveEnabled{CurveGraphV5(points:c.sortedPoints,selected:$model.selectedPointID,onMove:{id,t,s in model.movePoint(id:id,t:t,speed:s)},onAdd:{t in model.addPoint(at:t)}).frame(width:w,height:60).offset(x:start,y:58)}
                    }
                    Rectangle().fill(Color.red).frame(width:2).offset(x:visible/2,y:2)
                }.clipShape(RoundedRectangle(cornerRadius:12)).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance:0).onChanged{v in if panAnchor==nil{panAnchor=model.pan};model.pan=(panAnchor ?? model.pan)+v.translation.width;clampPan(visible,width);updateHead(visible,width)}.onEnded{_ in panAnchor=nil;clampPan(visible,width);updateHead(visible,width)})
                    .simultaneousGesture(MagnificationGesture().updating($pinch){v,s,_ in s=v}.onEnded{v in model.zoom=min(max(model.zoom*v,1),14);clampPan(visible,max(visible,visible*model.zoom))})
            }.frame(height:(model.clip?.curveEnabled ?? false) ? 124:66)
        }.padding(.vertical,8).background(.regularMaterial).clipShape(RoundedRectangle(cornerRadius:20)).padding(.horizontal,8)
    }

    var speedBar: some View { VStack(spacing:8){if let c=model.clip{HStack{Text("Скорость").font(.caption.weight(.semibold));Slider(value:Binding(get:{c.baseSpeed},set:{model.setBaseSpeed($0)}),in:0.05...20);Text("\(c.baseSpeed,specifier:"%.2f")×").font(.caption.monospacedDigit())};Toggle("Кривая скорости",isOn:Binding(get:{c.curveEnabled},set:{model.setCurveEnabled($0)})).font(.caption);if c.curveEnabled{ScrollView(.horizontal,showsIndicators:false){HStack{Button("Velocity"){model.applyPreset(0)};Button("TikTok Ramp"){model.applyPreset(1)};Button("Flash Ramp"){model.applyPreset(2)};Button("AMV Smooth"){model.applyPreset(3)};Button{model.addPoint()}label:{Label("Точка",systemImage:"plus")};Button(role:.destructive){model.deleteSelectedPoint()}label:{Image(systemName:"trash")}.disabled(model.selectedPointID==nil)}.buttonStyle(.bordered)}}}else{Text("Импортируйте видео").font(.caption).foregroundStyle(.secondary)}}.padding(10).background(.ultraThinMaterial) }

    var curveEditor: some View { Group{if let c=model.clip{VStack(spacing:8){HStack{Text("Редактор кривой").font(.headline);Spacer();Button{model.addPoint()}label:{Label("Точка",systemImage:"plus.circle")};Button{model.showCurveEditor=false}label:{Image(systemName:"xmark.circle.fill")}};Slider(value:Binding(get:{model.playhead},set:{model.seek($0)}),in:c.trimStart...c.trimEnd);HStack{Text(format(c.trimStart));Spacer();Text(format(model.playhead));Spacer();Text(format(c.trimEnd))}.font(.caption2.monospacedDigit()).foregroundStyle(.secondary);CurveGraphV5(points:c.sortedPoints,selected:$model.selectedPointID,onMove:{id,t,s in model.movePoint(id:id,t:t,speed:s)},onAdd:{t in model.seek(c.trimStart+t*c.sourceDuration);model.addPoint(at:t)}).frame(height:180)}}.padding(12).background(.regularMaterial) } }

    func trimGesture(_ leading:Bool,_ width:CGFloat)->some Gesture{DragGesture().onChanged{v in guard let c=model.clip else{return};let ds=Double(v.translation.width/max(width,1))*c.duration;if leading{if leftAnchor==nil{leftAnchor=c.trimStart};model.setTrimStart((leftAnchor ?? c.trimStart)+ds)}else{if rightAnchor==nil{rightAnchor=c.trimEnd};model.setTrimEnd((rightAnchor ?? c.trimEnd)+ds)}}.onEnded{_ in leftAnchor=nil;rightAnchor=nil}}
    func clampPan(_ visible:CGFloat,_ width:CGFloat){model.pan=min(max(model.pan,visible-width),0)}
    func updateHead(_ visible:CGFloat,_ width:CGFloat){guard let c=model.clip else{return};let x=min(max(visible/2-model.pan,0),width);model.seek(Double(x/max(width,1))*c.duration)}
    func format(_ s:Double)->String{let x=max(0,s);return String(format:"%d:%05.2f",Int(x)/60,x-Double(Int(x)/60*60))}
}

@main
struct VeloCutV5App: App { var body: some Scene { WindowGroup { ContentViewV5().preferredColorScheme(.dark) } } }
