from pathlib import Path

path = Path(__file__).resolve().parents[1] / "EditFlow/EditFlow/ViewModels/EditorViewModel.swift"
text = path.read_text()
pair = "    private var trimSessionOrigin: MediaClip?\n    private var lastTrimSnapGuide: Double?\n"
while pair + pair in text:
    text = text.replace(pair + pair, pair)
path.write_text(text)
print("Trim state declarations normalized")
