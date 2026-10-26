# AGENTS.md — Cyberpunk 2077 Decoupled Aim Mod

Instructions for AI coding agents working in this repository. Read this file fully before doing anything.

---

## 0. Fill these in (human: edit once, agent: treat as ground truth)

| Placeholder | Value |
|---|---|
| `<ModName>` | `DetachedReticle` *(rename freely, then update everywhere)* |
| `<GAME_ROOT>` | `E:\Cyberpunk 2077` *(edit to your install path)* |
| Game version the reference dump was made from | `TODO — e.g. 2.xx` |

---

## 1. Project intent

Modify Cyberpunk 2077's **aiming system** so the camera's aim direction is **decoupled** from the weapon's physical orientation.

Target behavior:

1. **Camera reticle** shows the *intended aim point* (where the camera is looking).
2. A **separate weapon reticle** shows where the gun is *physically pointing*.
3. The weapon **rotates toward the camera's aim point** with realistic movement and a slight delay (smoothed, not instant).
4. **Shots originate from the weapon's muzzle**, travelling along the weapon's actual orientation, not from the camera along the camera's direction.

### Design considerations (to resolve, not assume)

- **Parallax / convergence:** the muzzle is offset from the camera. Decide whether the weapon aims at the camera's trace hit point so shots converge on the reticle at range, and how this behaves at close range.
- **Smoothing model:** spring/damper vs. slerp vs. rate-limited rotation. Must be framerate-independent.
- **Obstruction:** behavior when the muzzle is blocked by geometry or cover while the camera is clear.
- **Scope:** player-only. NPC behavior must remain untouched unless research shows it is unavoidable.
- **Excluded contexts:** melee, vehicles, cyberware weapons, scanning, throwables, etc. — decide explicitly per context.
- **Compatibility:** other mods wrapping the same methods must keep working.

Note: The intent is not to use Third person camera mod or making the game third person shooter! it is to decouple the weapon's physical orientation from the camera's aim direction. It should work in both first person and third person camera. and it should work for all projectile-based weapons.

---

## 2. Working phases — do not skip ahead

**Phase 0 — Research (read-only).** Understand how the game currently handles weapons, aiming, firing, and projectiles. Output goes to `docs/research/`. **Do not write mod code in this phase.**

**Phase 1 — Feasibility.** Based on the research, state clearly which parts are achievable in redscript/TweakXL and which need native code (RED4ext plugin) or are not feasible. Get human approval on the approach before implementing.

**Phase 2 — Prototype.** Smallest possible change that proves one piece (e.g. reading the muzzle transform, or moving the projectile origin).

**Phase 3+ — Iterate** (weapon rotation, dual reticle, polish, compatibility).

If asked to jump to implementation before Phase 1 is approved, remind the human and ask.

### Phase 0 research questions

- Which classes/methods run from "fire pressed" to "bullet/hit exists"? List them in call order.
- Which of those are **script-side** (have bodies in the dump) vs. **`native`** (signature only, implemented in the engine)?
- How is the weapon's aim/fire direction determined? Where is the camera's aim data read?
- How is the muzzle represented (slot, component, transform)? Can script code read its world transform?
- How are hitscan vs. projectile weapons distinguished? What does `TweakDB` define for fire modes/projectiles?
- How is the on-screen reticle driven (ink/UI controllers)? Can a second reticle be added?
- How does the player's upper-body/weapon pose get driven (animation graph features vs. script)?

Write findings to `docs/research/weapon-fire-flow.md` with **file path + symbol names** for every claim.

---

## 3. Repository layout

The repo mirrors the game directory so the repo contents **are** the release.

```
/
├── AGENTS.md
├── README.md
├── .gitignore
├── docs/                      # design notes + research (tracked)
│   └── research/
├── r6/
│   ├── scripts/<ModName>/     # .reds files (tracked)
│   └── tweaks/<ModName>/      # TweakXL .yaml / .xl files (tracked, if needed)
├── red4ext/plugins/<ModName>/ # only if a native plugin becomes necessary
│
├── reference/                 # NOT tracked — local only
│   ├── game-scripts/          # decompiled vanilla scripts (read-only)
│   └── wiki/                  # optional local copies of wiki pages (read-only)
└── dist/                      # NOT tracked — release zips
```

### Workspace roots in the IDE (multi-root)

1. This repo (writable)
2. `<GAME_ROOT>\red4ext\plugins\Codeware\Scripts` (read-only)
3. `<GAME_ROOT>\red4ext\plugins\ArchiveXL\Scripts` (read-only)
4. `<GAME_ROOT>\red4ext\plugins\TweakXL\Scripts` (read-only)
5. `<GAME_ROOT>\tools\redmod\tweaks` (read-only; vanilla `.tweak` files, requires REDmod DLC)

