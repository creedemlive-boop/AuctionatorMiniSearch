-- =========================
-- Core.lua - Initialization, events, and slash commands
-- =========================


-- AuctionatorMiniSearch is the global addon namespace (defined in .toc)
local AMS = _G["AuctionatorMiniSearch"]
local L = AMS.L
local AMS_RESCAN_COOLDOWN_SECONDS = 15 * 60
local AMS_LATEST_SCHEMA_VERSION = 2

local function AMS_DebugPrint(...)
  if AMS.debugMode then
    print(...)
  end
end

local function AMS_StripLegacyItemLevelSuffix(name)
  if type(name) ~= "string" or name == "" then
    return name
  end

  local cleaned = string.gsub(name, "%s*%([iI][lL][vV][lL]?%s*%d+%)$", "")
  return cleaned
end

-- Returns a shortened status text for compact UI mode.
function AMS.GetShortStatusText(text)
  if type(text) ~= "string" or text == "" then
    return text
  end

  if string.sub(text, 1, 2) == "|c" then
    return text
  end

  local shortMap = {
    { pattern = "^(Preis%-Index%-Datenbank wird durchsucht|Scanning price index database)", short = "Index-Aufbau..." },
    { pattern = "^(Weitere Preise werden in Datenbank hinzugefügt|Adding more prices to database)", short = "Fehlende Items laden..." },
    { pattern = "^(Fehlende Items werden geprüft|Checking missing items)", short = "Fehlende Items prüfen..." },
    { pattern = "^(Index%-Abgleich|Index reconcile)", short = "Index-Abgleich..." },
    { pattern = "^(Preise werden im Hintergrund aktualisiert|Refreshing prices in background)", short = "Preise aktualisieren..." },
    { pattern = "^(Zero%-Preis Items werden geprüft|Checking zero%-price items)", short = "Zero-Preis Check..." },
    { pattern = "^(Scan%-Cooldown aktiv|Scan cooldown active)", short = "Scan-Cooldown aktiv" },
  }

  for _, entry in ipairs(shortMap) do
    if string.match(text, entry.pattern) then
      return entry.short
    end
  end

  return text
end

local function AMS_ExtractItemIDFromVariantKey(variantKey)
  if type(variantKey) == "number" then
    return variantKey
  end

  if type(variantKey) ~= "string" or variantKey == "" then
    return nil
  end

  local asNumber = tonumber(variantKey)
  if asNumber then
    return asNumber
  end

  local fromItemPrefix = string.match(variantKey, "^item:(%d+)")
  if fromItemPrefix then
    return tonumber(fromItemPrefix)
  end

  local fromGenericPrefix = string.match(variantKey, "^[a-z]+:(%d+)")
  if fromGenericPrefix then
    return tonumber(fromGenericPrefix)
  end

  local firstNumber = string.match(variantKey, "(%d+)")
  if firstNumber then
    return tonumber(firstNumber)
  end

  return nil
end

local function AMS_BuildSafeItemLink(itemID)
  local numericItemID = tonumber(itemID)
  if not numericItemID then
    return nil
  end

  return "item:" .. tostring(numericItemID)
end

local function AMS_CloneLocaleNames(names)
  if type(names) ~= "table" then
    return nil
  end

  local out = {}
  for localeKey, localeName in pairs(names) do
    if type(localeKey) == "string" and type(localeName) == "string" and localeName ~= "" then
      out[localeKey] = AMS_StripLegacyItemLevelSuffix(localeName)
    end
  end

  if next(out) == nil then
    return nil
  end

  return out
end

local function AMS_BuildCompactSearchEntry(entry)
  if type(entry) ~= "table" then
    return nil
  end

  local itemID = tonumber(entry.itemID)
  if not itemID then
    return nil
  end

  local compact = {
    itemID = itemID,
    price = tonumber(entry.price) or 0,
    lastCheckedAt = tonumber(entry.lastCheckedAt) or 0,
  }

  local minPrice = tonumber(entry.minPrice)
  local maxPrice = tonumber(entry.maxPrice)
  if minPrice and minPrice > 0 and minPrice ~= compact.price then
    compact.minPrice = minPrice
  end
  if maxPrice and maxPrice > 0 and maxPrice ~= compact.price then
    compact.maxPrice = maxPrice
  end

  local namesByLocale = AMS_CloneLocaleNames(entry.names)
  if not namesByLocale then
    local dataLocale = "enUS"
    if AMS.GetDefaultLocale then
      dataLocale = AMS.GetDefaultLocale()
    end

    local fallbackName = AMS_StripLegacyItemLevelSuffix(entry.nameLocalized or entry.baseName or entry.name)
    if fallbackName and fallbackName ~= "" then
      namesByLocale = {
        [dataLocale] = fallbackName,
      }
    end
  end

  if namesByLocale then
    compact.names = namesByLocale
  end

  return compact
