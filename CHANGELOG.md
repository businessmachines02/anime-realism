# Changelog

## 3.1.8 — FIELD later-fight abort (macOS / Love 11.5)

Long FIELD fights could kill the Love window with **no error screen**. Different moves, usually later in the fight, often around close-the-gap or the next cue after a punch. Terminal showed `exit(1)` or a native crash.

Two ways the window died, both looking the same to the player:

1. **LuaJIT native abort.** Love 11.5’s LuaJIT 2.1.0 on ARM64 macOS SIGSEGV’d inside the allocator (`unlink` of a free-list chunk with a garbage pointer). FIELD’s per-frame walk/pose loop is a hot JIT path. Aug 12 crash report: `gen1recomp.app` 0.1.69, main thread, LuaJIT, no Lua traceback.
2. **Lua error Love cannot display.** An error during voxel `beginScene` / engine update never reaches the Love error screen. `main` returns 1. lldb stopped at `exit` with an empty stack (Love had already returned). Removing the FIELD swallow brought this death back even with JIT off.

### Fixes that have to stay together

- **`jit.off()` while a FIELD fight is live, `jit.on()` when it ends** (`field/session/lifecycle.lua`). Interpreter-only for the fight. This is what stopped the allocator SIGSEGV in long Pewter Gym fights.
- **Do not rethrow Lua errors on FIELD.** `pcall` update / `input.step` / letterbox / `drawWorld`; log `[ar] ERR` and keep going. Rethrow mid-voxel is silent `exit(1)`.
- **One present-clock tick per display frame, never inside `drawWorld`.** Double ticks made attacks bouncy and collapsed punch + withdraw + next cue onto one voxel pose. Ticking during pose mutates `ow.entities` while Dramatic Shape is drawing (NaN/nil → GL abort).
- **Skip classic SGB / wavy / `applyHitFx` over the live voxel world.** Shake and the zone shader on top of 3D aborted Love the same way (window gone, no screen).
- **Battler `pose()` is voxel-safe.** Finite px/py, cardinal facing, dummy `sprite.def` + `resolveImage`. Dramatic Shape crashes native if those are nil or non-finite.

### Cleanup (not the fix)

Crash-hunt extras were removed: `ar-trail.log`, per-frame position dumps, `[ar] TRACE` spam. Numbered install flags (`_arFbvInputStep6`, `_arFbvUpdate31`, …) collapsed to **one flag per wrap**.
