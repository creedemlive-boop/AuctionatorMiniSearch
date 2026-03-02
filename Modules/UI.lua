-- =========================
-- UI.lua - Window, buttons, scroll frame, and progress bar
-- =========================

local AMS = _G["AuctionatorMiniSearch"]
local L = AMS.L
local MIN_FRAME_WIDTH = 540
local MIN_FRAME_HEIGHT = 500
local MINIMAP_BUTTON_SIZE = 31
local MINIMAP_BORDER_SIZE = 53
local MINIMAP_DEFAULT_RADIUS_OFFSET = 10
local MINIMAP_CUSTOM_ICON_PATH = "Interface\\AddOns\\AuctionatorMiniSearch\\Assets\\icon"
local MINIMAP_FALLBACK_ICON_PATH = "Interface\\Icons\\INV_Misc_Spyglass_03"

local function RefreshResetPopupTexts()
  StaticPopupDialogs["AMS_RESET_SV_CONFIRM"] = StaticPopupDialogs["AMS_RESET_SV_CONFIRM"] or {}
  StaticPopupDialogs["AMS_RESET_SV_CONFIRM"].text = L("RESET_CONFIRM_TEXT")
  StaticPopupDialogs["AMS_RESET_SV_CONFIRM"].button1 = L("RESET_BUTTON")
  StaticPopupDialogs["AMS_RESET_SV_CONFIRM"].button2 = L("CANCEL_BUTTON")
end

-- Calculates min/max frame bounds based on parent UI size and physical resolution.
function AMS.GetFrameSizeBounds()
  local minWidth, minHeight = MIN_FRAME_WIDTH, MIN_FRAME_HEIGHT

  local maxWidth = UIParent:GetWidth() - 40
  local maxHeight = UIParent:GetHeight() - 40

  local getPhysicalScreenSize = rawget(_G, "GetPhysicalScreenSize")
  if type(getPhysicalScreenSize) == "function" then
    local physicalWidth, physicalHeight = getPhysicalScreenSize()
    if type(physicalWidth) == "number" and physicalWidth > 0 and type(physicalHeight) == "number" and physicalHeight > 0 then
      local parentScale = UIParent:GetEffectiveScale() or 1
      if parentScale > 0 then
        local uiWidthFromResolution = physicalWidth / parentScale
        local uiHeightFromResolution = physicalHeight / parentScale
        maxWidth = math.min(maxWidth, uiWidthFromResolution - 40)
        maxHeight = math.min(maxHeight, uiHeightFromResolution - 40)
      end
    end
  end

  maxWidth = math.max(minWidth, maxWidth)
  maxHeight = math.max(minHeight, maxHeight)

  return minWidth, minHeight, maxWidth, maxHeight
end

local minimapButton = CreateFrame("Button", "AuctionatorMiniSearchMinimapButton", Minimap)
minimapButton:SetSize(MINIMAP_BUTTON_SIZE, MINIMAP_BUTTON_SIZE)
minimapButton:SetFrameStrata("MEDIUM")
minimapButton:SetFrameLevel(8)
minimapButton:RegisterForClicks("LeftButtonUp")
minimapButton:RegisterForDrag("LeftButton")
minimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

local minimapBg = minimapButton:CreateTexture(nil, "BACKGROUND")
minimapBg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
minimapBg:SetSize(20, 20)
minimapBg:SetPoint("TOPLEFT", 7, -5)

local minimapIcon = minimapButton:CreateTexture(nil, "ARTWORK")
if not minimapIcon:SetTexture(MINIMAP_CUSTOM_ICON_PATH) then
  minimapIcon:SetTexture(MINIMAP_FALLBACK_ICON_PATH)
end
minimapIcon:SetPoint("TOPLEFT", 7, -6)
minimapIcon:SetPoint("BOTTOMRIGHT", -7, 6)

local minimapBorder = minimapButton:CreateTexture(nil, "OVERLAY")
minimapBorder:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
minimapBorder:SetSize(MINIMAP_BORDER_SIZE, MINIMAP_BORDER_SIZE)
minimapBorder:SetPoint("TOPLEFT")

local function NormalizeMinimapAngle(angle)
  local numericAngle = tonumber(angle) or 220
  while numericAngle < 0 do
    numericAngle = numericAngle + 360
  end
  while numericAngle >= 360 do
    numericAngle = numericAngle - 360
  end
  return numericAngle
end

local function UpdateMinimapButtonPosition()
  local angle = 220
  if AMS.settings and AMS.settings.minimap and AMS.settings.minimap.angle then
    angle = AMS.settings.minimap.angle
  end
  angle = NormalizeMinimapAngle(angle)

  local minimapRadius = (Minimap:GetWidth() / 2) + MINIMAP_DEFAULT_RADIUS_OFFSET
  local x = math.cos(math.rad(angle)) * minimapRadius
  local y = math.sin(math.rad(angle)) * minimapRadius

  minimapButton:ClearAllPoints()
  minimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

function AMS.UpdateMinimapButtonPosition()
  UpdateMinimapButtonPosition()
end

function AMS.UpdateMinimapButtonVisibility()
  local hide = false
  if AMS.settings and AMS.settings.minimap and AMS.settings.minimap.hide == true then
    hide = true
  end

  if hide then
    minimapButton:Hide()
  else
    minimapButton:Show()
  end
end

minimapButton:SetScript("OnClick", function()
  if AMS.CompartmentClickHandler then
    AMS.CompartmentClickHandler()
  end
end)

minimapButton:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:AddLine(L("MINIMAP_TOOLTIP_TITLE"), 1, 0.82, 0)
  GameTooltip:AddLine(L("MINIMAP_TOOLTIP_HINT"), 0.9, 0.9, 0.9)
  GameTooltip:Show()
end)

minimapButton:SetScript("OnLeave", function()
  GameTooltip:Hide()
end)

