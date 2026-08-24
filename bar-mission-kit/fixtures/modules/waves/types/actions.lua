---@meta actions

--- The mission kit derives its authoring surface from these types, so the
--- alias and class names here are load-bearing beyond the checker.

--- An ALIAS, not a bare number: the editor derives its slot names from
--- param types, and a `number` has nothing to call itself in a sentence.

---@alias WaveIntensity number

--- `name` doubles as the director's name and its savegame key.
---@class WavePackRef
---@field name string "<module>.<pack>", the running director's name
---@field module string the flavor module that can rebuild the spec
---@field pack string which builder inside it

--- It IS an effect, not merely effect-shaped: a Do takes the chain directly,
--- so every link returns something Do accepts and the statement reads as one
--- sentence however many dials it turns.
---@class MissionWavesChain : MissionEffect
---@field Against fun(team: MissionTeam): MissionWavesChain
---@field From fun(fx: number, fz: number): MissionWavesChain
---@field Intensity fun(intensity: WaveIntensity): MissionWavesChain

---@class WavesBegin
---@overload fun(pack: WavePackRef): MissionWavesChain

---@class WavesIntensify
---@overload fun(pack: WavePackRef, intensity: WaveIntensity): MissionEffect

---@class WavesSurge
---@overload fun(pack: WavePackRef): MissionEffect

---@class WavesEnd
---@overload fun(pack: WavePackRef): MissionEffect

---@class WavesSpawned
---@overload fun(pack: WavePackRef, count: integer?): MissionCondition

---@class WavesCleared
---@overload fun(pack: WavePackRef, count: integer?): MissionCondition

---@class WavesBossDefeated
---@overload fun(pack: WavePackRef, count: integer?): MissionCondition

---@class WavesActions
---@field Begin WavesBegin
---@field Intensify WavesIntensify
---@field Surge WavesSurge
---@field End WavesEnd
---@field Spawned WavesSpawned
---@field Cleared WavesCleared
---@field BossDefeated WavesBossDefeated

---@type WavesActions
Waves = {}
