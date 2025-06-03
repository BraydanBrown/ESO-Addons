--[[  
  ResearchDump.lua  
  Version 1.5 - Multi-Character Shopping List with GUI
  Dumps missing research info to chat using native ESO API only.  
--]]

-- Initialize addon namespace
ResearchDump = ResearchDump or {}
ResearchDump.columnData = {}

-- Wait for addon to be loaded
local function OnAddOnLoaded(eventCode, addonName)
    if addonName ~= "ResearchDump" then return end
    EVENT_MANAGER:UnregisterForEvent("ResearchDump", EVENT_ADD_ON_LOADED)
    
    -- Initialize SavedVariables
    ResearchDumpSavedVars = ResearchDumpSavedVars or {}
    ResearchDumpSavedVars.researchData = ResearchDumpSavedVars.researchData or {}
    ResearchDumpSavedVars.exportData = ResearchDumpSavedVars.exportData or {}
    
    -- Get current character name
    local currentPlayer = GetDisplayName() .. " @" .. GetUnitName("player")
    
    -- Update research data for current character
    UpdateCurrentCharacterResearchData(currentPlayer)
    
    -- Initialize GUI
    ResearchDumpUI.CreateWindow()
    
    d("|c00FF00ResearchDump loaded successfully!|r Use /dumpresearch to see missing traits.")
end

EVENT_MANAGER:RegisterForEvent("ResearchDump", EVENT_ADD_ON_LOADED, OnAddOnLoaded)

-- Keybind function for toggling shopping list
function ResearchDump_ToggleShoppingList()
    if ResearchDumpUI and ResearchDumpUI.Toggle then
        ResearchDumpUI.Toggle()
    else
        d("|cFF0000Error: ResearchDumpUI not initialized properly.|r")
    end
end

-- Function to update research data for the current character
function UpdateCurrentCharacterResearchData(playerName)
    if not ResearchDumpSavedVars.researchData[playerName] then
        ResearchDumpSavedVars.researchData[playerName] = {}
    end
    
    local craftingTypes = {
        CRAFTING_TYPE_BLACKSMITHING,
        CRAFTING_TYPE_CLOTHIER,
        CRAFTING_TYPE_WOODWORKING,
        CRAFTING_TYPE_JEWELRYCRAFTING
    }
    
    for _, craftType in ipairs(craftingTypes) do
        ResearchDumpSavedVars.researchData[playerName][craftType] = ResearchDumpSavedVars.researchData[playerName][craftType] or {}
        
        local numLines = GetNumSmithingResearchLines(craftType)
        for lineIndex = 1, numLines do
            ResearchDumpSavedVars.researchData[playerName][craftType][lineIndex] = ResearchDumpSavedVars.researchData[playerName][craftType][lineIndex] or {}
            
            for traitIndex = 1, 9 do
                local _, _, known = GetSmithingResearchLineTraitInfo(craftType, lineIndex, traitIndex)
                ResearchDumpSavedVars.researchData[playerName][craftType][lineIndex][traitIndex] = known
            end
        end
    end
end

