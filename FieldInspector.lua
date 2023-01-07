--
-- Mod: FS22_FieldInspector
--
-- Author: MasterxOfxNone
-- source: 
-- credits: JTSage for the initial code
FieldInspector = {}

local FieldInspector_mt = Class(FieldInspector)

function FieldInspector:new(mission, modDirectory, modName, logger)
    local self = setmetatable({}, FieldInspector_mt)

    self.myName = "FieldInspector"
    self.logger = logger
    self.isServer = mission:getIsServer()
    self.isClient = mission:getIsClient()
    self.isMPGame = g_currentMission.missionDynamicInfo.isMultiplayer
    self.mission = mission
    self.modDirectory = modDirectory
    self.modName = modName
    self.gameInfoDisplay = mission.hud.gameInfoDisplay
    self.inputHelpDisplay = mission.hud.inputHelp
    self.speedMeterDisplay = mission.hud.speedMeter
    self.ingameMap = mission.hud.ingameMap

    source(modDirectory .. 'lib/fs22ModPrefSaver.lua')

    self.settings = FS22PrefSaver:new("FS22_FieldInspector", "fieldInspector.xml", true, {
        displayOrder = "OF1_FLD_FRT_SEP_GRO_OF2",
        displayMode = {3, "int"},
        displayMode5X = 0.2,
        displayMode5Y = 0.2,

        isEnabledVisible = true,
        isEnabledAlphaSort = true,
        isEnabledShowPlayer = false,
        isEnabledShowAll = false,
        isEnabledShowUnowned = false,
        isEnabledShowFieldFruit = true,
        isEnabledShowFieldFruitColor = true,
        isEnabledShowFieldFruitGrowth = true,
        isEnabledShowFieldFruitGrowthColor = true,
        isEnabledPadFieldNum = true,

        setValueMaxDepth = {5, "int"},

        setValueTextMarginX = {15, "int"},
        setValueTextMarginY = {10, "int"},
        setValueTextSize = {12, "int"},
        isEnabledTextBold = false,

        colorNormal = {{1.000, 1.000, 1.000, 1}, "color"},
        colorFillType = {{0.700, 0.700, 0.700, 1}, "color"},
        colorUser = {{0.000, 0.777, 1.000, 1}, "color"},
        colorAI = {{0.956, 0.462, 0.644, 1}, "color"},
        colorRunning = {{0.871, 0.956, 0.423, 1}, "color"},
        colorAIMark = {{1.000, 0.082, 0.314, 1}, "color"},
        colorSep = {{1.000, 1.000, 1.000, 1}, "color"},
        colorSpeed = {{1.000, 0.400, 0.000, 1}, "color"},
        colorDiesel = {{0.434, 0.314, 0.000, 1}, "color"},
        colorDEF = {{0.162, 0.440, 0.880, 1}, "color"},
        colorMethane = {{1.000, 0.930, 0.000, 1}, "color"},
        colorElectric = {{0.031, 0.578, 0.314, 1}, "color"},
        colorDamaged = {{0.830, 0.019, 0.033, 1}, "color"},

        colorField = {{0.423, 0.956, 0.624, 1}, "color"},
        colorFruit = {{0.956, 0.462, 0.644, 1}, "color"},
        colorGrowth = {{0.000, 0.777, 1.000, 1}, "color"},

        setStringTextHelper = "_AI_",
        setStringTextADHelper = "_AD_",
        setStringTextOnField1 = ">>",
        setStringTextOnField2 = "<<",
        setStringTextField = "Field ",
        setStringTextFieldNoNum = "-F-",
        setStringTextFieldFruit = "",
        setStringTextFieldFruitGrowth = "",
        setStringTextDamaged = "-!!-",
        setStringTextSep = " | "
    }, function()
        self.inspectText.size =
            self.gameInfoDisplay:scalePixelToScreenHeight(self.settings:getValue("setValueTextSize"))
    end, nil, self.logger)

    self.debugTimerRuns = 0
    self.setValueTimerFrequency = 15
    self.inspectText = {}
    self.boxBGColor = {544, 20, 200, 44}
    self.bgName = 'dataS/menu/blank.png'
    self.menuTextSizes = {8, 10, 12, 14, 16}

    local modDesc = loadXMLFile("modDesc", modDirectory .. "modDesc.xml");
    self.version = getXMLString(modDesc, "modDesc.version");
    delete(modDesc)

    self.display_data = {}

    self.shown_farms_mp = 0

    self.lastGrowthStates = {}
    -- self.fieldTexts, self.fieldIndices = self:getFieldTexts()
    self.growthStateTexts, self.fruitTypeTexts, self.fruitTypes = self:getGrowthAndFruitData()
    -- self.groundLayerTexts, self.groundLayers = self:getGroundLayerData()
    -- self.weedStateTexts, self.weedStates = self:getWeedData()
    -- self.angleTexts, self.angles = self:getAngleData()
    -- self.groundTypeTexts, self.groundTypes = self:getGroundTypeData()
    -- self.stoneStateTexts, self.stoneStates = self:getStoneData()

    self.logger:print(":new() Initialized", FS22Log.LOG_LEVEL.VERBOSE, "method_track")

    return self
end

function FieldInspector:save()
    self.settings:saveSettings()
end

function FieldInspector:openConstructionScreen()
    -- hack for construction screen showing blank box.
    g_fieldInspector.inspectBox:setVisible(false)
