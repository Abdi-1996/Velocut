import SwiftUI
import AVFoundation

enum VeloCutTheme: String, CaseIterable, Identifiable {
    case iosGlass = "iOS Glass", capcut = "Cut Dark", davinci = "Resolve", afterEffects = "Motion Pro", veloDark = "Velo Dark", veloLight = "Velo Light"
    var id: String { rawValue }
    var background: Color {
        switch self {
        case .iosGlass: return Color(uiColor: .systemGroupedBackground)
        case .capcut: return Color(white: 0.055)
        case .davinci: return Color(white: 0.105)
        case .afterEffects: return Color(red: 0.10, green: 0.10, blue: 0.14)
        case .veloDark: return Color(white: 0.075)
        case .veloLight: return Color(white: 0.95)
        }
    }
    var panel: Color {
        switch self {
        case .iosGlass: return Color(uiColor: .secondarySystemGroupedBackground)
        case .capcut: return Color(white: 0.11)
        case .davinci: return Color(white: 0.16)
        case .afterEffects: return Color(red: 0.16, green: 0.16, blue: 0.21)
        case .veloDark: return Color(white: 0.13)
        case .veloLight: return .white
        }
    }
}

enum VeloCutAudioEffect: String, CaseIterable, Identifiable {
    case none="Clean", bass="Bass Boost", muffled="Muffled", phone="Phone", hall="Hall", deep="Deep", nightcore="Nightcore", slowReverb="Slow + Reverb", echo="Echo", distortion="Distortion"
    var id:String{rawValue}
}

enum VeloCutCache {
    static var root: URL {
        let fm=FileManager.default
        let base=fm.urls(for:.cachesDirectory,in:.userDomainMask).first!.appendingPathComponent("VeloCut",isDirectory:true)
        try? fm.createDirectory(at:base,withIntermediateDirectories:true)
        for n in ["Thumbnails","Waveforms","Preview","RIFE"] { try? fm.createDirectory(at:base.appendingPathComponent(n),withIntermediateDirectories:true) }
        return base
    }
    static func clear(){try? FileManager.default.removeItem(at:root);_ = root}
    static func sizeBytes()->Int64{
        let fm=FileManager.default; guard let e=fm.enumerator(at:root,includingPropertiesForKeys:[.fileSizeKey]) else{return 0}
        var n:Int64=0
        for case let u as URL in e { n += Int64((try? u.resourceValues(forKeys:[.fileSizeKey]).fileSize) ?? 0) }
        return n
    }
}

struct VeloCutThemeSettingsV50: View {
    @ObservedObject var model: EditorViewModel
    @State private var cacheSize:Int64=0
    var body: some View {
        Form {
            Section("Theme") {
                Picker("Interface",selection:$model.workspaceTheme){ForEach(VeloCutTheme.allCases){Text($0.rawValue).tag($0)}}
                ColorPicker("Accent",selection:.constant(.accentColor),supportsOpacity:false)
            }
            Section("Timeline") {
                HStack{Text("Track size");Slider(value:$model.trackHeightScale,in:0.65...1.8)}
                Button("Collapse all"){model.collapsedTracks=[0,1,2,10,11,12]}
                Button("Expand all"){model.collapsedTracks=[]}
            }
            Section("Cache") {
                Slider(value:$model.cacheLimitGB,in:2...20,step:1)
                Text(String(format:"Limit %.0f GB • used %.1f MB",model.cacheLimitGB,Double(cacheSize)/1048576)).font(.caption)
                Button("Clear cache",role:.destructive){VeloCutCache.clear();cacheSize=0}
            }
        }.onAppear{cacheSize=VeloCutCache.sizeBytes()}
    }
}
