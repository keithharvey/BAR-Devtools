---@meta policy trigger

--- These globals exist in no real scope: mission_loader injects them into each triggers/*.lua sandbox;
--- this meta file mirrors that injection so the language server sees what a trigger file sees.

---@param condition MissionCondition
---@return TriggerChain
function When(condition) end

---Complete implies Reveal.
---When objectives.lua exists, an Objective id no declaration there backs is a load error here.
---@param name ObjectiveName
---@return MissionObjective
function Objective(name) end

---Unit-def reference by name; resolution to an id happens where Spring exists.
---@param name UnitDefName
---@return MissionUnitDefRef
function UnitDef(name) end

---Validated against the roster at load: an
---unknown name is a load error, not a silent never-true condition.
---@param name MissionUnitName
---@return MissionUnitRef
function Unit(name) end

---units.lua sandbox only, not injected into trigger files.

---@param unitDef MissionUnitDefRef
---@param team MissionTeamRole
---@return MissionSpawnChain
function Spawn(unitDef, team) end

---units.lua sandbox only. OrSpawnAt is required because it says where to
---build one when the team turns out to have none.

---@param unitDef MissionUnitDefRef
---@param team MissionTeamRole
---@return MissionClaimChain
function Claim(unitDef, team) end

---@type { Player: MissionTeam }
Team = {}

---What units.lua exported: `return { hub = hub }` makes Units.hub the
---reference to that unit, named by its export key unless Named said otherwise.
---@type table<string, MissionUnitRef>
Units = {}

---What objectives.lua exported: `return { relieve = relieve }` makes
---Objectives.relieve the reference to that objective.
---@type table<string, MissionObjective>
Objectives = {}