end

function FieldInspector:getFieldTexts()
    local fieldTexts = {}
    local fieldIndices = {}

    for fieldIndex, _ in ipairs(g_fieldManager:getFields()) do
        table.insert(fieldTexts, tostring(fieldIndex))
        table.insert(fieldIndices, fieldIndex)
    end

    table.insert(fieldTexts, g_i18n:getText("text_fieldInspector_all"))
    table.insert(fieldIndices, 0)

    return fieldTexts, fieldIndices
end

function FieldInspector:getGrowthAndFruitData()
    local prepareText = g_i18n:getText("ui_growthMapReadyToPrepareForHarvest")
    local harvestText = g_i18n:getText("ui_growthMapReadyToHarvest")
    local witheredText = g_i18n:getText("ui_growthMapWithered")
    local growingText = g_i18n:getText("ui_growthMapGrowing")
    local cutText = g_i18n:getText("ui_growthMapCut")
    local sownText = g_i18n:getText("ui_growthMapSown")

    local growthStateTexts = {}

    local fruitTypeTexts = {}
    local fruitTypes = {}

    for index, fruitType in pairs(g_fruitTypeManager.indexToFruitType) do
        if fruitType.isGrowing and fruitType.cutState > 0 and fruitType.numGrowthStates > 0 and fruitType.allowsSeeding then
            local fillType = g_fruitTypeManager:getFillTypeByFruitTypeIndex(index)
            local numFruitTypes = #fruitTypes + 1
            local texts = {}

            local harvestingState = 1
            local preparingState = 1
            local growingState = 0

            local maxGrowingState = fruitType.minHarvestingGrowthState - 1

            local minPreparingState = fruitType.minPreparingGrowthState
            local maxPreparingState = fruitType.maxPreparingGrowthState

            local maxHarvestingState = fruitType.maxHarvestingGrowthState
            local witheredState = fruitType.witheredState or maxHarvestingState + 1

            if minPreparingState >= 0 then
                maxGrowingState = math.min(maxGrowingState, minPreparingState - 1)
            end

            if maxPreparingState >= 0 then
                witheredState = maxPreparingState + 1
            end

            -- if fruitType.preparedGrowthState >= 0 then
            -- maxGrowingState = maxHarvestingState
            -- end

            local numPreparingStates = 0

            if minPreparingState >= 0 and maxPreparingState >= 0 then
                numPreparingStates = 1 + (maxPreparingState - minPreparingState)
            end

            local numHarvestingStates = 1 + (maxHarvestingState - fruitType.minHarvestingGrowthState)

            for growthState = 1, (2 ^ fruitType.numStateChannels - 1) do
                if growthState == witheredState and witheredState ~= maxHarvestingState then
                    table.insert(texts, witheredText)
                elseif growthState == fruitType.cutState then
                    table.insert(texts, cutText)
                elseif growthState <= maxGrowingState then
                    if maxGrowingState > 1 and growingState > 0 then
                        if maxGrowingState > 2 then
                            table.insert(texts,
                                string.format("%s (%d/%d)", growingText, growingState, maxGrowingState - 1))
                        else
                            table.insert(texts, growingText)
                        end
                    else
                        table.insert(texts, sownText)
                    end

                    growingState = growingState + 1
                elseif numPreparingStates > 0 and growthState >= minPreparingState and growthState <= maxPreparingState then
                    if numPreparingStates > 1 then
                        table.insert(texts, string.format("%s %d", prepareText, preparingState))

                        preparingState = preparingState + 1
                    else
                        table.insert(texts, prepareText)
                    end
                elseif growthState <= maxHarvestingState then
                    table.insert(texts, harvestText)
                end
            end

            self.lastGrowthStates[numFruitTypes] = 1
            growthStateTexts[numFruitTypes] = texts
            fruitTypeTexts[numFruitTypes] = fillType.title
            fruitTypes[numFruitTypes] = index
        end
    end

    return growthStateTexts, fruitTypeTexts, fruitTypes
end

function FieldInspector:getGrowthAndFruitTexts(field, index)
    local plowedText = g_i18n:getText("ui_growthMapPlowed")
    local cultivatedText = g_i18n:getText("ui_growthMapCultivated")

    local fruitTypeText, growthStateText
    local fruitType = g_fruitTypeManager:getFruitTypeByIndex(index)
    if fruitType ~= nil then
        local withered = fruitType.maxHarvestingGrowthState + 1
        local cutState = fruitType.cutState
        local maxAskState = math.max(withered, cutState)

        local maxGrowthState = 0
        local maxArea = 0
        local x, z = FieldUtil.getMeasurementPositionOfField(field)

        for i = 0, maxAskState do
            local area, _ = FieldUtil.getFruitArea(x - 1, z - 1, x + 1, z - 1, x - 1, z + 1, FieldUtil.FILTER_EMPTY,
                FieldUtil.FILTER_EMPTY, index, i, i, 0, 0, 0, false)

            if maxArea < area then
                maxGrowthState = i
                maxArea = area
            end
        end

        local tIndex
        for i = 1, #self.fruitTypes do
            if index == self.fruitTypes[i] then
                tIndex = i
                break
            end
        end

        local growthStateTextTable = self.growthStateTexts[tIndex]
        growthStateText = growthStateTextTable[maxGrowthState]
        if growthStateText == nil then
            growthStateText = cultivatedText;
        end
        
        fruitTypeText = self.fruitTypeTexts[tIndex]
    else
        growthStateText = "No Growth"
        fruitTypeText = "No Fruit"
    end

    return growthStateText, fruitTypeText, fruitType
