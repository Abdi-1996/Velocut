from pathlib import Path

path = Path('EditFlow/EditFlow/Views/Editor/TimelineView.swift')
text = path.read_text()

old = '''    private var rulerPanGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard movingClipID == nil, trimmingClipID == nil else { return }
'''
new = '''    private var rulerPanGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard movingClipID == nil, trimmingClipID == nil, !isPinching else { return }
'''
if old not in text:
    raise SystemExit('ruler pan block not found')
text = text.replace(old, new, 1)
text = text.replace('Slider(value: $trackHeight, in: 38...82)', 'Slider(value: $trackHeight, in: 46...86)', 1)
text = text.replace('''    private var tickStep: Double {
        if zoom >= 120 { return 0.5 }
        if zoom >= 70 { return 1 }
        return 2
    }
''', '''    private var tickStep: Double {
        if zoom >= 120 { return 0.5 }
        return 1
    }
''', 1)
path.write_text(text)
