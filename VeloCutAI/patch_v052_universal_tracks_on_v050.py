from pathlib import Path
import re

p=Path('VeloCutAI/VeloCutAI/VeloCutV4.swift')
s=p.read_text()

# This patch is intentionally lane-only. It does NOT replace timelineCanvas,
# scrolling, zoom, playhead or timeline gestures from v0.5.

# Model state: target lane for imports + lane used by the existing audio source.
anchor='@Published var audioTimelineStart = 0.0'
if anchor not in s: raise RuntimeError('v0.5 audio state missing')
s=s.replace(anchor,anchor+'\n    @Published var importTargetTrack = 0\n    @Published var audioTrack = 0',1)

# Existing video imports now land on the lane selected by that lane's + button.
s=s.replace('newClips.append(EditorClip(url: url, name: url.deletingPathExtension().lastPathComponent, duration: d, trimStart: 0, trimEnd: d))',
            'newClips.append(EditorClip(url: url, name: url.deletingPathExtension().lastPathComponent, duration: d, trimStart: 0, trimEnd: d, track: importTargetTrack))',1)

# Track-only view state.
state_pat=re.compile(r'(@State\s+private\s+var\s+multiSelectedClips\s*:\s*Set<UUID>\s*=\s*\[\])')
s,n=state_pat.subn(r'''\1
    @State private var trackNamesV52:[Int:String]=[0:"V1",1:"V2",2:"V3"]
    @State private var trackColorsV52:[Int:Color]=[0:.blue,1:.purple,2:.pink]
    @State private var bypassedTracksV52:Set<Int>=[]
    @State private var audioExtractLaneV52=0
    @State private var extractAudioItemV52:PhotosPickerItem?''',s,count=1)
if n!=1: raise RuntimeError('editor state anchor missing')

# Remove only the separate v0.5 A1 visual row. Timeline/navigation remain untouched.
s=s.replace(';audioLaneV50','',2)
s=s.replace('timeline;audioLaneV50','timeline',2)
s=s.replace('timeline.frame(maxHeight:.infinity);audioLaneV50','timeline.frame(maxHeight:.infinity)',2)

# Existing v0.5 lane title becomes a compact square; preserve its expand/collapse action.
s=s.replace('''HStack(spacing:3){
                        Text("V\\(lane+1)")
                        Image(systemName:expandedLanes.contains(lane) ? "chevron.up":"chevron.down")
                    }
                    .font(.system(size:9,weight:.bold))
                    .padding(4)
                    .background(.thinMaterial,in:Capsule())''', '''VStack(spacing:1){
                        Text(trackNamesV52[lane] ?? "V\\(lane+1)").lineLimit(1)
                        Image(systemName:expandedLanes.contains(lane) ? "chevron.up":"chevron.down").font(.system(size:6))
                    }
                    .font(.system(size:8,weight:.bold))
                    .frame(width:34,height:30)
                    .background(trackColorsV52[lane] ?? Color.secondary,in:RoundedRectangle(cornerRadius:7))
                    .foregroundStyle(.white)''',1)

# Reposition header a little and attach rename/color context menu.
header_pos='.position(x:24,y:top+12)'
header_new='''.position(x:20,y:top+17)
                .contextMenu{
                    Button("Rename"){trackNamesV52[lane]="Track \\(lane+1)"}
                    Menu("Color"){
                        Button("Blue"){trackColorsV52[lane] = .blue}
                        Button("Purple"){trackColorsV52[lane] = .purple}
                        Button("Pink"){trackColorsV52[lane] = .pink}
                        Button("Green"){trackColorsV52[lane] = .green}
                        Button("Orange"){trackColorsV52[lane] = .orange}
                    }
                }'''
if header_pos not in s: raise RuntimeError('lane header position missing')
s=s.replace(header_pos,header_new,1)

# Insert Bypass and a permanent + into EACH existing lane.
handle='''LaneHeightHandleV4(height:h){laneHeights[lane]=$0}
                    .position(x:geo.size.width-22,y:top+h-7)'''