end

function FieldInspector:getGroundLayerData()
    local unknownTexts = g_i18n:getText("text_fieldInspector_unknown")

    local fieldGroundSystem = g_currentMission.fieldGroundSystem
    local sprayTypeMaxValue = fieldGroundSystem:getMaxValue(FieldDensityMap.SPRAY_TYPE)

    local chopperStraw = fieldGroundSystem:getChopperTypeValue(FieldChopperType.CHOPPER_STRAW)
    local chopperMaize = fieldGroundSystem:getChopperTypeValue(FieldChopperType.CHOPPER_MAIZE)

    local groundLayerTexts = {EasyDevUtils.getFieldSprayTypeTitle("NONE", "None")}

    local groundLayers = {0}

    for i = 1, sprayTypeMaxValue do
        local sprayType = nil
        local name = unknownTexts

        for identifier, layerId in pairs(fieldGroundSystem.fieldSprayTypeValue) do
            if layerId == i then
                sprayType = identifier

                break
            end
        end

        if sprayType ~= nil then
            name = FieldSprayType.getName(sprayType)
            name = EasyDevUtils.getFieldSprayTypeTitle(name, name)
        elseif i == chopperStraw then
            name = EasyDevUtils.getFieldSprayTypeTitle("STRAW", "Straw")
        elseif i == chopperMaize then
            name = EasyDevUtils.getFieldSprayTypeTitle("MAIZE", "Maize")
        elseif i == sprayTypeMaxValue then
            name = EasyDevUtils.getFieldSprayTypeTitle("MASK", "Mask")
        end

        table.insert(groundLayerTexts, name)
        table.insert(groundLayers, i)
    end

    return groundLayerTexts, groundLayers
end

function FieldInspector:getWeedData()
    -- Future: Use 'getFieldInfoStates' and '<herbicide><replacements>' from the maps_weed.xml to make this dynamic

    local smallText = EasyDevUtils.getText("text_fieldInspector_small")
    local mediumText = EasyDevUtils.getText("text_fieldInspector_medium")
    local largeText = EasyDevUtils.getText("text_fieldInspector_large")
    local growingText = EasyDevUtils.getText("text_fieldInspector_growing")
    local witheredText = EasyDevUtils.getText("text_fieldInspector_withered")

    local weedStateTexts = {g_i18n:getText("ui_none"), string.format("%s (%s)", smallText, growingText),
                            string.format("%s (%s)", mediumText, growingText), smallText, mediumText, largeText,
                            EasyDevUtils.getText("text_fieldInspector_partial"),
                            string.format("%s (%s)", smallText, witheredText),
                            string.format("%s (%s)", mediumText, witheredText),
                            string.format("%s (%s)", largeText, witheredText)}

    local weedStates = {}

    for i = 0, #weedStateTexts - 1 do
        table.insert(weedStates, i)
    end

    return weedStateTexts, weedStates
end

function FieldInspector:getAngleData()
    local angleMaxValue = g_currentMission.fieldGroundSystem:getGroundAngleMaxValue()

    if angleMaxValue == nil then
        return {"0°"}, {0}
    end

    local angles = {}
    local angleTexts = {}
    local increment = 180 / (angleMaxValue + 1)

    for i = 0, angleMaxValue do
        table.insert(angleTexts, string.format("%d°", increment * i))
        table.insert(angles, i)
    end

    -- Same values but allows a user to see 360° worth of available angles
    for i = 0, angleMaxValue do
        table.insert(angleTexts, string.format("%d°", 180 + increment * i))
        table.insert(angles, i)
    end

    return angleTexts, angles
end

function FieldInspector:getGroundTypeData()
    local groundTypeTexts = {}
    local groundTypes = {}

    for i, groundType in ipairs(FieldGroundType.getAllOrdered()) do
        table.insert(groundTypes, groundType)
    end

    table.sort(groundTypes)

    for i, groundType in ipairs(groundTypes) do
        local name = FieldGroundType.getName(groundType) or "INVALID"

        groundTypeTexts[i] = EasyDevUtils.getFieldGroundTypeTitle(name, name)
    end

    return groundTypeTexts, groundTypes
end

function FieldInspector:getStoneData()
    local stoneStateTexts = {}
    local stoneStates = {}

    local stoneSystem = g_currentMission.stoneSystem

    if stoneSystem ~= nil then
        local stateText = EasyDevUtils.getText("text_fieldInspector_state")

        local maskValue = stoneSystem:getMaskValue()
        local pickedValue = stoneSystem:getPickedValue()
        local minValue, maxValue = g_currentMission.stoneSystem:getMinMaxValues()

        table.insert(stoneStateTexts, string.format(stateText, tostring(maskValue)))
        table.insert(stoneStates, maskValue)

        for value = minValue, maxValue do
            if value ~= maskValue and value ~= pickedValue then
                table.insert(stoneStateTexts, string.format(stateText, tostring(value)))
                table.insert(stoneStates, value)
            end
        end

        table.insert(stoneStateTexts, EasyDevUtils.getText("text_fieldInspector_picked"))
        table.insert(stoneStates, pickedValue)
    else
        stoneStateTexts[1] = g_i18n:getText("ui_none")
        stoneStates[1] = 0
    end

    return stoneStateTexts, stoneStates
