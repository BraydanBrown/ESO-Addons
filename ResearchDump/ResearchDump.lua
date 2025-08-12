--[[
  ResearchDump - minimal tracker for ESO crafting:
  - Shows active research (with remaining time)
  - Shows known traits per research line
  - Shows tradeskill line ranks
  Notes:
  * Uses only the live API (no external libs)
  * Known trait detection follows the CraftStore pattern:
      local traitType, traitName, known /*3rd*/, researchable /*4th*/ = GetSmithingResearchLineTraitInfo(...)
--]]

ResearchDump = ResearchDump or {}
local RD = ResearchDump

-- =========================
-- Strings / Keybind label
-- =========================
ZO_CreateStringId("SI_BINDING_NAME_RESEARCHDUMP_TOGGLE", "Toggle Research Window")

-- =========================
-- Utilities / constants
-- =========================
local CRAFTS = {
  CRAFTING_TYPE_BLACKSMITHING,
  CRAFTING_TYPE_CLOTHIER,
  CRAFTING_TYPE_WOODWORKING,
  CRAFTING_TYPE_JEWELRYCRAFTING,
}

local function fmtTime(secs)
  if not secs or secs <= 0 then return "-" end
  local d = math.floor(secs / 86400)
  local h = math.floor((secs % 86400) / 3600)
  local m = math.floor((secs % 3600) / 60)
  if d > 0 then return string.format("%dd %dh", d, h) end
  if h > 0 then return string.format("%dh %dm", h, m) end
  return string.format("%dm", m)
end

-- Resolve a reliable trait name. CraftStore prefers the string table over the raw return.
local function resolveTraitName(traitType, fallback)
  local s = GetString("SI_ITEMTRAITTYPE", traitType)
  if s and s ~= "" then return s end
  if fallback and fallback ~= "" then return fallback end
  return tostring(traitType)
end

-- =========================
-- Data collection
-- =========================

-- Collect per-craft research lines with known counts and running timers
local function collectResearch()
  local outSections = {}

  for _, craftType in ipairs(CRAFTS) do
    local craftName = GetCraftingSkillName(craftType)
    local numLines = GetNumSmithingResearchLines(craftType) or 0
    local activeCount = 0
    local section = { string.format("|cFFFF99%s|r", craftName) }

    for lineIndex = 1, numLines do
      local lineName, _, numTraits = GetSmithingResearchLineInfo(craftType, lineIndex)
      numTraits = numTraits or 0

      local known = 0
      local running = {}

      for traitIndex = 1, numTraits do
        -- IMPORTANT: known is the *third* return
        local traitType, traitName, isKnown = GetSmithingResearchLineTraitInfo(craftType, lineIndex, traitIndex)
        if isKnown then known = known + 1 end

        -- Active research / remaining time
        local isResearching, _, _, timeRemaining = GetSmithingResearchLineTraitTimes(craftType, lineIndex, traitIndex)
        if isResearching and timeRemaining and timeRemaining > 0 then
          activeCount = activeCount + 1
          local label = resolveTraitName(traitType, traitName)
          running[#running+1] = string.format("%s (%s)", label, fmtTime(timeRemaining))
        end
      end

      local line = string.format("  • %s: %d/%d known%s",
        lineName, known, numTraits,
        (#running > 0) and (" | " .. table.concat(running, ", ")) or "")
      section[#section+1] = line
    end

    section[#section+1] = string.format("     Active research: %d\n", activeCount)
    outSections[#outSections+1] = table.concat(section, "\n")
  end

  return table.concat(outSections, "\n")
end

-- Collect the Tradeskill skill line ranks (Alchemy, Blacksmithing, etc.)
local function collectTradeskillLevels()
  local lines = {}
  local n = GetNumSkillLines(SKILL_TYPE_TRADESKILL) or 0
  for i = 1, n do
    local name, rank = GetSkillLineInfo(SKILL_TYPE_TRADESKILL, i)
    if name and name ~= "" then
      lines[#lines+1] = string.format("%s: %d", name, rank or 0)
    end
  end
  return table.concat(lines, "\n")
end

-- =========================
-- UI update
-- =========================
function RD.Refresh()
  if not ResearchDumpWindow or ResearchDumpWindow:IsHidden() then return end
  ResearchDumpWindowBodyResearch:SetText(collectResearch())
  ResearchDumpWindowBodySkills:SetText(collectTradeskillLevels())
end

local function show()
  ResearchDumpWindow:SetHidden(false)
  RD.Refresh()
end

local function hide()
  ResearchDumpWindow:SetHidden(true)
end

function ResearchDump_Toggle()
  if ResearchDumpWindow:IsHidden() then show() else hide() end
end

-- =========================
-- Init / Events
-- =========================
local function onLoaded(_, addonName)
  if addonName ~= "ResearchDump" then return end
  EVENT_MANAGER:UnregisterForEvent("ResearchDump_OnLoaded", EVENT_ADD_ON_LOADED)

  -- Saved vars (reserved for future options)
  RD.sv = ZO_SavedVars:NewAccountWide("ResearchDump_SV", 1, nil, { firstRun = true })

  -- Slash command (so "/rd" works again)
  SLASH_COMMANDS["/rd"] = ResearchDump_Toggle

  -- Keep the panel current when research changes or ticks
  local n = "ResearchDump"
  EVENT_MANAGER:RegisterForEvent(n.."Started",   EVENT_SMITHING_TRAIT_RESEARCH_STARTED,   RD.Refresh)
  EVENT_MANAGER:RegisterForEvent(n.."Completed", EVENT_SMITHING_TRAIT_RESEARCH_COMPLETED, RD.Refresh)
  EVENT_MANAGER:RegisterForEvent(n.."Times",     EVENT_SMITHING_RESEARCH_TIMES_UPDATED,   RD.Refresh)
  EVENT_MANAGER:RegisterForUpdate(n.."Tick", 60000, RD.Refresh) -- refresh every 60s

  -- Optionally auto-open once for quick testing:
  -- zo_callLater(show, 1000)
end

EVENT_MANAGER:RegisterForEvent("ResearchDump_OnLoaded", EVENT_ADD_ON_LOADED, onLoaded)
