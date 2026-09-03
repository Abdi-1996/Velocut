from pathlib import Path

root = Path('.')
vm_path = root / 'EditFlow/EditFlow/ViewModels/EditorViewModel.swift'
editor_path = root / 'EditFlow/EditFlow/Views/Editor/EditorView.swift'
timeline_path = root / 'EditFlow/EditFlow/Views/Editor/TimelineView.swift'
project_path = root / 'EditFlow/project.yml'
changelog_path = root / 'EditFlow/CHANGELOG.md'
workflow_path = root / '.github/workflows/build-editflow.yml'

vm = vm_path.read_text()
editor = editor_path.read_text()
timeline = timeline_path.read_text()
project = project_path.read_text()
changelog = changelog_path.read_text()
workflow = workflow_path.read_text()

if 'MARKETING_VERSION: 1.6.9' in project and 'trimPreviewImage' in vm:
    raise SystemExit(0)

vm = vm.replace(
    'import SwiftUI\n',
    'import SwiftUI\nimport UIKit\n',
    1,
)

vm = vm.replace(
    '    @Published var showingExport = false\n',
    '    @Published var showingExport = false\n'
    '    @Published private(set) var trimPreviewImage: UIImage?\n'
    '    @Published private(set) var trimPreviewSourceTime: Double?\n',
    1,
)

vm = vm.replace(
    '    private var lastTrimSnapGuide: Double?\n',
    '    private var lastTrimSnapGuide: Double?\n'
    '    private var trimPreviewFrameTask: Task<Void, Never>?\n'
    '    private var trimPreviewFrameGeneration = 0\n',
    1,
)

vm = vm.replace(
    '        previewBuildTask?.cancel()\n        if let endObserver {\n',
    '        previewBuildTask?.cancel()\n'
    '        trimPreviewFrameTask?.cancel()\n'
    '        TrimPreviewFrameService.shared.cancelPendingRequest()\n'
    '        if let endObserver {\n',
    1,
)

anchor = '''    func mediaURL(for clip: MediaClip) -> URL {
        store.projectDirectory(project.id).appendingPathComponent(clip.relativePath)
    }
'''
insert = anchor + '''
    func updateTrimPreviewFrame(for clip: MediaClip, showingStart: Bool) {
        pausePlayback()

        trimPreviewFrameTask?.cancel()
        trimPreviewFrameGeneration += 1
        let generation = trimPreviewFrameGeneration

        guard clip.kind == .video else {
            TrimPreviewFrameService.shared.cancelPendingRequest()
            trimPreviewImage = nil
            trimPreviewSourceTime = nil
            return
        }

        let sourceFrame = 1 / Double(max(1, project.frameRate))
        let sourceTime: Double
        if showingStart {
            sourceTime = min(max(0, clip.trimStart), clip.sourceDuration)
        } else {
            sourceTime = max(
                clip.trimStart,
                min(clip.sourceDuration, clip.trimEnd - sourceFrame)
            )
        }

        trimPreviewSourceTime = sourceTime
        let url = mediaURL(for: clip)

        trimPreviewFrameTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 18_000_000)
            guard !Task.isCancelled else { return }

            let image = await TrimPreviewFrameService.shared.frame(
                url: url,
                sourceTime: sourceTime
            )

            guard let self,
                  !Task.isCancelled,
                  generation == self.trimPreviewFrameGeneration else {
                return
            }

            self.trimPreviewImage = image
        }
    }

    func clearTrimPreviewFrame() {
        trimPreviewFrameTask?.cancel()
        trimPreviewFrameTask = nil
        trimPreviewFrameGeneration += 1
        TrimPreviewFrameService.shared.cancelPendingRequest()
        trimPreviewImage = nil
        trimPreviewSourceTime = nil
    }
'''
if anchor not in vm:
    raise SystemExit('EditorViewModel mediaURL anchor not found')
vm = vm.replace(anchor, insert, 1)