end

function FieldInspector.getPlayerWorldLocation(getCameraBackup)
    if g_currentMission ~= nil then
        local player = g_currentMission.player
        local controlledVehicle = g_currentMission.controlledVehicle

        if controlledVehicle ~= nil then
            local x, y, z = getWorldTranslation(controlledVehicle.rootNode)
            local dirX, _, dirZ = localDirectionToWorld(controlledVehicle.rootNode, 0, 0, 1)

            return x, y, z, dirX, dirZ, player, controlledVehicle
        end

        if g_currentMission.controlPlayer and player ~= nil and (player.rootNode ~= nil and player.rootNode ~= 0) then
            local x, y, z = getWorldTranslation(player.rootNode)

            return x, y, z, -math.sin(player.rotY), -math.cos(player.rotY), player
        end

        if getCameraBackup then
            local x, y, z = getWorldTranslation(getCamera(0))

            return x, y, z, 0, 0, player
        end
    end

    return nil
end

function FieldInspector.isPlayerOnField()
    local startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, posX, posZ =
        FieldInspector.getProjectedArea(5, 5, 2, false)
    local _, fieldArea, _ = FSDensityMapUtil.getFieldDensity(startWorldX, startWorldZ, widthWorldX, widthWorldZ,
        heightWorldX, heightWorldZ)

    local currentFieldIndex = 0

    if fieldArea ~= 0 then
        local farmland = g_farmlandManager:getFarmlandAtWorldPosition(posX, posZ)

        if farmland ~= nil then
            local lastDistance = math.huge

            for _, field in ipairs(g_fieldManager.farmlandIdFieldMapping[farmland.id] or EMPTY_TABLE) do
                local distance = MathUtil.vector2Length(posX - field.posX, posZ - field.posZ)

                if distance < lastDistance then
                    lastDistance = distance
                    currentFieldIndex = field.fieldId
                end
            end
        end
    end

    return currentFieldIndex ~= 0, currentFieldIndex
end

function FieldInspector.getProjectedArea(sizeX, sizeZ, distance, getWidthAndHeight)
    local posX, _, posZ, dirX, dirZ = FieldInspector.getPlayerWorldLocation(true)

    sizeX = sizeX or 5
    sizeZ = sizeZ or 5
    distance = distance or 2

    local sideX, _, sideZ = MathUtil.crossProduct(dirX, 0, dirZ, 0, 1, 0)
    local startWorldX = posX - sideX * sizeX * 0.5 + dirX * distance
    local startWorldZ = posZ - sideZ * sizeX * 0.5 + dirZ * distance
    local widthWorldX = posX + sideX * sizeX * 0.5 + dirX * distance
    local widthWorldZ = posZ + sideZ * sizeX * 0.5 + dirZ * distance
    local heightWorldX = posX - sideX * sizeX * 0.5 + dirX * (distance + sizeZ)
    local heightWorldZ = posZ - sideZ * sizeX * 0.5 + dirZ * (distance + sizeZ)

    local positionX = (startWorldX + widthWorldX + heightWorldX) / 3
    local positionZ = (startWorldZ + widthWorldZ + heightWorldZ) / 3

    if getWidthAndHeight then
        startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ = MathUtil.getXZWidthAndHeight(
            startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ)
    end

    return startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, positionX, positionZ
end

function FieldInspector:updateFields()
    local new_data_table = {}
    local myFarmID = self.mission:getFarmId()

    -- I want to see my farm name, this defaults to 1 farm on single player mode
    self.shown_farms_mp = self.isMPGame and 0 or 1

    if g_currentMission ~= nil then

        local sortOrder = {}

        for _, thisField in ipairs(g_fieldManager:getFields()) do
            local thisFarmID = g_farmlandManager:getFarmlandOwner(thisField.farmland.id)
            local isMyFarmID = thisFarmID == myFarmID

            -- todo     show multipler details

            if isMyFarmID then
                local thisFarm = g_farmManager:getFarmById(thisFarmID)
                local thisFarmColor = thisFarm.color
                local thisFarmName = thisFarm.name
                local farmName = g_i18n:getText("fieldInfo_ownerYou")

                table.insert(sortOrder, {
                    farm = thisFarm,
                    farmID = thisFarmID,
                    field = thisField,
                    fieldId = thisField.fieldId,
                    isMine = isMyFarmID
                })
            end
        end

        if self.settings:getValue("isEnabledAlphaSort") then
            -- Alpha sort fields
            JTSUtil.sortTableByKey(sortOrder, "fieldId")
        end

        if self.isMPGame then
            -- We need to sort by farmID last - also controls how many headings we see later.
            JTSUtil.sortTableByKey(sortOrder, "farmID")
        end

        local lastFarmID = -1

        --  iterate through table of fields, add more details to outgoing data table
        for _, sortEntry in ipairs(sortOrder) do
            local thisFarmID = sortEntry.farmID

            local thisFarm = sortEntry.farm
            local thisFarmName = thisFarm.name
            local thisFarmColor = thisFarm.color

            local thisField = sortEntry.field
            local thisFieldId = sortEntry.fieldId

            local growthStateText, fruitTypeText, fruitType =
                self:getGrowthAndFruitTexts(thisField, thisField.fruitType)

            if fruitType ~= nil then
                local isMine = sortEntry.isMine

                if self.isMPGame and thisFarmID ~= lastFarmID then
                    -- this counts how many farms we have active in the display
                    lastFarmID = thisFarmID
                    self.shown_farms_mp = self.shown_farms_mp + 1
                end

                -- check if on field
                local onField, onWhatField = self:isPlayerOnField()

                table.insert(new_data_table, {
                    isMine = isMine,
                    farmInfo = {
                        farmID = thisFarmID,
                        farmName = thisFarmName,
                        farmColor = thisFarmColor
                    },
                    fieldInfo = {
                        onField = onField and thisFieldId == onWhatField,
                        fieldNum = thisField.fieldId,
                        fieldColor = thisField.mapHotspot.color
                    },
                    fruitInfo = {
                        fruitType = fruitType,
                        fruitTypeText = fruitTypeText,
                        fruitGrowthState = growthStateText,
                        fruitTypeColor = fruitType.defaultMapColor
                    }
                })
            end
        end
    end

    self.display_data = {unpack(new_data_table)}
