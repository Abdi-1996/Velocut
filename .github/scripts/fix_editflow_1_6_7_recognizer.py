from pathlib import Path

path = Path('EditFlow/EditFlow/Views/Editor/TimelineView.swift')
text = path.read_text()
old = '''        recognizer.minimumNumberOfTouches = 1
        recognizer.maximumNumberOfTouches = 1
'''
if old in text:
    text = text.replace(old, '', 1)
    path.write_text(text)
