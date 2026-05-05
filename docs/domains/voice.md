# Voice Input Domain

Architecture and gotchas for `VoiceInputView` and `VoiceInputConfirmationView`.

## Self-Contained VoiceInputView

`VoiceInputView` manages its own `.sheet(item:)` for confirmation. **No callback chains to parent** — data flows directly within the view.

## VoiceInputConfirmationView Has Its Own NavigationStack

Present via `.sheet()`, **NEVER via `.navigationDestination()`** (nested `NavigationStack` = empty/broken view).

## Edit-Only Mode (`onUpdate`)

`VoiceInputConfirmationView` `onUpdate` mode:
- Pass `onUpdate: ((ParsedOperation) -> Void)?` for edit-only behavior (returns updated `ParsedOperation` without saving)
- `nil` = save mode (legacy)

## TransactionCard Cannot Be Used as Read-Only Preview

⚠️ `TransactionCard` has built-in `.onTapGesture` + `.sheet` — inner gesture intercepts outer.

Build a custom preview card with `Button` + same subcomponents (`IconView`, `FormattedAmountView`).

## Speech Recognition Gotchas

### `cancel()` fires callback with empty/truncated text

⚠️ Guard with:

```swift
guard self.isRecording || self.isStopping else { return }
```

Never overwrite `transcribedText` with empty string.

### Silence detection — text-based VAD

Audio-based VAD is unreliable with background noise. Use **text-based timeout**:
- Reset timer on every `transcribedText` change
- Auto-stop after N seconds of no new text

### Amplitude smoothing

Asymmetric — fast attack (`0.6` weight), slow decay (`0.08`).

Text-driven spikes via `onChange(of: transcribedText)` blended with `0.4/0.6`.

## SiriGlowView Animation

`MeshGradient` (iOS 18+) with `TimelineView(.animation)`.

⚠️ **Read `amplitudeRef.value` directly each frame — no `@State` intermediary** (causes stale values).