end

function FieldInspector:draw()
    if not self.isClient then
        return
    end

    if self.inspectBox ~= nil then
        local info_text = self.display_data
        local overlayH, dispTextH, dispTextW = 0, 0, 0
        local outputTextLines = {}

        if #info_text == 0 and not self.settings:getValue("isEnabledVisible") or g_sleepManager:getIsSleeping() or
            g_noHudModeEnabled or not g_currentMission.hud.isVisible then
            -- we have no entries, hide the overlay and leave
            self.inspectBox:setVisible(false)
            return
        elseif g_gameSettings:getValue("ingameMapState") == 4 and self.settings:getValue("displayMode") % 2 ~= 0 and
            g_currentMission.inGameMenu.hud.inputHelp.overlay.visible then
            -- Left side display hide on big map with help open
            self.inspectBox:setVisible(false)
            return
        else
            -- we have entries, lets get the overall height of the box and unhide
            self.inspectBox:setVisible(true)
            dispTextH = (self.inspectText.size * #info_text) + (self.inspectText.size * self.shown_farms_mp)
            overlayH = dispTextH + (2 * self.inspectText.marginHeight)
        end

        setTextBold(self.settings:getValue("isEnabledTextBold"))
        setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_TOP)

        -- overlayX/Y is where the box starts
        local overlayX, overlayY = self:findOrigin()
        -- dispTextX/Y is where the text starts (sort of)
        local dispTextX, dispTextY = self:findOrigin()

        if (self.settings:getValue("displayMode") == 2) then
            -- top right (subtract both margins)
            dispTextX = dispTextX - self.marginWidth
            dispTextY = dispTextY - self.marginHeight
            overlayY = overlayY - overlayH
        elseif (self.settings:getValue("displayMode") == 3) then
            -- bottom left (add x width, add Y height)
            dispTextX = dispTextX + self.marginWidth
            dispTextY = dispTextY - self.marginHeight + overlayH
        elseif (self.settings:getValue("displayMode") == 4) then
            -- bottom right (subtract x width, add Y height)
            dispTextX = dispTextX - self.marginWidth
            dispTextY = dispTextY - self.marginHeight + overlayH
        else
            -- top left (add X width, subtract Y height)
            dispTextX = dispTextX + self.marginWidth
            dispTextY = dispTextY - self.marginHeight
            overlayY = overlayY - overlayH
        end

        if (self.settings:getValue("displayMode") % 2 == 0) then
            setTextAlignment(RenderText.ALIGN_RIGHT)
        else
            setTextAlignment(RenderText.ALIGN_LEFT)
        end

        if g_currentMission.hud.sideNotifications ~= nil and self.settings:getValue("displayMode") == 2 then
            if #g_currentMission.hud.sideNotifications.notificationQueue > 0 then
                local deltaY = g_currentMission.hud.sideNotifications:getHeight()
                dispTextY = dispTextY - deltaY
                overlayY = overlayY - deltaY
            end
        end

        self.inspectText.posX = dispTextX
        self.inspectText.posY = dispTextY

        local displayOrderTable = JTSUtil.stringSplit(self.settings:getValue("displayOrder"), "_")

        local lastFarmID = -1

        for _, thisEntry in pairs(info_text) do
            if self.isMPGame and lastFarmID ~= thisEntry.farmInfo.farmID then
                -- Show the farm name, it's different from the last entry
                lastFarmID = thisEntry.farmInfo.farmID

                JTSUtil.dispStackAdd(outputTextLines, thisEntry.farmInfo.farmName, thisEntry.farmInfo.farmColor, true)
            end

            JTSUtil.stackNewRow(outputTextLines)

            for _, dispElement in pairs(displayOrderTable) do
                local doAddSeperator = false

                if dispElement:sub(1, 3) == "OF1" and thisEntry.fieldInfo.onField then
                    -- On Field mark prefix, no separator
                    JTSUtil.dispStackAdd(outputTextLines, self.settings:getValue("setStringTextOnField1"),
                        self:getNamedColor("colorUser"))
                end

                if dispElement:sub(1, 3) == "OF2" and thisEntry.fieldInfo.onField then
                    -- On Field mark suffix, no separator
                    JTSUtil.dispStackAdd(outputTextLines, self.settings:getValue("setStringTextOnField2"),
                        self:getNamedColor("colorUser"))
                end

                if dispElement:sub(1, 3) == "FLD" then
                    -- Field mark
                    local fieldNum = self.settings:getValue("isEnabledPadFieldNum") and
                                         string.format('%02d', thisEntry.fieldInfo.fieldNum) or
                                         thisEntry.fieldInfo.fieldNum
                    local fieldNumText = JTSUtil.qConcat(self.settings:getValue("setStringTextField"), fieldNum, ": ")
                    local fieldColor = thisEntry.fieldInfo.fieldColor
                    if type(fieldColor) ~= 'table' then
                        fieldColor = self:getNamedColor("colorField")
                    end

                    JTSUtil.dispStackAdd(outputTextLines, fieldNumText, fieldColor)
                end

                if dispElement:sub(1, 3) == "FRT" and self.settings:getValue("isEnabledShowFieldFruit") and
                    thisEntry.fruitInfo ~= nil then
                    -- Field fruit mark
                    doAddSeperator = true

                    local fruitTypeText = thisEntry.fruitInfo.fruitTypeText
                    local fruitTypeColor = thisEntry.fruitInfo.fruitTypeColor
                    if not self.settings:getValue("isEnabledShowFieldFruitColor") or type(fruitTypeColor) ~= 'table' then
                        fruitTypeColor = self:getNamedColor("colorFruit")
                    end

                    JTSUtil.dispStackAdd(outputTextLines, fruitTypeText, fruitTypeColor)
                end

                if dispElement:sub(1, 3) == "GRO" and self.settings:getValue("isEnabledShowFieldFruitGrowth") and
                    thisEntry.fruitInfo ~= nil then
                    -- Field fruit growth state
                    doAddSeperator = true

                    local growthStateText = thisEntry.fruitInfo.fruitGrowthState
                    local growthStateColor = self.settings:getValue("isEnabledShowFieldFruitGrowthColor") and
                                                 self:getNamedColor("colorDEF") or self:getNamedColor("colorGrowth")

                    JTSUtil.dispStackAdd(outputTextLines, growthStateText, growthStateColor)
                end

                if dispElement == "SEP" or (dispElement:sub(-1) == "*" and doAddSeperator) then
                    -- Seperator (or Element with star)
                    JTSUtil.dispStackAdd(outputTextLines, self.settings:getValue("setStringTextSep"),
                        self:getNamedColor("colorSep"))
                end

                if dispElement:sub(-1) == "-" and doAddSeperator then
                    -- Extra space
                    JTSUtil.dispStackAdd(outputTextLines, " ", {1, 1, 1, 1})
                end
            end
        end

        self.logger:printVariable(outputTextLines, FS22Log.LOG_LEVEL.VERBOSE, "outputTextLines", 3)

        for dispLineNum = 1, #outputTextLines do
            local thisLinePlainText = ""

            for _, dispElement in ipairs(JTSUtil.dispGetLine(outputTextLines, dispLineNum,
                (self.settings:getValue("displayMode") % 2 == 0))) do
                setTextColor(unpack(dispElement.color))
                thisLinePlainText = self:renderText(dispTextX, dispTextY, thisLinePlainText, dispElement.text)
            end

            dispTextY = dispTextY - self.inspectText.size

            local tmpW = getTextWidth(self.inspectText.size, thisLinePlainText)

            if tmpW > dispTextW then
                dispTextW = tmpW
            end
        end

        -- update overlay background
        if self.settings:getValue("displayMode") % 2 == 0 then
            self.inspectBox.overlay:setPosition(overlayX - (dispTextW + (2 * self.inspectText.marginWidth)), overlayY)
        else
            self.inspectBox.overlay:setPosition(overlayX, overlayY)
        end

        self.inspectBox.overlay:setDimension(dispTextW + (self.inspectText.marginWidth * 2), overlayH)

        -- reset text render to "defaults" to be kind
        setTextColor(1, 1, 1, 1)
        setTextAlignment(RenderText.ALIGN_LEFT)
        setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_BASELINE)
        setTextBold(false)
    end