end

local function AMS_GetSchemaVersion(settings)
  if type(settings) ~= "table" then
    return 1
  end

  local version = tonumber(settings.schemaVersion)
  if not version or version < 1 then
    return 1
  end

  return math.floor(version)
end

local function AMS_MigrateSettingsToLatest(settings)
  if type(settings) ~= "table" then
    return AMS_LATEST_SCHEMA_VERSION
  end

  local version = AMS_GetSchemaVersion(settings)

  if version < 2 then
    -- v2: tooltip price option removed and compact index persistence introduced.
    settings.showPriceTooltip = nil
    version = 2
  end

  settings.schemaVersion = AMS_LATEST_SCHEMA_VERSION
  return version
end

-- Auctionator data references
AMS.priceDB = nil
AMS.auctionatorAPI = nil
AMS.auctionatorMissing = false

-- =========================
-- SavedVariables / settings
-- =========================
AMS.clientKey = "Retail"
AMS.settings = nil

-- Compatible IsAddOnLoaded check for WoW versions that support C_AddOns.
local function AMS_IsAuctionatorLoaded()
  if C_AddOns and C_AddOns.IsAddOnLoaded then
    return C_AddOns.IsAddOnLoaded("Auctionator")
  end
end


-- Loads and normalizes saved AMS settings and persisted index data.
function AMS.LoadSavedSettings()
  AMS_DB = AMS_DB or {}
  AMS_DB[AMS.clientKey] = AMS_DB[AMS.clientKey] or {}
  AMS.settings = AMS_DB[AMS.clientKey]
  AMS_MigrateSettingsToLatest(AMS.settings)

  AMS.settings.rowCount = AMS.settings.rowCount or 15
  AMS.settings.uiPos = AMS.settings.uiPos or { point = "CENTER", x = 0, y = 0 }
  AMS.settings.uiSize = AMS.settings.uiSize or { width = 540, height = 500 }
  AMS.settings.minimap = AMS.settings.minimap or { angle = 220 }
  AMS.settings.lastRescanAt = AMS.settings.lastRescanAt or 0
  AMS.settings.debugMode = AMS.settings.debugMode or false
  AMS.settings.refreshAgeDays = AMS.settings.refreshAgeDays or 2
  AMS.settings.autoDeleteAgeDays = AMS.settings.autoDeleteAgeDays or 0
  AMS.settings.minSearchLength = AMS.settings.minSearchLength or 2
  if type(AMS.settings.liveSearch) ~= "boolean" then
    AMS.settings.liveSearch = true
  end
  if type(AMS.settings.showAnalysisSuffix) ~= "boolean" then
    AMS.settings.showAnalysisSuffix = true
  end
  if type(AMS.settings.statusDetailedMessages) ~= "boolean" then
    AMS.settings.statusDetailedMessages = true
  end
  if type(AMS.settings.keepFocusOnEnter) ~= "boolean" then
    AMS.settings.keepFocusOnEnter = false
  end
  if type(AMS.settings.reconcileOnOpen) ~= "boolean" then
    AMS.settings.reconcileOnOpen = false
  end
  if type(AMS.settings.keepPriceDBInMemory) ~= "boolean" then
    AMS.settings.keepPriceDBInMemory = false
  end

  AMS.settings.minSearchLength = tonumber(AMS.settings.minSearchLength) or 2
  if AMS.settings.minSearchLength < 1 then
    AMS.settings.minSearchLength = 1
  elseif AMS.settings.minSearchLength > 6 then
    AMS.settings.minSearchLength = 6
  end

  AMS.settings.refreshAgeDays = tonumber(AMS.settings.refreshAgeDays) or 2
  if AMS.settings.refreshAgeDays < 1 then
    AMS.settings.refreshAgeDays = 1
  end

  AMS.settings.autoDeleteAgeDays = tonumber(AMS.settings.autoDeleteAgeDays) or 0
  if AMS.settings.autoDeleteAgeDays < 0 then
    AMS.settings.autoDeleteAgeDays = 0
  elseif AMS.settings.autoDeleteAgeDays > 60 then
    AMS.settings.autoDeleteAgeDays = 60
  end

  if type(AMS.settings.minimap) ~= "table" then
    AMS.settings.minimap = { angle = 220 }
  end
  AMS.settings.minimap.angle = tonumber(AMS.settings.minimap.angle) or 220
  AMS.settings.minimap.hide = AMS.settings.minimap.hide == true
  AMS.settings.showPriceTooltip = nil

  -- Load index and missing-items list.
  if AMS.settings.searchIndex then
    AMS.searchIndex = AMS.settings.searchIndex
  else
    AMS.searchIndex = {}
  end
  if AMS.settings.missingItems then
    AMS.missingItems = AMS.settings.missingItems
  else
    AMS.missingItems = {}
  end

  do
    local dataLocale = "enUS"
    if AMS.GetDefaultLocale then
      dataLocale = AMS.GetDefaultLocale()
    end

    local indexedSet = {}
    local normalizedIndex = {}
    local seenItemIDs = {}

    for _, entry in ipairs(AMS.searchIndex) do
      if type(entry) == "table" then
        local itemID = tonumber(entry.itemID) or AMS_ExtractItemIDFromVariantKey(entry.variantKey)
        if itemID then
          local legacyName = AMS_StripLegacyItemLevelSuffix(entry.name or entry.baseName or entry.nameEN or entry.nameLocalized or ("Item " .. itemID))
          local englishLegacyName = AMS_StripLegacyItemLevelSuffix(entry.nameEN)
          local localizedLegacyName = AMS_StripLegacyItemLevelSuffix(entry.nameLocalized or entry.baseName or (dataLocale == "deDE" and legacyName or nil) or legacyName)

          local namesByLocale = {}
          if type(entry.names) == "table" then
            for localeKey, localeName in pairs(entry.names) do
              if type(localeKey) == "string" and type(localeName) == "string" and localeName ~= "" then
                namesByLocale[localeKey] = AMS_StripLegacyItemLevelSuffix(localeName)
              end
            end
          end

          if dataLocale ~= "enUS" and englishLegacyName and englishLegacyName ~= "" and localizedLegacyName and localizedLegacyName ~= "" and englishLegacyName == localizedLegacyName then
            englishLegacyName = ""
          end

          if englishLegacyName and englishLegacyName ~= "" then
            namesByLocale.enUS = namesByLocale.enUS or englishLegacyName
          end
          if localizedLegacyName and localizedLegacyName ~= "" then
            namesByLocale.deDE = namesByLocale.deDE or localizedLegacyName
          end
          if legacyName and legacyName ~= "" and not namesByLocale[dataLocale] then
            namesByLocale[dataLocale] = legacyName
          end

          if dataLocale ~= "enUS" and namesByLocale.enUS and namesByLocale.deDE and namesByLocale.enUS == namesByLocale.deDE then
            namesByLocale.enUS = nil
          end

          if (not namesByLocale.enUS or namesByLocale.enUS == "") and dataLocale == "enUS" then
            namesByLocale.enUS = legacyName
          end

          local englishName = namesByLocale.enUS
          local localizedName = namesByLocale.deDE or namesByLocale[dataLocale] or englishName or legacyName

          if localizedName and localizedName ~= "" then
            namesByLocale.deDE = namesByLocale.deDE or localizedName
          end

          local canonicalName = englishName or localizedName or ("Item " .. itemID)

          entry.itemID = itemID
          entry.variantKey = nil
          entry.itemLink = AMS_BuildSafeItemLink(itemID)
          entry.names = namesByLocale
          entry.nameEN = nil
          entry.nameLocalized = localizedName
          entry.name = canonicalName
          entry.baseName = localizedName or canonicalName
          entry.nameLower = string.lower(entry.name or "")
          entry.price = tonumber(entry.price) or 0
          entry.minPrice = tonumber(entry.minPrice) or entry.price
          entry.maxPrice = tonumber(entry.maxPrice) or entry.price
          entry.lastCheckedAt = tonumber(entry.lastCheckedAt) or 0
          if entry.lastLivePriceCheckAt ~= nil then
            entry.lastLivePriceCheckAt = tonumber(entry.lastLivePriceCheckAt) or 0
          end

          local existingEntry = seenItemIDs[itemID]
          if not existingEntry then
            seenItemIDs[itemID] = entry
            table.insert(normalizedIndex, entry)
            indexedSet[itemID] = true
          else
            if (not existingEntry.nameLocalized or existingEntry.nameLocalized == "") and entry.nameLocalized and entry.nameLocalized ~= "" then
              existingEntry.nameLocalized = entry.nameLocalized
              existingEntry.baseName = entry.nameLocalized
            end
            existingEntry.names = existingEntry.names or {}
            if type(entry.names) == "table" then
              for localeKey, localeName in pairs(entry.names) do
                if type(localeKey) == "string" and type(localeName) == "string" and localeName ~= "" and not existingEntry.names[localeKey] then
                  existingEntry.names[localeKey] = localeName
                end
              end
            end

            if dataLocale ~= "enUS" and existingEntry.names.enUS and existingEntry.names.deDE and existingEntry.names.enUS == existingEntry.names.deDE then
              existingEntry.names.enUS = nil
            end

            existingEntry.nameEN = nil
            local existingCanonical = existingEntry.names.enUS or existingEntry.nameLocalized or existingEntry.name or ("Item " .. itemID)
            existingEntry.name = existingCanonical
            existingEntry.nameLower = string.lower(existingCanonical)

            local existingMin = tonumber(existingEntry.minPrice) or tonumber(existingEntry.price) or 0
            local existingMax = tonumber(existingEntry.maxPrice) or tonumber(existingEntry.price) or 0
            local entryMin = tonumber(entry.minPrice) or tonumber(entry.price) or 0
            local entryMax = tonumber(entry.maxPrice) or tonumber(entry.price) or 0

            if existingMin <= 0 or (entryMin > 0 and entryMin < existingMin) then
              existingEntry.minPrice = entryMin
            end
            if entryMax > existingMax then
              existingEntry.maxPrice = entryMax
            end

            if type(entry.lastCheckedAt) == "number" and entry.lastCheckedAt > (existingEntry.lastCheckedAt or 0) then
              existingEntry.lastCheckedAt = entry.lastCheckedAt
            end

            if type(existingEntry.minPrice) == "number" and existingEntry.minPrice > 0 then
              existingEntry.price = existingEntry.minPrice
            end
          end
        end
      end
    end

    AMS.searchIndex = normalizedIndex

    local deduped = {}
    local seen = {}
    for _, id in ipairs(AMS.missingItems) do
      local numericID = tonumber(id)
      if numericID and not seen[numericID] and not indexedSet[numericID] then
        seen[numericID] = true
        table.insert(deduped, numericID)
      end
    end
    AMS.missingItems = deduped
  end

  AMS.indexReady = #AMS.searchIndex > 0
  AMS.lastRescanAt = AMS.settings.lastRescanAt
  AMS.debugMode = AMS.settings.debugMode

  AMS.ROW_COUNT = AMS.settings.rowCount
  AMS.ROW_HEIGHT = AMS.ROW_HEIGHT or 18

  -- Apply settings immediately if the UI already exists.
  if AMS.frame then
    local minWidth, minHeight, maxWidth, maxHeight = 540, 500, 1000, 1000
    if AMS.GetFrameSizeBounds then
      minWidth, minHeight, maxWidth, maxHeight = AMS.GetFrameSizeBounds()
    end
    local width = AMS.settings.uiSize.width or minWidth
    local height = AMS.settings.uiSize.height or minHeight
    width = math.min(math.max(width, minWidth), maxWidth)
    height = math.min(math.max(height, minHeight), maxHeight)

    AMS.frame:ClearAllPoints()
    AMS.frame:SetPoint(AMS.settings.uiPos.point, UIParent, AMS.settings.uiPos.point, AMS.settings.uiPos.x, AMS.settings.uiPos.y)
    AMS.frame:SetSize(width, height)
    AMS.BuildRows()
    if AMS.UpdateSearchLabel then
      AMS.UpdateSearchLabel()
    end
    if AMS.UpdateDebugIndicator then
      AMS.UpdateDebugIndicator()
    end
    if AMS.UpdateMinimapButtonPosition then
      AMS.UpdateMinimapButtonPosition()
    end
    if AMS.UpdateMinimapButtonVisibility then
      AMS.UpdateMinimapButtonVisibility()
    end
  end

  if AMS.BackfillLocaleNamesForIndex then
    C_Timer.After(0.05, function()
      AMS.BackfillLocaleNamesForIndex()
    end)
  end
