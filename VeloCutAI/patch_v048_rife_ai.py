from pathlib import Path
import re

# 1) Replace the old non-AI Smooth mode with the real RIFE-backed AI Smooth mode.
ui = Path('VeloCutAI/VeloCutAI/VeloCutV45UI.swift')
u = ui.read_text()
if 'case smooth = "Smooth"' not in u:
    raise RuntimeError('SpeedProcessingMode Smooth case not found')
u = u.replace('case smooth = "Smooth"', 'case aiSmooth = "AI Smooth"', 1)
ui.write_text(u)

# 2) Patch the generated v0.4.7 editor model/UI.
p = Path('VeloCutAI/VeloCutAI/VeloCutV4.swift')
s = p.read_text()

# All old Smooth remap checks now mean AI Smooth. It still keeps the denser 120-step
# time remap, then RIFE synthesizes the missing frames after the normal export.
s = s.replace('.smooth', '.aiSmooth')

# Model settings. RIFE v4.26 is bundled by the Swift package; Balanced is the safe
# default for iPhone, with optional Fast/HQ and 2x/4x interpolation.
anchor = '@Published var projectLoopEnabled = false'
if anchor not in s:
    raise RuntimeError('v0.4.7 projectLoopEnabled state not found')
s = s.replace(
    anchor,
    anchor + '\n    @Published var aiInterpolationFactor = 2\n    @Published var aiInterpolationQuality: VeloCutAIQuality = .balanced\n    @Published var aiInterpolationStatus = ""',
    1
)

# Make the Curve Editor processing selector wide enough for AI Smooth and show
# factor/quality settings only when the AI mode is selected.
s = s.replace('.pickerStyle(.segmented)\n                    .frame(width:150)', '.pickerStyle(.segmented)\n                    .frame(width:210)', 1)

old_label = '''Text(model.speedProcessingMode == .aiSmooth ? "Smooth remap" : "Fast preview")
                        .font(.system(size:8))
                        .foregroundStyle(.secondary)'''
new_label = '''Text(model.speedProcessingMode == .aiSmooth ? "RIFE v4.26 AI" : "Fast preview")
                        .font(.system(size:8))
                        .foregroundStyle(.secondary)'''
if old_label not in s:
    raise RuntimeError('Curve processing status label not found')
s = s.replace(old_label, new_label, 1)

settings_anchor = '''                .padding(.horizontal,14)

                VStack(spacing:4) {
                    Slider('''
settings_block = '''                .padding(.horizontal,14)

                if model.speedProcessingMode == .aiSmooth {
                    VStack(alignment:.leading,spacing:7) {
                        HStack(spacing:8) {
                            Picker("AI Frames",selection:$model.aiInterpolationFactor) {
                                Text("2×").tag(2)
                                Text("4×").tag(4)
                            }
                            .pickerStyle(.segmented)
                            .frame(width:120)

                            Picker("AI Quality",selection:$model.aiInterpolationQuality) {
                                ForEach(VeloCutAIQuality.allCases) { q in Text(q.rawValue).tag(q) }
                            }
                            .pickerStyle(.menu)
                            Spacer()
                        }
                        HStack(spacing:5) {
                            Image(systemName:"cpu")
                            Text("Practical-RIFE v4.26 • Metal • локально на iPhone")
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal,14)
                }

                VStack(spacing:4) {
                    Slider('''
if settings_anchor not in s:
    raise RuntimeError('Curve AI settings insertion point not found')
s = s.replace(settings_anchor, settings_block, 1)

# Replace export completion with an optional RIFE pass. Normal export stays exactly
# as before in Fast mode. AI Smooth post-processes the exported video and then muxes
# the original audio back in.
old_export = '''await withCheckedContinuation { c in session.exportAsynchronously { c.resume() } }; guard session.status == .completed else { throw session.error ?? NSError(domain:"VeloCut",code:3) }; exportedURL=out; exportProgress=1'''
new_export = '''await withCheckedContinuation { c in session.exportAsynchronously { c.resume() } }
            guard session.status == .completed else { throw session.error ?? NSError(domain:"VeloCut",code:3) }
            exportTimer?.invalidate()
            if speedProcessingMode == .aiSmooth {
                aiInterpolationStatus = "RIFE AI"
                exportProgress = 0.72
                let aiOut = try await VeloCutRIFEProcessor.interpolateVideo(
                    inputURL: out,
                    factor: aiInterpolationFactor,
                    quality: aiInterpolationQuality
                ) { [weak self] value in
                    Task { @MainActor in
                        guard let self else { return }
                        self.exportProgress = 0.72 + min(max(value,0),1) * 0.28
                        self.aiInterpolationStatus = String(format:"RIFE AI %d× • %d%%",self.aiInterpolationFactor,Int(value*100))
                    }
                }
                exportedURL = aiOut
                aiInterpolationStatus = ""
            } else {
                exportedURL = out
            }
            exportProgress = 1'''
if old_export not in s:
    raise RuntimeError('startExport completion block not found')
s = s.replace(old_export, new_export, 1)

# Export overlay explains when the extra AI render pass is running.
old_overlay = 'Text("Экспорт \\(Int(model.exportProgress*100))%").font(.headline)'
new_overlay = 'Text(model.aiInterpolationStatus.isEmpty ? "Экспорт \\(Int(model.exportProgress*100))%" : model.aiInterpolationStatus).font(.headline)'
if old_overlay in s:
    s = s.replace(old_overlay, new_overlay, 1)

p.write_text(s)
print('Applied VeloCut v0.4.8 Practical-RIFE AI Smooth integration')