minimapButton:SetScript("OnDragStart", function(self)
  self:SetScript("OnUpdate", function()
    local cursorX, cursorY = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale() or 1
    cursorX = cursorX / scale
    cursorY = cursorY / scale

    local centerX, centerY = Minimap:GetCenter()
    local deltaX = cursorX - centerX
    local deltaY = cursorY - centerY

    local angle
    if math.atan2 then
      angle = math.deg(math.atan2(deltaY, deltaX))
    else
      if deltaX == 0 then
        angle = deltaY >= 0 and 90 or 270
      else
        angle = math.deg(math.atan(deltaY / deltaX))
        if deltaX < 0 then
          angle = angle + 180
        elseif deltaY < 0 then
          angle = angle + 360
        end
      end
    end

    angle = NormalizeMinimapAngle(angle)

    AMS.settings = AMS.settings or {}
    AMS.settings.minimap = AMS.settings.minimap or {}
    AMS.settings.minimap.angle = angle

    UpdateMinimapButtonPosition()
  end)
end)

minimapButton:SetScript("OnDragStop", function(self)
  self:SetScript("OnUpdate", nil)
  if AMS.SaveSettings then
    AMS.SaveSettings()
  end
end)

UpdateMinimapButtonPosition()
AMS.UpdateMinimapButtonVisibility()

-- Default row count and row height (can be overridden by SavedVariables)
AMS.ROW_COUNT = AMS.ROW_COUNT or 15
AMS.ROW_HEIGHT = AMS.ROW_HEIGHT or 18

-- These tables are populated here and used later by Search.lua
AMS.rows = {}

-- =========================
-- Main window
-- =========================

local frame = CreateFrame("Frame", "AuctionatorMiniSearchFrame", UIParent, "BackdropTemplate")
AMS.frame = frame

UISpecialFrames = UISpecialFrames or {}
local hasSpecialFrame = false
for _, frameName in ipairs(UISpecialFrames) do
  if frameName == "AuctionatorMiniSearchFrame" then
    hasSpecialFrame = true
    break
  end
end
if not hasSpecialFrame then
  table.insert(UISpecialFrames, "AuctionatorMiniSearchFrame")
end

frame:SetSize(540, 500)
frame:SetPoint("CENTER")
frame:SetBackdrop({
  bgFile = "Interface/Tooltips/UI-Tooltip-Background",
  edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
  tile = true, tileSize = 16, edgeSize = 16,
  insets = { left = 4, right = 4, top = 4, bottom = 4 }
})
frame:SetBackdropColor(0, 0, 0, 0.9)
frame:Hide()

frame:SetResizable(true)
frame:SetResizeBounds(MIN_FRAME_WIDTH, MIN_FRAME_HEIGHT, 1000, 1000)
frame:SetClampedToScreen(true)

frame:SetScript("OnShow", function()
  if AMS.ApplyLocalization then
    AMS.ApplyLocalization()
  end

  local minWidth, minHeight, maxWidth, maxHeight = AMS.GetFrameSizeBounds()
  frame:SetResizeBounds(minWidth, minHeight, maxWidth, maxHeight)

  local currentWidth, currentHeight = frame:GetSize()
  local clampedWidth = math.min(math.max(currentWidth, minWidth), maxWidth)
  local clampedHeight = math.min(math.max(currentHeight, minHeight), maxHeight)
  if clampedWidth ~= currentWidth or clampedHeight ~= currentHeight then
    frame:SetSize(clampedWidth, clampedHeight)
  end

  if AMS.searchBox then
    AMS.searchBox:SetText("")
    AMS.ClearRows(AMS.rows)
    if AMS.statusText then
      AMS.statusText:SetText(L("STATUS_READY"))
    end
  end

  if AMS.UpdateDebugIndicator then
    AMS.UpdateDebugIndicator()
  end
end)

frame:SetScript("OnHide", function()
  if AMS.optionsFrame and AMS.optionsFrame:IsShown() then
    AMS.optionsFrame:Hide()
  end

  if AMS.CancelAllRefreshJobs then
    AMS.CancelAllRefreshJobs()
  end
end)

frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", function(self)
  self:StopMovingOrSizing()
  if AMS and AMS.SaveSettings then
    AMS.SaveSettings()
  end
end)

frame:SetScript("OnSizeChanged", function(self, width, height)
  local minWidth, minHeight, maxWidth, maxHeight = AMS.GetFrameSizeBounds()
  self:SetResizeBounds(minWidth, minHeight, maxWidth, maxHeight)

  local clampedWidth = math.min(math.max(width, minWidth), maxWidth)
  local clampedHeight = math.min(math.max(height, minHeight), maxHeight)
  if clampedWidth ~= width or clampedHeight ~= height then
    self:SetSize(clampedWidth, clampedHeight)
    return
  end

  if AMS and AMS.SaveSettings then
    AMS.SaveSettings()
  end
  
  -- Adjust content width
  if AMS.content and AMS.scrollFrame then
    local contentWidth = AMS.scrollFrame:GetWidth() - 20
    AMS.content:SetWidth(contentWidth)
    
    -- Update all rows
    for _, row in ipairs(AMS.rows) do
      if row then
        row:SetWidth(contentWidth)
      end
    end
  end
end)

-- Resize handle (bottom-right)
local resizer = CreateFrame("Button", nil, frame)
resizer:SetSize(16, 16)
resizer:SetPoint("BOTTOMRIGHT", -5, 5)
resizer:EnableMouse(true)
resizer:SetScript("OnMouseDown", function(self)
  frame:StartSizing("BOTTOMRIGHT")
end)
resizer:SetScript("OnMouseUp", function(self)
  frame:StopMovingOrSizing()
  if AMS and AMS.SaveSettings then
    AMS.SaveSettings()
  end
end)