---

## 4. Source of truth

Use in this priority order:

1. `reference/game-scripts/` — decompiled vanilla scripts. **Authoritative for what exists.**
2. Dependency script folders (Codeware, TweakXL, ArchiveXL) — authoritative for their APIs.
3. `reference/wiki/` and <https://wiki.redmodding.org/> — language rules and patterns. Pages are available as Markdown by appending `.md` to the URL.
4. Your own memory — **lowest priority; never sufficient alone.**

### Regenerating the vanilla dump

```
redscript-cli decompile -i "<GAME_ROOT>\r6\cache\final.redscripts" -o reference\game-scripts
```

Flag names and the input file name have changed between redscript versions — run `redscript-cli --help` and verify before relying on this. Regenerate after **every game patch** and update the version in section 0.

---

## 5. Rules

### Truthfulness (most important)

- **Never invent** class names, method names, fields, enums, TweakDB records, or engine behavior. Every symbol you use must be found in `reference/game-scripts/` or a dependency's scripts. Quote the file path when you cite it.
- If you can't find something, say so. Do not guess a plausible name.
- Distinguish clearly between **verified** (seen in the dump), **inferred**, and **unknown**.
- `native` functions: you can see their signature, **not** their behavior. Do not claim to know what they do internally.
- Cyberpunk's shooting pipeline may be largely native. If research shows the required behavior can't be reached from script, **say so plainly** and propose alternatives (e.g. a RED4ext plugin) instead of forcing a hack.

### redscript

- redscript has **Swift-like syntax but is not Swift.** Don't assume Swift APIs, generics, optionals, or visibility rules.
- Prefer **`@wrapMethod`** (calls `wrappedMethod()`) so other mods can coexist. Use `@addMethod` / `@addField` to extend classes. **Avoid `@replaceMethod`** unless there is no alternative, and justify it in a comment.
- Check whether another installed mod already patches the same method (`<GAME_ROOT>\r6\scripts\`), since conflicts are likely around aiming/weapons.
- Keep patches **small and local**. Don't copy large blocks of vanilla code into the repo.
- Scripts without a `module` statement go into the global scope; use a module for new self-contained classes.
- Generic skeleton (names are placeholders):

```swift
@wrapMethod(SomeVanillaClass)
protected func SomeVanillaMethod() -> Void {
  wrappedMethod();
  // mod logic here
}
```

### Safety and scope

- **Never modify** anything under `reference/`.
- **Never write** into `<GAME_ROOT>` outside of an explicit, human-approved deploy step. Develop in the repo; deploy by copying `r6/` (and `red4ext/` if used) into the game folder.
- **Do not commit** game files, decompiled CDPR scripts, extracted assets, or archives. (`reference/` is git-ignored for this reason.) Short snippets in research notes for citation are fine; bulk copies are not.
- Don't add new dependencies without asking. Required dependencies must be listed in `README.md`.
- Don't touch `.gitignore` to "fix" an ignored file — ask first; the ignore rules are deliberate (whitelist-style).

### Working style

- Ask before making big design decisions (smoothing model, convergence behavior, native vs. script).
- Keep responses concrete: file paths, symbol names, short diffs.
- When a change can break other mods or save games, flag it.
- Record decisions and open questions in `docs/`.

---

## 6. Dependencies

| Dependency | Needed for | Required? |
|---|---|---|
| redscript | compiling `.reds` | Yes |
| RED4ext | script extender, native plugins | Yes |
| Codeware | script utility library | Yes (verify actual use) |
| TweakXL | TweakDB edits | Only if tweaks are used |
| ArchiveXL | custom assets | No (only if assets are added) |
| Cyber Engine Tweaks | in-game console / tweak inspection for dev | Dev only |
| WolvenKit | inspecting entity/appearance files (muzzle slots, etc.) | Dev only |

Update this table as the design firms up.

---

## 7. Testing and debugging

- Compile errors/warnings: `<GAME_ROOT>\r6\logs\redscript_rCURRENT.log` (redscript compiles on game start).
- RED4ext and CET write their own logs under `<GAME_ROOT>\red4ext\logs\` and `<GAME_ROOT>\bin\x64\plugins\cyber_engine_tweaks\`.
- Use CET's console and tweak editor to inspect live values. Verify any logging function exists in the dump before using it.
- After every game update: regenerate `reference/game-scripts/`, re-check the methods this mod wraps, and note the tested game version in `README.md`.

---

## 8. Release

- The repo layout equals the game-folder layout. A release is a zip of the tracked mod folders (`r6/`, plus `red4ext/` if used) with `README.md`, built into `dist/`.
- Release contains **only** mod files: no `reference/`, no `docs/`, no dumps, no logs.
