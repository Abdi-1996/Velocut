from pathlib import Path
import re
p=Path('VeloCutAI/VeloCutAI/VeloCutV4.swift')
s=p.read_text()

# Add only metadata/state around the existing v0.5 timeline. Do not replace its canvas.
state='@State private var multiSelectedClips:Set<UUID>=[]'
if state not in s: raise RuntimeError('v0.5 timeline state missing')
s=s.replace(state,state+'''\n    @State private var extraTrackCount=0
    @State private var trackNames:[Int:String]=[0:"V1",1:"V2",2:"V3",3:"Audio"]
    @State private var trackColors:[Int:Color]=[0:.blue,1:.purple,2:.pink,3:.cyan]
    @State private var bypassedTracks:Set<Int>=[]
    @State private var animationCollapsed=true
    @State private var animationHeight:CGFloat=72''',1)

# Number of rows is dynamic; importing audio creates a normal fourth row in the SAME canvas.
mark='    private var timeline:some View'
if mark not in s: raise RuntimeError('timeline property missing')
helpers='''    private var visibleTrackCount:Int { max(3 + extraTrackCount, model.musicURL == nil ? 3 : 4) }

    private var animationTimelineV62:some View{
        VStack(spacing:0){
            HStack(spacing:7){
                Button{withAnimation(.snappy){animationCollapsed.toggle()}}label:{Image(systemName:animationCollapsed ? "chevron.right":"chevron.down")}
                Text("Animation").font(.caption.bold())
                Button{model.haptic(.selection)}label:{Image(systemName:"diamond.badge.plus")}
                Spacer()
                Button{model.haptic(.selection)}label:{Image(systemName:"plus.square.on.square")}
                Button{model.haptic(.selection)}label:{Image(systemName:"square.and.arrow.down")}
            }.padding(.horizontal,12).frame(height:30).background(.thinMaterial)
            if !animationCollapsed {
                GeometryReader{g in
                    let center=g.size.width/2
                    ZStack{
                        RoundedRectangle(cornerRadius:7).fill(Color.secondary.opacity(0.045))
                        HStack(spacing:18){ForEach(0..<7,id:\\.self){_ in Image(systemName:"diamond.fill").font(.system(size:7)).foregroundStyle(.secondary)}}
                        Rectangle().fill(Color.red.opacity(0.8)).frame(width:1.1,height:max(38,animationHeight)).position(x:center,y:max(38,animationHeight)/2)
                    }
                }.frame(height:max(38,animationHeight))
                Capsule().fill(Color.secondary.opacity(0.35)).frame(width:40,height:4).frame(height:10)
                    .gesture(DragGesture().onChanged{v in animationHeight=min(180,max(38,animationHeight+v.translation.height))})
            }
        }
    }

'''
s=s.replace(mark,helpers+mark,1)

# Keep v0.5 header and put Animation immediately above the existing timeline canvas.
needle='''        VStack(spacing:4){
            ScrollView(.vertical,showsIndicators:false){GeometryReader{geo in timelineCanvas(geo)}.frame(height:timelineRequiredHeight)}.frame(minHeight:180,maxHeight:360)
            audioLaneV50
        }'''
if needle not in s: raise RuntimeError('v052 timeline stack missing')
s=s.replace(needle,'''        VStack(spacing:4){
            animationTimelineV62
            ScrollView(.vertical,showsIndicators:false){GeometryReader{geo in timelineCanvas(geo)}.frame(height:timelineRequiredHeight)}.frame(minHeight:180,maxHeight:380)
        }''',1)

# Generalize old fixed three lane geometry, preserving exact v0.5 canvas behavior.
s=s.replace('let laneHeight:(Int)->CGFloat={lane in model.collapsedTracks.contains(lane) ? 28 : max(32,(laneHeights[lane] ?? 46)*CGFloat(model.trackHeightScale))}',
'''let laneHeight:(Int)->CGFloat={lane in model.collapsedTracks.contains(lane) ? 28 : max(32,(laneHeights[lane] ?? 46)*CGFloat(model.trackHeightScale))}''',1)