-- Resize handle texture
local resizerTexture = resizer:CreateTexture(nil, "OVERLAY")
resizerTexture:SetAllPoints()
resizerTexture:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
resizer:SetScript("OnEnter", function(self)
  resizerTexture:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
end)
resizer:SetScript("OnLeave", function(self)
  resizerTexture:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
end)


-- Titel

local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", 0, -10)
title:SetText(L("APP_TITLE"))

local debugIndicator = CreateFrame("Frame", nil, frame)
debugIndicator:SetSize(26, 26)
debugIndicator:SetPoint("TOPLEFT", 8, -8)
debugIndicator:EnableMouse(true)
debugIndicator:Hide()

local debugGlow = debugIndicator:CreateTexture(nil, "BACKGROUND")
debugGlow:SetPoint("TOPLEFT", -4, 4)
debugGlow:SetPoint("BOTTOMRIGHT", 4, -4)
debugGlow:SetTexture("Interface\\Buttons\\UI-Quickslot2")
debugGlow:SetVertexColor(1, 0.35, 0.35, 0.9)

local debugIcon = debugIndicator:CreateTexture(nil, "ARTWORK")
debugIcon:SetAllPoints()
debugIcon:SetTexture("Interface\\Icons\\INV_Misc_Wrench_01")
debugIcon:SetVertexColor(1, 0.85, 0.2)

debugIndicator:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:AddLine(L("DEBUG_TOOLTIP_ACTIVE"), 1, 0.35, 0.35)
  GameTooltip:AddLine(L("DEBUG_TOOLTIP_SCAN"), 0.9, 0.9, 0.9)
  GameTooltip:AddLine(L("DEBUG_TOOLTIP_ICON"), 0.75, 0.75, 0.75)
  GameTooltip:Show()
end)

debugIndicator:SetScript("OnLeave", function()
  GameTooltip:Hide()
end)

function AMS.UpdateDebugIndicator()
  if AMS.debugMode then
    debugIndicator:Show()
  else
    debugIndicator:Hide()
  end
end

-- Close-Button
local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", -5, -5)

-- =========================
-- Search box
-- =========================

local searchBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
AMS.searchBox = searchBox

searchBox:SetWidth(340)
searchBox:SetHeight(30)
searchBox:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -55)
searchBox:SetAutoFocus(false)

local searchLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
searchLabel:SetPoint("BOTTOMLEFT", searchBox, "TOPLEFT", 0, 2)
AMS.searchLabel = searchLabel

function AMS.UpdateSearchLabel()
  local minChars = 2
  if AMS.settings and type(AMS.settings.minSearchLength) == "number" then
    minChars = AMS.settings.minSearchLength
  end
  searchLabel:SetText(L("SEARCH_LABEL_FMT", minChars))
end

-- Clears all UI rows (for example after pressing the clear button).
function AMS.ClearRows(rows)
  for _, row in ipairs(rows) do
    row.text:SetText("")
    row.icon:SetTexture(nil)
    row.itemID = nil
    row.itemName = nil
    row.itemLink = nil
    row.price = nil
    row.minPrice = nil
    row.maxPrice = nil
    row:Hide()
  end
end

AMS.UpdateSearchLabel()

local searchButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
searchButton:SetSize(80, 22)
searchButton:SetPoint("LEFT", searchBox, "RIGHT", 10, 0)
searchButton:SetText(L("BUTTON_SEARCH"))
searchButton:Hide()

AMS.searchButton = searchButton

-- Clear-Button
local clearButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
clearButton:SetSize(60, 22)
clearButton:SetPoint("LEFT", searchButton, "RIGHT", 5, 0)
clearButton:SetText(L("BUTTON_CLEAR"))
clearButton:Hide()

clearButton:SetScript("OnClick", function()
  searchBox:SetText("")
  AMS.ClearRows(AMS.rows)
  if AMS.statusText then
    AMS.statusText:SetText(L("STATUS_READY"))
  end
end)

local searchIconButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
searchIconButton:SetSize(28, 28)
searchIconButton:SetPoint("LEFT", searchBox, "RIGHT", 18, 0)
searchIconButton:SetText("")
searchIconButton.icon = searchIconButton:CreateTexture(nil, "ARTWORK")
searchIconButton.icon:SetAllPoints()
searchIconButton.icon:SetTexture("Interface\\Icons\\INV_Misc_Spyglass_03")
AMS.searchIconButton = searchIconButton
searchIconButton:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:AddLine(L("TOOLTIP_SEARCH"), 1, 0.82, 0)
  GameTooltip:Show()
end)
searchIconButton:SetScript("OnLeave", function()
  GameTooltip:Hide()
end)

local clearIconButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
clearIconButton:SetSize(28, 28)
clearIconButton:SetPoint("LEFT", searchIconButton, "RIGHT", 10, 0)
clearIconButton:SetText("")
clearIconButton.icon = clearIconButton:CreateTexture(nil, "ARTWORK")
clearIconButton.icon:SetAllPoints()
clearIconButton.icon:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
clearIconButton.icon:SetVertexColor(1, 0.8, 0.8)
clearIconButton:SetScript("OnClick", function()
  searchBox:SetText("")
  AMS.ClearRows(AMS.rows)
  if AMS.statusText then
    AMS.statusText:SetText(L("STATUS_READY"))
  end
end)
clearIconButton:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:AddLine(L("TOOLTIP_CLEAR"), 1, 0.82, 0)
  GameTooltip:Show()
end)
clearIconButton:SetScript("OnLeave", function()
  GameTooltip:Hide()
end)

local optionsIconButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
optionsIconButton:SetSize(28, 28)
optionsIconButton:SetPoint("LEFT", clearIconButton, "RIGHT", 10, 0)
optionsIconButton:SetText("")
optionsIconButton.icon = optionsIconButton:CreateTexture(nil, "ARTWORK")
optionsIconButton.icon:SetAllPoints()
optionsIconButton.icon:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")

