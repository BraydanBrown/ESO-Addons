--[[  
  ResearchDump.lua  
  Version 1.5 - Cleaned Version with Essential Features Only
  Supports only craftgui, craftguiexpanding, and shopping commands
--]]

-- Initialize addon namespace
ResearchDump = ResearchDump or {}
ResearchDump.columnData = {}

-- Helper function to process character names and remove the first @ character
local function ProcessCharacterName(fullName)
    if not fullName then return "" end
    
    -- Find the first @ character and remove it along with everything before it
    local atPos = string.find(fullName, "@")
    if atPos then
        return string.sub(fullName, atPos + 1)
    end
    
    return fullName
end

-- Wait for addon to be loaded
local function OnAddOnLoaded(eventCode, addonName)
    if addonName ~= "ResearchDump" then return end
    EVENT_MANAGER:UnregisterForEvent("ResearchDump", EVENT_ADD_ON_LOADED)
    
    -- Initialize SavedVariables
    ResearchDumpSavedVars = ResearchDumpSavedVars or {}
    ResearchDumpSavedVars.researchData = ResearchDumpSavedVars.researchData or {}
    
    -- Get current character name
    local currentPlayer = GetDisplayName() .. " @" .. GetUnitName("player")
    
    -- Update research data for current character
    UpdateCurrentCharacterResearchData(currentPlayer)
      -- Initialize GUI
    ResearchDumpUI.CreateWindow()
end

EVENT_MANAGER:RegisterForEvent("ResearchDump", EVENT_ADD_ON_LOADED, OnAddOnLoaded)

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
    
    -- Always build results for potential GUI display
    table.insert(results, "=== Multi-Character Research Shopping List ===")
    table.insert(results, "Generated: " .. GetDateStringFromTimestamp(GetTimeStamp()))
    table.insert(results, "")
    
    -- Check if we have any character data
    if not ResearchDumpSavedVars.researchData or next(ResearchDumpSavedVars.researchData) == nil then
        local noDataText = "No character research data found. Please log in with each character first."
        table.insert(results, noDataText)
        return results
    end
    
    local craftingTypes = {
        { type = CRAFTING_TYPE_BLACKSMITHING, name = "Blacksmithing", key = "blacksmithing" },
        { type = CRAFTING_TYPE_CLOTHIER, name = "Clothier", key = "clothier" },
        { type = CRAFTING_TYPE_WOODWORKING, name = "Woodworking", key = "woodworking" },
        { type = CRAFTING_TYPE_JEWELRYCRAFTING, name = "Jewelry Crafting", key = "jewelry" }
    }
    
    -- Initialize data structures
    local craftGroups = {}
    for _, craft in ipairs(craftingTypes) do
        craftGroups[craft.key] = {
            name = craft.name,
            items = {}
        }
    end
    
    -- Collect missing traits across all characters
    for playerName, researchData in pairs(ResearchDumpSavedVars.researchData) do
        for _, craft in ipairs(craftingTypes) do
            local numLines = GetNumSmithingResearchLines(craft.type)
            
            for lineIndex = 1, numLines do
                local lineName = GetSmithingResearchLineInfo(craft.type, lineIndex)
                
                for traitIndex = 1, 9 do
                    if researchData[craft.type] and 
                       researchData[craft.type][lineIndex] and 
                       researchData[craft.type][lineIndex][traitIndex] == false then
                        
                        local traitType = GetSmithingResearchLineTraitInfo(craft.type, lineIndex, traitIndex)
                        local traitName = GetString("SI_ITEMTRAITTYPE", traitType)
                        
                        if traitName and not string.find(traitName, "<<") then
                            local itemKey = lineName .. " - " .. traitName
                            local found = false
                            
                            -- Check if this item already exists
                            for _, item in ipairs(craftGroups[craft.key].items) do
                                if item.key == itemKey then
                                    item.count = item.count + 1
                                    table.insert(item.characters, ProcessCharacterName(playerName))
                                    found = true
                                    break
                                end
                            end
                            
                            -- Add new item if not found
                            if not found then
                                table.insert(craftGroups[craft.key].items, {
                                    key = itemKey,
                                    lineName = lineName,
                                    traitName = traitName,
                                    count = 1,
                                    characters = { ProcessCharacterName(playerName) }
                                })
                            end
                        end
                    end
                end
            end
        end
    end
    
    -- Store column data for GUI display
    ResearchDump.columnData = {}
    
    -- Generate output and populate column data
    local totalItems = 0
    for _, craft in ipairs(craftingTypes) do
        ResearchDump.columnData[craft.key] = {
            name = craft.name,
            content = {}
        }
        
        if #craftGroups[craft.key].items > 0 then
            -- Sort items by count (most needed first)
            table.sort(craftGroups[craft.key].items, function(a, b)
                return a.count > b.count
            end)
              local craftSection = "=== " .. craftGroups[craft.key].name .. " ==="
            table.insert(results, craftSection)
            table.insert(ResearchDump.columnData[craft.key].content, craftSection)
            
            for _, item in ipairs(craftGroups[craft.key].items) do
                local itemText = string.format("Need %d: %s", item.count, item.key)
                local charactersText = "  Characters: " .. table.concat(item.characters, ", ")
                
                table.insert(results, itemText)
                table.insert(results, charactersText)
                
                table.insert(ResearchDump.columnData[craft.key].content, itemText)
                table.insert(ResearchDump.columnData[craft.key].content, charactersText)
                totalItems = totalItems + item.count
            end
            
            table.insert(results, "")
            table.insert(ResearchDump.columnData[craft.key].content, "")        else
            local completeText = craftGroups[craft.key].name .. ": All characters completed!"
            table.insert(results, "=== " .. completeText .. " ===")
            table.insert(results, "")
            table.insert(ResearchDump.columnData[craft.key].content, "=== " .. completeText .. " ===")
        end
    end
      -- Summary
    local summaryText
    if totalItems > 0 then
        summaryText = string.format("Total items needed: %d across %d character(s)", totalItems, GetNumCharacters())
    else
        summaryText = "No research items needed across all characters!"
    end
    
    table.insert(results, "=== Summary ===")
    table.insert(results, summaryText)
    
    return results