end

function FieldInspector:update(dt)
    if not self.isClient then
        return
    end

    if g_updateLoopIndex % self.setValueTimerFrequency == 0 then
        -- Lets not be rediculous, only update the fields "infrequently"
        self:updateFields()
    end
end

function FieldInspector:getNamedColor(name)
    return Utils.getNoNil(self.settings:getValue(name), {1, 1, 1, 1})
end

function FieldInspector:renderText(x, y, fullTextSoFar, text)
    local newX = x

    if self.settings:getValue("displayMode") % 2 == 0 then
        newX = newX - getTextWidth(self.inspectText.size, fullTextSoFar)
    else
        newX = newX + getTextWidth(self.inspectText.size, fullTextSoFar)
    end

    renderText(newX, y, self.inspectText.size, text)
    return text .. fullTextSoFar
end

function FieldInspector:onStartMission(mission)
    -- Load the mod, make the box that info lives in.

    self.logger:print(JTSUtil.qConcat("Loaded - version : ", self.version), FS22Log.LOG_LEVEL.INFO, "user_info")

    if not self.isClient then
        return
    end

    -- Check required mods
    self:checkOtherMods();

    -- Just call both, load fails gracefully if it doesn't exists.
    self.settings:loadSettings()
    self.settings:saveSettings()

    self.logger:print(":onStartMission()", FS22Log.LOG_LEVEL.VERBOSE, "method_track")

    self:createTextBox()