StaticPopupDialogs["AMS_RESET_SV_CONFIRM"] = {
  text = L("RESET_CONFIRM_TEXT"),
  button1 = L("RESET_BUTTON"),
  button2 = L("CANCEL_BUTTON"),
  OnAccept = function()
    if AMS.ResetSavedData then
      AMS.ResetSavedData()
    end
  end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
}
RefreshResetPopupTexts()

local function CreateOptionsWindow()
  if AMS.optionsFrame then
    return AMS.optionsFrame
  end

  local optionsFrame = CreateFrame("Frame", "AuctionatorMiniSearchOptionsFrame", UIParent, "BackdropTemplate")
  optionsFrame:SetSize(650, 430)
  optionsFrame:SetPoint("CENTER")
  optionsFrame:SetFrameStrata("DIALOG")
  optionsFrame:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
  })
  optionsFrame:SetBackdropColor(0, 0, 0, 0.95)
  optionsFrame:EnableMouse(true)
  optionsFrame:SetMovable(true)
  optionsFrame:RegisterForDrag("LeftButton")
  optionsFrame:SetScript("OnDragStart", optionsFrame.StartMoving)
  optionsFrame:SetScript("OnDragStop", optionsFrame.StopMovingOrSizing)
  optionsFrame:Hide()

  table.insert(UISpecialFrames, "AuctionatorMiniSearchOptionsFrame")

  local titleText = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  titleText:SetPoint("TOPLEFT", 16, -12)
  titleText:SetText(L("OPTIONS_TITLE"))

  local closeButton = CreateFrame("Button", nil, optionsFrame, "UIPanelCloseButton")
  closeButton:SetPoint("TOPRIGHT", -4, -4)

  local leftPanel = CreateFrame("Frame", nil, optionsFrame, "BackdropTemplate")
  leftPanel:SetPoint("TOPLEFT", 12, -42)
  leftPanel:SetPoint("BOTTOMLEFT", 12, 12)
  leftPanel:SetWidth(160)
  leftPanel:SetBackdrop({
    bgFile = "Interface/Buttons/WHITE8x8",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 }
  })
  leftPanel:SetBackdropColor(0.07, 0.07, 0.07, 0.8)

  local contentPanel = CreateFrame("Frame", nil, optionsFrame, "BackdropTemplate")
  contentPanel:SetPoint("TOPLEFT", leftPanel, "TOPRIGHT", 10, 0)
  contentPanel:SetPoint("BOTTOMRIGHT", optionsFrame, "BOTTOMRIGHT", -12, 12)
  contentPanel:SetBackdrop({
    bgFile = "Interface/Buttons/WHITE8x8",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 }
  })
  contentPanel:SetBackdropColor(0.04, 0.04, 0.04, 0.75)

  local contentTitle = contentPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  contentTitle:SetPoint("TOPLEFT", 16, -12)

  local optionWidgets = {}
  local activeTab = "general"
  local tabButtons = {}

  local function ClearOptionWidgets()
    for _, widget in ipairs(optionWidgets) do
      widget:Hide()
      widget:SetParent(nil)
    end
    wipe(optionWidgets)
  end

  local yOffset = -40
  local function ReserveLine(height)
    local top = yOffset
    yOffset = yOffset - height
    return top
  end

  local function AddInfoText(text)
    local info = contentPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    info:SetPoint("TOPLEFT", 20, ReserveLine(22))
    info:SetWidth(contentPanel:GetWidth() - 50)
    info:SetJustifyH("LEFT")
    info:SetText("|cff9aa0a6" .. text .. "|r")
    table.insert(optionWidgets, info)
  end

  local function AddSectionHeader(text)
    local header = contentPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", 20, ReserveLine(24))
    header:SetText(text)
    table.insert(optionWidgets, header)
  end

  local function AddCheckOption(labelText, getValue, setValue, infoText)
    local check = CreateFrame("CheckButton", nil, contentPanel, "UICheckButtonTemplate")
    check:SetPoint("TOPLEFT", 16, ReserveLine(28))
    check:SetChecked(getValue())
    check:SetScript("OnClick", function(self)
      setValue(self:GetChecked() == true)
      if AMS.SaveSettings then
        AMS.SaveSettings()
      end
    end)

    local label = contentPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", check, "RIGHT", 4, 0)
    label:SetText(labelText)

    table.insert(optionWidgets, check)
    table.insert(optionWidgets, label)

    if infoText and infoText ~= "" then
      AddInfoText(infoText)
    end
  end

  local function AddStepperOption(labelText, minValue, maxValue, stepValue, getValue, setValue, infoText)
    local row = CreateFrame("Frame", nil, contentPanel)
    row:SetPoint("TOPLEFT", 20, ReserveLine(30))
    row:SetSize(contentPanel:GetWidth() - 40, 26)

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", 0, 0)
    label:SetText(labelText)

    local valueText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    valueText:SetPoint("RIGHT", -62, 0)
    valueText:SetWidth(38)
    valueText:SetJustifyH("CENTER")

    local minusButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    minusButton:SetSize(24, 20)
    minusButton:SetPoint("RIGHT", valueText, "LEFT", -4, 0)
    minusButton:SetText("-")

    local plusButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    plusButton:SetSize(24, 20)
    plusButton:SetPoint("LEFT", valueText, "RIGHT", 4, 0)
    plusButton:SetText("+")

    local function Refresh()
      local value = tonumber(getValue()) or minValue
      valueText:SetText(tostring(value))
      minusButton:SetEnabled(value > minValue)
      plusButton:SetEnabled(value < maxValue)
    end

    minusButton:SetScript("OnClick", function()
      local current = tonumber(getValue()) or minValue
      local nextValue = current - stepValue
      if nextValue < minValue then
        nextValue = minValue
      end
      setValue(nextValue)
      if AMS.SaveSettings then
        AMS.SaveSettings()
      end
      Refresh()
    end)

    plusButton:SetScript("OnClick", function()
      local current = tonumber(getValue()) or minValue
      local nextValue = current + stepValue
      if nextValue > maxValue then
        nextValue = maxValue
      end
      setValue(nextValue)
      if AMS.SaveSettings then
        AMS.SaveSettings()
      end
      Refresh()
    end)

    Refresh()

    table.insert(optionWidgets, row)
    table.insert(optionWidgets, minusButton)
    table.insert(optionWidgets, plusButton)
    table.insert(optionWidgets, valueText)
    table.insert(optionWidgets, label)

    if infoText and infoText ~= "" then
      AddInfoText(infoText)
    end
  end

  local function AddActionButton(labelText, onClickHandler, infoText)
    local button = CreateFrame("Button", nil, contentPanel, "UIPanelButtonTemplate")
    button:SetSize(180, 24)
    button:SetPoint("TOPLEFT", 20, ReserveLine(30))
    button:SetText(labelText)
    button:SetScript("OnClick", onClickHandler)
    table.insert(optionWidgets, button)

    if infoText and infoText ~= "" then
      AddInfoText(infoText)
    end
  end

  local function AddChoiceOption(labelText, choices, getValue, setValue, infoText)
    local row = CreateFrame("Frame", nil, contentPanel)
    row:SetPoint("TOPLEFT", 20, ReserveLine(30))
    row:SetSize(contentPanel:GetWidth() - 40, 26)

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", 0, 0)
    label:SetText(labelText)

    local valueText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    valueText:SetPoint("RIGHT", -62, 0)
    valueText:SetWidth(80)
    valueText:SetJustifyH("CENTER")

    local minusButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    minusButton:SetSize(24, 20)
    minusButton:SetPoint("RIGHT", valueText, "LEFT", -4, 0)
    minusButton:SetText("-")

    local plusButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    plusButton:SetSize(24, 20)
    plusButton:SetPoint("LEFT", valueText, "RIGHT", 4, 0)
    plusButton:SetText("+")

    local function IndexOfValue(value)
      for i, entry in ipairs(choices) do
        if entry.value == value then
          return i
        end
      end
      return 1
    end

    local function Refresh()
      local current = getValue()
      local index = IndexOfValue(current)
      valueText:SetText(choices[index].label)
    end

    minusButton:SetScript("OnClick", function()
      local current = getValue()
      local index = IndexOfValue(current) - 1
      if index < 1 then
        index = #choices
      end
      setValue(choices[index].value)
      if AMS.SaveSettings then
        AMS.SaveSettings()
      end
      Refresh()
    end)

    plusButton:SetScript("OnClick", function()
      local current = getValue()
      local index = IndexOfValue(current) + 1
      if index > #choices then
        index = 1
      end
      setValue(choices[index].value)
      if AMS.SaveSettings then
        AMS.SaveSettings()
      end
      Refresh()
    end)

    Refresh()

    table.insert(optionWidgets, row)
    table.insert(optionWidgets, minusButton)
    table.insert(optionWidgets, plusButton)
    table.insert(optionWidgets, valueText)
    table.insert(optionWidgets, label)

    if infoText and infoText ~= "" then
      AddInfoText(infoText)
    end
  end

  local function ApplyRowCountFromOptions(newValue)
    AMS.ROW_COUNT = newValue
    if AMS.settings then
      AMS.settings.rowCount = newValue
    end
    if AMS.BuildRows then
      AMS.BuildRows()
    end

    local searchText = AMS.searchBox and AMS.searchBox:GetText()
    local minLength = AMS.settings and tonumber(AMS.settings.minSearchLength) or 2
    if searchText and string.len(searchText) >= minLength and AMS.PerformSearch then
      AMS.PerformSearch(searchText)
    elseif AMS.rows then
      AMS.ClearRows(AMS.rows)
    end
  end

  local function RenderTab(tabKey)
    activeTab = tabKey
    ClearOptionWidgets()
    yOffset = -40

    if tabKey == "general" then
      contentTitle:SetText(L("TAB_GENERAL"))
      AddSectionHeader(L("SECTION_DISPLAY"))

      AddCheckOption(
        L("OPTION_LIVE_SEARCH_LABEL"),
        function()
          return not AMS.settings or AMS.settings.liveSearch ~= false
        end,
        function(value)
          AMS.settings.liveSearch = value
        end,
        L("OPTION_LIVE_SEARCH_INFO")
      )

      AddCheckOption(
        L("OPTION_PRICE_TOOLTIP_LABEL"),
        function()
          return not AMS.settings or AMS.settings.showPriceTooltip ~= false
        end,
        function(value)
          AMS.settings.showPriceTooltip = value
        end,
        L("OPTION_PRICE_TOOLTIP_INFO")
      )

      AddCheckOption(
        L("OPTION_MINIMAP_ICON_LABEL"),
        function()
          return not AMS.settings or not AMS.settings.minimap or AMS.settings.minimap.hide ~= true
        end,
        function(value)
          AMS.settings.minimap = AMS.settings.minimap or {}
          AMS.settings.minimap.hide = not (value == true)
          if AMS.UpdateMinimapButtonVisibility then
            AMS.UpdateMinimapButtonVisibility()
          end
        end,
        L("OPTION_MINIMAP_ICON_INFO")
      )
    elseif tabKey == "search" then
      contentTitle:SetText(L("TAB_SEARCH"))
      AddSectionHeader(L("SECTION_SEARCH_BEHAVIOR"))
      AddStepperOption(
        L("OPTION_MIN_CHARS_LABEL"),
        1,
        6,
        1,
        function()
          return AMS.settings and AMS.settings.minSearchLength or 2
        end,
        function(value)
          AMS.settings.minSearchLength = value
          if AMS.UpdateSearchLabel then
            AMS.UpdateSearchLabel()
          end
        end,
        L("OPTION_MIN_CHARS_INFO")
      )

      AddCheckOption(
        L("OPTION_KEEP_FOCUS_LABEL"),
        function()
          return AMS.settings and AMS.settings.keepFocusOnEnter == true
        end,
        function(value)
          AMS.settings.keepFocusOnEnter = value == true
        end,
        L("OPTION_KEEP_FOCUS_INFO")
      )
    elseif tabKey == "data" then
      contentTitle:SetText(L("TAB_DATA"))
      AddSectionHeader(L("SECTION_INDEX_STORAGE"))
      AddCheckOption(
        L("OPTION_DEBUG_LABEL"),
        function()
          return AMS.debugMode == true
        end,
        function(value)
          AMS.debugMode = value == true
          if AMS.settings then
            AMS.settings.debugMode = AMS.debugMode
          end
          if AMS.UpdateDebugIndicator then
            AMS.UpdateDebugIndicator()
          end
        end,
        L("OPTION_DEBUG_INFO")
      )

      AddCheckOption(
        L("OPTION_STATUS_DETAIL_LABEL"),
        function()
          return not AMS.settings or AMS.settings.statusDetailedMessages ~= false
        end,
        function(value)
          AMS.settings.statusDetailedMessages = value == true
          if AMS.statusText and AMS.GetShortStatusText and AMS.statusText.GetText then
            local currentText = AMS.statusText:GetText()
            if currentText and currentText ~= "" then
              AMS.statusText:SetText(currentText)
            end
          end
        end,
        L("OPTION_STATUS_DETAIL_INFO")
      )

      AddStepperOption(
        L("OPTION_REFRESH_DAYS_LABEL"),
        1,
        14,
        1,
        function()
          return AMS.settings and AMS.settings.refreshAgeDays or 2
        end,
        function(value)
          AMS.settings.refreshAgeDays = value
        end,
        L("OPTION_REFRESH_DAYS_INFO")
      )

      AddStepperOption(
        L("OPTION_AUTODELETE_DAYS_LABEL"),
        0,
        60,
        1,
        function()
          return AMS.settings and AMS.settings.autoDeleteAgeDays or 0
        end,
        function(value)
          AMS.settings.autoDeleteAgeDays = value
        end,
        L("OPTION_AUTODELETE_DAYS_INFO")
      )

      AddActionButton(
        L("OPTION_REBUILD_INDEX_LABEL"),
        function()
          if AMS.BuildIndex then
            AMS.BuildIndex()
          end
        end,
        L("OPTION_REBUILD_INDEX_INFO")
      )

      AddActionButton(
        L("OPTION_RESET_DATA_LABEL"),
        function()
          StaticPopup_Show("AMS_RESET_SV_CONFIRM")
        end,
        L("OPTION_RESET_DATA_INFO")
      )
    end
  end

  local tabs = {
    { key = "general", keyLabel = "TAB_GENERAL" },
    { key = "search", keyLabel = "TAB_SEARCH" },
    { key = "data", keyLabel = "TAB_DATA" },
  }

  for index, tab in ipairs(tabs) do
    local tabButton = CreateFrame("Button", nil, leftPanel, "UIPanelButtonTemplate")
    tabButton:SetSize(130, 24)
    tabButton:SetPoint("TOPLEFT", 14, -16 - (index - 1) * 30)
    tabButton:SetText(L(tab.keyLabel))
    tabButton:SetScript("OnClick", function()
      RenderTab(tab.key)
    end)
    tabButtons[index] = tabButton
  end

  local function RefreshTabLabels()
    for index, tab in ipairs(tabs) do
      local button = tabButtons[index]
      if button then
        button:SetText(L(tab.keyLabel))
      end
    end
    titleText:SetText(L("OPTIONS_TITLE"))
  end

  optionsFrame.RefreshTabLabels = RefreshTabLabels
  optionsFrame.RenderTab = RenderTab
  optionsFrame.GetActiveTab = function()
    return activeTab
  end

  optionsFrame:SetScript("OnShow", function()
    RenderTab(activeTab)
  end)

  AMS.optionsFrame = optionsFrame
  return optionsFrame