preview_old = '''        Group {
            if let clip = viewModel.previewClip,
               clip.kind == .image,
               let image = UIImage(contentsOfFile: viewModel.mediaURL(for: clip).path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(imagePadding)
            } else if viewModel.player.currentItem == nil {
                EmptyPreview()
            } else {
                PlayerContainer(player: viewModel.player)
            }
        }
'''
preview_new = '''        ZStack {
            Group {
                if let trimImage = viewModel.trimPreviewImage {
                    Image(uiImage: trimImage)
                        .resizable()
                        .scaledToFit()
                        .padding(imagePadding)
                } else if let clip = viewModel.previewClip,
                          clip.kind == .image,
                          let image = UIImage(contentsOfFile: viewModel.mediaURL(for: clip).path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(imagePadding)
                } else if viewModel.player.currentItem == nil {
                    EmptyPreview()
                } else {
                    PlayerContainer(player: viewModel.player)
                }
            }

            if let trimTime = viewModel.trimPreviewSourceTime,
               viewModel.trimPreviewImage != nil {
                VStack {
                    Spacer()
                    Text("TRIM  \(trimTime.formattedDuration)")
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.62), in: Capsule())
                        .padding(.bottom, 10)
                }
                .allowsHitTesting(false)
            }
        }
'''
if preview_old not in editor:
    raise SystemExit('PreviewMediaSurface anchor not found')
editor = editor.replace(preview_old, preview_new, 1)

begin_old = '''        viewModel.select(sourceClip)
        viewModel.pausePlayback()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
'''
begin_new = '''        viewModel.select(sourceClip)
        viewModel.pausePlayback()
        viewModel.updateTrimPreviewFrame(
            for: sourceClip,
            showingStart: edge == .left
        )
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
'''
if begin_old not in timeline:
    raise SystemExit('Unified trim begin anchor not found')
timeline = timeline.replace(begin_old, begin_new, 1)

update_old = '''        trimPreviewClip = result.clip
        trimSnapGuide = result.guide

        if result.guide != lastSnapGuide {
'''
update_new = '''        trimPreviewClip = result.clip
        trimSnapGuide = result.guide
        viewModel.updateTrimPreviewFrame(
            for: result.clip,
            showingStart: activeEdge == .left
        )

        if result.guide != lastSnapGuide {
'''
# Use the occurrence inside TimelineUnifiedTrimOverlay, which appears after its declaration.
unified_index = timeline.find('private struct TimelineUnifiedTrimOverlay: View')
if unified_index == -1:
    raise SystemExit('TimelineUnifiedTrimOverlay not found')
prefix = timeline[:unified_index]
suffix = timeline[unified_index:]
if update_old not in suffix:
    raise SystemExit('Unified trim update anchor not found')
suffix = suffix.replace(update_old, update_new, 1)
timeline = prefix + suffix

reset_old = '''    private func resetState() {
        trimOrigin = nil
        activeEdge = nil
        lastSnapGuide = nil
'''
reset_new = '''    private func resetState() {
        viewModel.clearTrimPreviewFrame()
        trimOrigin = nil
        activeEdge = nil
        lastSnapGuide = nil
'''
unified_index = timeline.find('private struct TimelineUnifiedTrimOverlay: View')
prefix = timeline[:unified_index]
suffix = timeline[unified_index:]
if reset_old not in suffix:
    raise SystemExit('Unified trim reset anchor not found')
suffix = suffix.replace(reset_old, reset_new, 1)
timeline = prefix + suffix

project = project.replace('MARKETING_VERSION: 1.6.8', 'MARKETING_VERSION: 1.6.9', 1)
project = project.replace('CURRENT_PROJECT_VERSION: 17', 'CURRENT_PROJECT_VERSION: 18', 1)

entry = '''## 1.6.9

### Added

- The large editor preview now shows the exact source frame under the active trim boundary while dragging a clip edge.
- Left-edge trimming previews the frame at the new `trimStart`; right-edge trimming previews the last included frame immediately before the new `trimEnd`.
- Added a cancellable, latest-request-wins trim frame generator so fast edge drags do not display stale frames.

### Changed

- Playback pauses during edge trimming and the normal playhead preview returns immediately after the trim gesture ends.
- Trim preview generation is local with AVFoundation and does not require network access.

'''
if '## 1.6.9' not in changelog:
    changelog = changelog.replace('# Changelog\n\n', '# Changelog\n\n' + entry, 1)

workflow = workflow.replace('# Final clean CI for EditFlow 1.6.8', '# Final clean CI for EditFlow 1.6.9', 1)
workflow = workflow.replace('EditFlow-1.6.8-unsigned.ipa', 'EditFlow-1.6.9-unsigned.ipa')
workflow = workflow.replace('EditFlow-1.6.8-unsigned-IPA', 'EditFlow-1.6.9-unsigned-IPA')

vm_path.write_text(vm)
editor_path.write_text(editor)
timeline_path.write_text(timeline)
project_path.write_text(project)
changelog_path.write_text(changelog)
workflow_path.write_text(workflow)