-- Function to generate shopping list across all characters
local function GenerateShoppingList(exportMode)
    local results = {}
    local shoppingList = {}
    
    if not exportMode then
        d("=== Multi-Character Research Shopping List ===")
    else
        table.insert(results, "=== Multi-Character Research Shopping List ===")
        table.insert(results, "Generated: " .. GetDateStringFromTimestamp(GetTimeStamp()))
        table.insert(results, "")
    end
    
    -- Check if we have any character data
    if not ResearchDumpSavedVars.researchData or next(ResearchDumpSavedVars.researchData) == nil then
        local noDataText = "No character research data found. Please log in with each character first."
        if not exportMode then
            d(noDataText)
        else
            table.insert(results, noDataText)
        end
        return results
    end
    
    -- Analyze missing traits across all characters
    local craftingTypes = {
        { type = CRAFTING_TYPE_BLACKSMITHING, name = "Blacksmithing", key = "blacksmithing" },
        { type = CRAFTING_TYPE_CLOTHIER, name = "Clothier", key = "clothier" },
        { type = CRAFTING_TYPE_WOODWORKING, name = "Woodworking", key = "woodworking" },
        { type = CRAFTING_TYPE_JEWELRYCRAFTING, name = "Jewelry Crafting", key = "jewelry" }
    }
    
    -- Group items by crafting type for better organization
    local craftGroups = {}
    for _, craft in ipairs(craftingTypes) do
        craftGroups[craft.key] = { 
            name = craft.name, 
            items = {},
            content = {}
        }
    end
    
    -- Analyze all traits for all crafting types
    for _, craft in ipairs(craftingTypes) do
        local numLines = GetNumSmithingResearchLines(craft.type)
        for lineIndex = 1, numLines do
            local lineName = GetSmithingResearchLineInfo(craft.type, lineIndex)
            
            for traitIndex = 1, 9 do
                local neededCount = 0
                local charactersList = {}
                
                -- Check all characters for this trait
                for playerName, researchData in pairs(ResearchDumpSavedVars.researchData) do
                    if researchData[craft.type] and 
                       researchData[craft.type][lineIndex] and 
                       researchData[craft.type][lineIndex][traitIndex] == false then
                        neededCount = neededCount + 1
                        table.insert(charactersList, playerName)
                    end
                end
                
                -- If characters need this trait, add to appropriate craft group
                if neededCount > 0 then
                    local traitType = GetSmithingResearchLineTraitInfo(craft.type, lineIndex, traitIndex)
                    local traitName = GetString("SI_ITEMTRAITTYPE", traitType)
                    
                    if traitName and not string.find(traitName, "<<") then
                        table.insert(craftGroups[craft.key].items, {
                            name = lineName .. " - " .. traitName,
                            count = neededCount,
                            characters = charactersList
                        })
                    end
                end
            end
        end
        
        -- Sort items within each craft type by count (highest first), then by name
        table.sort(craftGroups[craft.key].items, function(a, b)
            if a.count == b.count then
                return a.name < b.name
            end
            return a.count > b.count
        end)
        
        -- Generate content for this craft group
        local content = {}
        for _, item in ipairs(craftGroups[craft.key].items) do
            table.insert(content, string.format("%dx %s", item.count, item.name))
        end
        
        if #content == 0 then
            table.insert(content, "No items needed!")
        end
        
        craftGroups[craft.key].content = content
    end
    
    -- Store results for UI display
    ResearchDump.columnData = craftGroups
    
    -- For export mode, create formatted output
    if exportMode then
        for _, craft in ipairs(craftingTypes) do
            local group = craftGroups[craft.key]
            if #group.items > 0 then
                table.insert(results, "— " .. group.name .. " —")
                for _, item in ipairs(group.items) do
                    table.insert(results, string.format("%dx %s", item.count, item.name))
                end
                table.insert(results, "")
            end
        end
        
        local totalItems = 0
        for _, craft in ipairs(craftingTypes) do
            for _, item in ipairs(craftGroups[craft.key].items) do
                totalItems = totalItems + item.count
            end
        end
        
        if totalItems > 0 then
            table.insert(results, string.format("Total items needed: %d across %d character(s)", totalItems, GetCharacterCount()))
        else
            table.insert(results, "No research items needed across all characters!")
        end
    end
    
    return results
end

-- Helper function to count tracked characters
function GetCharacterCount()
    local count = 0
    for _ in pairs(ResearchDumpSavedVars.researchData) do
        count = count + 1
    end
    return count
end

