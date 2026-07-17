# Related work

* REQUIRED Chobby PR: https://github.com/beyond-all-reason/BYAR-Chobby/pull/1041
* REQUIRED Engine PR: https://github.com/beyond-all-reason/RecoilEngine/pull/3032
* REQUIRED Teiserver: https://github.com/beyond-all-reason/teiserver/pull/1280
* 📐 ARCHITECTURE: [Game Controllers & Policies](https://github.com/beyond-all-reason/Beyond-All-Reason/issues/8018) — the design rationale behind this PR
* 📐Original Issue (Chobby): https://github.com/beyond-all-reason/BYAR-Chobby/issues/1040
* [Co-op proposal Discord thread](https://discord.com/channels/549281623154229250/1402416120211968000/1406489698565755000)

### 📚 Stacked split— review bottom-up

- **1/7 · Transfer library (enums, comms, serialization, test infra) (#8125)** ← start here
- 2/7 · Modes & economy boundary (presets, waterfill, share ledger) (#8126)
- 3/7 · Policies (context → policy → policy_result → action) (#8123)
- 4/7 · Transfer runtime (controllers, economy boundary, gadget swap) (#8062)
- 5/7 · Tech Core / Keystone (#8063)
- 6/7 · Sharing Tab UI (#8064)
- 7/7 · Game modes export (widget, headless startscript, CI workflow) (#8095)

Each PR merges into the one below it; together they reproduce the `sharing_tab` branch (bar one intentional change — `index.lua` lazy-loads the mode helpers).

# The idea

> Full architecture & rationale — controllers, policies, the Waterfill solver, and the policy DSL it unlocks — is written up in **[Beyond-All-Reason#8018: Game Controllers & Policies](https://github.com/beyond-all-reason/Beyond-All-Reason/issues/8018)**. Short version:

The engine stops being the economy authority and becomes the economy **data plane** for team redistribution. It keeps measuring (income, pull, expense, per-frame excess) and exposes that state through an API. A registered synced-Lua controller pulls a snapshot on its own cadence, runs redistribution, and writes back its own economy stats directly. Unit transfers, team giveaways (`GiveEverythingTo`), and `/take` are replaced by game-side gadgets; native overflow sharing is the one piece behind a flag — `nativeExcessSharing = false` hands it to the Lua controller.

On top of that boundary, sharing is configured by **modes** — named presets that set, lock, and hide the individual modoptions. The lobby (Chobby) presents them; the game enforces them. Each modoption stays cardinal (one knob, one behavior) so modes compose them freely.

# Modes

**Enabled** *(default)* — all sharing on, no tax. Today's game, unchanged.
<img width="1185" height="577" alt="image" src="https://github.com/user-attachments/assets/f9e8520d-9eae-4cca-8de5-b9d717d04f57" />

**Disabled** — no unit or resource sharing
<img width="1176" height="570" alt="image" src="https://github.com/user-attachments/assets/c5005a44-f1e3-473b-ab28-9c267144902e" />

**Easy Tax** — anti-co-op preset. Taxes resource sharing, assist, and resurrection; gifted eco buildings are stunned and mobile constructors build-delayed, so you can't dodge the tax by handing over production. `/take` runs on a stun delay.
<img width="1326" height="696" alt="image" src="https://github.com/user-attachments/assets/2070367d-f1fd-4b9f-ab45-5aa4a0fc99c1" />

**Tech Core** — tech levels gate what you can build; you raise your level by constructing **Keystone** buildings. Unit sharing and resource tax both scale with tier (e.g. constructors become shareable at T2; tax eases as you climb). `/take` runs on a 60s delay for Resource buildings (the Take Delay Category in the screenshot below).
<img width="1326" height="918" alt="image" src="https://github.com/user-attachments/assets/1705b70e-f5e3-4b4d-8229-f7a4c3acc9a0" />

**Customize** — every knob editable; roll your own policy.

Note: This is the one mode that preserves the previous mode's values when switching to it, so you can switch from tech core to customize and customize will behave exactly like tech core.

For players and mode developers, Customize provides a lot of benefits for this design:
1. Removes a lot of complexity from the other modes, allowing us to hide/lock the opinionated mode without impacting customization of any new capabilities those modes may bring to the table.
2. Lets people roll their own fully customizable mode, if they want.
3. Gives us all the knobs needed to prove that each diverse mod option is actually orthogonal during testing.
4. Lets users intuitively understand how this works under the covers and that the individual mod options are the implementation details for each top-level mode.

<img width="1353" height="970" alt="image" src="https://github.com/user-attachments/assets/b693ad5c-a63b-4d08-814d-af77d8c0a358" />

# Other changes

- **Geo/Mex upgrades fixed** (credit Hobo): the unit-sharing filter now lets "Utility" (resource) buildings transfer, so you can upgrade an ally's mex. Could become its own toggle later (#1040), out of scope here.
- **`/take` moved into the game** (was engine-native), which is what enables the delay/category take modes above.
- **Invalid-unit feedback**: units a mode disallows show in tooltips and highlight when you hover an ally in the player list.

# Demos

* [Sharing modes](https://www.youtube.com/watch?v=SGxRAC0BykQ)
* [Unit sharing functionality](https://youtu.be/yn9U-Q-35Oo)
* [Invalid-unit highlighting](https://youtu.be/37eQF3YlZBE)

# LLM usage

Tons of AI usage, but this started on much earlier models so I really had to beat it into shape and the code is clearly my style of decompositional functional programming, and that doesn't happen accidentally.