end

function FieldInspector:checkOtherMods()
    
end

function FieldInspector:findOrigin()
    local tmpX = 0
    local tmpY = 0

    if (self.settings:getValue("displayMode") == 2) then
        -- top right display
        tmpX, tmpY = self.gameInfoDisplay:getPosition()
        tmpX = 1
        tmpY = tmpY - 0.012
    elseif (self.settings:getValue("displayMode") == 3) then
        -- Bottom left, correct origin.
        tmpX = 0.01622
        tmpY = 0 + self.ingameMap:getHeight() + 0.01622
        if g_gameSettings:getValue("ingameMapState") > 1 then
            tmpY = tmpY + 0.032
        end
    elseif (self.settings:getValue("displayMode") == 4) then
        -- bottom right display
        tmpX = 1
        tmpY = 0.01622
        if g_currentMission.inGameMenu.hud.speedMeter.overlay.visible then
            tmpY = tmpY + self.speedMeterDisplay:getHeight() + 0.032
            if g_modIsLoaded["FS22_EnhancedVehicle"] or g_modIsLoaded["FS22_guidanceSteering"] then
                tmpY = tmpY + 0.03
            end
        end
    elseif (self.settings:getValue("displayMode") == 5) then
        tmpX = self.settings:getValue("displayMode5X")
        tmpY = self.settings:getValue("displayMode5Y")
    else
        -- top left display
        tmpX = 0.014
        tmpY = 0.945
        if g_currentMission.inGameMenu.hud.inputHelp.overlay.visible then
            tmpY = tmpY - self.inputHelpDisplay:getHeight() - 0.012
        end
    end

    return tmpX, tmpY
end

function FieldInspector:createTextBox()
    -- make the box we live in.
    self.logger:print(":createTextBox()", FS22Log.LOG_LEVEL.VERBOSE, "method_track")

    local baseX, baseY = self:findOrigin()

    local boxOverlay = nil

    self.marginWidth, self.marginHeight = self.gameInfoDisplay:scalePixelToScreenVector({8, 8})

    if (self.settings:getValue("displayMode") % 2 == 0) then -- top right
        boxOverlay = Overlay.new(self.bgName, baseX, baseY - self.marginHeight, 1, 1)
    else -- default to 1
        boxOverlay = Overlay.new(self.bgName, baseX, baseY + self.marginHeight, 1, 1)
    end

    local boxElement = HUDElement.new(boxOverlay)

    self.inspectBox = boxElement

    self.inspectBox:setUVs(GuiUtils.getUVs(self.boxBGColor))
    self.inspectBox:setColor(unpack(SpeedMeterDisplay.COLOR.GEARS_BG))
    self.inspectBox:setVisible(false)
    self.gameInfoDisplay:addChild(boxElement)

    self.inspectText.marginWidth, self.inspectText.marginHeight =
        self.gameInfoDisplay:scalePixelToScreenVector({self.settings:getValue("setValueTextMarginX"),
                                                       self.settings:getValue("setValueTextMarginY")})
    self.inspectText.size = self.gameInfoDisplay:scalePixelToScreenHeight(self.settings:getValue("setValueTextSize"))
end

function FieldInspector:delete()
    -- clean up on remove
    if self.inspectBox ~= nil then
        self.inspectBox:delete()
    end
end

function FieldInspector:registerActionEvents()
    local _, reloadConfig = g_inputBinding:registerActionEvent('FieldInspector_reload_config', self,
        FieldInspector.actionReloadConfig, false, true, false, true)
    g_inputBinding:setActionEventTextVisibility(reloadConfig, false)
    local _, toggleVisible = g_inputBinding:registerActionEvent('FieldInspector_toggle_visible', self,
        FieldInspector.actionToggleVisible, false, true, false, true)
    g_inputBinding:setActionEventTextVisibility(toggleVisible, false)
    local _, toggleAllFarms = g_inputBinding:registerActionEvent('FieldInspector_toggle_allfarms', self,
        FieldInspector.actionToggleAllFarms, false, true, false, true)
    g_inputBinding:setActionEventTextVisibility(toggleAllFarms, false)
end

function FieldInspector:actionReloadConfig()
    local thisModEnviroment = getfenv(0)["g_fieldInspector"]

    thisModEnviroment.logger:print("force reload settings", FS22Log.LOG_LEVEL.INFO, "user_info")

    thisModEnviroment.settings:loadSettings()
end

function FieldInspector:actionToggleAllFarms()
    local thisModEnviroment = getfenv(0)["g_fieldInspector"]

    thisModEnviroment.logger:print("toggle all farms", FS22Log.LOG_LEVEL.INFO, "user_info")

    thisModEnviroment.settings:setValue("isEnabledShowUnowned",
        not thisModEnviroment.settings:getValue("isEnabledShowUnowned"))
    thisModEnviroment.settings:saveSettings()
end