end

-- Resets saved AMS data and optionally rebuilds the index if the frame is open.
function AMS.ResetSavedData()
  AMS_DB = AMS_DB or {}
  AMS_DB[AMS.clientKey] = nil

  AMS.settings = nil
  AMS.searchIndex = {}
  AMS.missingItems = {}
  AMS.missingSet = {}
  AMS.retryCount = AMS.retryCount or {}
  wipe(AMS.retryCount)
  AMS.analysisCache = {}
  AMS.analysisCacheOrder = {}
  AMS.indexReady = false
  AMS.lastRescanAt = 0

  if AMS.searchBox then
    AMS.searchBox:SetText("")
    AMS.searchBox:Enable()
  end

  if AMS.ClearRows and AMS.rows then
    AMS.ClearRows(AMS.rows)
  end

  if AMS.LoadSavedSettings then
    AMS.LoadSavedSettings()
  end

  if AMS.statusText then
    AMS.statusText:SetText(L("STATUS_RESET_REBUILDING"))
  end

  if AMS.frame and AMS.frame:IsShown() and AMS.BuildIndex then
    C_Timer.After(0.05, function()
      AMS.BuildIndex()
    end)
  end
end


-- Persists runtime settings and index data back to SavedVariables.
function AMS.SaveSettings()
  if not AMS.settings then return end
  AMS.settings.schemaVersion = AMS_LATEST_SCHEMA_VERSION
  AMS.settings.rowCount = AMS.ROW_COUNT
  AMS.settings.refreshAgeDays = AMS.settings.refreshAgeDays or 2
  AMS.settings.autoDeleteAgeDays = AMS.settings.autoDeleteAgeDays or 0
  AMS.settings.reconcileOnOpen = AMS.settings.reconcileOnOpen == true
  AMS.settings.keepPriceDBInMemory = AMS.settings.keepPriceDBInMemory == true
  AMS.settings.lastRescanAt = AMS.lastRescanAt or AMS.settings.lastRescanAt or 0
  AMS.settings.debugMode = AMS.debugMode == true
  if AMS.frame then
    local point, _, _, x, y = AMS.frame:GetPoint()
    AMS.settings.uiPos = { point = point or "CENTER", x = x or 0, y = y or 0 }
    local width, height = AMS.frame:GetSize()
    AMS.settings.uiSize = { width = width or 540, height = height or 500 }
  end
  -- Save index and missing-items list in compact form.
  local compactIndex = {}
  for _, entry in ipairs(AMS.searchIndex or {}) do
    local compact = AMS_BuildCompactSearchEntry(entry)
    if compact then
      table.insert(compactIndex, compact)
    end
  end
  AMS.settings.searchIndex = compactIndex

  local compactMissing = {}
  local seenMissing = {}
  for _, id in ipairs(AMS.missingItems or {}) do
    local numericID = tonumber(id)
    if numericID and not seenMissing[numericID] then
      seenMissing[numericID] = true
      table.insert(compactMissing, numericID)
    end
  end
  AMS.settings.missingItems = compactMissing