-- Debug function to test API availability
local function TestAPIFunctions()
    d("=== Testing ESO API Functions ===")
    local functions = {
        "GetNumSmithingResearchLines",
        "GetSmithingResearchLineInfo", 
        "GetNumSmithingResearchLineTraits",
        "GetSmithingResearchLineTraitInfo",
        "GetSmithingResearchLineTraitType",
        "IsSmithingTraitKnownForResult",
        "CanItemLinkBeTraitResearched",
        -- Test research-related functions
        "GetSmithingResearchLineTraitTimes",
        "GetSmithingResearchLineUnlockedTraits",
        "IsSmithingResearchLineTraitKnown",
        "GetNumResearchProjects",
        "GetResearchProjectInfo",
        -- Test crafting station functions
        "ZO_SharedSmithingResearch_CanTraitBeResearched",
        "ZO_SharedSmithingResearch_IsTraitKnownForResult"
    }
    
    for _, funcName in ipairs(functions) do
        if _G[funcName] then
            d("✓ " .. funcName .. " - Available")
        else
            d("✗ " .. funcName .. " - NOT AVAILABLE")
        end
    end
    
    -- Test some basic constants
    d("=== Testing Constants ===")
    local constants = {
        "CRAFTING_TYPE_BLACKSMITHING",
        "CRAFTING_TYPE_CLOTHIER",
        "CRAFTING_TYPE_WOODWORKING",
        "CRAFTING_TYPE_JEWELRYCRAFTING"
    }
    
    for _, constName in ipairs(constants) do
        if _G[constName] then
            d("✓ " .. constName .. " = " .. tostring(_G[constName]))
        else
            d("✗ " .. constName .. " - NOT AVAILABLE")
        end
    end
end

-- Global variables to store results for export
local exportResults = {}

local function DumpGearCrafting(exportMode)
    local results = {}
    
    if not exportMode then
        d("=== Gear-Crafting Missing Traits ===")
    else
        table.insert(results, "=== Gear-Crafting Missing Traits ===")
        table.insert(results, "Generated: " .. GetDateStringFromTimestamp(GetTimeStamp()))
        table.insert(results, "Character: " .. GetDisplayName() .. " (@" .. GetUnitName("player") .. ")")
        table.insert(results, "")
    end
    
    local craftingTypes = {
        { type = CRAFTING_TYPE_BLACKSMITHING, name = "Blacksmithing" },
        { type = CRAFTING_TYPE_CLOTHIER, name = "Clothier" },
        { type = CRAFTING_TYPE_WOODWORKING, name = "Woodworking" },
        { type = CRAFTING_TYPE_JEWELRYCRAFTING, name = "Jewelry Crafting" }
    }
    
    for _, craft in ipairs(craftingTypes) do
        local craftSection = "— " .. craft.name .. " —"
        if not exportMode then
            d(craftSection)
        else
            table.insert(results, craftSection)
        end
        
        local success, numResearchLines = pcall(GetNumSmithingResearchLines, craft.type)
        if success and numResearchLines and numResearchLines > 0 then
            local hasUnknownTraits = false
            local craftMissing = {}
            local craftResearching = {}
            
            for lineIndex = 1, numResearchLines do
                local lineSuccess, lineName, lineIcon = pcall(GetSmithingResearchLineInfo, craft.type, lineIndex)
                if lineSuccess and lineName then
                    for traitIndex = 1, 9 do
                        local traitSuccess, traitType, traitDescription, known = pcall(GetSmithingResearchLineTraitInfo, craft.type, lineIndex, traitIndex)
                        
                        if traitSuccess and traitType then
                            if known == false then
                                local timesSuccess, remaining = pcall(GetSmithingResearchLineTraitTimes, craft.type, lineIndex, traitIndex)
                                  if timesSuccess and remaining and remaining > 0 then
                                    -- Currently researching this trait
                                    local traitName = GetString("SI_ITEMTRAITTYPE", traitType)
                                    if traitName and traitName ~= "" and not string.find(traitName, "<<") then
                                        local researchText = "Researching: " .. traitName .. " on " .. lineName .. " (time left: " .. math.floor(remaining/3600) .. "h)"
                                        if not exportMode then
                                            d(researchText)
                                        else
                                            table.insert(craftResearching, researchText)
                                        end
                                    end
                                else
                                    -- This trait is not known and not being researched
                                    local traitName = GetString("SI_ITEMTRAITTYPE", traitType)
                                    if traitName and traitName ~= "" and not string.find(traitName, "<<") then
                                        local missingText = "Missing: " .. traitName .. " on " .. lineName
                                        hasUnknownTraits = true
                                        if not exportMode then
                                            d(missingText)
                                        else
                                            table.insert(craftMissing, missingText)
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
            
            if exportMode then
                -- Add researching traits first
                for _, line in ipairs(craftResearching) do
                    table.insert(results, line)
                end
                -- Then add missing traits
                for _, line in ipairs(craftMissing) do
                    table.insert(results, line)
                end
            end
            
            if not hasUnknownTraits then
                local completeText = "All available traits known for " .. craft.name .. "!"
                if not exportMode then
                    d(completeText)
                else
                    table.insert(results, completeText)
                end
            end
        else
            local errorText = "No research lines found for " .. craft.name
            if not exportMode then
                d(errorText)
            else
                table.insert(results, errorText)
            end
        end
        
        if exportMode then
            table.insert(results, "")
        end
    end
    
    return results