function FieldInspector:actionToggleVisible()
    local thisModEnviroment = getfenv(0)["g_fieldInspector"]
    thisModEnviroment.logger:print("toggle display", FS22Log.LOG_LEVEL.INFO, "user_info")

    thisModEnviroment.settings:setValue("isEnabledVisible", not thisModEnviroment.settings:getValue("isEnabledVisible"))
    thisModEnviroment.settings:saveSettings()
end

function FieldInspector.addMenuOption(original, target, id, i18n_title, i18n_tooltip, options, callback)
    local menuOption = original:clone()

    menuOption.target = target
    menuOption.id = id

    menuOption:setCallback("onClickCallback", callback)
    menuOption:setDisabled(false)

    local settingTitle = menuOption.elements[4]
    local toolTip = menuOption.elements[6]

    menuOption:setTexts({unpack(options)})
    settingTitle:setText(g_i18n:getText(i18n_title))
    toolTip:setText(g_i18n:getText(i18n_tooltip))

    return menuOption
end

function FieldInspector.initGui(self)

    -- isEnabledVisible = true,
    -- isEnabledAlphaSort = true,
    -- isEnabledShowPlayer = false,
    -- isEnabledShowAll = false,
    -- isEnabledShowUnowned = false,
    -- isEnabledShowFieldFruit = true,
    -- isEnabledShowFieldFruitGrowth = true,
    -- isEnabledPadFieldNum = true,

    local boolMenuOptions = {"Visible", "AlphaSort", "ShowPlayer", "ShowAll", "ShowUnowned", "ShowFieldFruit",
                             "ShowFieldFruitColor", "ShowFieldFruitGrowth", "PadFieldNum", "TextBold"}

    if not g_fieldInspector.createdGUI then
        -- Create controls -- Skip if we've already done this once
        g_fieldInspector.createdGUI = true

        local title = TextElement.new()
        title:applyProfile("settingsMenuSubtitle", true)
        title:setText(g_i18n:getText("title_fieldInspector"))
        self.boxLayout:addElement(title)

        self.menuOption_DisplayMode = FieldInspector.addMenuOption(self.checkInvertYLook, g_fieldInspector,
            "fieldInspector_DisplayMode", "setting_fieldInspector_DisplayMode", "toolTip_fieldInspector_DisplayMode",
            {g_i18n:getText("setting_fieldInspector_DisplayMode1"),
             g_i18n:getText("setting_fieldInspector_DisplayMode2"),
             g_i18n:getText("setting_fieldInspector_DisplayMode3"),
             g_i18n:getText("setting_fieldInspector_DisplayMode4")}, "onMenuOptionChanged_DisplayMode")
        self.boxLayout:addElement(self.menuOption_DisplayMode)

        for _, thisOptionName in ipairs(boolMenuOptions) do
            -- Boolean style options
            local thisFullOptName = "menuOption_" .. thisOptionName
            self[thisFullOptName] = FieldInspector.addMenuOption(self.checkInvertYLook, g_fieldInspector,
                "fieldInspector_" .. thisOptionName, "setting_fieldInspector_" .. thisOptionName,
                "toolTip_fieldInspector_" .. thisOptionName, {g_i18n:getText("ui_no"), g_i18n:getText("ui_yes")},
                "onMenuOptionChanged_boolOpt")
            self.boxLayout:addElement(self[thisFullOptName])
        end

        local textSizeTexts = {}
        for _, size in ipairs(g_fieldInspector.menuTextSizes) do
            table.insert(textSizeTexts, tostring(size) .. " px")
        end

        self.menuOption_TextSize = FieldInspector.addMenuOption(self.checkInvertYLook, g_fieldInspector,
            "fieldInspector_setValueTextSize", "setting_fieldInspector_TextSize", "toolTip_fieldInspector_TextSize",
            textSizeTexts, "onMenuOptionChanged_setValueTextSize")
        self.boxLayout:addElement(self.menuOption_TextSize)
    end

    -- Set Current Values
    self.menuOption_DisplayMode:setState(g_fieldInspector.settings:getValue("displayMode"))

    for _, thisOption in ipairs(boolMenuOptions) do
        local thisMenuOption = "menuOption_" .. thisOption
        local thisRealOption = "isEnabled" .. thisOption
        self[thisMenuOption]:setIsChecked(g_fieldInspector.settings:getValue(thisRealOption))
    end

    local textSizeState = 3 -- backup value for it set odd in the xml.
    for idx, textSize in ipairs(g_fieldInspector.menuTextSizes) do
        if g_fieldInspector.settings:getValue("setValueTextSize") == textSize then
            textSizeState = idx
        end
    end
    self.menuOption_TextSize:setState(textSizeState)
end

function FieldInspector:onMenuOptionChanged_setValueTextSize(state)
    self.settings:setValue("setValueTextSize", g_fieldInspector.menuTextSizes[state])
    self.inspectText.size = self.gameInfoDisplay:scalePixelToScreenHeight(self.settings:getValue("setValueTextSize"))
    self.settings:saveSettings()
end

function FieldInspector:onMenuOptionChanged_DisplayMode(state)
    self.settings:setValue("displayMode", state)
    self.settings:saveSettings()
end

function FieldInspector:onMenuOptionChanged_boolOpt(state, info)
    self.settings:setValue("isEnabled" .. string.sub(info.id, (#"fieldInspector_" + 1)),
        state == CheckedOptionElement.STATE_CHECKED)
    self.settings:saveSettings()
end