controls='''Button{
                    if bypassedTracksV52.contains(lane){bypassedTracksV52.remove(lane)}else{bypassedTracksV52.insert(lane)}
                    model.haptic(.selection)
                }label:{
                    Text("B").font(.system(size:9,weight:.bold)).frame(width:24,height:26)
                        .background(bypassedTracksV52.contains(lane) ? Color.orange.opacity(0.45):Color.secondary.opacity(0.14),in:RoundedRectangle(cornerRadius:6))
                }.buttonStyle(.plain).position(x:54,y:top+17)

                Menu{
                    PhotosPicker(selection:Binding(get:{[PhotosPickerItem]()},set:{items in model.importTargetTrack=lane;photoItems=items}),maxSelectionCount:20,matching:.videos){
                        Label("Video",systemImage:"film")
                    }
                    PhotosPicker(selection:Binding(get:{extractAudioItemV52},set:{item in audioExtractLaneV52=lane;extractAudioItemV52=item}),matching:.videos){
                        Label("Audio from video",systemImage:"video.badge.waveform")
                    }
                    Button{model.importTargetTrack=lane;model.isAudioImporting=true}label:{Label("Audio file",systemImage:"waveform.badge.plus")}
                    Button{model.haptic(.selection)}label:{Label("Photo",systemImage:"photo")}
                    Button{model.haptic(.selection)}label:{Label("FX",systemImage:"sparkles")}
                    Button{model.haptic(.selection)}label:{Label("Text",systemImage:"textformat")}
                    Button{model.haptic(.selection)}label:{Label("Transition",systemImage:"arrow.left.and.right")}
                    Button{model.addGlobalSpeedFX()}label:{Label("Speed FX",systemImage:"waveform.path.ecg")}
                }label:{
                    Image(systemName:"plus.circle.fill").font(.system(size:18)).frame(width:28,height:28)
                }.buttonStyle(.plain).position(x:geo.size.width-17,y:top+17)

                LaneHeightHandleV4(height:h){laneHeights[lane]=$0}
                    .position(x:geo.size.width-22,y:top+h-7)'''
if handle not in s: raise RuntimeError('lane height handle missing')
s=s.replace(handle,controls,1)

# Draw the existing audio source directly inside whichever universal lane it belongs to.
insert_before='''                if expandedLanes.contains(lane){
                    RoundedRectangle(cornerRadius:7)'''
audio_block='''                if lane == model.audioTrack, let audioName=model.musicName, model.musicURL != nil {
                    let aw=max(52,CGFloat(max(0.1,model.audioDuration)*pps))
                    let ax=center+CGFloat((model.audioTimelineStart-model.projectTime)*pps)+aw/2
                    HStack(spacing:4){
                        Image(systemName:"waveform").font(.system(size:8))
                        Text(audioName).font(.system(size:8,weight:.semibold)).lineLimit(1)
                    }
                    .padding(.horizontal,6)
                    .frame(width:aw,height:max(28,h-8))
                    .background(Color.cyan.opacity(bypassedTracksV52.contains(lane) ? 0.08:0.22),in:RoundedRectangle(cornerRadius:7))
                    .overlay(RoundedRectangle(cornerRadius:7).stroke(Color.cyan.opacity(0.55),lineWidth:1))
                    .position(x:ax,y:top+h/2)
                    .gesture(DragGesture(minimumDistance:2).onChanged{v in
                        model.audioTimelineStart=max(0,model.audioTimelineStart+Double(v.translation.width)/pps)
                    }.onEnded{_ in model.schedulePreview()})
                }

                if expandedLanes.contains(lane){
                    RoundedRectangle(cornerRadius:7)'''
if insert_before not in s: raise RuntimeError('expanded lane anchor missing')
s=s.replace(insert_before,audio_block,1)

# Extract-audio picker from each lane + and route result back to that exact lane.
modifier_anchor='.sheet(isPresented:$model.isAudioImporting){AudioPicker{model.isAudioImporting=false;model.importMusic($0)}}'
if modifier_anchor not in s: raise RuntimeError('audio sheet modifier missing')
modifier_new='''.sheet(isPresented:$model.isAudioImporting){AudioPicker{model.isAudioImporting=false;model.audioTrack=model.importTargetTrack;model.importMusic($0)}}
        .onChange(of:extractAudioItemV52){_,item in
            guard let item else{return}
            let lane=audioExtractLaneV52
            Task{
                if let movie=try? await item.loadTransferable(type:PickedMovie.self){
                    await MainActor.run{model.audioTrack=lane;model.importTargetTrack=lane}
                    await model.extractAudioFromVideo(movie.url)
                }else{await MainActor.run{model.errorMessage="Не удалось открыть выбранное видео"}}
                await MainActor.run{extractAudioItemV52=nil}
            }
        }'''
s=s.replace(modifier_anchor,modifier_new,1)

p.write_text(s)
print('Applied universal lane controls directly on v0.5 timeline; removed separate A1')