end

-- Enhanced function that analyzes items in inventory
local function DumpResearchableItems(exportMode)
    local results = {}
    
    if not exportMode then
        d("=== Researchable Items in Inventory ===")
    else
        table.insert(results, "=== Researchable Items in Inventory ===")
    end
    
    local bagId = BAG_BACKPACK
    local bagSlots = GetBagSize(bagId)
    if not bagSlots then
        local errorText = "Error: Could not get bag size"
        if not exportMode then
            d(errorText)
        else
            table.insert(results, errorText)
        end
        return results
    end
    
    local foundItems = false
    local itemsChecked = 0
    
    for slotIndex = 0, bagSlots - 1 do
        local itemLink = GetItemLink(bagId, slotIndex)
        if itemLink and itemLink ~= "" then
            itemsChecked = itemsChecked + 1
            
            -- Check if this item can be researched
            local itemType = GetItemLinkItemType(itemLink)
            local traitType = GetItemLinkTraitInfo(itemLink)
            
            -- Check if this is a researchable item type
            if itemType and (itemType == ITEMTYPE_WEAPON or itemType == ITEMTYPE_ARMOR or itemType == ITEMTYPE_JEWELRY) then
                -- Use pcall for safety
                local canResearchSuccess, canBeResearched = pcall(CanItemLinkBeTraitResearched, itemLink)
                
                if canResearchSuccess and canBeResearched then
                    local itemName = GetItemLinkName(itemLink)
                    local traitName = GetString("SI_ITEMTRAITTYPE", traitType)
                    
                    if itemName and traitName and not string.find(traitName, "<<") then
                        local itemText = "Can research: " .. itemName .. " (" .. traitName .. ")"
                        if not exportMode then
                            d(itemText)
                        else
                            table.insert(results, itemText)
                        end
                        foundItems = true
                    elseif itemName then
                        local itemText = "Can research: " .. itemName .. " (Unknown trait)"
                        if not exportMode then
                            d(itemText)
                        else
                            table.insert(results, itemText)
                        end
                        foundItems = true
                    end
                elseif not canResearchSuccess then
                    -- Fallback method if CanItemLinkBeTraitResearched doesn't work
                    if traitType and traitType ~= ITEM_TRAIT_TYPE_NONE then
                        local itemName = GetItemLinkName(itemLink)
                        if itemName then
                            local itemText = "Possible research item: " .. itemName .. " (trait " .. tostring(traitType) .. ")"
                            if not exportMode then
                                d(itemText)
                            else
                                table.insert(results, itemText)
                            end
                            foundItems = true
                        end
                    end
                end
            end
        end
    end
    
    if not foundItems then
        local noItemsText = "No researchable items found in inventory."
        if not exportMode then
            d(noItemsText)
        else
            table.insert(results, noItemsText)
        end
    end
    
    return results
