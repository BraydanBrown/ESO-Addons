ResearchDump = ResearchDump or {}
local RD = ResearchDump

ZO_CreateStringId("SI_BINDING_NAME_RESEARCHDUMP_TOGGLE", "Toggle Research Window")

local CRAFTS = {
    CRAFTING_TYPE_BLACKSMITHING,
    CRAFTING_TYPE_CLOTHIER,
    CRAFTING_TYPE_WOODWORKING,
    CRAFTING_TYPE_JEWELRYCRAFTING,
}

-- Character management
RD.currentCharacter = nil
RD.characterList = {}

-- ========= Utilities =========

local function trimString(s)
    return s:match("^%s*(.-)%s*$")
end

local function fmtTime(secs)
    if not secs or secs <= 0 then return "-" end
    local d = math.floor(secs / 86400)
    local h = math.floor((secs % 86400) / 3600)
    local m = math.floor((secs % 3600) / 60)
    if d > 0 then return string.format("%dd %dh", d, h) end
    if h > 0 then return string.format("%dh %dm", h, m) end
    return string.format("%dm", m)
end

local function traitLabel(traitType, fallback)
    local s = GetString("SI_ITEMTRAITTYPE", traitType)
    if s and s ~= "" then return s end
    return fallback and fallback ~= "" and fallback or tostring(traitType)
end

-- ========= Data collection (live + saved) =========

-- Save character data (all fields are optional except characterName)
function RD.SaveCharacterData(characterName, researchData, skillsData, traitsLines)
    characterName = characterName or (GetDisplayName() .. ":" .. GetUnitName("player"))
    RD.sv.characters[characterName] = RD.sv.characters[characterName] or {}

    if researchData then
        RD.sv.characters[characterName].research = researchData
        RD.sv.characters[characterName].lastUpdate = GetTimeStamp()
    end
    if skillsData then
        RD.sv.characters[characterName].skills = skillsData
    end
    if traitsLines then
        -- array of strings grouped by craft; safe for SavedVars
        RD.sv.characters[characterName].traits = traitsLines
    end

    RD.UpdateCharacterList()
end

-- Build "traits still needed" lines for the **current** character (live)
local function buildMissingTraitsLinesLive()
    local out = {}
    for _, craftType in ipairs(CRAFTS) do
        local craftName = GetCraftingSkillName(craftType)
        local numLines = GetNumSmithingResearchLines(craftType) or 0
        local grouped = {}  -- lineName -> {trait names}

        for lineIndex = 1, numLines do
            local lineName, _, numTraits = GetSmithingResearchLineInfo(craftType, lineIndex)
            numTraits = numTraits or 0
            for traitIndex = 1, numTraits do
                local traitType, traitName, isKnown = GetSmithingResearchLineTraitInfo(craftType, lineIndex, traitIndex)
                local t1, _, t3 = GetSmithingResearchLineTraitTimes(craftType, lineIndex, traitIndex)

                local timeRemaining
                if type(t1) == "number" then timeRemaining = t1
                elseif type(t3) == "number" then timeRemaining = t3 end

                -- "need to be researched" = not known and not currently researching
                if not isKnown and (not timeRemaining or timeRemaining <= 0) then
                    local list = grouped[lineName]
                    if not list then
                        list = {}
                        grouped[lineName] = list
                    end
                    table.insert(list, traitLabel(traitType, traitName))
                end
            end
        end

        table.insert(out, string.format("|cFFFF99%s|r", craftName))
        local added = false
        for lineName, traits in pairs(grouped) do
            if #traits > 0 then
                table.sort(traits)
                table.insert(out, string.format("  • %s: %s", lineName, table.concat(traits, ", ")))
                added = true
            end
        end
        if not added then
            table.insert(out, "  • All traits known or in progress")
        end
        table.insert(out, "") -- blank line between crafts
    end
    return out
end