end

-- Function to generate individual character crafting recommendations
local function GenerateCraftingRecommendations(exportMode)
    local results = {}
    
    -- Always build results for potential GUI display
    table.insert(results, "=== Individual Character Crafting Recommendations ===")
    table.insert(results, "Generated: " .. GetDateStringFromTimestamp(GetTimeStamp()))
    table.insert(results, "")
    
    -- Check if we have any character data
    if not ResearchDumpSavedVars.researchData or next(ResearchDumpSavedVars.researchData) == nil then
        local noDataText = "No character research data found. Please log in with each character first."
        table.insert(results, noDataText)
        return results
    end
    
    local craftingTypes = {
        { type = CRAFTING_TYPE_BLACKSMITHING, name = "Blacksmithing", key = "blacksmithing" },
        { type = CRAFTING_TYPE_CLOTHIER, name = "Clothier", key = "clothier" },
        { type = CRAFTING_TYPE_WOODWORKING, name = "Woodworking", key = "woodworking" },
        { type = CRAFTING_TYPE_JEWELRYCRAFTING, name = "Jewelry Crafting", key = "jewelry" }
    }
    
    -- Material recommendations for each craft type
    local craftMaterials = {
        [CRAFTING_TYPE_BLACKSMITHING] = {
            material = "Iron",
            examples = { "Iron Axe", "Iron Mace", "Iron Sword", "Iron Battle Axe", "Iron Maul", "Iron Greatsword", "Iron Dagger" }
        },
        [CRAFTING_TYPE_CLOTHIER] = {
            material = "Jute/Rawhide",
            examples = { "Jute Hat", "Jute Robe", "Jute Gloves", "Rawhide Belt", "Rawhide Boots", "Rawhide Bracers", "Rawhide Guards" }
        },
        [CRAFTING_TYPE_WOODWORKING] = {
            material = "Maple",
            examples = { "Maple Bow", "Maple Staff", "Maple Shield" }
        },
        [CRAFTING_TYPE_JEWELRYCRAFTING] = {
            material = "Pewter",
            examples = { "Pewter Ring", "Pewter Necklace" }
        }
    }
    
    -- Helper function to count known traits in a research line
    local function countKnownTraits(researchData, craftType, lineIndex)
        local count = 0
        if researchData and researchData[craftType] and researchData[craftType][lineIndex] then
            for traitIndex = 1, 9 do
                if researchData[craftType][lineIndex][traitIndex] == true then
                    count = count + 1
                end
            end
        end
        return count
    end
    
    -- Helper function to check if character is currently researching a trait
    local function isCurrentlyResearching(craftType, lineIndex, traitIndex)
        -- Check if current character is researching this trait
        local currentPlayer = GetDisplayName() .. " @" .. GetUnitName("player")
        if ResearchDumpSavedVars.researchData[currentPlayer] then
            local success, remaining = pcall(GetSmithingResearchLineTraitTimes, craftType, lineIndex, traitIndex)
            return success and remaining and remaining > 0
        end
        return false
    end
    
    -- Analyze each character individually
    local characterRecommendations = {}
    
    for playerName, researchData in pairs(ResearchDumpSavedVars.researchData) do
        characterRecommendations[playerName] = {}
        
        -- For each crafting type
        for _, craft in ipairs(craftingTypes) do
            local numLines = GetNumSmithingResearchLines(craft.type)
            
            for lineIndex = 1, numLines do
                local lineName = GetSmithingResearchLineInfo(craft.type, lineIndex)
                local knownTraits = countKnownTraits(researchData, craft.type, lineIndex)
                
                -- Find missing traits for this character
                for traitIndex = 1, 9 do
                    if researchData[craft.type] and 
                       researchData[craft.type][lineIndex] and 
                       researchData[craft.type][lineIndex][traitIndex] == false and
                       not isCurrentlyResearching(craft.type, lineIndex, traitIndex) then
                        
                        local traitType = GetSmithingResearchLineTraitInfo(craft.type, lineIndex, traitIndex)
                        local traitName = GetString("SI_ITEMTRAITTYPE", traitType)
                        
                        if traitName and not string.find(traitName, "<<") then
                            -- Calculate priority score: fewer known traits = higher priority
                            local priorityScore = (9 - knownTraits) * 100 + (9 - traitIndex)
                            
                            table.insert(characterRecommendations[playerName], {
                                craftType = craft.type,
                                craftName = craft.name,
                                lineName = lineName,
                                traitName = traitName,
                                knownTraits = knownTraits,
                                priorityScore = priorityScore,
                                material = craftMaterials[craft.type].material,
                                exampleItem = craftMaterials[craft.type].examples[((lineIndex - 1) % #craftMaterials[craft.type].examples) + 1]
                            })
                        end
                    end
                end
            end
        end
        
        -- Sort recommendations by priority score (higher = more important)
        table.sort(characterRecommendations[playerName], function(a, b)
            return a.priorityScore > b.priorityScore
        end)
    end
      -- Generate output for each character
    for playerName, recommendations in pairs(characterRecommendations) do
        if #recommendations > 0 then
            local characterSection = "=== " .. ProcessCharacterName(playerName) .. " ==="
            table.insert(results, characterSection)
            
            -- Show top 10 recommendations per character
            local maxRecommendations = math.min(10, #recommendations)
            for i = 1, maxRecommendations do
                local rec = recommendations[i]
                local recommendationText = string.format("Priority %d: %s (%s) - %s line: %d/9 traits", 
                    i, rec.exampleItem, rec.traitName, rec.lineName, rec.knownTraits)
                
                table.insert(results, recommendationText)
            end
            
            if #recommendations > maxRecommendations then
                local moreText = string.format("  ... and %d more recommendations", #recommendations - maxRecommendations)
                table.insert(results, moreText)
            end
            
            table.insert(results, "")
        else
            local completeText = ProcessCharacterName(playerName) .. " - All available traits researched!"
            table.insert(results, "=== " .. completeText .. " ===")
            table.insert(results, "")
        end
    end
      -- Summary statistics
    local totalRecommendations = 0
    for _, recommendations in pairs(characterRecommendations) do
        totalRecommendations = totalRecommendations + #recommendations
    end
    
    local summaryText = string.format("Total crafting recommendations: %d across %d character(s)", 
        totalRecommendations, GetNumCharacters())
    
    table.insert(results, "=== Summary ===")
    table.insert(results, summaryText)
    table.insert(results, "Tip: Use the cheapest materials (Iron, Jute, Rawhide, Maple, Pewter) for research items!")
    
    return results
end

-- Function to generate crafting recommendations organized by craft type and character
local function GenerateCraftingRecommendationsByType(exportMode)
    local results = {}
    
    -- Always build results for potential GUI display
    table.insert(results, "=== Crafting Recommendations by Type ===")
    table.insert(results, "Generated: " .. GetDateStringFromTimestamp(GetTimeStamp()))
    table.insert(results, "")
    
    -- Check if we have any character data
    if not ResearchDumpSavedVars.researchData or next(ResearchDumpSavedVars.researchData) == nil then
        local noDataText = "No character research data found. Please log in with each character first."
        table.insert(results, noDataText)
        return results
    end
    
    local craftingTypes = {
        { type = CRAFTING_TYPE_BLACKSMITHING, name = "Blacksmithing", key = "blacksmithing", maxRecommendations = 3 },
        { type = CRAFTING_TYPE_CLOTHIER, name = "Clothier", key = "clothier", maxRecommendations = 3 },
        { type = CRAFTING_TYPE_WOODWORKING, name = "Woodworking", key = "woodworking", maxRecommendations = 3 },
        { type = CRAFTING_TYPE_JEWELRYCRAFTING, name = "Jewelry Crafting", key = "jewelry", maxRecommendations = 1 }
    }
    
    -- Material recommendations for each craft type
    local craftMaterials = {
        [CRAFTING_TYPE_BLACKSMITHING] = {
            material = "Iron",
            examples = { "Iron Axe", "Iron Mace", "Iron Sword", "Iron Battle Axe", "Iron Maul", "Iron Greatsword", "Iron Dagger" }
        },
        [CRAFTING_TYPE_CLOTHIER] = {
            material = "Jute/Rawhide",
            examples = { "Jute Hat", "Jute Robe", "Jute Gloves", "Rawhide Belt", "Rawhide Boots", "Rawhide Bracers", "Rawhide Guards" }
        },
        [CRAFTING_TYPE_WOODWORKING] = {
            material = "Maple",
            examples = { "Maple Bow", "Maple Staff", "Maple Shield" }
        },
        [CRAFTING_TYPE_JEWELRYCRAFTING] = {
            material = "Pewter",
            examples = { "Pewter Ring", "Pewter Necklace" }
        }
    }
    
    -- Helper function to count known traits in a research line
    local function countKnownTraits(researchData, craftType, lineIndex)
        local count = 0
        if researchData and researchData[craftType] and researchData[craftType][lineIndex] then
            for traitIndex = 1, 9 do
                if researchData[craftType][lineIndex][traitIndex] == true then
                    count = count + 1
                end
            end
        end
        return count
    end
    
    -- Helper function to check if character is currently researching a trait
    local function isCurrentlyResearching(craftType, lineIndex, traitIndex)
        local currentPlayer = GetDisplayName() .. " @" .. GetUnitName("player")
        if ResearchDumpSavedVars.researchData[currentPlayer] then
            local success, remaining = pcall(GetSmithingResearchLineTraitTimes, craftType, lineIndex, traitIndex)
            return success and remaining and remaining > 0
        end
        return false
    end
    
    -- Organize recommendations by craft type, then by character
    local craftTypeData = {}
    
    for _, craft in ipairs(craftingTypes) do
        craftTypeData[craft.key] = {
            name = craft.name,
            maxRecommendations = craft.maxRecommendations,
            characters = {}
        }
        
        -- Analyze each character for this craft type
        for playerName, researchData in pairs(ResearchDumpSavedVars.researchData) do
            local characterRecommendations = {}
            local numLines = GetNumSmithingResearchLines(craft.type)
            
            for lineIndex = 1, numLines do
                local lineName = GetSmithingResearchLineInfo(craft.type, lineIndex)
                local knownTraits = countKnownTraits(researchData, craft.type, lineIndex)
                
                -- Find missing traits for this character and craft type
                for traitIndex = 1, 9 do
                    if researchData[craft.type] and
                       researchData[craft.type][lineIndex] and 
                       researchData[craft.type][lineIndex][traitIndex] == false and
                       not isCurrentlyResearching(craft.type, lineIndex, traitIndex) then
                        
                        local traitType = GetSmithingResearchLineTraitInfo(craft.type, lineIndex, traitIndex)
                        local traitName = GetString("SI_ITEMTRAITTYPE", traitType)
                        
                        if traitName and not string.find(traitName, "<<") then
                            -- Calculate priority score: fewer known traits = higher priority
                            local priorityScore = (9 - knownTraits) * 100 + (9 - traitIndex)
                            
                            table.insert(characterRecommendations, {
                                craftType = craft.type,
                                craftName = craft.name,
                                lineName = lineName,
                                traitName = traitName,
                                knownTraits = knownTraits,
                                priorityScore = priorityScore,
                                material = craftMaterials[craft.type].material,
                                exampleItem = craftMaterials[craft.type].examples[((lineIndex - 1) % #craftMaterials[craft.type].examples) + 1]
                            })
                        end
                    end
                end
            end
            
            -- Sort recommendations by priority score (higher = more important)
            table.sort(characterRecommendations, function(a, b)
                return a.priorityScore > b.priorityScore
            end)
            
            -- Store character recommendations if any exist
            if #characterRecommendations > 0 then
                craftTypeData[craft.key].characters[playerName] = characterRecommendations
            end
        end
    end
    
    return craftTypeData
end

-- Function to generate column data for expanding menu crafting recommendations
local function GenerateExpandingMenuColumnData()
    local craftTypeData = GenerateCraftingRecommendationsByType(true)
    local columnData = {
        blacksmithing = { content = {} },
        clothier = { content = {} },
        woodworking = { content = {} },
        jewelry = { content = {} }
    }
    
    -- Map craft keys to column keys
    local craftToColumn = {
        blacksmithing = "blacksmithing",
        clothier = "clothier", 
        woodworking = "woodworking",
        jewelry = "jewelry"
    }
    
    for craftKey, craftData in pairs(craftTypeData) do
        local columnKey = craftToColumn[craftKey]
        if columnKey then
            table.insert(columnData[columnKey].content, "=== " .. craftData.name .. " ===")
            
            if craftData.characters and next(craftData.characters) then
                for characterName, recommendations in pairs(craftData.characters) do
                    table.insert(columnData[columnKey].content, "▼ " .. ProcessCharacterName(characterName))
                    local maxRecs = craftData.maxRecommendations
                    local actualRecs = math.min(maxRecs, #recommendations)
                    for i = 1, actualRecs do
                        local rec = recommendations[i]
                        table.insert(columnData[columnKey].content, string.format("  %d. %s (%s) - %s line: %d/9 traits", 
                            i, rec.exampleItem, rec.traitName, rec.lineName, rec.knownTraits))
                    end
                    table.insert(columnData[columnKey].content, "")
                end
            else
                table.insert(columnData[columnKey].content, "All characters completed!")
            end
            table.insert(columnData[columnKey].content, "")
        end
    end
    
    return columnData
end

-- ResearchDumpUI implementation
ResearchDumpUI = {} 
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

-- Function to generate column data for crafting recommendations
local function GenerateCraftingColumnData()
    local results = GenerateCraftingRecommendations(true)
    local columnData = {
        blacksmithing = { content = {}, header = "Characters" },
        clothier = { content = {}, header = "Characters" },
        woodworking = { content = {}, header = "Characters" },
        jewelry = { content = {}, header = "Characters" }
    }
    
    -- Parse the results and organize by character sections
    local characters = {}
    local currentCharacter = nil
    local characterRecommendations = {}
    
    for _, line in ipairs(results) do
        if string.match(line, "^=== .+ ===") then
            -- This is a character header
            if currentCharacter and #characterRecommendations > 0 then
                -- Store previous character's data
                characters[currentCharacter] = characterRecommendations
            end
            currentCharacter = string.match(line, "^=== (.+) ===")
            characterRecommendations = {}
        elseif currentCharacter and string.match(line, "^Priority %d+:") then
            -- This is a recommendation line
            table.insert(characterRecommendations, line)
        end
    end
    
    -- Store the last character
    if currentCharacter and #characterRecommendations > 0 then
        characters[currentCharacter] = characterRecommendations
    end
    
    -- Distribute characters across the 4 columns
    local columnNames = { "blacksmithing", "clothier", "woodworking", "jewelry" }
    local columnIndex = 1
    
    for characterName, recommendations in pairs(characters) do
        local columnKey = columnNames[columnIndex]
        
        -- Add character header
        table.insert(columnData[columnKey].content, "=== " .. ProcessCharacterName(characterName) .. " ===")
        
        -- Add top 5 recommendations
        local maxRecommendations = math.min(5, #recommendations)
        if maxRecommendations > 0 then
            for i = 1, maxRecommendations do
                table.insert(columnData[columnKey].content, recommendations[i])
            end
        else
            table.insert(columnData[columnKey].content, "  No recommendations")
        end
        
        -- Add spacing between characters
        table.insert(columnData[columnKey].content, "")
        
        -- Move to next column (cycle through all 4 columns)
        columnIndex = columnIndex + 1
        if columnIndex > 4 then
            columnIndex = 1
        end
    end
    
    return columnData
end

-- Function to update column headers dynamically
local function UpdateColumnHeaders(headerTexts)
    if not ResearchDumpUI.window then
        return
    end
    
    local scrollContainer = ResearchDumpUI.window:GetNamedChild("ScrollContainer")
    if not scrollContainer then return end
    
    local scrollChild = scrollContainer:GetNamedChild("ScrollChild")
    if not scrollChild then return end
    
    local columnContainer = scrollChild:GetNamedChild("ColumnContainer")
    if not columnContainer then return end
    
    local columns = {
        { name = "BlacksmithingColumn", key = "blacksmithing" },
        { name = "ClothierColumn", key = "clothier" },
        { name = "WoodworkingColumn", key = "woodworking" },
        { name = "JewelryColumn", key = "jewelry" }
    }
    
    for _, col in ipairs(columns) do
        local column = columnContainer:GetNamedChild(col.name)
        if column then
            local header = column:GetNamedChild("Header")
            if header and headerTexts[col.key] then
                header:SetText(headerTexts[col.key])
            end
        end
    end
end

-- Show the window with shopping list content
function ResearchDumpUI.ShowShoppingList()
    if not ResearchDumpUI.window then
        ResearchDumpUI.CreateWindow()
    end
    
    -- Generate shopping list data
    GenerateShoppingList(false) -- This populates ResearchDump.columnData
    
    -- Update title
    if ResearchDumpUI.titleText then
        ResearchDumpUI.titleText:SetText("ResearchDump - Shopping List")
    end
    
    -- Restore original column headers for shopping list
    local headerTexts = {
        blacksmithing = "Blacksmithing",
        clothier = "Clothier",
        woodworking = "Woodworking",
        jewelry = "Jewelry Crafting"
    }
    UpdateColumnHeaders(headerTexts)
    
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
            if textArea then
                if ResearchDump.columnData[columnKey] and ResearchDump.columnData[columnKey].content then
                    local content = table.concat(ResearchDump.columnData[columnKey].content, "\n")
                    if content and content ~= "" then
                        textArea:SetText(content)
                    else
                        textArea:SetText("No items needed!")
                    end
                else
                    textArea:SetText("No items needed!")
                end
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
end

-- Show the window with expanding menu crafting recommendations content
function ResearchDumpUI.ShowExpandingMenuCraftingRecommendations()
    if not ResearchDumpUI.window then
        ResearchDumpUI.CreateWindow()
    end
    
    -- Generate expanding menu crafting recommendations column data
    local expandingMenuColumnData = GenerateExpandingMenuColumnData()
    
    -- Update title
    if ResearchDumpUI.titleText then
        ResearchDumpUI.titleText:SetText("ResearchDump - Crafting Recommendations by Type")
    end
    
    -- Restore original column headers for craft types
    local headerTexts = {
        blacksmithing = "Blacksmithing",
        clothier = "Clothier",
        woodworking = "Woodworking",
        jewelry = "Jewelry Crafting"
    }
    UpdateColumnHeaders(headerTexts)
    
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
            if textArea then
                if expandingMenuColumnData[columnKey] and expandingMenuColumnData[columnKey].content then
                    local content = table.concat(expandingMenuColumnData[columnKey].content, "\n")
                    if content and content ~= "" then
                        textArea:SetText(content)
                    else
                        textArea:SetText("No recommendations for this craft!")
                    end
                else
                    textArea:SetText("No recommendations for this craft!")
                end
            end
        end
    else
        -- Fallback to old single text area if columns aren't available
        local craftTypeData = GenerateCraftingRecommendationsByType(true)
        local allContent = {}
        
        for craftKey, craftData in pairs(craftTypeData) do
            table.insert(allContent, "=== " .. craftData.name .. " ===")
            if craftData.characters and next(craftData.characters) then
                for characterName, recommendations in pairs(craftData.characters) do
                    table.insert(allContent, "▼ " .. ProcessCharacterName(characterName))
                    local maxRecs = craftData.maxRecommendations
                    local actualRecs = math.min(maxRecs, #recommendations)
                    for i = 1, actualRecs do
                        local rec = recommendations[i]
                        table.insert(allContent, string.format("  %d. %s (%s) - %s line: %d/9 traits", 
                            i, rec.exampleItem, rec.traitName, rec.lineName, rec.knownTraits))
                    end
                    table.insert(allContent, "")
                end
            else
                table.insert(allContent, "All characters completed!")
            end
            table.insert(allContent, "")
        end
        
        local content = table.concat(allContent, "\n")
        if ResearchDumpUI.textArea then
            ResearchDumpUI.textArea:SetText(content)
            ResearchDumpUI.textArea:SetDimensions(ResearchDumpUI.scrollContainer:GetWidth() - 20, 800)
        end
    end
      -- Show the window
    ResearchDumpUI.window:SetHidden(false)
    ResearchDumpUI.isVisible = true
end

-- Show the window with crafting recommendations content
function ResearchDumpUI.ShowCraftingRecommendations()
    if not ResearchDumpUI.window then
        ResearchDumpUI.CreateWindow()
    end
    
    -- Generate crafting recommendations column data
    local craftingColumnData = GenerateCraftingColumnData()
    
    -- Update title
    if ResearchDumpUI.titleText then
        ResearchDumpUI.titleText:SetText("ResearchDump - Crafting Recommendations (Top 5 per Character)")
    end
    
    -- Update column headers to show they contain characters, not craft types
    local headerTexts = {
        blacksmithing = "Characters (1)",
        clothier = "Characters (2)", 
        woodworking = "Characters (3)",
        jewelry = "Characters (4)"
    }
    UpdateColumnHeaders(headerTexts)
    
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
            if textArea then
                if craftingColumnData[columnKey] and craftingColumnData[columnKey].content then
                    local content = table.concat(craftingColumnData[columnKey].content, "\n")
                    if content and content ~= "" then
                        textArea:SetText(content)
                    else
                        textArea:SetText("No recommendations!")
                    end
                else
                    textArea:SetText("No recommendations!")
                end
            end
        end
    else
        -- Fallback to old single text area if columns aren't available
        local results = GenerateCraftingRecommendations(true)
        local content = table.concat(results, "\n")
        if ResearchDumpUI.textArea then
            ResearchDumpUI.textArea:SetText(content)
            ResearchDumpUI.textArea:SetDimensions(ResearchDumpUI.scrollContainer:GetWidth() - 20, 800)
        end
    end
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

-- Slash Commands

-- /craft command - for crafting recommendations
SLASH_COMMANDS["/craft"] = function(param)
    -- Convert param to string to avoid nil concatenation error
    local paramStr = param and tostring(param) or ""
    -- Trim and convert to lowercase
    param = paramStr:lower():gsub("^%s*(.-)%s*$", "%1")
    
    if param == "" or param == "recommendations" then
        ResearchDumpUI.ShowExpandingMenuCraftingRecommendations()
    elseif param == "gui" or param == "window" then
        ResearchDumpUI.ShowCraftingRecommendations()
    elseif param == "expanding" or param == "menu" or param == "expandingmenu" then
        ResearchDumpUI.ShowExpandingMenuCraftingRecommendations()
    end
end

-- /dumpresearch command - supports only shopping, craftgui, and craftguiexpanding
SLASH_COMMANDS["/dumpresearch"] = function(param)
    -- Convert param to string to avoid nil concatenation error
    local paramStr = param and tostring(param) or ""
    -- Trim and convert to lowercase
    param = paramStr:lower():gsub("^%s*(.-)%s*$", "%1")

    if param == "shopping" or param == "list" then
        GenerateShoppingList()
    elseif param == "craft" or param == "recommendations" then
        GenerateCraftingRecommendations()
    elseif param == "craftgui" or param == "craft gui" then
        ResearchDumpUI.ShowCraftingRecommendations()
    elseif param == "craftexpanding" or param == "craft expanding" or param == "craftmenu" then
        ResearchDumpUI.ShowExpandingMenuCraftingRecommendations()
    elseif param == "gui" or param == "window" then
        ResearchDumpUI.ShowShoppingList()
    end
end
