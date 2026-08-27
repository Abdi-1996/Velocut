from pathlib import Path

p=Path('VeloCutAI/VeloCutAI/VeloCutV4.swift')
s=p.read_text()

# 1) Restore the ORIGINAL per-lane resize engine from v0.5 and connect global track scale.
# patch_v04 already provides laneHeights + LaneHeightHandleV4; universal tracks must reuse it.
old_curve_geom='let pps=34.0*model.timelineZoom, center=geo.size.width/2, rulerH=22.0, fxH=42.0, curveH=56.0'
new_curve_geom='let pps=34.0*model.timelineZoom, center=geo.size.width/2, rulerH=22.0, fxH=42.0, curveH=56.0*CGFloat(model.trackHeightScale)'
if old_curve_geom not in s:
    raise RuntimeError('v0.5 timeline curve geometry missing')
s=s.replace(old_curve_geom,new_curve_geom,1)

old_lane_height='let laneHeight:(Int)->CGFloat={laneHeights[$0] ?? 46}'
new_lane_height='let laneHeight:(Int)->CGFloat={(laneHeights[$0] ?? 46)*CGFloat(model.trackHeightScale)}'
if old_lane_height not in s:
    raise RuntimeError('v0.5 laneHeight closure missing')
s=s.replace(old_lane_height,new_lane_height,1)

if 'let laneH=48.0' not in s:
    raise RuntimeError('universal lane local height missing')
s=s.replace('let laneH=48.0','let laneH=laneHeight(lane)',1)

# Re-add the native v0.5 resize handle that was lost when the universal lane header replaced the old lane block.
chevron='Button{if expandedLanes.contains(lane){expandedLanes.remove(lane)}else{expandedLanes.insert(lane)}}label:{Image(systemName:expandedLanes.contains(lane) ? "chevron.up":"chevron.down").font(.system(size:8,weight:.bold)).frame(width:20,height:20).background(.thinMaterial,in:Circle())}.buttonStyle(.plain).position(x:84,y:top+laneH/2)'
if chevron not in s:
    raise RuntimeError('universal lane chevron missing')
resize='''\n                LaneHeightHandleV4(height:laneH){newHeight in
                    laneHeights[lane]=newHeight/max(0.65,CGFloat(model.trackHeightScale))
                }
                .position(x:geo.size.width-44,y:top+laneH-7)'''
s=s.replace(chevron,chevron+resize,1)

# Required timeline height must follow both individual lane heights and global scale.
old_required='let video = (0..<3).reduce(CGFloat.zero) { $0 + (laneHeights[$1] ?? 46) }\n        let curves = CGFloat(expandedLanes.count) * 56'
new_required='let video = (0..<3).reduce(CGFloat.zero) { $0 + (laneHeights[$1] ?? 46) } * CGFloat(model.trackHeightScale)\n        let curves = CGFloat(expandedLanes.count) * 56 * CGFloat(model.trackHeightScale)'
if old_required not in s:
    raise RuntimeError('timelineRequiredHeight geometry missing')
s=s.replace(old_required,new_required,1)

# 2) Real rename UI instead of auto-writing Track 1 / Track 2 / Track 3.
state_anchor='@State private var trackNames:[Int:String]=[0:"V1",1:"V2",2:"V3"]'
if state_anchor not in s:
    raise RuntimeError('trackNames state missing')
s=s.replace(state_anchor,state_anchor+'''\n    @State private var renamingLane:Int?\n    @State private var renameTrackText=""\n    @State private var showRenameTrack=false''',1)

old_rename='Button("Переименовать"){trackNames[lane]="Track \\(lane+1)"}'
new_rename='Button("Переименовать"){renamingLane=lane;renameTrackText=trackNames[lane] ?? "V\\(lane+1)";showRenameTrack=true}'
if old_rename not in s:
    raise RuntimeError('rename action missing')
s=s.replace(old_rename,new_rename,1)

body_hook='.onChange(of:photoItems){_,items in loadPhotos(items)}'
if body_hook not in s:
    raise RuntimeError('editor modifier anchor missing')
rename_alert='''.alert("Переименовать дорожку",isPresented:$showRenameTrack){
            TextField("Название дорожки",text:$renameTrackText)
            Button("Отмена",role:.cancel){renamingLane=nil}
            Button("Сохранить"){
                if let lane=renamingLane{
                    let clean=renameTrackText.trimmingCharacters(in:.whitespacesAndNewlines)
                    trackNames[lane]=clean.isEmpty ? "V\\(lane+1)" : String(clean.prefix(18))
                }
                renamingLane=nil
            }
        }'''
s=s.replace(body_hook,body_hook+'\n        '+rename_alert,1)

# 3) Primary Audio-track import opens Photos gallery, selects a VIDEO, then extracts its audio.
old_audio_file='Button{pendingAudioLane=lane;model.isAudioImporting=true}label:{Label("Аудиофайл",systemImage:"waveform.badge.plus")}'
old_extract='Button{pendingExtractLane=lane;showTrackExtractPicker=true}label:{Label("Извлечь аудио из видео",systemImage:"video.badge.waveform")}'
if old_audio_file not in s or old_extract not in s:
    raise RuntimeError('audio lane menu anchors missing')
s=s.replace(old_audio_file,'Button{pendingExtractLane=lane;showTrackExtractPicker=true}label:{Label("Аудиодорожка из видео",systemImage:"video.badge.waveform")}',1)
s=s.replace(old_extract,'Button{pendingAudioLane=lane;model.isAudioImporting=true}label:{Label("Аудиофайл из Файлов",systemImage:"waveform.badge.plus")}',1)

# Keep the selected lane until extraction is complete; then the new TimelineAudioClip is drawn in that same lane.
old_change='''        .onChange(of:trackExtractItem){_,item in
            guard let item,let lane=pendingExtractLane else{return}
            Task{if let movie=try? await item.loadTransferable(type:PickedMovie.self){await model.extractAudioFromVideo(movie.url,toTrack:lane,at:model.projectTime)}else{await MainActor.run{model.errorMessage="Не удалось открыть видео"}};await MainActor.run{trackExtractItem=nil;pendingExtractLane=nil}}
        }'''
new_change='''        .onChange(of:trackExtractItem){_,item in
            guard let item,let lane=pendingExtractLane else{return}
            Task{
                if let movie=try? await item.loadTransferable(type:PickedMovie.self){
                    await model.extractAudioFromVideo(movie.url,toTrack:lane,at:model.projectTime)
                }else{
                    await MainActor.run{model.errorMessage="Не удалось открыть выбранное видео из галереи"}
                }
                await MainActor.run{trackExtractItem=nil;pendingExtractLane=nil}
            }
        }'''
if old_change not in s:
    raise RuntimeError('audio gallery callback missing')
s=s.replace(old_change,new_change,1)

p.write_text(s)
print('Fixed native lane resizing, editable names, and video-gallery audio extraction')
