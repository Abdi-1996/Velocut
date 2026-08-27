from pathlib import Path

p=Path('VeloCutAI/VeloCutAI/VeloCutV4.swift')
s=p.read_text()

# 1) Make the existing v0.5 track-height slider affect the REAL lane geometry.
old_geom='let pps=34.0*model.timelineZoom, center=geo.size.width/2, rulerH=22.0, fxH=42.0, videoH=46.0, curveH=34.0'
new_geom='let pps=34.0*model.timelineZoom, center=geo.size.width/2, rulerH=22.0, fxH=42.0, videoH=46.0*model.trackHeightScale, curveH=34.0*model.trackHeightScale'
if old_geom not in s:
    raise RuntimeError('v0.5 timeline geometry anchor missing')
s=s.replace(old_geom,new_geom,1)

if 'let laneH=48.0' not in s:
    raise RuntimeError('universal lane height anchor missing')
s=s.replace('let laneH=48.0','let laneH=videoH',1)

# Give enlarged tracks enough vertical room without changing the timeline/navigation engine.
s=s.replace('.frame(minHeight:230)', '.frame(minHeight:CGFloat(230*model.trackHeightScale))', 1)

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

# 3) Primary Audio-track import opens Photos gallery, selects a VIDEO, then extracts audio.
old_audio_file='Button{pendingAudioLane=lane;model.isAudioImporting=true}label:{Label("Аудиофайл",systemImage:"waveform.badge.plus")}'
old_extract='Button{pendingExtractLane=lane;showTrackExtractPicker=true}label:{Label("Извлечь аудио из видео",systemImage:"video.badge.waveform")}'
if old_audio_file not in s or old_extract not in s:
    raise RuntimeError('audio lane menu anchors missing')
s=s.replace(old_audio_file,'Button{pendingExtractLane=lane;showTrackExtractPicker=true}label:{Label("Аудиодорожка из видео",systemImage:"video.badge.waveform")}',1)
s=s.replace(old_extract,'Button{pendingAudioLane=lane;model.isAudioImporting=true}label:{Label("Аудиофайл из Файлов",systemImage:"waveform.badge.plus")}',1)

# Make the gallery extraction callback explicit and keep the chosen lane until extraction finishes.
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
print('Fixed real track scaling, editable names, and video-gallery audio extraction')
