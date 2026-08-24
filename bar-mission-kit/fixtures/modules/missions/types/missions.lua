---@meta actions

--- Mission files must load identically in the synced sandbox (which strips
--- rawset) and in busted.

--- Alias names are LOAD-BEARING beyond the checker: the mission kit derives its
--- semantic model from them (alias -> slot semantic, literal unions -> editor enums).
---@alias UnitDefName string unit def name, e.g. "armpw"
---@alias MissionUnitName string roster unit name, declared by units.lua Named(...)
---@alias MissionUnitGroup string roster group name, declared by units.lua Grouped(...)
---@alias ObjectiveName string
---@alias MissionTeamRole "player"|"enemy"|"gaia" spawn-time team role, resolved at arm
--- Wall-clock seconds, never frames. An alias so an editor can name the unit the
--- author is typing in; the DSL converts using the engine's own tick rate.
---@alias MissionSeconds number

--- CLOSED BY TYPE so the checker flags typos across every inputs/OnEvent consumer.
---@alias MissionEventName
---| "UnitFinished"
---| "UnitDestroyed"
---| "UnitGiven"
---| "UnitTaken"
---| "UnitEnteredLos"
---| "mission.objective_changed"
---| "waves.wave_spawned"
---| "waves.wave_cleared"
---| "waves.boss_spawned"
---| "waves.boss_defeated"

--- inputs name bus events (nil = poll every cadence). Captures configuration,
--- never progress (progress lives in engine state, the savegame rule).
---@class MissionCondition
---@field evaluate fun(ctx: MissionContext): boolean
---@field inputs MissionEventName[]|nil events that can change this answer; nil = poll every cadence

--- Unit destroyed/spotted answers are latched: once true, stay true.
---@class MissionContext
---@field GetUnitDefCount fun(teamID: integer, unitDefName: string): integer count of finished units of that def
---@field IsObjectiveComplete fun(name: string): boolean
---@field IsUnitDestroyed fun(name: string): boolean
---@field IsUnitSpotted fun(name: string, allyTeamID: integer): boolean
---@field TransferGroup fun(groupName: string, teamID: integer)
---@field Protect fun(name: string) combat-module protection by roster name
---@field Unprotect fun(name: string)
---@field StartWaves fun(request: table) waves-module pressure, by pack
---@field StopWaves fun(pack: string)
---@field SetWaveIntensity fun(pack: string, intensity: number)
---@field SurgeWaves fun(pack: string)
---@field WaveStatus fun(pack: string): WaveStatus|nil
---@field frame integer current game frame

---@class MissionEffect
---@field execute fun(ctx: MissionContext)

--- Complete implies Reveal. Title/CompletedWhen/When/RevealedWhen/Foreshadow chain
--- in objectives.lua ONLY, the way Spawn belongs to units.lua.
---@class MissionObjective
---@field Complete fun(): MissionEffect
---@field Reveal fun(): MissionEffect
---@field IsComplete fun(): MissionCondition
---@field Title fun(title: string): MissionObjectiveDeclaration objectives.lua sandbox only
---@field CompletedWhen fun(condition: MissionCondition): MissionObjectiveDeclaration objectives.lua sandbox only
---@field RevealedWhen fun(condition: MissionCondition): MissionObjectiveDeclaration objectives.lua sandbox only
---@field Foreshadow fun(): MissionObjectiveDeclaration objectives.lua sandbox only

--- Declaration order gates reveal ONLY; completion gating stays explicit, via When.
---@class MissionObjectiveDeclaration
---@field Title fun(title: string): MissionObjectiveDeclaration display wording; defaults to the id with underscores as spaces
---@field CompletedWhen fun(condition: MissionCondition): MissionObjectiveDeclaration one way to complete; a second CompletedWhen is another way (OR), each compiling to its own trigger
---@field When fun(condition: MissionCondition): MissionObjectiveDeclaration another condition on the LATEST CompletedWhen; all in a disjunct must hold (AND)
---@field RevealedWhen fun(condition: MissionCondition): MissionObjectiveDeclaration replace the default reveal cadence with the mission's own moment
---@field Foreshadow fun(): MissionObjectiveDeclaration draw the line greyed-out before its reveal
---@field IsComplete fun(): MissionCondition