local function collectTradeskillLevels(characterName)
    characterName = characterName or (GetDisplayName() .. ":" .. GetUnitName("player"))

    -- Saved for other characters
    if characterName ~= (GetDisplayName() .. ":" .. GetUnitName("player")) then
        local saved = RD.sv.characters[characterName]
        if saved and type(saved.skills) == "string" and saved.skills ~= "" then
            return saved.skills
        else
            return "No skill data available for " .. RD.GetCharacterDisplayName(characterName)
        end
    end

    -- Live for current character
    local out = {}
    local n = GetNumSkillLines(SKILL_TYPE_TRADESKILL) or 0
    for i = 1, n do
        local name, rank = GetSkillLineInfo(SKILL_TYPE_TRADESKILL, i)
        if name and name ~= "" then
            out[#out+1] = string.format("%s: %d", name, rank or 0)
        end
    end
    local result = table.concat(out, "\n")
    RD.SaveCharacterData(characterName, nil, result, nil)
    return result
end

local function collectResearch(characterName)
    characterName = characterName or (GetDisplayName() .. ":" .. GetUnitName("player"))
    local me = (GetDisplayName() .. ":" .. GetUnitName("player"))

    -- Saved for other characters
    if characterName ~= me then
        local saved = RD.sv.characters[characterName]
        if saved and type(saved.research) == "string" and saved.research ~= "" then
            RD.traitsLines = saved.traits or {}
            return saved.research
        else
            RD.traitsLines = {}
            return "No research data available for " .. RD.GetCharacterDisplayName(characterName)
        end
    end

    -- Live for current character
    local sections = {}
    local traitsNeededLines = {}

    for _, craftType in ipairs(CRAFTS) do
        local craftName = GetCraftingSkillName(craftType)
        local numLines = GetNumSmithingResearchLines(craftType) or 0
        local activeCount = 0
        local lines = { string.format("|cFFFF99%s|r", craftName) }

        -- Build totals + running
        for lineIndex = 1, numLines do
            local lineName, _, numTraits = GetSmithingResearchLineInfo(craftType, lineIndex)
            numTraits = numTraits or 0
            local known, running = 0, {}

            for traitIndex = 1, numTraits do
                local traitType, traitName, isKnown = GetSmithingResearchLineTraitInfo(craftType, lineIndex, traitIndex)
                if isKnown then known = known + 1 end

                local t1, _, t3 = GetSmithingResearchLineTraitTimes(craftType, lineIndex, traitIndex)
                local timeRemaining = nil
                if type(t1) == "number" then timeRemaining = t1
                elseif type(t3) == "number" then timeRemaining = t3 end

                if timeRemaining and timeRemaining > 0 then
                    activeCount = activeCount + 1
                    table.insert(running, string.format("%s (%s)", traitLabel(traitType, traitName), fmtTime(timeRemaining)))
                end
            end

            local base = string.format("  • %s: %d/%d known", lineName, known, numTraits)
            if #running > 0 then
                base = base .. " | researching: " .. table.concat(running, ", ")
            end
            lines[#lines+1] = base
        end

        lines[#lines+1] = string.format("     Active research: %d\n", activeCount)
        sections[#sections+1] = table.concat(lines, "\n")
    end

    -- Compute "still needed" (right column)
    traitsNeededLines = buildMissingTraitsLinesLive()

    local result = table.concat(sections, "\n")
    RD.traitsLines = traitsNeededLines
    RD.SaveCharacterData(characterName, result, nil, traitsNeededLines)

    return result
end

-- ========= Character list / dropdown =========

function RD.UpdateCharacterList()
    RD.characterList = {}
    for charName, _ in pairs(RD.sv.characters) do
        table.insert(RD.characterList, charName)
    end
    table.sort(RD.characterList)

    if RD.characterDropdown and not RD.characterDropdown:IsHidden() then
        RD.PopulateCharacterDropdown()
    end
end

function RD.GetCharacterDisplayName(fullName)
    local _, charName = string.match(fullName, "^(.+):(.+)$")
    return charName or fullName
end

function RD.CreateCharacterDropdown()
    if RD.characterDropdown then return end

    local dropdown = WINDOW_MANAGER:CreateControlFromVirtual("ResearchDumpCharacterDropdown", ResearchDumpWindow, "ZO_ComboBox")
    dropdown:SetAnchor(TOPRIGHT, ResearchDumpWindowTitle, BOTTOMRIGHT, 0, 8)
    dropdown:SetDimensions(200, 30)

    local comboBox = ZO_ComboBox_ObjectFromContainer(dropdown)
    comboBox:SetSortsItems(false)
    comboBox:SetFont("ZoFontWinT1")
    comboBox:SetSpacing(4)

    RD.characterDropdown = dropdown
    RD.characterComboBox = comboBox

    RD.PopulateCharacterDropdown()
end

function RD.PopulateCharacterDropdown()
    if not RD.characterComboBox then return end

    RD.characterComboBox:ClearItems()

    local currentChar = GetDisplayName() .. ":" .. GetUnitName("player")

    -- current character first
    local entry = RD.characterComboBox:CreateItemEntry(RD.GetCharacterDisplayName(currentChar) .. " (Current)", RD.OnCharacterSelected)
    entry.characterName = currentChar
    RD.characterComboBox:AddItem(entry, ZO_COMBOBOX_SUPRESS_UPDATE)

    -- others
    for _, charName in ipairs(RD.characterList) do
        if charName ~= currentChar then
            local displayName = RD.GetCharacterDisplayName(charName)
            local e = RD.characterComboBox:CreateItemEntry(displayName, RD.OnCharacterSelected)
            e.characterName = charName
            RD.characterComboBox:AddItem(e, ZO_COMBOBOX_SUPRESS_UPDATE)
        end
    end

    if not RD.currentCharacter then
        RD.currentCharacter = currentChar
    end

    for _, item in ipairs(RD.characterComboBox:GetItems()) do
        if item.characterName == RD.currentCharacter then
            RD.characterComboBox:SelectItem(item, true)
            break
        end
    end
end

function RD.OnCharacterSelected(_, _, entry)
    RD.currentCharacter = entry.characterName

    if RD.researchLabel then
        RD.researchLabel:SetText("")
    end

    zo_callLater(function()
        RD.Refresh()
        RD.UpdateTraitsList()
    end, 100)
end

-- ========= UI helpers =========

-- Safe scroll resize for the middle column
local function ResizeScrollToText(scroll, label, pad)
    pad = pad or 16

    local scrollWidth = scroll:GetWidth()
    local child = scroll:GetNamedChild("ScrollChild")

    -- set size/anchors before measuring
    label:ClearAnchors()
    label:SetAnchor(TOPLEFT, child, TOPLEFT, 8, 8)
    label:SetWidth(scrollWidth - 32)
    label:SetHeight(0)

    -- compute height and size the child
    local textHeight = label:GetTextHeight()
    if not textHeight or textHeight < 20 then textHeight = 20 end

    label:SetHeight(textHeight + pad)
    child:SetWidth(scrollWidth)
    child:SetHeight(textHeight + pad * 2)

    -- reset scroll to top
    if scroll.SetVerticalScroll then
        scroll:SetVerticalScroll(0)
    elseif scroll.scroll and scroll.scroll.SetVerticalScroll then
        scroll.scroll:SetVerticalScroll(0)
    end
end

-- ========= Refresh (fills left + middle) =========

function RD.Refresh()
    if not ResearchDumpWindow or ResearchDumpWindow:IsHidden() then return end

    -- Middle column label (create once)
    if not RD.researchLabel then
        local scroll = ResearchDumpWindowResearchScroll
        local child  = scroll:GetNamedChild("ScrollChild")
        RD.researchLabel = WINDOW_MANAGER:CreateControl("ResearchDump_ResearchText", child, CT_LABEL)
        RD.researchLabel:SetFont("ZoFontGame")
        RD.researchLabel:SetHorizontalAlignment(TEXT_ALIGN_LEFT)
        RD.researchLabel:SetVerticalAlignment(TEXT_ALIGN_TOP)
        RD.researchLabel:SetAnchor(TOPLEFT, child, TOPLEFT, 8, 8)
        RD.researchLabel:SetWrapMode(TEXT_WRAP_MODE_NONE)
        RD.researchLabel:SetMaxLineCount(0)
    end

    local selectedCharacter = RD.currentCharacter or (GetDisplayName() .. ":" .. GetUnitName("player"))

    -- Middle: totals text
    local scroll = ResearchDumpWindowResearchScroll
    RD.researchLabel:SetWrapMode(TEXT_WRAP_MODE_NONE)
    RD.researchLabel:SetMaxLineCount(0)
    RD.researchLabel:SetHeight(0)
    RD.researchLabel:SetWidth(scroll:GetWidth() - 32)

    local researchText = collectResearch(selectedCharacter)
    RD.researchLabel:SetText(researchText)

    zo_callLater(function()
        ResizeScrollToText(ResearchDumpWindowResearchScroll, RD.researchLabel)
    end, 50)

    -- Left: skills
    local skillsText = collectTradeskillLevels(selectedCharacter)
    ResearchDumpWindowBodySkills:SetText(skillsText)

    -- Right: traits needed
    RD.UpdateTraitsList()
end

-- ========= Right column (traits still needed) =========

function RD.UpdateTraitsList()
    local scroll = ResearchDumpWindowTraitsScroll
    if not scroll then return end
    local child = scroll:GetNamedChild("ScrollChild")

    -- remove existing rows
    for i = child:GetNumChildren(), 1, -1 do
        local c = child:GetChild(i)
        child:RemoveChild(c)
    end

    local lines = RD.traitsLines or {}
    local y = 8
    for i, line in ipairs(lines) do
        local name = child:GetName() .. "Line" .. i
        local lbl = CreateControl(name, child, CT_LABEL)
        lbl:SetFont("ZoFontGame")
        lbl:SetWrapMode(TEXT_WRAP_MODE_NONE)
        lbl:SetMaxLineCount(0)
        lbl:SetText(line)
        lbl:ClearAnchors()
        lbl:SetAnchor(TOPLEFT, child, TOPLEFT, 8, y)
        lbl:SetWidth(scroll:GetWidth() - 16)
        local h = lbl:GetTextHeight()
        if h < 18 then h = 18 end
        y = y + h + 4
    end

    child:SetHeight(y + 8)
    if scroll.SetVerticalScroll then scroll:SetVerticalScroll(0) end
end

-- ========= Scene (ESC/back + cursor) =========

local RD_SCENE, RD_FRAGMENT
local function EnsureScene()
    if RD_SCENE then return end
    RD_FRAGMENT = ZO_FadeSceneFragment:New(ResearchDumpWindow)
    RD_SCENE = ZO_Scene:New("ResearchDumpScene", SCENE_MANAGER)
    RD_SCENE:AddFragmentGroup(FRAGMENT_GROUP.MOUSE_DRIVEN_UI_WINDOW) -- cursor/UI mode
    RD_SCENE:AddFragment(RD_FRAGMENT)
end

local function show()
    EnsureScene()
    SCENE_MANAGER:Push("ResearchDumpScene")
    RD.CreateCharacterDropdown()
    RD.UpdateCharacterList()
    RD.Refresh()
end

local function hide()
    SCENE_MANAGER:Hide("ResearchDumpScene")
end

function ResearchDump_Toggle()
    if SCENE_MANAGER:IsShowing("ResearchDumpScene") then
        hide()
    else
        show()
    end
end

-- If your XML still calls this, keep it harmless:
function ResearchDump_OnKeyDown(_, key)
    if key == KEY_ESCAPE then
        ResearchDump_Toggle()
    end
end

-- ========= Slash command =========

local function SlashCommandHandler(text)
    text = text and trimString(text) or ""

    if text == "" then
        ResearchDump_Toggle()
        return
    end

    local targetChar
    local searchText = string.lower(text)

    -- exact match
    for charName, _ in pairs(RD.sv.characters) do
        local displayName = string.lower(RD.GetCharacterDisplayName(charName))
        if displayName == searchText then
            targetChar = charName
            break
        end
    end
    -- partial match
    if not targetChar then
        for charName, _ in pairs(RD.sv.characters) do
            local displayName = string.lower(RD.GetCharacterDisplayName(charName))
            if string.find(displayName, searchText, 1, true) then
                targetChar = charName
                break
            end
        end
    end

    if targetChar then
        RD.currentCharacter = targetChar
        if not ResearchDumpWindow:IsHidden() then
            RD.PopulateCharacterDropdown()
            RD.Refresh()
        else
            show()
        end
        d("ResearchDump: Switched to " .. RD.GetCharacterDisplayName(targetChar))
    else
        local available = {}
        for charName, _ in pairs(RD.sv.characters) do
            table.insert(available, RD.GetCharacterDisplayName(charName))
        end
        if #available > 0 then
            d("ResearchDump: Character '" .. text .. "' not found. Available: " .. table.concat(available, ", "))
        else
            d("ResearchDump: No character data found. Use /rd to open the window and collect data.")
        end
    end
end

-- ========= Addon init =========

local function onLoaded(_, addonName)
    if addonName ~= "ResearchDump" then return end
    EVENT_MANAGER:UnregisterForEvent("ResearchDump_OnLoaded", EVENT_ADD_ON_LOADED)

    RD.sv = ZO_SavedVars:NewAccountWide("ResearchDump_SV", 1, nil, {
        firstRun = true,
        characters = {},
    })

    local currentChar = GetDisplayName() .. ":" .. GetUnitName("player")
    RD.currentCharacter = currentChar
    RD.UpdateCharacterList()

    for _, cmd in ipairs({"/rd","/research","/craft","/researchdump"}) do
        SLASH_COMMANDS[cmd] = SlashCommandHandler
    end

    local n = "ResearchDump"
    EVENT_MANAGER:RegisterForEvent(n.."Started",   EVENT_SMITHING_TRAIT_RESEARCH_STARTED,   RD.Refresh)
    EVENT_MANAGER:RegisterForEvent(n.."Completed", EVENT_SMITHING_TRAIT_RESEARCH_COMPLETED, RD.Refresh)
    EVENT_MANAGER:RegisterForEvent(n.."Times",     EVENT_SMITHING_RESEARCH_TIMES_UPDATED,   RD.Refresh)
    EVENT_MANAGER:RegisterForUpdate(n.."Tick", 60000, RD.Refresh)
end

EVENT_MANAGER:RegisterForEvent("ResearchDump_OnLoaded", EVENT_ADD_ON_LOADED, onLoaded)
