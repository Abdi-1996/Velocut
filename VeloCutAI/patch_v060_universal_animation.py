from pathlib import Path
import re
p=Path('VeloCutAI/VeloCutAI/VeloCutV4.swift');s=p.read_text()

state='@Published var audioDuration = 0.0'
if state not in s: raise RuntimeError('v052 state missing')
s=s.replace(state,state+'''\n    @Published var universalTracks:[UniversalTrack] = (0..<3).map{UniversalTrack(name:"V\\($0+1)",order:$0)}
    @Published var animationTimelineCollapsed = true
    @Published var animationTimelineHeight = 92.0
    @Published var animationClips:[AnimationClipV6] = []
    @Published var selectedAnimationClipID:UUID? = nil''',1)

# Model operations: track add/delete/rename/color/bypass/reorder + animation blocks.
model_anchor='    func removeMusic() {'
idx=s.find(model_anchor)
if idx<0: raise RuntimeError('model anchor missing')
ops='''    func addUniversalTrack(after id:UUID?=nil){
        let insert=(id.flatMap{v in universalTracks.firstIndex(where:{$0.id==v})}.map{$0+1}) ?? universalTracks.count
        universalTracks.insert(UniversalTrack(name:"Track \\(universalTracks.count+1)",order:insert),at:min(insert,universalTracks.count))
        normalizeUniversalTrackOrder(); haptic(.selection)
    }
    func deleteUniversalTrack(_ id:UUID){guard universalTracks.count>1 else{return};universalTracks.removeAll{$0.id==id};normalizeUniversalTrackOrder();haptic(.warning)}
    func renameUniversalTrack(_ id:UUID,_ name:String){if let i=universalTracks.firstIndex(where:{$0.id==id}){universalTracks[i].name=name.isEmpty ? "Track \\(i+1)":name}}
    func toggleUniversalBypass(_ id:UUID){if let i=universalTracks.firstIndex(where:{$0.id==id}){universalTracks[i].bypassed.toggle();schedulePreview()}}
    func moveUniversalTrack(_ id:UUID,by delta:Int){guard let i=universalTracks.firstIndex(where:{$0.id==id}) else{return};let j=max(0,min(universalTracks.count-1,i+delta));guard i != j else{return};let t=universalTracks.remove(at:i);universalTracks.insert(t,at:j);normalizeUniversalTrackOrder();haptic(.selection)}
    func normalizeUniversalTrackOrder(){for i in universalTracks.indices{universalTracks[i].order=i}}
    func addAnimationClip(){let c=AnimationClipV6(start:projectTime,duration:max(0.5,min(2,projectDuration-projectTime)));animationClips.append(c);selectedAnimationClipID=c.id;animationTimelineCollapsed=false;haptic(.selection)}
    func duplicateAnimationClip(_ id:UUID){guard var c=animationClips.first(where:{$0.id==id}) else{return};c.id=UUID();c.start=min(projectDuration,max(0,c.start+c.duration));c.name += " Copy";animationClips.append(c);selectedAnimationClipID=c.id}
    func deleteAnimationClip(_ id:UUID){animationClips.removeAll{$0.id==id};if selectedAnimationClipID==id{selectedAnimationClipID=nil}}

'''
s=s[:idx]+ops+s[idx:]

# Put collapsible animation timeline immediately above normal timeline in both layouts.
s=s.replace('VStack(spacing:0){workspaceHandle;if let target=curveTarget', 'VStack(spacing:0){workspaceHandle;animationTimelineV6;if let target=curveTarget',1)
s=s.replace('preview.frame(height:max(150,root.size.height*model.previewSplit));playback;workspaceHandle\n                if let target=curveTarget', 'preview.frame(height:max(150,root.size.height*model.previewSplit));playback;workspaceHandle;animationTimelineV6\n                if let target=curveTarget',1)