---@class MissionObjectiveDeclarationEntry
---@field id string
---@field title string
---@field completions MissionCondition[][] disjuncts (one per CompletedWhen), each AND-composed into its own derived trigger; empty = a standing objective, transparent to the reveal cadence
---@field revealedWhen MissionCondition|nil set by RevealedWhen
---@field revealAtArm boolean|nil marked by the loader: no declared moment, no completable predecessor
---@field foreshadow boolean

--- Both conditions are latched; unknown names never arm (validated at load).
---@class MissionUnitRef
---@field name MissionUnitName
---@field IsDestroyed fun(): MissionCondition
---@field IsSpotted fun(team: MissionTeam): MissionCondition

--- Positions are map fractions until real maps pin real coordinates; a chain
--- without At fails the load.
---@class MissionSpawnChain
---@field At fun(fx: number, fz: number): MissionSpawnChain
---@field Named fun(name: MissionUnitName): MissionSpawnChain
---@field Grouped fun(group: MissionUnitGroup): MissionSpawnChain
---@field Neutral fun(): MissionSpawnChain starts inert: neither shoots nor is shot at, until handed over
---@field IsSpotted fun(team: MissionTeam): MissionCondition the handle is also the reference
---@field IsDestroyed fun(): MissionCondition

--- No At: a claimed unit is already somewhere. OrSpawnAt is required because it
--- says where to build one when the team turns out to have none.
---@class MissionClaimChain
---@field Named fun(name: MissionUnitName): MissionClaimChain
---@field Grouped fun(group: MissionUnitGroup): MissionClaimChain
---@field OrSpawnAt fun(fx: number, fz: number): MissionClaimChain
---@field IsSpotted fun(team: MissionTeam): MissionCondition
---@field IsDestroyed fun(): MissionCondition

---@class MissionRosterEntry
---@field def UnitDefName
---@field team MissionTeamRole
---@field fx number map-fraction position, resolved against map size at spawn
---@field fz number
---@field name MissionUnitName|nil declared by Named
---@field group MissionUnitGroup|nil declared by Grouped
---@field claim boolean|nil written by Claim: bind to an existing unit if the team has one
---@field neutral boolean|nil written by Neutral: spawn inert, cleared when the unit changes hands

--- Identity = source filename + declaration order: the unregister-by-identity
--- key for hot reload.
---@class TriggerDescriptor
---@field id string "<filename>:<order>"
---@field filename string mission-relative trigger file path
---@field order integer 1-based declaration order within the file
---@field condition MissionCondition
---@field effects MissionEffect[] executed in Do order when the condition fires
---@field once boolean fire at most once (default true)
---@field delayFrames integer hold the effects until the conditions have held this long; 0 fires at once

--- No terminator: the loader finalizes all chains when the include returns; a
--- chain without a Do fails the load.
---@class TriggerChain
---@field When fun(condition: MissionCondition): TriggerChain another condition; all must hold
---@field After fun(seconds: MissionSeconds): TriggerChain hold the effects until the conditions have held that long
---@field Do fun(effect: MissionEffect): TriggerChain repeatable; effects run in Do order
---@field Once fun(once: boolean?): TriggerChain default true; pass false for repeating triggers

--- Carries the name only; resolution to an id happens where Spring exists.
---@class MissionUnitDefRef
---@field name UnitDefName

--- Demo rule: resolves to the first human team at mission load.
---@class MissionTeam
---@field teamID integer
---@field allyTeam integer
---@field Has fun(unitDef: MissionUnitDefRef, count: integer): MissionCondition

--- The pile a checkpoint saves; definitions reload from source and this is reapplied on top.
---@class TriggerEngineState
---@field fired table<string, boolean> trigger id -> has fired
---@field heldSince table<string, integer> trigger id -> frame its conditions first held, for delays

--- The manifest's requires list IS the vocabulary whitelist; a global collision
--- is a load error.
---@class MissionDslFile
---@field filename string mission-relative trigger file path
---@field Register fun(descriptor: TriggerDescriptor)
---@field names table<string, boolean> roster unit names, for load-time validation
---@field groups table<string, boolean> roster group names, for load-time validation

---@class MissionDslContribution
---@field ForFile fun(file: MissionDslFile): { env: table<string, any>, Finalize: fun()|nil }
