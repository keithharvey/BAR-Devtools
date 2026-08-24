---@meta actions

--- Until arms its Unprotect trigger when the protection is applied, not at load.
---@class CombatProtect
---@overload fun(unit: MissionUnitRef): MissionProtectEffect

---@class CombatUnprotect
---@overload fun(unit: MissionUnitRef): MissionEffect

---@class MissionProtectEffect
---@field execute fun(ctx: MissionContext)
---@field Until fun(condition: MissionCondition): MissionEffect

---@class CombatActions
---@field Protect CombatProtect
---@field Unprotect CombatUnprotect

---@type CombatActions
Combat = {}