end

-- Opens/closes the options window.
function AMS.ToggleOptionsFrame()
  local optionsFrame = CreateOptionsWindow()
  optionsFrame:SetShown(not optionsFrame:IsShown())
end

optionsIconButton:SetScript("OnClick", function()
  AMS.ToggleOptionsFrame()
end)
optionsIconButton:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:AddLine(L("TOOLTIP_OPTIONS"), 1, 0.82, 0)
  GameTooltip:Show()
end)
optionsIconButton:SetScript("OnLeave", function()
  GameTooltip:Hide()
end)


local statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
AMS.statusText = statusText

local rawStatusSetText = statusText.SetText

function AMS.SetStatusText(text)
  local finalText = text
  if AMS.settings and AMS.settings.statusDetailedMessages == false and AMS.GetShortStatusText then
    finalText = AMS.GetShortStatusText(text)
  end
  rawStatusSetText(statusText, finalText)
end

statusText.SetText = function(self, text)
  AMS.SetStatusText(text)
end

statusText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 12)
statusText:SetText(L("STATUS_READY"))

-- Shows an error message in the status line using red text.
function AMS.ShowErrorMessage(msg)
  if AMS.statusText then
    AMS.statusText:SetText("|cffff3333" .. msg .. "|r")
  end
end

-- =========================
-- Row-count buttons
-- =========================