end

-- =========================
-- Auctionator database initialization
-- =========================

-- Checks whether the Auctionator addon is loaded (uses WoW addon API).
function AMS.CheckAuctionatorLoaded()
  local loaded = AMS_IsAuctionatorLoaded()
  if not loaded then
    AMS_DebugPrint(L("LOG_AUCTIONATOR_NOT_INSTALLED"))
    return false
  end
  return true
end

-- Detects Auctionator API/DB availability and binds the active realm price DB.
function AMS.InitPriceDB(loadPriceDB)
  if loadPriceDB == nil then
    loadPriceDB = true
  end

  if not AMS.CheckAuctionatorLoaded() then
    AMS_DebugPrint(L("LOG_AUCTIONATOR_NOT_LOADED"))
    return
  end

  local auctionatorGlobal = rawget(_G, "Auctionator")

  if auctionatorGlobal and auctionatorGlobal.API and auctionatorGlobal.API.v1 then
    AMS.auctionatorAPI = auctionatorGlobal.API.v1
    AMS_DebugPrint(L("LOG_API_DETECTED"))
  else
    AMS.auctionatorAPI = nil
    AMS_DebugPrint(L("LOG_API_NOT_FOUND_FALLBACK"))
  end

  if not loadPriceDB then
    return
  end

  local auctionatorPriceDatabase = rawget(_G, "AUCTIONATOR_PRICE_DATABASE")

  if not auctionatorPriceDatabase then
    AMS.priceDB = nil
    if AMS.auctionatorAPI then
      AMS_DebugPrint(L("LOG_DB_NIL_API_ACTIVE"))
      return
    else
      AMS_DebugPrint(L("LOG_DB_NIL"))
      return
    end
  end

  -- Resolve realm key similarly to Auctionator (connected realm root).
  local key = nil
  if auctionatorGlobal and auctionatorGlobal.State and type(auctionatorGlobal.State.CurrentRealm) == "string" and auctionatorGlobal.State.CurrentRealm ~= "" then
    key = auctionatorGlobal.State.CurrentRealm
  elseif auctionatorGlobal and auctionatorGlobal.Variables and type(auctionatorGlobal.Variables.GetConnectedRealmRoot) == "function" then
    key = auctionatorGlobal.Variables.GetConnectedRealmRoot()
  else
    key = GetRealmName()
  end

  if type(key) ~= "string" or key == "" then
    key = GetRealmName()
  end

  local priceDB = auctionatorPriceDatabase[key]

  -- If still serialized, try to deserialize it (same strategy as Auctionator).
  if type(priceDB) == "string" and C_EncodingUtil and C_EncodingUtil.DeserializeCBOR then
    local success, data = pcall(C_EncodingUtil.DeserializeCBOR, priceDB)
    if success and type(data) == "table" then
      priceDB = data
      -- Keep the decoded table local to AMS to avoid pinning a large copy globally.
    else
      AMS_DebugPrint(L("LOG_DB_DESERIALIZE_ERROR"))
      priceDB = nil
    end
  end

  AMS.priceDB = priceDB

  if (not AMS.priceDB or type(AMS.priceDB) ~= "table") and not AMS.auctionatorAPI then
    local msg = L("LOG_NO_PRICE_DATA_REALM_FMT", key)
    AMS_DebugPrint(msg, 1, 0.2, 0.2)
    if AMS.ShowErrorMessage then
      AMS.ShowErrorMessage(msg)
    end
    AMS_DebugPrint(L("LOG_NO_PRICE_DATA_REALM_FACTION_FMT", key))
    return
  end

  if AMS.priceDB and type(AMS.priceDB) == "table" then
    AMS_DebugPrint(L("LOG_DB_LOADED"))
  elseif AMS.auctionatorAPI then
    AMS_DebugPrint(L("LOG_API_MODE_ACTIVE"))
  end