end

-- Function to export results to actual text file in addon directory
local function ExportToFile()
    d("Generating research report and saving to file...")
    
    local results = {}
    
    -- Get all data types including shopping list
    local gearResults = DumpGearCrafting(true)
    local itemResults = DumpResearchableItems(true)
    local shoppingResults = GenerateShoppingList(true)
    
    -- Combine results
    for _, line in ipairs(gearResults) do
        table.insert(results, line)
    end
    
    table.insert(results, "")
    
    for _, line in ipairs(itemResults) do
        table.insert(results, line)
    end
    
    table.insert(results, "")
    
    for _, line in ipairs(shoppingResults) do
        table.insert(results, line)
    end
    
    -- Create filename with timestamp
    local timestamp = GetDateStringFromTimestamp(GetTimeStamp())
    local fileName = "ResearchDump_" .. timestamp:gsub("[^%w]", "_")
    
    -- Create the plain text content
    local txtContent = table.concat(results, "\n")
      -- Save to SavedVariables for persistent storage
    ResearchDumpSavedVars.exportData = {
        version = "1.5",
        lastExport = timestamp,
        fileName = fileName .. ".txt",
        content = txtContent
    }
    
    -- Also store in a global variable for immediate access
    _G["ResearchDumpTxtExport"] = {
        content = txtContent,
        filename = fileName .. ".txt",
        timestamp = timestamp,
        lines = #results
    }
    
    -- Try to save a lua file in the addon directory that can be easily converted to txt
    local luaFileContent = "-- ResearchDump Export File\n" ..
                          "-- Generated: " .. timestamp .. "\n" ..
                          "-- Character: " .. GetDisplayName() .. " (@" .. GetUnitName("player") .. ")\n" ..
                          "-- To convert to .txt file, copy everything between the [=[ ]=] markers\n\n" ..
                          "ResearchDumpExport = [=[\n" ..
                          txtContent .. "\n" ..
                          "]=]\n\n" ..
                          "-- Usage: Copy the content between [=[ ]=] and save as " .. fileName .. ".txt"
    
    -- Store the lua file content for manual saving
    _G["ResearchDumpLuaFile"] = {
        content = luaFileContent,
        filename = fileName .. ".lua"
    }
    
    d("|c00FF00Research report generated successfully!|r")
    d("|cFFFF00Saved to SavedVariables: ResearchDump.lua|r")
    d("|cFFFF00To create text file:|r")
    d("|cFFFF001. Use: /script d(ResearchDumpTxtExport.content)|r")
    d("|cFFFF002. Copy the output and save as: " .. fileName .. ".txt|r")
    d("|cFFFF00Or check SavedVariables folder for ResearchDump.lua file|r")
    d("Report contains " .. #results .. " lines of data.")
      -- Store results globally for potential future use
    exportResults = results
end

-- Global function for XML event handlers to close the window
function ResearchDump_CloseWindow()
    if ResearchDumpUI and ResearchDumpUI.Hide then
        ResearchDumpUI.Hide()
    elseif ResearchDumpWindow then
        -- Fallback: directly hide the window if UI object isn't available
        ResearchDumpWindow:SetHidden(true)
    end
end

-- Global functions for XML resize event handlers
function ResearchDump_OnResizeStart()
    -- Called when window resize starts - can be used for performance optimizations
end

function ResearchDump_OnResizeStop()
    -- Called when window resize stops - can be used to refresh content layout
    if ResearchDumpUI and ResearchDumpUI.textArea and ResearchDumpUI.scrollContainer then
        -- Refresh text area dimensions after resize
        ResearchDumpUI.textArea:SetDimensions(ResearchDumpUI.scrollContainer:GetWidth() - 20, 800)
    end
end

-- GUI Window for Shopping List
ResearchDumpUI = {} -- Make this global so XML can access it
ResearchDumpUI.window = nil
ResearchDumpUI.isVisible = false

-- Initialize the GUI window (uses XML-defined controls)
function ResearchDumpUI.CreateWindow()
    if ResearchDumpUI.window then
        return -- Window already exists
    end
    
    -- Get the XML-defined window
    ResearchDumpUI.window = ResearchDumpWindow
    if not ResearchDumpUI.window then
        d("|cFF0000Error: ResearchDumpWindow not found! Make sure the XML file loaded properly.|r")
        return
    end
    
    -- Get child controls with error checking
    local scrollContainer = ResearchDumpWindow:GetNamedChild("ScrollContainer")
    if scrollContainer then
        local scrollChild = scrollContainer:GetNamedChild("ScrollChild")
        if scrollChild then
            local columnContainer = scrollChild:GetNamedChild("ColumnContainer")
            if columnContainer then
                -- Get references to all column text areas
                local blacksmithingColumn = columnContainer:GetNamedChild("BlacksmithingColumn")
                local clothierColumn = columnContainer:GetNamedChild("ClothierColumn")
                local woodworkingColumn = columnContainer:GetNamedChild("WoodworkingColumn")
                local jewelryColumn = columnContainer:GetNamedChild("JewelryColumn")
                
                ResearchDumpUI.columnTextAreas = {
                    blacksmithing = blacksmithingColumn and blacksmithingColumn:GetNamedChild("TextArea"),
                    clothier = clothierColumn and clothierColumn:GetNamedChild("TextArea"),
                    woodworking = woodworkingColumn and woodworkingColumn:GetNamedChild("TextArea"),
                    jewelry = jewelryColumn and jewelryColumn:GetNamedChild("TextArea")
                }
            end
            -- Keep the old text area reference for backwards compatibility
            ResearchDumpUI.textArea = scrollChild:GetNamedChild("TextArea")
        end
    end
    
    ResearchDumpUI.scrollContainer = scrollContainer
    local titleBar = ResearchDumpWindow:GetNamedChild("TitleBar")
    if titleBar then
        ResearchDumpUI.titleText = titleBar:GetNamedChild("Title")
    end
    
    -- Ensure window starts hidden
    ResearchDumpUI.window:SetHidden(true)
end

-- Show the window with shopping list content
function ResearchDumpUI.ShowShoppingList()
    if not ResearchDumpUI.window then
        ResearchDumpUI.CreateWindow()
    end
    
    -- Generate shopping list data
    GenerateShoppingList(false) -- This populates ResearchDump.columnData
    
    -- Check if we have column text areas
    if ResearchDumpUI.columnTextAreas then
        -- Populate each column with its respective data
        local columnMap = {
            blacksmithing = "blacksmithing",
            clothier = "clothier",
            woodworking = "woodworking",
            jewelry = "jewelry"
        }
        
        for key, columnKey in pairs(columnMap) do
            local textArea = ResearchDumpUI.columnTextAreas[key]
            if textArea and ResearchDump.columnData and ResearchDump.columnData[columnKey] then
                local content = table.concat(ResearchDump.columnData[columnKey].content, "\n")
                textArea:SetText(content)
            elseif textArea then
                textArea:SetText("No items needed!")
            end
        end
    else
        -- Fallback to old single text area if columns aren't available
        local results = GenerateShoppingList(true)
        local content = table.concat(results, "\n")
        if ResearchDumpUI.textArea then
            ResearchDumpUI.textArea:SetText(content)
            ResearchDumpUI.textArea:SetDimensions(ResearchDumpUI.scrollContainer:GetWidth() - 20, 800)
        end
    end
    
    -- Show the window
    ResearchDumpUI.window:SetHidden(false)
    ResearchDumpUI.isVisible = true
    
    d("|c00FF00Shopping list window opened with column layout!|r")
end

-- Show the window with any content
function ResearchDumpUI.ShowContent(title, content)
    if not ResearchDumpUI.window then
        ResearchDumpUI.CreateWindow()
    end
      -- Update title if provided
    if title and ResearchDumpUI.titleText then
        ResearchDumpUI.titleText:SetText(title)
    end
      -- Update the text area
    ResearchDumpUI.textArea:SetText(content)
    -- For EditBox controls, we don't use GetTextHeight() - instead let it auto-size or use a fixed height
    ResearchDumpUI.textArea:SetDimensions(ResearchDumpUI.scrollContainer:GetWidth() - 20, 800)
    
    -- Show the window
    ResearchDumpUI.window:SetHidden(false)
    ResearchDumpUI.isVisible = true
end

-- Hide the window
function ResearchDumpUI.Hide()
    if ResearchDumpUI.window then
        ResearchDumpUI.window:SetHidden(true)
        ResearchDumpUI.isVisible = false
    end
end

-- Toggle window visibility
function ResearchDumpUI.Toggle()
    if ResearchDumpUI.isVisible then
        ResearchDumpUI.Hide()
    else
        ResearchDumpUI.ShowShoppingList()
    end
end

-- Register "/dumpresearch" as a new slash command:
SLASH_COMMANDS["/dumpresearch"] = function(param)
    -- Convert param to string to avoid nil concatenation error
    local paramStr = param and tostring(param) or ""
      -- Trim and convert to lowercase
    param = paramStr:lower():gsub("^%s*(.-)%s*$", "%1")

    if param == "" or param == "all" then
        d("ResearchDump: Running all functions...")
        DumpGearCrafting()
        DumpResearchableItems()
    elseif param == "gear" or param == "traits" then
        d("ResearchDump: Running gear crafting...")
        DumpGearCrafting()
    elseif param == "items" or param == "inventory" then
        d("ResearchDump: Running researchable items...")
        DumpResearchableItems()
    elseif param == "shopping" or param == "list" then
        d("ResearchDump: Generating shopping list...")
        GenerateShoppingList()
    elseif param == "gui" or param == "window" then
        d("ResearchDump: Opening shopping list window...")
        ResearchDumpUI.ShowShoppingList()
    elseif param == "export" or param == "file" then
        d("ResearchDump: Exporting to file...")
        ExportToFile()
    elseif param == "exportgui" then
        d("ResearchDump: Opening export in window...")
        local gearResults = DumpGearCrafting(true)
        local itemResults = DumpResearchableItems(true)
        local shoppingResults = GenerateShoppingList(true)
        local allResults = {}
        
        for _, line in ipairs(gearResults) do
            table.insert(allResults, line)
        end
        table.insert(allResults, "")
        for _, line in ipairs(itemResults) do
            table.insert(allResults, line)
        end
        table.insert(allResults, "")        for _, line in ipairs(shoppingResults) do
            table.insert(allResults, line)
        end
        ResearchDumpUI.ShowContent("ResearchDump - Full Report", table.concat(allResults, "\n"))
    elseif param == "test" or param == "debug" then
        d("ResearchDump: Testing API functions...")
        TestAPIFunctions()
    else
        d("Usage:")
        d("  /dumpresearch [all|gear|items|shopping|gui|export|exportgui|test]")
        d("  all/empty - Show both missing traits and researchable items")
        d("  gear/traits - Show only missing traits")
        d("  items/inventory - Show only researchable items in inventory")
        d("  shopping/list - Generate multi-character shopping list")
        d("  gui/window - Open shopping list in copyable GUI window")
        d("  export/file - Export results to SavedVariables and provide text version")
        d("  exportgui - Open full report in copyable GUI window")
        d("  test/debug - Test which API functions are available")
    end
end
