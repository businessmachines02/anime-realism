# The REACT Battle System — Overview

An overhauled reactive defense system that expands on traditional turn-based Pokémon battles.


## Core Resource: Focus Meter

Every Pokémon has a **Focus Meter** (0–100).
- Starts each battle at **50**.
- Regenerates **+15** at the end of any turn where no reactive option was used ("Commit").
- Regenerates **+5** at the end of a turn where a reactive option *was* used.
- This is what stops "always dodge every turn" from being the default — reacting is a spendable resource, not a free roll.

## The Fourth Option: Commit

- **Cost:** 0 Focus
- **Effect:** You take the hit normally (standard damage, standard accuracy check on the attacker's side). No mitigation, no evade.
- **Reward:** Bigger Focus regen (+15 instead of +5), and your own attack this turn is unaffected/undelayed.
- **Why it matters:** banking Focus now to guarantee a Brace-counter or Dodge later against a bigger threat is a real strategic choice, not just "the weak option."

---

## 1. Dodge — *the gambler's option*

| | |
|---|---|
| **Cost** | 25 Focus |
| **Success %** | `clamp(20 + (Spe_def − Spe_atk) × 0.1, 10, 75)` — faster Pokémon dodge more reliably, but never above 75% or below 10% |
| **On success** | Full evade, zero damage taken |
| **Counter (sub-roll on success)** | 30% chance, scales with Speed stat. Weak hit (~40% of a normal attack's power), uses Speed instead of Attack for damage calc — a quick, opportunistic jab |
| **On fail** | Take **130%** damage (caught off-balance) + lose priority next turn (opponent's next move goes first regardless of Speed) |
| **Best against** | Single-hit, single-target physical/special moves. Fast Pokémon's tool of choice. |
| **Countered by** | Multi-hit moves (each hit re-rolls dodge separately, so sustained pressure punishes over-dodging), and moves with innate high accuracy/never-miss effects |

---

## 2. Take Cover — *the attrition option*

| | |
|---|---|
| **Entry cost** | 20 Focus to enter cover |
| **Upkeep** | Free to *stay* in cover |
| **Exit cost** | 10 Focus to emerge and attack |
| **Cover Durability** | Pool = `Defense stat × 1.5`. Depletes when hit while covered. |
| **While covered, choose each turn:** | **Stay** (skip your attack, cover holds/refreshes) or **Emerge** (attack this turn, but you're re-exposed — next incoming hit does 120% damage) |
| **Cover break** | If Durability hits 0, cover shatters — you take that hit's damage in full and are auto-exposed next turn |
| **Cover-piercing moves** | High-BP, AoE, or "explosive" moves (Earthquake, Explosion-type effects) deal **bonus damage to Durability** or ignore cover outright — stops turtling from being a free win |
| **Type flavor bonus** | Ground (dig in), Water (submerge), Ghost (phase out) get **+20% Durability** — good spot for type identity/animation flair |
| **Best against** | Sustained pressure, chip damage, when you need to stall for a switch or status to wear off |

---

## 3. Brace — *the reliable option*

| | |
|---|---|
| **Cost** | 15 Focus (cheapest — the "safe floor" choice, good for newer players) |
| **Call mechanic** | Before the attack resolves, you call the incoming category: **Physical / Special / Status** |
| **On correct call** | Damage reduced by `50% + min(20%, Def_or_SpDef ÷ 10)` — scales with your bulk, caps around 70% reduction |
| **On wrong call** | Take **115–120%** damage (you braced the wrong way — off-balance, though less severely than a failed Dodge). No longer a free "worst case = baseline" option; there's a real bet being made. |
| **Counter (only on correct call)** | 40% base chance, scales with Attack-to-Defense ratio. Power scales with **% damage absorbed** — the harder you tank it, the harder you swing back. **Cooldown: locked for 4–5 turns after triggering** (longer than Dodge's, since it hits heavier) — stops Brace from quietly out-DPSing Dodge over a long fight while keeping its higher per-hit ceiling. |
| **Bonus** | Correct call also reduces incoming status-effect duration/chance by ~30% (you braced for it mentally too) |
| **Best against** | High-accuracy/unavoidable moves, and as a bulky Pokémon's core tool — this is the "wall" archetype's signature play |

---

## 4. Entrench — *the commitment option*

| | |
|---|---|
| **Cost** | 30 Focus upfront, paid once, covers the full duration (no per-turn upkeep) |
| **Duration** | Fixed **2–3 turns**, regardless of stats — everyone gets the same window, so it's not just strictly better for tanks |
| **Mitigation** | Flat reduction, holds steady the entire duration (does *not* deplete like Cover's pool): `50% base + (Def_or_SpDef ÷ 10, capped at 85%)` |
| **Lockout (the real cost)** | While Entrenched, you **cannot** Dodge, Cover, Brace, or attack. You are fully committed — no reacting to anything else that turn. |
| **What gets through anyway** | Status moves land freely, stat-drop moves stack unopposed, hazards/setup go untouched — the opponent can just not attack you and punish the turtle for free |
| **Penetration** | Each incoming attack rolls to penetrate the shell, chance based on **move category**, not a flat number: <br>• Physical moves: higher penetration chance (shells are easier to shoulder through) <br>• Special moves: lower penetration chance (shell resists "energy" better) <br>*(or flip this if it fits your typing philosophy better — the point is the opponent has a real counter-play: pick the right category of move)* |
| **On penetration** | Attack lands at full/normal damage, ignoring Entrench's mitigation entirely for that hit |
| **Counter on penetration** | 15–20% chance, weak/cheap damage, no cooldown needed (already gated by the rare penetration roll) — a "clipped them as they broke through" consolation, not a big payoff like Brace's |
| **Early exit** | Can be broken early voluntarily, refunding a small portion of unused Focus (e.g. 5 per turn remaining) — gives an out if the opponent switches to bait, rather than being locked into a wasted turtle for the full duration |
| **Best against** | Committed, sustained physical (or special, depending on your category split) pressure where you're confident the opponent won't pivot to status/setup — a bold, all-in read rather than a safe default |

---

## Quick Comparison

| | Cost | Risk | Reward Ceiling | Identity |
|---|---|---|---|---|
| **Dodge** | 25 | High (fail = worse than doing nothing) | Full evade + fast weak counter | Speedsters, glass cannons |
| **Take Cover** | 20 (+10 to exit) | Medium (durability can be broken) | Stall + safe re-engagement | Bulky/defensive, type-flavor showcase |
| **Brace** | 15 | Medium (wrong call = 115-120% dmg; counter has a cooldown) | Heavy counter + status resist | Tanks, beginner-friendly |
| **Entrench** | 30 (upfront, covers full duration) | High (locked out of all other reactions for 2-3 turns) | Highest flat mitigation in the game | Committed tanks, "the mountain doesn't move" |
| **Commit** | 0 | None reactive | Best Focus regen | Resource banking, aggressive players |

## Resolved Additions

### Focus Cap Scaling
- **Base cap:** 100 (unchanged from before).
- **Level scaling:** `+1 cap per 2 levels above 50` → a Lv.100 Pokémon caps at 125, a Lv.50 caps at 100. Keeps early/mid-game battles tight and resource-scarce, while late-game/postgame battles (where fights run longer and hit harder) give players more reactive plays to work with.
- **Optional stat tie-in:** let a Pokémon's **base Speed stat** contribute a small bonus (`+1 cap per 20 base Speed over 80`) — reinforces the fantasy that agile Pokémon sustain reactive play longer, and gives Speed a second axis of value beyond turn order and Dodge's success rate.
- These stack: a fast, high-level Pokémon (e.g. Lv.100 Dragapult) could have a noticeably higher ceiling than a slow, high-level tank (e.g. Lv.100 Snorlax) — which is thematically correct and gives Brace-users a reason to lean on the *cheap, reliable* option rather than out-lasting on Focus alone.

### Dodge Counter Cooldown
- After a Dodge-counter triggers, it's **locked for 3 turns** (can't proc again even if Dodge succeeds again in that window — you can still Dodge for the evade, just no bonus counter).
- This caps Dodge's counter DPS well below Brace's, since Brace's heavier counter has no cooldown — it's balanced instead by Brace's coin-flip call mechanic and lower reduction ceiling.
- Net effect: Dodge is the *burst/opportunist* tool (strong early, tapers off), Brace is the *sustain* tool (steady, rewards correct reads over a long fight). Gives the two archetypes distinct rhythm instead of one strictly outscaling the other.

### Unreactable Signature Moves
- Flag a small, curated set of moves as **Unreactable** — cannot be Dodged, Covered, or Braced (though normal type resistance/immunity still applies).
- Gate them behind an existing high-stakes resource so they can't be spammed: tie to **Terastallize/Dynamax/Z-Move-style once-per-battle mechanics**, or a signature move usable only once Focus has been fully drained to 0 (a "desperation finisher" framing — mechanically and narratively fitting).
- Telegraph clearly before use (a charge turn, a distinct animation cue, a UI warning) so the opponent has a real "oh no, brace for impact narratively but mechanically there's nothing to be done" moment — that's the anime beat you're going for, and it only lands if the player *knows* it's coming and still can't stop it.
- Keep the list small (a handful of ace/legendary-tier moves) — if too many moves are unreactable, the whole reactive layer stops mattering.

### Unreactable Moves vs. Take Cover: Durability Absorbs, Then Overflows
- Unreactable moves do **not** fully bypass Cover — a full bypass punishes players for having invested Focus into a Durability setup, which feels bad rather than epic.
- Instead, Unreactable moves deal **250–300% damage to Durability** (vs. the normal cover-piercing bonus damage).
- If Durability **survives**, the player keeps their cover — a meaningful, earned payoff for a well-built tank (especially with the +20% type bonus). This is the "its cover held!?" anime beat.
- If Durability **breaks**, any overflow damage carries through to the Pokémon directly, and cover shatters as normal (auto-exposed next turn).
- Net effect: Unreactable moves are still rare/threatening and usually punch through unprepared defenders, but a defender who specifically built for it gets a real (if uncommon) chance to no-sell the "unstoppable" attack — without ever letting Cover be a *free*, zero-cost counter to the whole category.

### Entrench Duration Scaling
- Duration is **tiered, not linear/unlimited**, and locked in at activation (no extending mid-Entrench):

| Focus Spent | Duration | Note |
|---|---|---|
| 30 (base) | 2 turns | Default |
| 45 | 3 turns | +15 for the 3rd turn |
| 60 | 4 turns | +15 for the 4th turn — **hard cap**, no further extension |

- Hard-capping at 4 turns keeps Entrench a finite, tense commitment rather than an "out-turtle everything" button that would undercut Dodge/Brace/Cover entirely.
- The early-exit refund (5 Focus per unused turn) softens a bad read (e.g., opponent pivots to status turn 1 of a paid-for 4-turn Entrench) without erasing the opportunity cost of the Focus that turn.

---

# Upcoming for future releases

## Growth Layer — Reactive Mastery, Terrain Affinity, Matchup Memory

Everything below is a **modifier layer on top of the base system above** — it nudges success%, mitigation, and Durability, but never replaces the core math. This is what gives a Pokémon a sense of *history*: a mon that's fought 50 battles should feel different from a fresh one, without ever becoming unhittable.

### Reactive Mastery (per-Pokémon, per-option skill growth)

- Each individual Pokémon has four growable stats, 0–100: **Dodge Mastery**, **Brace Mastery**, **Cover Mastery**, **Entrench Mastery**. These belong to the individual mon (like EVs/happiness), not the species.
- **XP source:** earning Mastery XP scales with the threat of what was handled — successfully reacting to a high-BP move nets more XP than reacting to a weak one. Some partial XP is even earned on a *failed* reaction ("learned from getting hit too"), so grinding against trivial attacks isn't the optimal path.
- **Applied bonus:** `bonus = Mastery ÷ 4, capped at +15` to the option's success%/mitigation. Diminishing, not linear — this is the critical guardrail. Without a hard per-option cap, a heavily-played veteran mon becomes literally unhittable, which kills tension instead of building the intended anime "growth" feel.
- **Decay (optional):** Mastery in an option that goes unused for a long stretch can slowly drift down, keeping it feel like a practiced skill rather than a permanent unlock.
- **Separate from "Perfect Execution":** a rare, single-turn critical-success event (bonus action or extra damage that turn) is kept as its own roll, distinct from Mastery XP gain. Coupling them would let a single great roll both win the turn *and* permanently boost future odds — a compounding snowball. Keeping them decoupled keeps each legible on its own.

### Terrain Affinity

- A **Type × Terrain** matrix that flatly modifies each reactive stat, reflecting real anime logic (Flying types struggling to maneuver in caves, Water types thriving near water, etc.):

| Terrain | Boosted | Penalized |
|---|---|---|
| Cave | Rock / Ground / Ghost (Cover, Entrench) | Flying (Dodge — no room to maneuver) |
| Water / Rain | Water (Dodge, Cover) | Fire, Electric (all options) |
| Open Field | Flying, Normal (Dodge) | Ground, Rock (Dodge) |
| Snow / Ice | Ice (all options) | Fire (Entrench — can't dig in) |

- **Flat, capped modifier** (±10–15%), not multiplicative. A multiplicative terrain bonus stacked on top of a Mastery bonus is exactly the kind of double-dip that causes runaway numbers — keep every layer additive and capped.

### Matchup Memory

Two tiers, both **per-Pokémon** (this specific mon's memory, not a global species record):

- **Species memory:** having faced a given species many times grants a small, capped bonus to whichever reactive stat was actually used most against it.
- **Species + Move memory (sharper):** having specifically seen a given species use a given move grants a more specific, slightly higher bonus against that exact combo — this is the "I've seen this exact attack before" anime beat.

Guardrails:
- **Log-scale growth, not linear**: `bonus = min(cap, log(encounters + 1) × k)`. The 5th encounter should matter far more than the 50th, so a player can't simply grind a hard-counter into existence through repetition alone.
- **Small absolute cap**, roughly **+10% total** from memory, applied after Mastery and Terrain — this should feel like an edge, not a solved matchup.
- **Narrative payoff at milestones**, independent of the mechanical bonus — e.g., unique flavor text or an animation cue around the 25-encounter mark ("it tenses — it's seen this move before"), even when the numeric bonus itself is modest. The *feeling* of history can outpace the actual math, which is often where the anime payoff really lives.

### Stacking Guardrail (critical)

Mastery + Terrain + Matchup Memory are all additive modifiers to the same base success%/mitigation numbers from the core system. Without a ceiling, they compound past the point of being fun. **Hard rule: all growth-layer modifiers combined cannot push a stat's total bonus above +15** over its base-system value (e.g., Dodge's base ceiling stays 75%; a fully-grown, favorite-terrain, most-hated-rival mon can approach but never exceed 90%). This keeps a maxed-out veteran genuinely formidable in its best matchup, without ever becoming unbeatable.