mark='    private var timeline:some View'
if mark not in s: raise RuntimeError('timeline property missing')
ui=r'''    private var animationTimelineV6:some View{
        VStack(spacing:0){
            HStack(spacing:7){
                Button{withAnimation(.snappy){model.animationTimelineCollapsed.toggle()}}label:{Image(systemName:model.animationTimelineCollapsed ? "chevron.right":"chevron.down")}
                Text("Animation").font(.caption.bold())
                Button{model.addAnimationClip()}label:{Image(systemName:"plus.diamond.fill")}
                Spacer()
                if !model.animationTimelineCollapsed { Text("KEYFRAME TIMELINE").font(.system(size:8,weight:.semibold)).foregroundStyle(.secondary) }
            }.padding(.horizontal,10).frame(height:30).background(.thinMaterial)
            if !model.animationTimelineCollapsed {
                GeometryReader{geo in
                    let pps=34.0*model.timelineZoom,center=geo.size.width/2
                    ZStack(alignment:.topLeading){
                        Rectangle().fill(Color.secondary.opacity(0.045))
                        ForEach(model.animationClips){clip in
                            let w=max(48,CGFloat(clip.duration*pps));let x=center+CGFloat((clip.start-model.projectTime)*pps)+w/2
                            HStack(spacing:5){Image(systemName:"diamond.fill").font(.system(size:7));Text(clip.name).font(.caption2).lineLimit(1);Spacer()}
                                .padding(.horizontal,7).frame(width:w,height:30)
                                .background(model.selectedAnimationClipID==clip.id ? Color.accentColor.opacity(0.28):Color.secondary.opacity(0.14),in:RoundedRectangle(cornerRadius:7))
                                .position(x:x,y:24).onTapGesture{model.selectedAnimationClipID=clip.id}
                                .contextMenu{Button("Duplicate"){model.duplicateAnimationClip(clip.id)};Button("Save preset"){};Button("Delete",role:.destructive){model.deleteAnimationClip(clip.id)}}
                                .gesture(DragGesture().onChanged{v in if let i=model.animationClips.firstIndex(where:{$0.id==clip.id}){model.animationClips[i].start=max(0,clip.start+Double(v.translation.width)/pps)}})
                        }
                        Rectangle().fill(Color.red.opacity(0.85)).frame(width:1.2,height:max(50,model.animationTimelineHeight)).position(x:center,y:max(50,model.animationTimelineHeight)/2)
                    }.clipped()
                }.frame(height:max(50,model.animationTimelineHeight))
                Capsule().fill(Color.secondary.opacity(0.35)).frame(width:38,height:4).frame(height:10)
                    .gesture(DragGesture().onChanged{v in model.animationTimelineHeight=min(220,max(50,model.animationTimelineHeight+Double(v.translation.height)))})
            }
        }
    }

    private var universalTrackStripV6:some View{
        VStack(spacing:3){
            ForEach(model.universalTracks){track in
                HStack(spacing:5){
                    Menu{
                        Button("Rename"){}
                        Button("Change color"){}
                        Button("Add track below"){model.addUniversalTrack(after:track.id)}
                        Button("Delete",role:.destructive){model.deleteUniversalTrack(track.id)}
                    }label:{Text(track.name).font(.system(size:9,weight:.bold)).lineLimit(1).frame(width:42,height:30).background(Color.secondary.opacity(track.bypassed ? 0.08:0.18),in:RoundedRectangle(cornerRadius:7))}
                    .simultaneousGesture(LongPressGesture(minimumDuration:0.35).sequenced(before:DragGesture()).onEnded{value in if case .second(true,let drag?)=value{model.moveUniversalTrack(track.id,by:drag.translation.height>12 ? 1:(drag.translation.height < -12 ? -1:0))}})
                    Button{model.toggleUniversalBypass(track.id)}label:{Text("B").font(.caption.bold()).frame(width:28,height:28).background(track.bypassed ? Color.accentColor.opacity(0.35):Color.secondary.opacity(0.10),in:RoundedRectangle(cornerRadius:6))}
                    Spacer()
                    Menu{Button("Video"){};Button("Photo"){};Button("Audio"){};Button("Text"){};Button("Effect"){};Button("Transition"){};Button("Speed FX"){};Button("Animation"){model.addAnimationClip()}}label:{Image(systemName:"plus.circle.fill").font(.title3)}
                }.padding(.horizontal,8).opacity(track.bypassed ? 0.48:1)
            }
            Button{model.addUniversalTrack()}label:{Label("Add track",systemImage:"plus").font(.caption)}
        }
    }

'''
s=s.replace(mark,ui+mark,1)

# Put track management strip above the existing timeline canvas. This is transitional UI while existing clips retain old lane IDs.
s=s.replace('VStack(spacing:4){\n            ScrollView(.vertical,showsIndicators:false)', 'VStack(spacing:4){\n            universalTrackStripV6\n            ScrollView(.vertical,showsIndicators:false)',1)

p.write_text(s)
print('Applied v0.6 universal tracks + collapsible animation timeline')