end

function AMS.ReleaseTransientMemory(forceReleasePriceDB)
  AMS.analysisCache = {}
  AMS.analysisCacheOrder = {}
  AMS._priceRangeByItemID = nil

  local shouldReleasePriceDB = forceReleasePriceDB == true
  if not shouldReleasePriceDB then
    shouldReleasePriceDB = not (AMS.settings and AMS.settings.keepPriceDBInMemory == true)
  end

  if shouldReleasePriceDB then
    AMS.priceDB = nil
  end

  if collectgarbage then
    collectgarbage("collect")
  end
end

-- =========================
-- Event handling
-- =========================


-- CreateFrame is a WoW API function for creating UI frames.
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGOUT")

-- Events:
-- ADDON_LOADED: SavedVariables become available for this addon
-- PLAYER_LOGIN: safe to initialize Auctionator DB and UI
-- PLAYER_LOGOUT: persist settings
eventFrame:SetScript("OnEvent", function(self, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 == "AuctionatorMiniSearch" then
      AMS.LoadSavedSettings()
      -- Keep startup memory low: DB is loaded lazily only when an index build/reconcile requires it.
      if AMS_IsAuctionatorLoaded() and not AMS.auctionatorAPI then
        AMS.InitPriceDB(false)
      end
    end
  elseif event == "PLAYER_LOGIN" then
    -- Ensure settings are loaded (in case ADDON_LOADED wasn't caught) and init DB
    AMS.LoadSavedSettings()
  elseif event == "PLAYER_LOGOUT" then
    AMS.SaveSettings()
  end
end)

-- =========================
-- Slash commands
-- =========================

SLASH_AUCTIONATORMINI1 = "/ams"

local function AMS_StartFollowupRefreshes()
  local function StartFollowups()
    if not AMS.auctionatorAPI then
      AMS.InitPriceDB(false)
    end

    if AMS.RefreshMissingItems then
      AMS.RefreshMissingItems()
    end
    C_Timer.After(0.15, function()
      if AMS.RefreshZeroPriceItems then
        AMS.RefreshZeroPriceItems()
      end
    end)
    C_Timer.After(0.30, function()
      AMS.RefreshStalePrices()
    end)
  end

  AMS._amsStartFollowupRefreshes = StartFollowups

  local shouldRunReconcile = AMS.settings and AMS.settings.reconcileOnOpen == true

  if shouldRunReconcile and AMS.RefreshIndexFromPriceDB then
    if type(AMS.priceDB) ~= "table" then
      AMS.InitPriceDB()
    end
    AMS.RefreshIndexFromPriceDB()
    if not AMS.isReconcilingIndex and AMS._amsStartFollowupRefreshes then
      local cb = AMS._amsStartFollowupRefreshes
      AMS._amsStartFollowupRefreshes = nil
      cb()
    end
  else
    StartFollowups()
  end
end

local function AMS_TryStartRescan(ignoreCooldown)
  local now = time()
  local lastRescanAt = AMS.lastRescanAt or 0
  local secondsSinceLastScan = now - lastRescanAt
  local shouldRunRescan = ignoreCooldown or (secondsSinceLastScan >= AMS_RESCAN_COOLDOWN_SECONDS)

  if not shouldRunRescan then
    local remaining = AMS_RESCAN_COOLDOWN_SECONDS - secondsSinceLastScan
    if remaining < 0 then
      remaining = 0
    end
    local minutesRemaining = math.ceil(remaining / 60)
    if AMS.statusText then
      AMS.statusText:SetText(L("STATUS_SCAN_COOLDOWN_FMT", minutesRemaining))
    end
    return false
  end

  AMS.lastRescanAt = now
  if AMS.SaveSettings then
    AMS.SaveSettings()
  end

  C_Timer.After(0.05, AMS_StartFollowupRefreshes)
  return true
end

local function AMS_ToggleMainFrame()
  if not AMS.settings and AMS.LoadSavedSettings then
    AMS.LoadSavedSettings()
  end

  if not AMS.frame then
    print(L("LOG_ERR_UI_NOT_LOADED"))
    return
  end
  if not AMS.searchBox then
    print(L("LOG_ERR_SEARCHBOX_NOT_INIT"))
    return
  end

  if AMS.auctionatorMissing then
    print(L("LOG_ERR_AUCTIONATOR_ADDON_INACTIVE"))
    return
  end

  local wasHidden = not AMS.frame:IsShown()
  AMS.frame:SetShown(wasHidden)

  if not wasHidden then
    AMS.ReleaseTransientMemory(false)
    return
  end

  local needsPriceDBForBuild = not AMS.indexReady
  local needsPriceDBForReconcile = AMS.settings and AMS.settings.reconcileOnOpen == true
  if (needsPriceDBForBuild or needsPriceDBForReconcile) and type(AMS.priceDB) ~= "table" then
    AMS.InitPriceDB()
  end

  if wasHidden and not AMS.indexReady then
    C_Timer.After(0.1, function()
      local hasDB = type(AMS.priceDB) == "table" and next(AMS.priceDB) ~= nil

      if not hasDB then
        if AMS.ShowErrorMessage then
          AMS.ShowErrorMessage(L("ERROR_NO_PRICE_DB_SCAN"))
        end
        return
      end
      AMS.BuildIndex()
    end)
  elseif wasHidden and AMS.indexReady and AMS.RefreshStalePrices then
    AMS_TryStartRescan(false)
  end
end

SlashCmdList["AUCTIONATORMINI"] = function(msg)
  if msg and msg ~= "" then
    local cmd, arg = strsplit(" ", msg, 2)
    if cmd == "scan" then
      if not AMS.debugMode then
        print(L("LOG_SCAN_DEBUG_ONLY"))
        return
      end

      if AMS.isReconcilingIndex or AMS.isRefreshingMissing or AMS.isRefreshingZeroPrices or AMS.isRefreshingStale then
        print(L("LOG_SCAN_ALREADY_RUNNING"))
        return
      end

      if not AMS.frame then
        print(L("LOG_ERR_UI_NOT_LOADED"))
        return
      end

      if not AMS.frame:IsShown() then
        AMS.frame:Show()
      end

      AMS_TryStartRescan(true)
  print(L("LOG_MANUAL_SCAN_STARTED"))
      return
    elseif cmd == "debugmode" then
      local opt = arg and string.lower(arg) or ""
      if opt == "on" then
        AMS.debugMode = true
      elseif opt == "off" then
        AMS.debugMode = false
      else
        AMS.debugMode = not AMS.debugMode
      end

      if AMS.SaveSettings then
        AMS.SaveSettings()
      end

      if AMS.UpdateDebugIndicator then
        AMS.UpdateDebugIndicator()
      end

      print(L("LOG_DEBUG_MODE_FMT", AMS.debugMode and L("STATE_ON") or L("STATE_OFF")))
      return
    end

    if cmd == "debug" and arg then
      local itemID = tonumber(arg)
      if not itemID then
        print(L("LOG_DEBUG_INVALID_ITEMID_FMT", tostring(arg)))
        return
      end

      print(L("LOG_DEBUG_HEADER_ITEMID_FMT", itemID))

      local inIndex = false
      for _, entry in ipairs(AMS.searchIndex or {}) do
        if entry.itemID == itemID then
          inIndex = true
          print(L("LOG_DEBUG_IN_SEARCHINDEX_FMT", tostring(entry.name), tostring(entry.price or 0), tostring(entry.lastCheckedAt or "nil")))
          break
        end
      end
      if not inIndex then
        print(L("LOG_DEBUG_NOT_IN_SEARCHINDEX"))
      end

      local inMissing = false
      for _, id in ipairs(AMS.missingItems or {}) do
        if id == itemID then
          inMissing = true
          print(L("LOG_DEBUG_IN_MISSING_FMT", (AMS.retryCount[itemID] or 0)))
          break
        end
      end
      if not inMissing then
        print(L("LOG_DEBUG_NOT_IN_MISSING"))
      end

      local auctionatorGlobal = rawget(_G, "Auctionator")
      if auctionatorGlobal and auctionatorGlobal.API and auctionatorGlobal.API.v1 and auctionatorGlobal.API.v1.GetAuctionPriceByItemID then
        local ok, apiPrice = pcall(auctionatorGlobal.API.v1.GetAuctionPriceByItemID, "AuctionatorMiniSearch", itemID)
        if ok and apiPrice then
          print(L("LOG_DEBUG_API_PRICE_FMT", tostring(apiPrice)))
        else
          print(L("LOG_DEBUG_API_PRICE_NIL"))
        end
      end

      if type(AMS.priceDB) == "table" then
        local found = false
        for key, value in pairs(AMS.priceDB) do
          if type(key) == "string" and (key == tostring(itemID) or string.match(key, ":" .. itemID .. "$") or string.match(key, ":" .. itemID .. ":")) then
            if type(value) == "table" and value.m then
              print(L("LOG_DEBUG_IN_PRICEDB_FMT", key, tostring(value.m)))
              found = true
            end
          end
        end
        if not found then
          print(L("LOG_DEBUG_NOT_IN_PRICEDB"))
        end
      else
        print(L("LOG_DEBUG_PRICEDB_INVALID"))
      end

      if C_Item and C_Item.GetItemNameByID then
        local name = C_Item.GetItemNameByID(itemID)
        if name then
          print(L("LOG_DEBUG_NAME_BY_ID_FMT", tostring(name)))
        else
          print(L("LOG_DEBUG_NAME_BY_ID_NIL"))
        end
      end

      if C_Item and C_Item.GetItemInfo then
        local name = C_Item.GetItemInfo(itemID)
        if name then
          print(L("LOG_DEBUG_ITEM_INFO_FMT", tostring(name)))
        else
          print(L("LOG_DEBUG_ITEM_INFO_NIL"))
        end
      end

      print(L("LOG_DEBUG_END"))
      return
    end
  end

  AMS_ToggleMainFrame()
end

function AMS.CompartmentClickHandler()
  AMS_ToggleMainFrame()
end
