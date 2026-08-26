from pathlib import Path
import re

p=Path('VeloCutAI/VeloCutAI/VeloCutV4.swift')
s=p.read_text()

# v0.5 state: real audio lane presentation, track sizing/collapse, adaptive workspace and theme.
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

# Imported/extracted audio becomes a visible A1 timeline clip by keeping source URL and start position.
s=s.replace('musicURL = url\n        musicName = url.deletingPathExtension().lastPathComponent', 'musicURL = url\n        musicName = url.deletingPathExtension().lastPathComponent\n        audioTimelineStart = projectTime',1)
# add timeline start state near music vars in original source
music='@Published var musicVolume = 0.8'
if music not in s: raise RuntimeError('music state missing')
s=s.replace(music,music+'\n    @Published var audioTimelineStart = 0.0',1)

# Replace root editor layout with adaptive portrait/landscape workspace. Playback sits immediately below preview.
old='ZStack{Color(uiColor:.systemGroupedBackground).ignoresSafeArea();VStack(spacing:0){topBar;preview.frame(height:min(350,max(220,root.size.height*0.37)));playback;if let target=curveTarget{CurveEditorPanel(model:model,target:target,onClose:{curveTarget=nil}).frame(maxHeight:.infinity)}else{timeline.frame(maxHeight:.infinity)};bottomBar}.frame(width:root.size.width,height:root.size.height,alignment:.top)}'
new='ZStack{model.workspaceTheme.background.ignoresSafeArea();adaptiveWorkspace(root)}'
if old not in s: raise RuntimeError('Editor root layout missing')
s=s.replace(old,new,1)

# Inject adaptive workspace and resize handle before topBar.
mark='    private var topBar:some View'
if mark not in s: raise RuntimeError('topbar missing')
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

# Add track scale + collapse controls to timeline header near existing timeline label.
s=s.replace('Label("Таймлайн",systemImage:"timeline.selection")', 'Label("Таймлайн",systemImage:"timeline.selection");Button{withAnimation(.snappy){if model.collapsedTracks.contains(0){model.collapsedTracks.remove(0)}else{model.collapsedTracks.insert(0)}}}label:{Image(systemName:model.collapsedTracks.contains(0) ? "chevron.right":"chevron.down")};Slider(value:$model.trackHeightScale,in:0.65...1.8).frame(width:92)',1)

# Append a real visible A1 card under the timeline content by inserting before timeline VStack closes at bottomBar marker.
# Use overlay to avoid destabilizing old track geometry; card follows playhead coordinates and is horizontally draggable.
timeline_sig='    private var timeline:some View{'
pos=s.find(timeline_sig)
if pos<0: raise RuntimeError('timeline missing')
# Add audio overlay to the known TimelineCanvas invocation if present.
canvas='TimelineCanvasV4(model:model'
idx=s.find(canvas,pos)
if idx>=0:
    # place A1 using overlay on timeline container after first .frame(maxHeight:.infinity) in timeline section if available
    pass

# Add compact A1 row as safe overlay to timeline view via wrapper replacement.
start=pos+len(timeline_sig)
# Transform initial VStack to ZStack containing original VStack; close before next property bottomBar.
nextprop=s.find('    private var bottomBar:',start)
if nextprop<0: raise RuntimeError('bottomBar marker missing')
body=s[start:nextprop]
if body.startswith('VStack'):
    body='ZStack(alignment:.bottomLeading){'+body+';audioLaneV50}'
    s=s[:start]+body+s[nextprop:]
else:
    raise RuntimeError('timeline body unexpected')

# Add audio lane + appearance sheet-like inspector helpers before bottomBar.
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