local function SetRowCount(n)
  AMS.ROW_COUNT = n
  if AMS.settings then
    AMS.settings.rowCount = n
  end
  AMS.BuildRows()
  
  local searchText = AMS.searchBox:GetText()
  if searchText and string.len(searchText) >= 2 and AMS.PerformSearch then
    AMS.PerformSearch(searchText)
  else
    AMS.ClearRows(AMS.rows)
  end
  
  if AMS and AMS.SaveSettings then
    AMS.SaveSettings()
  end
end

local btn15 = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
btn15:SetSize(40, 22)
btn15:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -85)
btn15:SetText("15")
btn15:SetScript("OnClick", function() SetRowCount(15) end)

local btn30 = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
btn30:SetSize(40, 22)
btn30:SetPoint("LEFT", btn15, "RIGHT", 5, 0)
btn30:SetText("30")
btn30:SetScript("OnClick", function() SetRowCount(30) end)

local btn50 = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
btn50:SetSize(40, 22)
btn50:SetPoint("LEFT", btn30, "RIGHT", 5, 0)
btn50:SetText("50")
btn50:SetScript("OnClick", function() SetRowCount(50) end)

-- Hint text for WoW item cache behavior
local cacheHint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
cacheHint:SetPoint("TOPLEFT", btn15, "BOTTOMLEFT", 0, -4)
cacheHint:SetWidth(460)
cacheHint:SetJustifyH("LEFT")
cacheHint:SetText(L("CACHE_HINT"))

