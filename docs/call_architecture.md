# Call layer architecture

Port of the RN VibeCalling call system. These documents are the spec:
- **UI:** `$SCRATCH/spec_call_ui.md`
- **Logic, APIs, timers, edge cases E-1…E-94:** `$SCRATCH/spec_call_logic.md`
- **Native, push, CallKit, Android, FCM:** `$SCRATCH/spec_call_native.md`

`$SCRATCH` = `/private/tmp/claude-501/-Volumes-Untitled-VB-ALL/2a05f123-d729-4eeb-869a-a90854c224cf/scratchpad`.

The memory notes `voip-callkit-edge-cases.md` (in `~/.claude/projects/-Volumes-Untitled-VB-ALL/memory/`) list the hard-won iOS CallKit and PushKit rules. Every one of them must survive.

## Layers and ownership

```
lib/app/callscreen/
  call/                         UI: incoming screen, call screen, header, body,
                                controls, PiP tile, pulse, safety panel,
                                feedback sheet, callback sheet, permission bar,
                                return-to-call bar (+ call/helper/ for screen-only logic)
  helper/
    call_session.dart           CONTRACT (models): CallPhase, CallRole, CallPeer, CallSession, CallMedia
    call_controller.dart        CONTRACT (implemented): the one call, guarded transitions, elapsed timer
    call_actions.dart           CONTRACT: user actions (UI calls; logic implements)
    call_signals.dart           CONTRACT: push and native signals (push layer calls; logic implements)
    call_platform.dart          CONTRACT: native call UI (logic calls; push and native layer implements)
    engine/call_engine.dart     CONTRACT: Agora singleton (UI reads media, rtc, channelId and calls the toggles)
    state/ …                    logic: constants, dedup, durable store
    …                           logic: payload, ringtone, permissions, navigator, timers, flows
    native/ …                   push and native layer: bridge, flutter_callkit_incoming, background isolate…
    push/ …                     push and native layer: FCM, classifiers, local notifications, tap routing…
  call_flow.dart                push and native layer: boot wiring (init, listeners, reconcile)
```

| Area | Owner |
| --- | --- |
| `lib/app/callscreen/call/**`, the router entries for `/call` and `/call/incoming`, the return-to-call bar in Home, `assets/i18n/*/call.json` UI keys, `test/ui/call_*` | **call-ui** |
| Everything in `helper/` except `native/` and `push/`, `lib/app/api/callscreen/**`, `listingflow/profile/helper/call_start.dart`, history redial, `test/call/logic_*` | **call-logic** |
| `helper/native/**`, `helper/push/**`, `call_flow.dart`, `lib/main.dart`, `ios/**`, `android/**`, the Firebase config files, `push_api.dart` / `auth_api.dart` token fields, `deep_links.dart` push extensions, `test/call/push_*` | **push-native** |

Contract files can be extended, but signatures are never renamed or removed. The implementer replaces each `// TODO(core)` body. `pubspec.yaml` is frozen: every package is already in, so ask the coordinator before adding one.

## Decisions (where RN was buggy or a spec left a choice)

1. **Back chevron on the call screen** → `CallActions.minimize()`. The call keeps running, Home shows a "return to call" bar, and the engine is not parked while a call is live. In RN, back silently dropped the call.
2. **Call screens always draw dark, with light status-bar icons.** Accent colours follow `context.colors.accent`, as RN does with `brand.rose`.
3. **Callback sheet:** a solid `modalCard` background, like the existing safety prompt (RN's 4 % white was see-through).
4. **Feedback "Block"** → on success, exit to Home (RN stranded the user on the ended screen).
5. **Exit after a call:** the caller goes to Discover with the host profile re-opened; the receiver just goes to Home (RN re-opened the receiver's own profile).
6. **The timer lives in `CallController.elapsed`** (wall clock), so it survives screen remounts.
7. **Timers RN lacked** (the backend still owns the truth):
   - an outgoing no-answer fallback at **60 s** → normal caller hang-up;
   - an in-app incoming fallback at **60 s** → local dismiss, no API;
   - remote dropped (Agora offline reason 1) → **30 s** grace, then hang-up;
   - Agora RECONNECTING for more than **30 s** → hang-up;
   - Agora token expiry (3600 s from initiate, no renew) → hang-up on `onTokenPrivilegeWillExpire`.
8. **Max duration (spec §9.5).** Cash balance read at connect.
   - `maxSeconds = floor(cash / rate) * 60`, end at `maxSeconds − 20 s` (the server bills from the receiver's earlier `/UpdateCall`, and Callend is sent before the Agora leave).
   - Toast at 5 minutes left (`call:low_balance_warning`).
   - Skipped for company callers and rate 0.
   - `LOW_BALANCE_WARNING` and `CALL_ENDED_LOW_BALANCE` pushes are hints; teardown comes from `CALL_ENDED`.
9. **Callend.** `endedById` is always set.
   - A caller cancelling before connect sends **no `status`** (E-92: the server derives `missed` while the call is pending and bills it if it is already ongoing).
   - A receiver decline sends `declined`; a connected call sends `completed`.
   - Busy rows are never ended (E-82).
10. **`/UpdateCall`** sends `answeredDeviceId` = the stable install id (`DeviceInfo`). `{alreadyOngoing: true}` is fine for the caller and the answering device (E-76, E-86).
11. **Cold-start status check** uses `GET /calls?filters[id][$eq]=…` (E-85). `CallStatus` gains `forceCompleteByAdmin` (`"force complete by admin"`), which counts as closed.
12. **`CALL_RINGING`** is a caller-side status and never rings (E-75). **`CALL_ANSWERED_ELSEWHERE`** is ignored by the device that answered (E-76).
13. **Expert presence probe** → `POST /expert-profiles/heartbeat` when the user is an expert (CE does this; RN never answered).
14. **Ringtones:** `audioplayers`, following CE's proven iOS audio-context rules. Silencing never throws and never touches `AVAudioSession` (mem #2).
15. **iOS:** Dart never calls `showCallkitIncoming` / `startCall` / `endCall` / `hideCallkitIncoming`. Native owns every CallKit report (spec_call_native §2.9). The call logic ends the native UI only through `CallPlatform.instance.endNativeCall`.
16. **Low-balance alert keeps two buttons**, both going to the wallet route. A third "Transfer" button and the transfer screen come with the wallet work.
17. **Second, different ring during a live call** → ignored (`CallController.receive` returns false). The backend busy check already stops most of these.

## Seams

- **UI → logic:**
  - read `CallController.instance.session` and `.elapsed`, and `CallEngine.instance.media`, `.rtc`, `.channelId`;
  - act through `CallActions.*` and the `CallEngine` toggles;
  - `CallSignals.callbackRequest` drives the callback sheet.
- **Push and native → logic:** `CallSignals.*`, with raw maps. The logic normalises payloads (spec_call_logic §5.5, §12.2-3).
- **Logic → native:** `CallPlatform.instance.*`. Push and native installs its implementation at boot.
- **Navigation:** the logic routes with `appRouter` and `AppRoutes.call` / `AppRoutes.incomingCall`. It waits for the router (pending-slot / 2 s hold rule) and never touches widgets.

## Tests

- No platform plugin may run in widget tests. Video views are built only when `media.engineReady` is true.
- `CallController.instance.debugSet(...)` and `CallEngine.instance.debugSetMedia(...)` drive the UI in tests.
- Logic tests use the fake Dio adapter pattern (`test/ui/*`).
