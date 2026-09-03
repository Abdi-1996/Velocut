from pathlib import Path

root = Path(__file__).resolve().parents[2]
timeline = root / "EditFlow/EditFlow/Views/Editor/TimelineView.swift"
changelog = root / "EditFlow/CHANGELOG.md"

text = timeline.read_text()
text = text.replace('String(format: \\\"%.3f\\\", clip.trimStart)', 'String(format: "%.3f", clip.trimStart)')
text = text.replace('String(format: \\\"%.3f\\\", clip.trimEnd)', 'String(format: "%.3f", clip.trimEnd)')
text = text.replace('String(format: \\"%.3f\\", clip.trimStart)', 'String(format: "%.3f", clip.trimStart)')
text = text.replace('String(format: \\"%.3f\\", clip.trimEnd)', 'String(format: "%.3f", clip.trimEnd)')
timeline.write_text(text)

entry = '''## 1.6.3\n\n### Fixed\n\n- Rebuilt clip-edge trimming around a dedicated touch-down recognizer so the trim handle owns the finger immediately, similar to CapCut mobile.\n- Trim now uses a local visual preview while dragging instead of mutating project clip timing every pixel, preventing the handle from losing its gesture as the clip width changes.\n- Left and right trim edges follow the finger in screen coordinates and commit source trim points only once on release.\n- Magnetic trim snapping remains active and displays an orange alignment guide with haptic feedback.\n- Speed-ramped clips now resolve trim boundaries from playback duration so the visible edge remains aligned with the finger.\n\n### Changed\n\n- Timeline scrolling and long-press clip movement are disabled from touch-down until the trim handle is released.\n\n'''
change = changelog.read_text()
if '## 1.6.3' not in change:
    change = change.replace('# Changelog\n\n', '# Changelog\n\n' + entry, 1)
    changelog.write_text(change)