-- Applies localized text to the full UI and refreshes status content.
function AMS.ApplyLocalization()
  title:SetText(L("APP_TITLE"))
  searchButton:SetText(L("BUTTON_SEARCH"))
  clearButton:SetText(L("BUTTON_CLEAR"))
  cacheHint:SetText(L("CACHE_HINT"))

  if AMS.UpdateSearchLabel then
    AMS.UpdateSearchLabel()
  end

  if AMS.frame and AMS.frame:IsShown() and AMS.statusText then
    if AMS.isReconcilingIndex then
      AMS.statusText:SetText(L("STATUS_INDEX_RECONCILING"))
    elseif AMS.isRefreshingMissing then
      AMS.statusText:SetText(L("STATUS_CHECKING_MISSING"))
    elseif AMS.isRefreshingZeroPrices then
      AMS.statusText:SetText(L("STATUS_ZEROPRICE_CHECKING"))
    elseif AMS.isRefreshingStale then
      AMS.statusText:SetText(L("STATUS_PRICES_REFRESHING_BG"))
    else
      local query = AMS.searchBox and AMS.searchBox:GetText() or ""
      local minLength = AMS.settings and tonumber(AMS.settings.minSearchLength) or 2
      if query ~= "" and string.len(query) >= minLength and AMS.PerformSearch then
        AMS.PerformSearch(query)
      else
        AMS.statusText:SetText(L("STATUS_READY"))
      end
    end
  end

  RefreshResetPopupTexts()

  if AMS.optionsFrame and AMS.optionsFrame.RefreshTabLabels then
    AMS.optionsFrame.RefreshTabLabels()
    if AMS.optionsFrame:IsShown() and AMS.optionsFrame.RenderTab and AMS.optionsFrame.GetActiveTab then
      AMS.optionsFrame.RenderTab(AMS.optionsFrame.GetActiveTab())
    end
  end
end


-- =========================
-- Progress display (variant A)
-- =========================
local progressBar = frame:CreateTexture(nil, "BACKGROUND")
AMS.progressBar = progressBar

progressBar:SetColorTexture(0.15, 0.15, 0.15, 1)
progressBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 38)
progressBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 38)
progressBar:SetHeight(8)

local progressFill = frame:CreateTexture(nil, "ARTWORK")
AMS.progressFill = progressFill

progressFill:SetColorTexture(0, 0.8, 0, 1)
progressFill:SetPoint("LEFT", progressBar, "LEFT", 0, 0)
progressFill:SetSize(1, 8)

progressBar:Hide()
progressFill:Hide()

-- =========================
-- ScrollFrame
-- =========================

local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", 12, -140)
scrollFrame:SetPoint("BOTTOMRIGHT", -30, 40)

local content = CreateFrame("Frame", nil, scrollFrame)
scrollFrame:SetScrollChild(content)

AMS.scrollFrame = scrollFrame
AMS.content = content

scrollFrame:EnableMouseWheel(true)
scrollFrame:SetScript("OnMouseWheel", function(self, delta)
  local current = self:GetVerticalScroll()
  local max = content:GetHeight() - scrollFrame:GetHeight()
  if max < 0 then max = 0 end

  local new = current - delta * AMS.ROW_HEIGHT
  if new < 0 then new = 0 end
  if new > max then new = max end

  self:SetVerticalScroll(new)
end)

scrollFrame.ScrollBar:SetMinMaxValues(0, 1)
scrollFrame.ScrollBar:SetValue(0)

scrollFrame.ScrollBar:SetScript("OnValueChanged", function(self, value)
  local max = content:GetHeight() - scrollFrame:GetHeight()
  if max < 0 then max = 0 end
  if value > max then value = max end
  if value < 0 then value = 0 end
  scrollFrame:SetVerticalScroll(value)
end)

-- =========================
-- Dynamic rows
-- =========================

