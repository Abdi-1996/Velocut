from pathlib import Path
import re

p=Path('VeloCutAI/VeloCutAI/VeloCutV4.swift')
s=p.read_text()

anchor='@Published var snapToBeat = false'
if anchor not in s: raise RuntimeError('v049 state missing')
s=s.replace(anchor,anchor+'''\n    @Published var trackHeightScale = 1.0
    @Published var collapsedTracks: Set<Int> = []
    @Published var previewSplit = 0.38
    @Published var workspaceTheme: VeloCutTheme = .iosGlass
    @Published var cacheLimitGB = 5.0
    @Published var audioFadeIn = 0.0
    @Published var audioFadeOut = 0.0
    @Published var audioEffect: VeloCutAudioEffect = .none
    @Published var audioPitch = 0.0
    @Published var audioSpeed = 1.0''',1)

s=s.replace('musicURL = url\n        musicName = url.deletingPathExtension().lastPathComponent', 'musicURL = url\n        musicName = url.deletingPathExtension().lastPathComponent\n        audioTimelineStart = projectTime',1)
music='@Published var musicVolume = 0.8'
if music not in s: raise RuntimeError('music state missing')
s=s.replace(music,music+'\n    @Published var audioTimelineStart = 0.0',1)

# Replace only the root GeometryReader content, regardless of the exact preview sizing from earlier patches.
root_pattern=re.compile(r'(    var body:some View\{\s*\n\s*GeometryReader\{root in\s*\n)\s*ZStack\{.*?\}(\s*\n\s*\}\s*\n\s*\.sheet\(isPresented:\$model\.isFileImporting\))',re.S)
replacement=r'''\1            ZStack{model.workspaceTheme.background.ignoresSafeArea();adaptiveWorkspace(root)}\2'''
s,count=root_pattern.subn(replacement,s,count=1)
if count != 1: raise RuntimeError('Editor root GeometryReader not found')

mark='    private var topBar:some View'
if mark not in s: raise RuntimeError('topbar declaration missing')
insert='''    @ViewBuilder private func adaptiveWorkspace(_ root: GeometryProxy)->some View {
        let landscape = root.size.width > root.size.height
        if landscape {
            VStack(spacing:0){
                HStack(spacing:0){
                    VStack(spacing:0){preview;playback}.frame(width:root.size.width*0.46)
                    Divider()
                    VStack(spacing:0){workspaceHandle;if let target=curveTarget{CurveEditorPanel(model:model,target:target,onClose:{curveTarget=nil})}else{timeline}}.frame(maxWidth:.infinity)
                }
                bottomBar
            }
        } else {
            VStack(spacing:0){
                preview.frame(height:max(150,root.size.height*model.previewSplit));playback;workspaceHandle
                if let target=curveTarget{CurveEditorPanel(model:model,target:target,onClose:{curveTarget=nil}).frame(maxHeight:.infinity)}else{timeline.frame(maxHeight:.infinity)}
                bottomBar
            }
        }
    }

    private var workspaceHandle: some View {
        Capsule().fill(Color.secondary.opacity(0.45)).frame(width:46,height:5).frame(height:18).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance:0).onChanged{v in
                let delta=Double(v.translation.height/700); model.previewSplit=min(0.62,max(0.22,model.previewSplit+delta))
            }.onEnded{_ in model.haptic(.selection)})
    }

'''
s=s.replace(mark,insert+mark,1)

header='Label("Таймлайн",systemImage:"timeline.selection")'
if header not in s: raise RuntimeError('timeline header missing')
s=s.replace(header, 'Label("Таймлайн",systemImage:"timeline.selection");Button{withAnimation(.snappy){if model.collapsedTracks.contains(0){model.collapsedTracks.remove(0)}else{model.collapsedTracks.insert(0)}}}label:{Image(systemName:model.collapsedTracks.contains(0) ? "chevron.right":"chevron.down")};Slider(value:$model.trackHeightScale,in:0.65...1.8).frame(width:92)',1)

timeline_sig='    private var timeline:some View{'
pos=s.find(timeline_sig)
if pos<0: raise RuntimeError('timeline missing')
start=pos+len(timeline_sig)
nextprop=s.find('    private var bottomBar:',start)
if nextprop<0: raise RuntimeError('bottomBar marker missing')
body=s[start:nextprop]
if not body.startswith('VStack'): raise RuntimeError('timeline body unexpected')
body='ZStack(alignment:.bottomLeading){'+body+';audioLaneV50}'
s=s[:start]+body+s[nextprop:]

mark='    private var bottomBar:'
extra='''    private var audioLaneV50: some View {
        Group{
            if let name=model.musicName, model.musicURL != nil {
                HStack(spacing:8){
                    Button{withAnimation(.snappy){if model.collapsedTracks.contains(10){model.collapsedTracks.remove(10)}else{model.collapsedTracks.insert(10)}}}label:{Image(systemName:model.collapsedTracks.contains(10) ? "chevron.right":"chevron.down")}
                    Text("A1").font(.caption.bold())
                    Image(systemName:"waveform")
                    Text(name).font(.caption).lineLimit(1)
                    Spacer();Text("Audio").font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.horizontal,10)
                .frame(height:model.collapsedTracks.contains(10) ? 28 : CGFloat(48*model.trackHeightScale))
                .background(model.workspaceTheme.panel.opacity(0.92),in:RoundedRectangle(cornerRadius:9))
                .padding(.horizontal,10).padding(.bottom,5)
                .gesture(DragGesture().onEnded{v in model.audioTimelineStart=max(0,model.audioTimelineStart+Double(v.translation.width/80));model.schedulePreview()})
            }
        }
    }

'''
s=s.replace(mark,extra+mark,1)

p.write_text(s)
print('Applied VeloCut v0.5.0 adaptive workspace and audio lane')
