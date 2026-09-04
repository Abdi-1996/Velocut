from pathlib import Path

path = Path('EditFlow/EditFlow/Views/Editor/EditorView.swift')
text = path.read_text()

text = text.replace('    @State private var selectedTool: EditorWorkspaceTool = .edit\n', '')

old_iphone = '''    private var iPhoneLayout: some View {
        VStack(spacing: 0) {
            preview
                .frame(minHeight: 225, idealHeight: 280, maxHeight: 330)
                .padding(.horizontal, 8)
                .padding(.top, 4)

            PlaybackControlBar(
                viewModel: viewModel,
                fullScreenAction: { isFullScreen = true }
            )

            if viewModel.hasInlineEditor {
                InlineEditorSettings(viewModel: viewModel)
                    .frame(minHeight: 245, idealHeight: 300, maxHeight: 360)
            } else {
                TimelineView(viewModel: viewModel)
                    .frame(minHeight: 185, idealHeight: 220)

                ContextualEditorBar(
                    viewModel: viewModel,
                    galleryAction: openMainGallery,
                    overlayAction: openOverlayGallery,
                    audioGalleryAction: { showingAudioVideoGallery = true },
                    fileAction: { showingImporter = true }
                )
            }
        }
        .background(Color(red: 0.035, green: 0.035, blue: 0.042))
    }
'''

new_iphone = '''    private var iPhoneLayout: some View {
        VStack(spacing: 0) {
            preview
                .frame(
                    minHeight: viewModel.hasInlineEditor ? 190 : 225,
                    idealHeight: viewModel.hasInlineEditor ? 220 : 280,
                    maxHeight: viewModel.hasInlineEditor ? 250 : 330
                )
                .padding(.horizontal, 8)
                .padding(.top, 4)

            PlaybackControlBar(
                viewModel: viewModel,
                fullScreenAction: { isFullScreen = true }
            )

            TimelineView(viewModel: viewModel)
                .frame(
                    minHeight: viewModel.hasInlineEditor ? 145 : 185,
                    idealHeight: viewModel.hasInlineEditor ? 165 : 220,
                    maxHeight: viewModel.hasInlineEditor ? 185 : 260
                )

            Group {
                if viewModel.hasInlineEditor {
                    InlineEditorSettings(viewModel: viewModel)
                        .frame(height: 220)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    ContextualEditorBar(
                        viewModel: viewModel,
                        galleryAction: openMainGallery,
                        overlayAction: openOverlayGallery,
                        audioGalleryAction: { showingAudioVideoGallery = true },
                        fileAction: { showingImporter = true }
                    )
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.16), value: viewModel.hasInlineEditor)
        }
        .background(Color(red: 0.035, green: 0.035, blue: 0.042))
    }
'''

if old_iphone not in text:
    raise SystemExit('iPhone layout source block not found')
text = text.replace(old_iphone, new_iphone)

start = text.find('enum EditorWorkspaceTool: String, CaseIterable, Identifiable {')
if start != -1:
    end = text.find('private struct PreviewMediaSurface: View {', start)
    if end == -1:
        raise SystemExit('PreviewMediaSurface anchor not found')
    text = text[:start] + text[end:]

start = text.find('private struct EditorToolDock: View {')
if start != -1:
    end = text.find('private struct MediaSidebar: View {', start)
    if end == -1:
        raise SystemExit('MediaSidebar anchor not found')
    text = text[:start] + text[end:]

path.write_text(text)

project = Path('EditFlow/project.yml')
project_text = project.read_text()
project_text = project_text.replace('MARKETING_VERSION: 1.8.0', 'MARKETING_VERSION: 1.8.1')
project_text = project_text.replace('CURRENT_PROJECT_VERSION: 20', 'CURRENT_PROJECT_VERSION: 21')
project.write_text(project_text)

changelog = Path('EditFlow/CHANGELOG.md')
changelog_text = changelog.read_text()
entry = '''## 1.8.1

### Fixed

- The timeline now remains visible when opening Speed Ramp, Effects, Transition, or Animation on iPhone.
- Replaced the old full lower-area mode switch with one CapCut-style bottom interaction region: contextual object tools and nested settings alternate in the same slot.
- The back button inside nested settings now returns to the selected clip's contextual tools without deselecting the clip.
- Removed obsolete workspace-dock code so there is only one runtime bottom tool system.

### Changed

- The preview and timeline compact slightly while nested settings are open so the selected clip remains visible and editable above the single bottom settings area.

'''
if '## 1.8.1' not in changelog_text:
    changelog_text = changelog_text.replace('# Changelog\n\n', '# Changelog\n\n' + entry, 1)
changelog.write_text(changelog_text)