-- Handles row clicks and item-link behavior (tooltip, chat-link, modified-click actions).
function AMS.HandleRowClick(itemID, itemName, itemLinkHint, button)
  if button ~= "LeftButton" or not itemID then
    return false
  end
  local itemLink = itemLinkHint
  local hadPlainItemHint = type(itemLink) == "string" and string.match(itemLink, "^item:%d+$") ~= nil

  if hadPlainItemHint then
    local resolvedLink = nil
    if C_Item and C_Item.GetItemLinkByID then
      resolvedLink = C_Item.GetItemLinkByID(itemID)
    end
    if (not resolvedLink) and C_Item and C_Item.GetItemInfo then
      local _, linkFromInfo = C_Item.GetItemInfo(itemID)
      if type(linkFromInfo) == "string" and linkFromInfo ~= "" then
        resolvedLink = linkFromInfo
      end
    end
    if resolvedLink then
      itemLink = resolvedLink
    else
      itemLink = nil
    end
  end

  if type(itemLink) == "string" and string.match(itemLink, "^item:") and C_Item and C_Item.GetItemInfo then
    local _, linkFromInfo = C_Item.GetItemInfo(itemLink)
    if type(linkFromInfo) == "string" and linkFromInfo ~= "" then
      itemLink = linkFromInfo
    end
  end

  if not itemLink and C_Item and C_Item.GetItemLinkByID then
    itemLink = C_Item.GetItemLinkByID(itemID)
  end
  if (not itemLink) and C_Item and C_Item.GetItemInfo then
    local _, linkFromInfo = C_Item.GetItemInfo(itemID)
    if type(linkFromInfo) == "string" and linkFromInfo ~= "" then
      itemLink = linkFromInfo
    end
  end

  if not itemLink then
    if C_Item and C_Item.RequestLoadItemDataByID then
      C_Item.RequestLoadItemDataByID(itemID)
    end
    local bracketName = itemName and ("[" .. itemName .. "]") or ("[" .. L("FALLBACK_ITEM_FMT", itemID) .. "]")
    local colorPrefix = "|cffffffff"

    if C_Item and C_Item.GetItemQualityByID and ITEM_QUALITY_COLORS then
      local quality = C_Item.GetItemQualityByID(itemID)
      local qualityColor = quality and ITEM_QUALITY_COLORS[quality]
      if qualityColor and qualityColor.hex then
        if string.sub(qualityColor.hex, 1, 2) == "|c" then
          colorPrefix = qualityColor.hex
        else
          colorPrefix = "|c" .. qualityColor.hex
        end
      end
    end

    itemLink = colorPrefix .. "|Hitem:" .. itemID .. "::::::::::::|h" .. bracketName .. "|h|r"
  end

  if HandleModifiedItemClick and HandleModifiedItemClick(itemLink) then
    return true
  end

  local wantsChatLink = (IsModifiedClick and IsModifiedClick("CHATLINK")) or (IsShiftKeyDown and IsShiftKeyDown())
  if wantsChatLink then
    if AMS.searchBox and AMS.searchBox.HasFocus and AMS.searchBox:HasFocus() then
      AMS.searchBox:ClearFocus()
    end

    local function TryInsertIntoChatEdit(targetEditBox)
      if not targetEditBox or not targetEditBox.IsShown or not targetEditBox:IsShown() then
        return false
      end

      local hadTextBefore = nil
      if targetEditBox.GetText then
        hadTextBefore = targetEditBox:GetText()
      end

      if targetEditBox.SetFocus then
        targetEditBox:SetFocus()
      end

      local inserted = false
      if ChatFrameUtil and ChatFrameUtil.InsertLink then
        inserted = ChatFrameUtil.InsertLink(itemLink)
      end
      if (not inserted) and ChatEdit_InsertLink then
        inserted = ChatEdit_InsertLink(itemLink)
      end
      if inserted then
        return true
      end

      if targetEditBox.Insert then
        targetEditBox:Insert(itemLink)
      end

      if targetEditBox.GetText then
        local textAfter = targetEditBox:GetText()
        if textAfter and textAfter ~= hadTextBefore then
          return true
        end
      end

      return false
    end

    local checked = {}
    local function TryCandidate(editBox)
      if not editBox then
        return false
      end
      if checked[editBox] then
        return false
      end
      checked[editBox] = true
      return TryInsertIntoChatEdit(editBox)
    end

    if ChatEdit_GetActiveWindow and TryCandidate(ChatEdit_GetActiveWindow()) then
      return true
    end

    if ChatEdit_GetLastActiveWindow and TryCandidate(ChatEdit_GetLastActiveWindow()) then
      return true
    end

    local chatWindowCount = NUM_CHAT_WINDOWS or 10
    for i = 1, chatWindowCount do
      local editBox = _G["ChatFrame" .. i .. "EditBox"]
      if TryCandidate(editBox) then
        return true
      end
    end

    if AMS.statusText then
      AMS.statusText:SetText(L("STATUS_NO_CHAT_EDITBOX"))
    end

    return false
  end

  return false
end

-- Recreates all visible result rows based on current row count and frame width.
function AMS.BuildRows()
  for _, row in ipairs(AMS.rows) do
    row:Hide()
  end
  wipe(AMS.rows)

  local contentWidth = scrollFrame:GetWidth() - 20
  content:SetWidth(contentWidth)

  for i = 1, AMS.ROW_COUNT do
    local row = CreateFrame("Button", nil, content)
    row:SetWidth(contentWidth)
    row:SetHeight(AMS.ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * AMS.ROW_HEIGHT)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16)
    row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)

    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
    row.text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)

    row:SetScript("OnEnter", function(self)
      if self.itemID then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.itemLink and type(self.itemLink) == "string" and self.itemLink ~= "" then
          GameTooltip:SetHyperlink(self.itemLink)
        else
          GameTooltip:SetHyperlink("item:" .. self.itemID)
        end

        if not AMS.settings or AMS.settings.showPriceTooltip ~= false then
          local priceText = nil
          local minPrice = tonumber(self.minPrice)
          local maxPrice = tonumber(self.maxPrice)
          local price = tonumber(self.price)
          if minPrice and maxPrice and minPrice > 0 and maxPrice > minPrice then
            priceText = AMS.FormatMoney(minPrice) .. " - " .. AMS.FormatMoney(maxPrice)
          elseif price and price > 0 then
            priceText = AMS.FormatMoney(price)
          end

          if priceText then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L("TOOLTIP_AMS_PRICE_FMT", priceText), 0.55, 0.9, 0.55)
          end
        end

        GameTooltip:Show()
      end
    end)

    row:SetScript("OnLeave", function()
      GameTooltip:Hide()
    end)

    row:SetScript("OnClick", function(self, button)
      if self.itemID then
        AMS.HandleRowClick(self.itemID, self.itemName, self.itemLink, button)
      end
    end)

    AMS.rows[i] = row
  end

  content:SetHeight(AMS.ROW_COUNT * AMS.ROW_HEIGHT)
  scrollFrame:SetVerticalScroll(0)
end

-- Create initial rows
AMS.BuildRows()