# laneTop already loops to lane; no change required. Replace the fixed lane-render block inserted by v0.4.
lane_pat=re.compile(r'''            ForEach\(0\.\.<3,id:\\\.self\)\{lane in\n                let top=laneTop\(lane\),h=laneHeight\(lane\).*?\n            \}''',re.S)
lane_repl=r'''            ForEach(0..<visibleTrackCount,id:\.self){lane in
                let top=laneTop(lane),h=laneHeight(lane)
                RoundedRectangle(cornerRadius:8)
                    .fill((trackColors[lane] ?? Color.secondary).opacity(bypassedTracks.contains(lane) ? 0.025:0.065))
                    .frame(height:max(35,h-3)).offset(y:top)

                Menu{
                    Button("Rename"){trackNames[lane]="Track \(lane+1)"}
                    Menu("Color"){
                        Button("Blue"){trackColors[lane]=.blue};Button("Purple"){trackColors[lane]=.purple};Button("Pink"){trackColors[lane]=.pink};Button("Green"){trackColors[lane]=.green};Button("Orange"){trackColors[lane]=.orange}
                    }
                    Button("Add track below"){extraTrackCount += 1;laneHeights[visibleTrackCount]=46;trackNames[visibleTrackCount]="Track \(visibleTrackCount+1)"}
                    if visibleTrackCount > 1 { Button("Delete track",role:.destructive){if lane >= 3 && extraTrackCount>0 {extraTrackCount -= 1}} }
                }label:{
                    Text(trackNames[lane] ?? "Track \(lane+1)").font(.system(size:9,weight:.bold)).lineLimit(1)
                        .frame(width:48,height:30).background(trackColors[lane] ?? Color.secondary,in:RoundedRectangle(cornerRadius:7)).foregroundStyle(.white)
                }
                .buttonStyle(.plain).position(x:31,y:top+h/2)
                .simultaneousGesture(LongPressGesture(minimumDuration:0.35).sequenced(before:DragGesture()).onEnded{v in
                    if case .second(true,let d?)=v,abs(d.translation.height)>16 { model.haptic(.selection) }
                })

                Button{if bypassedTracks.contains(lane){bypassedTracks.remove(lane)}else{bypassedTracks.insert(lane)}}label:{
                    Text("B").font(.system(size:9,weight:.bold)).frame(width:24,height:26)
                        .background(bypassedTracks.contains(lane) ? Color.orange.opacity(0.38):Color.secondary.opacity(0.13),in:RoundedRectangle(cornerRadius:6))
                }.buttonStyle(.plain).position(x:72,y:top+h/2)

                Menu{
                    Button{model.isFileImporting=true}label:{Label("Video / Photo",systemImage:"film")}
                    Button{model.isAudioImporting=true}label:{Label("Audio",systemImage:"waveform")}
                    Button{model.haptic(.selection)}label:{Label("Text",systemImage:"textformat")}
                    Button{model.haptic(.selection)}label:{Label("Effect",systemImage:"sparkles")}
                    Button{model.haptic(.selection)}label:{Label("Transition",systemImage:"arrow.left.and.right")}
                    Button{model.haptic(.selection)}label:{Label("Speed FX",systemImage:"waveform.path.ecg")}
                }label:{Image(systemName:"plus.circle.fill").font(.system(size:18))}
                .buttonStyle(.plain).position(x:geo.size.width-17,y:top+h/2)

                if lane == 3, let name=model.musicName, model.musicURL != nil {
                    let duration=max(0.1,model.audioDuration),w=max(54,CGFloat(duration*pps)),x=center+CGFloat((model.audioTimelineStart-model.projectTime)*pps)+w/2
                    HStack(spacing:5){Image(systemName:"waveform").font(.caption2);Text(name).font(.system(size:8,weight:.semibold)).lineLimit(1)}
                        .padding(.horizontal,7).frame(width:w,height:max(26,h-8))
                        .background((trackColors[lane] ?? Color.cyan).opacity(bypassedTracks.contains(lane) ? 0.08:0.2),in:RoundedRectangle(cornerRadius:7))
                        .overlay(RoundedRectangle(cornerRadius:7).stroke((trackColors[lane] ?? Color.cyan).opacity(0.55),lineWidth:1))
                        .position(x:x,y:top+h/2)
                        .gesture(DragGesture(minimumDistance:2).onChanged{v in model.audioTimelineStart=max(0,model.audioTimelineStart+Double(v.translation.width)/pps)}.onEnded{_ in model.schedulePreview()})
                }

                LaneHeightHandleV4(height:h){laneHeights[lane]=$0}.position(x:geo.size.width-42,y:top+h-7)
                if expandedLanes.contains(lane){
                    RoundedRectangle(cornerRadius:7).fill(Color.accentColor.opacity(0.035)).frame(height:curveH-2).offset(y:top+h)
                    Text("Speed").font(.system(size:8,weight:.semibold)).foregroundStyle(.secondary).position(x:22,y:top+h+10)
                }
            }'''
s,n=lane_pat.subn(lane_repl,s,count=1)
if n!=1: raise RuntimeError('fixed v0.5 lane block not found')

# Dynamic required height instead of hard-coded 3 lanes.
height_pat=re.compile(r'''    private var timelineRequiredHeight:CGFloat \{.*?\n    \}''',re.S)
height_repl='''    private var timelineRequiredHeight:CGFloat {
        let scale=CGFloat(model.trackHeightScale)
        let base:CGFloat = 22 + max(30,42*scale) + 12
        let video=(0..<visibleTrackCount).reduce(CGFloat.zero){sum,lane in sum + (model.collapsedTracks.contains(lane) ? 28 : max(32,(laneHeights[lane] ?? 46)*scale))}
        let expandedCount=(0..<visibleTrackCount).filter{expandedLanes.contains($0) && !model.collapsedTracks.contains($0)}.count
        return max(230,base+video+CGFloat(expandedCount)*max(34,56*scale))
    }'''
s,n=height_pat.subn(height_repl,s,count=1)
if n!=1: raise RuntimeError('required height missing')

p.write_text(s)
print('Applied controls directly over v0.5 timeline; no second timeline, no A1 row')
