from pathlib import Path

root = Path(__file__).resolve().parents[1]
path = root / "EditFlow/Views/Editor/TimelineView.swift"
text = path.read_text()
original = text


def replace_once(old: str, new: str) -> None:
    global text
    if new in text:
        return
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"Expected exactly one match, got {count}: {old[:90]!r}")
    text = text.replace(old, new, 1)

replace_once(
    "    @State private var movingClipID: UUID?\n    @State private var movePreview: TimelineMovePreview?\n",
    "    @State private var movingClipID: UUID?\n    @State private var trimmingClipID: UUID?\n    @State private var movePreview: TimelineMovePreview?\n",
)

replace_once(
    "                    snappingEnabled: snappingEnabled,\n                    movingClipID: $movingClipID,\n                    movePreview: Binding(\n",
    "                    snappingEnabled: snappingEnabled,\n                    movingClipID: $movingClipID,\n                    trimmingClipID: $trimmingClipID,\n                    movePreview: Binding(\n",
)

replace_once(
    "                .onTapGesture {\n                    guard movingClipID == nil else { return }\n                    viewModel.select(clip)\n                }\n",
    "                .onTapGesture {\n                    guard movingClipID == nil, trimmingClipID == nil else { return }\n                    viewModel.select(clip)\n                }\n",
)

text = text.replace(
    "                guard movingClipID == nil else { return }\n",
    "                guard movingClipID == nil, trimmingClipID == nil else { return }\n",
)

replace_once(
    "    @Binding var movingClipID: UUID?\n    @Binding var movePreview: TimelineView.TimelineMovePreview?\n",
    "    @Binding var movingClipID: UUID?\n    @Binding var trimmingClipID: UUID?\n    @Binding var movePreview: TimelineView.TimelineMovePreview?\n",
)

replace_once(
    "        .overlay(alignment: .leading) {\n            if selected && !isMoving {\n                trimHandle(edge: .left)\n                    .offset(x: -7)\n            }\n        }\n        .overlay(alignment: .trailing) {\n            if selected && !isMoving {\n                trimHandle(edge: .right)\n                    .offset(x: 7)\n            }\n        }\n",
    "        .overlay(alignment: .leading) {\n            if selected && !isMoving {\n                trimHandle(edge: .left)\n            }\n        }\n        .overlay(alignment: .trailing) {\n            if selected && !isMoving {\n                trimHandle(edge: .right)\n            }\n        }\n",
)

old_handle = '''    private func trimHandle(edge: TrimEdge) -> some View {\n        Rectangle()\n            .fill(handleColor)\n            .frame(width: 14, height: 36)\n            .overlay {\n                Capsule()\n                    .fill(.white.opacity(0.92))\n                    .frame(width: 2, height: 18)\n            }\n            .contentShape(Rectangle().inset(by: -14))\n            .highPriorityGesture(trimGesture(edge: edge))\n            .accessibilityLabel(edge == .left ? "Обрезать начало клипа" : "Обрезать конец клипа")\n    }\n'''
new_handle = '''    private func trimHandle(edge: TrimEdge) -> some View {\n        ZStack(alignment: edge == .left ? .leading : .trailing) {\n            Color.clear\n            Rectangle()\n                .fill(handleColor)\n                .frame(width: 14, height: 38)\n                .overlay {\n                    Capsule()\n                        .fill(.white.opacity(0.92))\n                        .frame(width: 2, height: 20)\n                }\n        }\n        .frame(width: 44, height: 44)\n        .contentShape(Rectangle())\n        .highPriorityGesture(trimGesture(edge: edge), including: .gesture)\n        .accessibilityLabel(edge == .left ? "Обрезать начало клипа" : "Обрезать конец клипа")\n    }\n'''
replace_once(old_handle, new_handle)

replace_once(
    "    private func activateMoveIfNeeded() {\n        guard !isMoving else { return }\n",
    "    private func activateMoveIfNeeded() {\n        guard !isMoving, trimmingClipID == nil else { return }\n",
)

old_trim = '''    private func trimGesture(edge: TrimEdge) -> some Gesture {\n        DragGesture(minimumDistance: 0, coordinateSpace: .global)\n            .onChanged { value in\n                switch edge {\n                case .left:\n                    if leftDragOrigin == nil { leftDragOrigin = clip }\n                    guard let origin = leftDragOrigin else { return }\n                    previewLeftTrim(origin: origin, translation: value.translation.width)\n                case .right:\n                    if rightDragOrigin == nil { rightDragOrigin = clip }\n                    guard let origin = rightDragOrigin else { return }\n                    previewRightTrim(origin: origin, translation: value.translation.width)\n                }\n            }\n            .onEnded { _ in\n                leftDragOrigin = nil\n                rightDragOrigin = nil\n                viewModel.finishNonRippleTrim()\n            }\n    }\n'''
new_trim = '''    private func trimGesture(edge: TrimEdge) -> some Gesture {\n        DragGesture(minimumDistance: 0, coordinateSpace: .global)\n            .onChanged { value in\n                if trimmingClipID != clip.id {\n                    trimmingClipID = clip.id\n                    viewModel.select(clip)\n                }\n\n                switch edge {\n                case .left:\n                    if leftDragOrigin == nil { leftDragOrigin = clip }\n                    guard let origin = leftDragOrigin else { return }\n                    previewLeftTrim(origin: origin, translation: value.translation.width)\n                case .right:\n                    if rightDragOrigin == nil { rightDragOrigin = clip }\n                    guard let origin = rightDragOrigin else { return }\n                    previewRightTrim(origin: origin, translation: value.translation.width)\n                }\n            }\n            .onEnded { _ in\n                leftDragOrigin = nil\n                rightDragOrigin = nil\n                if trimmingClipID == clip.id {\n                    trimmingClipID = nil\n                }\n                viewModel.finishNonRippleTrim()\n            }\n    }\n'''
replace_once(old_trim, new_trim)

if text != original:
    path.write_text(text)
    print("Applied EditFlow 1.6.2 trim handle fix")
else:
    print("Trim handle source fix already applied")

changelog_path = root / "CHANGELOG.md"
changelog = changelog_path.read_text()
if "## 1.6.2" not in changelog:
    entry = '''# Changelog\n\n## 1.6.2\n\n### Fixed\n\n- Left and right clip-edge trim handles now own the drag gesture instead of allowing timeline scrubbing to steal the same touch.\n- Added a dedicated trim interaction state that blocks horizontal scrubbing, vertical track scrolling, and long-press clip movement while an edge handle is active.\n- Trim handles now use a full 44x44-point touch target while keeping the visible edge control compact.\n- Releasing a trim handle immediately returns gesture control to the timeline.\n\n'''
    if not changelog.startswith("# Changelog\n"):
        raise SystemExit("Unexpected CHANGELOG header")
    changelog = entry + changelog[len("# Changelog\n\n"):]
    changelog_path.write_text(changelog)
    print("Documented EditFlow 1.6.2")
else:
    print("EditFlow 1.6.2 changelog already present")
