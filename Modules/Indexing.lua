-- =========================
-- Indexing.lua - Batch indexing and progress handling
-- =========================

local AMS = _G["AuctionatorMiniSearch"]
local L = AMS.L

-- Cancels all running background refresh/index jobs and resets related flags.
function AMS.CancelAllRefreshJobs()
  AMS.isReconcilingIndex = false
  AMS.isRefreshingMissing = false
  AMS.isRefreshingZeroPrices = false
  AMS.isRefreshingStale = false
  AMS._missingBatchContext = nil
  
  if AMS.statusText then
    AMS.statusText:SetText(L("STATUS_JOBS_ABORTED"))
  end
end

local function ResolveItemName(itemID)
  local getItemInfoGlobal = rawget(_G, "GetItemInfo")
  if type(getItemInfoGlobal) == "function" then
    local ok, name = pcall(getItemInfoGlobal, itemID)
    if ok and type(name) == "string" and name ~= "" then
      return name
    end
  end

  if C_Item and C_Item.GetItemNameByID then
    local byID = C_Item.GetItemNameByID(itemID)
    if type(byID) == "string" and byID ~= "" then
      return byID
    end
  end

  if C_Item and C_Item.GetItemInfo then
    local infoName = C_Item.GetItemInfo(itemID)
    if type(infoName) == "string" and infoName ~= "" then
      return infoName
    end
  end

  if C_Item and C_Item.RequestLoadItemDataByID then
    C_Item.RequestLoadItemDataByID(itemID)
  end

  return nil
end

local function ExtractItemIDFromDBKey(dbKey)
  if type(dbKey) == "number" then
    return dbKey
  end

  if type(dbKey) == "table" then
    local fromNamed = tonumber(dbKey.itemID or dbKey.itemId or dbKey.id)
    if fromNamed then
      return fromNamed
    end

    local fromIndexed = tonumber(dbKey[1])
    if fromIndexed then
      return fromIndexed
    end

    return nil
  end

  if type(dbKey) ~= "string" then
    return nil
  end

  local raw = tonumber(dbKey)
  if raw then
    return raw
  end

  local fromPrefixWithSuffix = string.match(dbKey, "^[a-z]+:(%d+):")
  if fromPrefixWithSuffix then
    return tonumber(fromPrefixWithSuffix)
  end

  local fromPrefix = string.match(dbKey, "^[a-z]+:(%d+)$")
  if fromPrefix then
    return tonumber(fromPrefix)
  end

  local fromItemPrefix = string.match(dbKey, "^item:(%d+)")
  if fromItemPrefix then
    return tonumber(fromItemPrefix)
  end

  return nil
end

local function HasVariantSuffixInDBKey(dbKey)
  if type(dbKey) ~= "string" then
    return false
  end

  return string.match(dbKey, "^[a-z]+:%d+:[^:]+") ~= nil
end

local function BuildDisplayName(name)
  local displayName = name
  if not displayName or displayName == "" then
    return displayName
  end

  return displayName
end

local function GetDataLocale()
  if AMS.GetDefaultLocale then
    return AMS.GetDefaultLocale()
  end
  return "enUS"
end

local function BuildNameFields(existingEntry, resolvedName)
  local dataLocale = GetDataLocale()
  local cleanName = BuildDisplayName(resolvedName)

  local namesByLocale = {}
  if existingEntry and type(existingEntry.names) == "table" then
    for localeKey, localeName in pairs(existingEntry.names) do
      if (localeKey == "deDE" or localeKey == "enUS") and type(localeName) == "string" and localeName ~= "" then
        namesByLocale[localeKey] = localeName
      end
    end
  end

  if existingEntry and type(existingEntry.nameEN) == "string" and existingEntry.nameEN ~= "" and not namesByLocale.enUS then
    namesByLocale.enUS = existingEntry.nameEN
  end
  if existingEntry and type(existingEntry.nameLocalized) == "string" and existingEntry.nameLocalized ~= "" and not namesByLocale.deDE then
    namesByLocale.deDE = existingEntry.nameLocalized
  end
  if existingEntry and type(existingEntry.baseName) == "string" and existingEntry.baseName ~= "" and not namesByLocale.deDE then
    namesByLocale.deDE = existingEntry.baseName
  end

  if cleanName and cleanName ~= "" then
    namesByLocale[dataLocale] = cleanName
  end

  local englishName = namesByLocale.enUS
  local localizedName = namesByLocale.deDE or namesByLocale[dataLocale] or englishName or cleanName
  local canonicalName = englishName or localizedName or cleanName

  return namesByLocale, canonicalName, englishName, localizedName
end

local function GetPriceForItemID(itemID)
  if AMS.auctionatorAPI and type(AMS.auctionatorAPI.GetAuctionPriceByItemID) == "function" then
    local ok, apiPrice = pcall(AMS.auctionatorAPI.GetAuctionPriceByItemID, "AuctionatorMiniSearch", itemID)
    if ok and type(apiPrice) == "number" and apiPrice > 0 then
      return apiPrice
    end
  end

  if type(AMS.priceDB) == "table" then
    local dbEntry = AMS.priceDB[tostring(itemID)]
    if type(dbEntry) == "table" and type(dbEntry.m) == "number" then
      return dbEntry.m
    end
  end

  return 0
end

local function BuildPriceRangeByItemID()
  local rangeByItemID = {}

  if type(AMS.priceDB) ~= "table" then
    return rangeByItemID
  end

  for dbKey, dbValue in pairs(AMS.priceDB) do
    if type(dbValue) == "table" and type(dbValue.m) == "number" and dbValue.m > 0 then
      local itemID = ExtractItemIDFromDBKey(dbKey)
      if itemID then
        local itemRange = rangeByItemID[itemID]
        if not itemRange then
          itemRange = {
            basePrice = dbValue.m,
            minPrice = dbValue.m,
            maxPrice = dbValue.m,
            hasVariantData = false,
            _variantKeySeen = {},
            _variantKeyCount = 0,
          }
          rangeByItemID[itemID] = itemRange
        end

        if not itemRange.basePrice or itemRange.basePrice <= 0 then
          itemRange.basePrice = dbValue.m
        end

        if HasVariantSuffixInDBKey(dbKey) then
          itemRange.hasVariantData = true
          if not itemRange._variantKeySeen[dbKey] then
            itemRange._variantKeySeen[dbKey] = true
            itemRange._variantKeyCount = itemRange._variantKeyCount + 1
          end

          if dbValue.m < itemRange.minPrice then
            itemRange.minPrice = dbValue.m
          end
          if dbValue.m > itemRange.maxPrice then
            itemRange.maxPrice = dbValue.m
          end
        else
          itemRange.basePrice = dbValue.m
        end
      end
    end
  end

  for _, itemRange in pairs(rangeByItemID) do
    local hasUsableVariantRange = itemRange.hasVariantData and itemRange._variantKeyCount >= 2 and itemRange.maxPrice > itemRange.minPrice
    if not hasUsableVariantRange then
      local basePrice = tonumber(itemRange.basePrice) or tonumber(itemRange.minPrice) or 0
      itemRange.minPrice = basePrice
      itemRange.maxPrice = basePrice
    end

    itemRange._variantKeySeen = nil
    itemRange._variantKeyCount = nil
    itemRange.hasVariantData = nil
    itemRange.basePrice = nil
  end

  return rangeByItemID
end

-- Rebuilds the fast lookup set for missing items and removes duplicates.
local function RebuildMissingSet()
  AMS.missingSet = {}
  if type(AMS.missingItems) ~= "table" then
    AMS.missingItems = {}
    return
  end

  local indexedSet = {}
  if type(AMS.searchIndex) == "table" then
    for _, entry in ipairs(AMS.searchIndex) do
      if entry and entry.itemID then
        indexedSet[entry.itemID] = true
      end
    end
  end

  local deduped = {}
  for _, id in ipairs(AMS.missingItems) do
    local numericID = tonumber(id)
    if numericID and not AMS.missingSet[numericID] and not indexedSet[numericID] then
      AMS.missingSet[numericID] = true
      table.insert(deduped, numericID)
    end
  end
  AMS.missingItems = deduped
end

local function AddMissingItem(id)
  local numericID = tonumber(id)
  if not numericID then
    return
  end

  AMS.missingItems = AMS.missingItems or {}
  AMS.missingSet = AMS.missingSet or {}

  if not AMS.missingSet[numericID] then
    AMS.missingSet[numericID] = true
    table.insert(AMS.missingItems, numericID)
  end
end

-- Inserts or updates a single search entry for the given item.
local function UpsertSearchEntry(itemID, name, price, minPrice, maxPrice)
  local normalizedItemID = tonumber(itemID)
  if not normalizedItemID then
    return false
  end

  local itemString = "item:" .. tostring(normalizedItemID)
  local displayName = BuildDisplayName(name)
  local normalizedMinPrice = tonumber(minPrice) or tonumber(price) or 0
  local normalizedMaxPrice = tonumber(maxPrice) or tonumber(price) or normalizedMinPrice
  local displayPrice = normalizedMinPrice > 0 and normalizedMinPrice or (tonumber(price) or 0)

  for _, entry in ipairs(AMS.searchIndex) do
    if tonumber(entry.itemID) == normalizedItemID then
      local namesByLocale, canonicalName, englishName, localizedName = BuildNameFields(entry, displayName)
      canonicalName = canonicalName or ("Item " .. tostring(normalizedItemID))
      entry.names = namesByLocale
      entry.nameEN = nil
      entry.nameLocalized = localizedName
      entry.name = canonicalName
      entry.baseName = localizedName or canonicalName
      entry.nameLower = string.lower(canonicalName or "")
      entry.price = displayPrice > 0 and displayPrice or (entry.price or 0)
      entry.minPrice = normalizedMinPrice > 0 and normalizedMinPrice or (entry.minPrice or entry.price or 0)
      entry.maxPrice = normalizedMaxPrice > 0 and normalizedMaxPrice or (entry.maxPrice or entry.price or 0)
      entry.itemLink = itemString or entry.itemLink
      entry.lastCheckedAt = time()
      return false
    end
  end

  local namesByLocale, canonicalName, englishName, localizedName = BuildNameFields(nil, displayName)
  canonicalName = canonicalName or ("Item " .. tostring(normalizedItemID))

  table.insert(AMS.searchIndex, {
    nameLower = string.lower(canonicalName or ""),
    name = canonicalName,
    baseName = localizedName or canonicalName,
    names = namesByLocale,
    nameLocalized = localizedName,
    price = displayPrice,
    minPrice = normalizedMinPrice,
    maxPrice = normalizedMaxPrice,
    itemID = normalizedItemID,
    itemLink = itemString,
    lastCheckedAt = time(),
  })
  return true
end

-- Refreshes stale prices from Auctionator API in batches.
function AMS.RefreshStalePrices()
  if AMS.isRefreshingStale then
    return
  end

  if not AMS.indexReady or type(AMS.searchIndex) ~= "table" or #AMS.searchIndex == 0 then
    return
  end

  if not AMS.auctionatorAPI then
    return
  end

  if type(AMS.auctionatorAPI.GetAuctionAgeByItemID) ~= "function" or type(AMS.auctionatorAPI.GetAuctionPriceByItemID) ~= "function" then
    return
  end

  AMS.isRefreshingStale = true

  local thresholdDays = 2
  if AMS.settings and type(AMS.settings.refreshAgeDays) == "number" then
    thresholdDays = AMS.settings.refreshAgeDays
  end

  local callerID = "AuctionatorMiniSearch"
  local total = #AMS.searchIndex
  local batchSize = 150
  local updated = 0
  local removed = 0
  local now = time()
  local thresholdSeconds = thresholdDays * 24 * 60 * 60
  local autoDeleteAgeDays = 0
  local removeByIndex = {}

  if AMS.settings and type(AMS.settings.autoDeleteAgeDays) == "number" then
    autoDeleteAgeDays = AMS.settings.autoDeleteAgeDays
  end

  if AMS.statusText then
    AMS.statusText:SetText(L("STATUS_PRICES_REFRESHING_BG"))
  end

  local function FinishRefresh()
    if removed > 0 then
      for i = total, 1, -1 do
        if removeByIndex[i] then
          table.remove(AMS.searchIndex, i)
        end
      end
    end

    AMS.isRefreshingStale = false
    AMS.analysisCache = {}

    if (updated > 0 or removed > 0) and AMS.SaveSettings then
      AMS.SaveSettings()
    end

    if AMS.statusText then
      if updated > 0 or removed > 0 then
        local statusText = removed > 0 and L("STATUS_PRICES_UPDATED_REMOVED_FMT", updated, removed) or L("STATUS_PRICES_UPDATED_FMT", updated)
        AMS.statusText:SetText(statusText)
      else
        AMS.statusText:SetText(L("STATUS_READY"))
      end
    end

    if AMS.frame and AMS.frame:IsShown() and AMS.searchBox and AMS.PerformSearch then
      local text = AMS.searchBox:GetText()
      if text and string.len(text) >= 2 then
        AMS.PerformSearch(text)
      end
    end
  end

  local function ProcessBatch(startIndex)
    if not AMS.isRefreshingStale then
      return
    end

    local endIndex = math.min(startIndex + batchSize - 1, total)

    for i = startIndex, endIndex do
      local entry = AMS.searchIndex[i]
      if entry and entry.itemID then
        local age = nil
        if autoDeleteAgeDays > 0 then
          local okAgeDelete, resultAgeDelete = pcall(AMS.auctionatorAPI.GetAuctionAgeByItemID, callerID, entry.itemID)
          if okAgeDelete and type(resultAgeDelete) == "number" then
            age = resultAgeDelete
            if age >= autoDeleteAgeDays then
              removeByIndex[i] = true
              removed = removed + 1
            end
          end
        end

        if not removeByIndex[i] then
        local isDue = true
        if type(entry.lastCheckedAt) == "number" and thresholdSeconds > 0 then
          isDue = (now - entry.lastCheckedAt) >= thresholdSeconds
        end

        if isDue then
          if not entry.price or entry.price <= 0 then
            local okPrice, latestPrice = pcall(AMS.auctionatorAPI.GetAuctionPriceByItemID, callerID, entry.itemID)
            if okPrice and type(latestPrice) == "number" and latestPrice > 0 and latestPrice ~= entry.price then
              entry.price = latestPrice
              updated = updated + 1
            end
          else
            if age == nil then
              local okAge, resultAge = pcall(AMS.auctionatorAPI.GetAuctionAgeByItemID, callerID, entry.itemID)
              if okAge and type(resultAge) == "number" then
                age = resultAge
              end
            end

            if type(age) == "number" and age >= thresholdDays then
              local okPrice, latestPrice = pcall(AMS.auctionatorAPI.GetAuctionPriceByItemID, callerID, entry.itemID)
              if okPrice and type(latestPrice) == "number" and latestPrice > 0 and latestPrice ~= entry.price then
                entry.price = latestPrice
                updated = updated + 1
              end
            end
          end

          entry.lastCheckedAt = now
        end
        end
      end
    end

    if endIndex < total then
      C_Timer.After(0.01, function()
        ProcessBatch(endIndex + 1)
      end)
    else
      FinishRefresh()
    end
  end

  ProcessBatch(1)
end

function AMS.RefreshZeroPriceItems()
  if AMS.isRefreshingZeroPrices then
    return
  end

  if not AMS.indexReady or type(AMS.searchIndex) ~= "table" or #AMS.searchIndex == 0 then
    return
  end

  if not AMS.auctionatorAPI or type(AMS.auctionatorAPI.GetAuctionPriceByItemID) ~= "function" then
    return
  end

  AMS.isRefreshingZeroPrices = true

  if AMS.statusText then
    AMS.statusText:SetText(L("STATUS_ZEROPRICE_CHECKING"))
  end

  local total = #AMS.searchIndex
  local batchSize = 200
  local updated = 0
  local checked = 0
  local now = time()

  local function FinishZeroRefresh()
    AMS.isRefreshingZeroPrices = false
    if updated > 0 and AMS.SaveSettings then
      AMS.SaveSettings()
    end

    if AMS.statusText then
      if updated > 0 then
        AMS.statusText:SetText(L("STATUS_ZEROPRICE_UPDATED_FMT", updated))
      else
        AMS.statusText:SetText(L("STATUS_ZEROPRICE_CHECK_DONE_FMT", checked))
      end
    end

    if AMS.frame and AMS.frame:IsShown() and AMS.searchBox and AMS.PerformSearch then
      local text = AMS.searchBox:GetText()
      if text and string.len(text) >= 2 then
        AMS.PerformSearch(text)
      end
    end
  end

  local function ProcessBatch(startIndex)
    if not AMS.isRefreshingZeroPrices then
      return
    end

    local endIndex = math.min(startIndex + batchSize - 1, total)

    for i = startIndex, endIndex do
      local entry = AMS.searchIndex[i]
      if entry and entry.itemID and (not entry.price or entry.price <= 0) then
        checked = checked + 1
        local okPrice, latestPrice = pcall(AMS.auctionatorAPI.GetAuctionPriceByItemID, "AuctionatorMiniSearch", entry.itemID)
        if okPrice and type(latestPrice) == "number" and latestPrice > 0 then
          entry.price = latestPrice
          entry.lastCheckedAt = now
          updated = updated + 1
        end
      end
    end

    if endIndex < total then
      C_Timer.After(0.01, function()
        ProcessBatch(endIndex + 1)
      end)
    else
      FinishZeroRefresh()
    end
  end

  ProcessBatch(1)
end

function AMS.RefreshIndexFromPriceDB()
  if AMS.isReconcilingIndex then
    return
  end

  if not AMS.indexReady or type(AMS.searchIndex) ~= "table" then
    return
  end

  if type(AMS.priceDB) ~= "table" then
    return
  end

  AMS.isReconcilingIndex = true

  if AMS.statusText then
    AMS.statusText:SetText(L("STATUS_INDEX_RECONCILING"))
  end

  local indexedSet = {}
  for _, entry in ipairs(AMS.searchIndex) do
    if entry and entry.itemID then
      indexedSet[entry.itemID] = true
    end
  end

  local keys = {}
  local priceRangeByItemID = BuildPriceRangeByItemID()
  for k, v in pairs(AMS.priceDB) do
    if type(v) == "table" and v.m then
      table.insert(keys, k)
    end
  end

  for _, entry in ipairs(AMS.searchIndex) do
    if entry and entry.itemID then
      local itemRange = priceRangeByItemID[entry.itemID]
      if itemRange then
        entry.minPrice = itemRange.minPrice
        entry.maxPrice = itemRange.maxPrice
        entry.price = itemRange.minPrice or entry.price
      end
    end
  end

  local total = #keys
  local batchSize = 500
  local added = 0

  if total == 0 then
    AMS.isReconcilingIndex = false
    if AMS.statusText then
      AMS.statusText:SetText(L("STATUS_READY"))
    end

    if AMS._amsStartFollowupRefreshes then
      local cb = AMS._amsStartFollowupRefreshes
      AMS._amsStartFollowupRefreshes = nil
      C_Timer.After(0.05, cb)
    end
    return
  end

  local function FinishReconcile()
    AMS.isReconcilingIndex = false

    if added > 0 then
      table.sort(AMS.searchIndex, function(a, b)
        return a.nameLower < b.nameLower
      end)
    end

    if AMS.SaveSettings and added > 0 then
      AMS.SaveSettings()
    end

    if AMS.statusText then
      if added > 0 then
        AMS.statusText:SetText(L("STATUS_INDEX_RECONCILE_ADDED_FMT", added))
      else
        AMS.statusText:SetText(L("STATUS_INDEX_COMPLETE"))
      end
    end

    if AMS._amsStartFollowupRefreshes then
      local cb = AMS._amsStartFollowupRefreshes
      AMS._amsStartFollowupRefreshes = nil
      C_Timer.After(0.05, cb)
    end

    if AMS.frame and AMS.frame:IsShown() and AMS.searchBox and AMS.PerformSearch then
      local text = AMS.searchBox:GetText()
      if text and string.len(text) >= 2 then
        AMS.PerformSearch(text)
      end
    end
  end

  local function ProcessBatch(startIndex)
    if not AMS.isReconcilingIndex then
      return
    end

    local endIndex = math.min(startIndex + batchSize - 1, total)

    for i = startIndex, endIndex do
      local key = keys[i]
      local itemID = ExtractItemIDFromDBKey(key)
      local value = AMS.priceDB[key]

      if itemID and not indexedSet[itemID] then
        local name = ResolveItemName(itemID)
        if name then
          local itemRange = priceRangeByItemID[itemID]
          local price = (itemRange and itemRange.minPrice) or ((type(value) == "table" and type(value.m) == "number") and value.m) or GetPriceForItemID(itemID)
          local minPrice = itemRange and itemRange.minPrice or price
          local maxPrice = itemRange and itemRange.maxPrice or price
          UpsertSearchEntry(itemID, name, price, minPrice, maxPrice)
          indexedSet[itemID] = true
          added = added + 1
        else
          AddMissingItem(itemID)
        end
      end
    end

    if AMS.statusText and total > 100 then
      local percent = math.floor((endIndex / total) * 100)
      AMS.statusText:SetText(L("STATUS_INDEX_RECONCILE_PROGRESS_FMT", percent, added))
    end

    if endIndex < total then
      C_Timer.After(0.02, function()
        ProcessBatch(endIndex + 1)
      end)
    else
      FinishReconcile()
    end
  end

  ProcessBatch(1)
end

-- =========================
-- Batch 2: Fehlende Items
-- =========================

-- Verarbeitet fehlende Items in Batches
-- GetItemInfo, C_Timer sind WoW-API-Funktionen
function AMS.ProcessMissingBatch(startIndex)
  if not AMS.isRefreshingMissing then
    return
  end

  if not AMS._missingBatchContext then
    RebuildMissingSet()
    AMS._missingBatchContext = {
      queue = AMS.missingItems,
      nextMissingItems = {},
      nextMissingSet = {},
      recovered = 0,
      mode = AMS.missingProcessMode or "build",
    }
    AMS.isRefreshingMissing = true

    AMS.missingItems = {}
    AMS.missingSet = {}
  end

  local context = AMS._missingBatchContext
  local batchSize = 100
  local total = #context.queue

  if total == 0 then
    AMS._missingBatchContext = nil
    AMS.isRefreshingMissing = false
    if context.mode == "build" then
      AMS.indexReady = true
      AMS.progressFill:SetWidth(380)
      AMS.statusText:SetText(L("STATUS_READY"))
      AMS.searchBox:Enable()
      AMS.progressBar:Hide()
      AMS.progressFill:Hide()
    else
      AMS.statusText:SetText(L("STATUS_NO_MISSING_ITEMS_OPEN"))
    end

    if AMS.SaveSettings then
      AMS.SaveSettings()
    end
    return
  end

  local endIndex = math.min(startIndex + batchSize - 1, total)

  for i = startIndex, endIndex do
    local id = context.queue[i]
    local name = ResolveItemName(id) -- WoW-API

    if name then
      local itemRange = AMS._priceRangeByItemID and AMS._priceRangeByItemID[id]
      local price = (itemRange and itemRange.minPrice) or GetPriceForItemID(id)
      local minPrice = itemRange and itemRange.minPrice or price
      local maxPrice = itemRange and itemRange.maxPrice or price
      local added = UpsertSearchEntry(id, name, price, minPrice, maxPrice)
      if added then
        context.recovered = context.recovered + 1
      end
    else
      AMS.retryCount[id] = (AMS.retryCount[id] or 0) + 1
      if not context.nextMissingSet[id] then
        context.nextMissingSet[id] = true
        table.insert(context.nextMissingItems, id)
      end
    end
  end

  local percent = math.floor((endIndex / total) * 100)
  if context.mode == "build" then
    AMS.statusText:SetText(L("STATUS_ADDING_MORE_PRICES_PROGRESS_FMT", percent))
    AMS.progressFill:SetWidth(380 * (percent / 100))
  else
    AMS.statusText:SetText(L("STATUS_CHECKING_MISSING_PROGRESS_FMT", percent))
  end

  if endIndex < total then
    C_Timer.After(0.05, function() -- WoW-API
      AMS.ProcessMissingBatch(endIndex + 1)
    end)
  else
    AMS.missingItems = context.nextMissingItems
    RebuildMissingSet()

    table.sort(AMS.searchIndex, function(a, b)
      return a.nameLower < b.nameLower
    end)

    if context.mode == "build" then
      AMS.indexReady = true
      AMS.progressFill:SetWidth(380)
      AMS.statusText:SetText(L("STATUS_READY"))
      AMS.searchBox:Enable()
      AMS.progressBar:Hide()
      AMS.progressFill:Hide()
      print(L("LOG_INDEX_FULLY_LOADED_FMT", #AMS.searchIndex))
    else
      AMS.statusText:SetText(L("STATUS_MISSING_UPDATED_FMT", context.recovered, #AMS.missingItems))
    end

    AMS._missingBatchContext = nil
    AMS.isRefreshingMissing = false

    if AMS.SaveSettings then
      AMS.SaveSettings()
    end

    if context.mode ~= "build" and AMS.frame and AMS.frame:IsShown() and AMS.searchBox and AMS.PerformSearch then
      local text = AMS.searchBox:GetText()
      if text and string.len(text) >= 2 then
        AMS.PerformSearch(text)
      end
    end
  end
end

function AMS.RefreshMissingItems()
  if AMS.isRefreshingMissing then
    return
  end

  RebuildMissingSet()
  if #AMS.missingItems == 0 then
    if AMS.statusText then
      AMS.statusText:SetText(L("STATUS_NO_MISSING_ITEMS"))
    end
    return
  end

  if AMS.statusText then
    AMS.statusText:SetText(L("STATUS_CHECKING_MISSING_COUNT_FMT", #AMS.missingItems))
  end

  AMS.missingProcessMode = "refresh"
  AMS.isRefreshingMissing = true
  AMS.ProcessMissingBatch(1)
end

-- =========================
-- Batch 1: Main index
-- =========================

-- Builds the main index in batches.
-- GetItemInfo and C_Timer are WoW API functions.
function AMS.BuildIndex()
  AMS.searchBox:Disable()
  AMS.indexReady = false

  AMS.progressBar:Show()
  AMS.progressFill:Show()
  AMS.progressFill:SetWidth(1)

  AMS.statusText:SetText("")

  wipe(AMS.searchIndex)
  wipe(AMS.missingItems)
  AMS.missingSet = {}
  wipe(AMS.retryCount)
  AMS.analysisCache = {}

  -- Check whether a valid price database table is available.
  if type(AMS.priceDB) ~= "table" then
    if AMS.ShowErrorMessage then
      AMS.ShowErrorMessage(L("ERROR_INVALID_PRICE_DB"))
    end
    AMS.indexReady = false
    AMS.progressBar:Hide()
    AMS.progressFill:Hide()
    return
  end

  local keys = {}
  AMS._priceRangeByItemID = BuildPriceRangeByItemID()
  for k, v in pairs(AMS.priceDB) do
    if type(v) == "table" and v.m then
      table.insert(keys, k)
    end
  end

  local total = #keys
  local batchSize = 200

  local function ProcessMainBatch(startIndex)
    local endIndex = math.min(startIndex + batchSize - 1, total)

    for i = startIndex, endIndex do
      local k = keys[i]
      local v = AMS.priceDB[k]

      if v and type(v) == "table" and v.m then
        local itemID = ExtractItemIDFromDBKey(k)
        if itemID then
          local id = itemID
          local name = ResolveItemName(id) -- WoW-API

          if name then
            local itemRange = AMS._priceRangeByItemID and AMS._priceRangeByItemID[id]
            local minPrice = itemRange and itemRange.minPrice or v.m
            local maxPrice = itemRange and itemRange.maxPrice or v.m
            local displayPrice = minPrice or v.m
            UpsertSearchEntry(id, name, displayPrice, minPrice, maxPrice)
          else
            AddMissingItem(id)
          end
        end
      end
    end

    local percent = math.floor((endIndex / total) * 100)
    AMS.statusText:SetText(L("STATUS_INDEX_DB_SCANNING_PROGRESS_FMT", percent))
    AMS.progressFill:SetWidth(380 * (percent / 100))

    if endIndex < total then
      C_Timer.After(0.05, function() -- WoW-API
        ProcessMainBatch(endIndex + 1)
      end)
    else
      if #AMS.missingItems > 0 then
        AMS.missingProcessMode = "build"
        AMS.isRefreshingMissing = true
        C_Timer.After(0.2, function() -- WoW-API
          AMS.ProcessMissingBatch(1)
        end)
      else
        AMS.indexReady = true
        AMS.progressFill:SetWidth(380)
        AMS.statusText:SetText(L("STATUS_READY"))
        AMS.searchBox:Enable()
        AMS._priceRangeByItemID = nil

        AMS.progressBar:Hide()
        AMS.progressFill:Hide()

        if AMS.SaveSettings then
          AMS.SaveSettings()
        end
      end
    end
  end

  ProcessMainBatch(1)
end

-- Backfills locale-specific names for existing index entries in small batches.
function AMS.BackfillLocaleNamesForIndex()
  if type(AMS.searchIndex) ~= "table" or #AMS.searchIndex == 0 then
    return
  end

  local dataLocale = "enUS"
  if AMS.GetDefaultLocale then
    dataLocale = AMS.GetDefaultLocale()
  end

  local total = #AMS.searchIndex
  local batchSize = 150
  local changed = 0

  local function ProcessBatch(startIndex)
    local endIndex = math.min(startIndex + batchSize - 1, total)

    for i = startIndex, endIndex do
      local entry = AMS.searchIndex[i]
      if type(entry) == "table" and entry.itemID then
        entry.names = type(entry.names) == "table" and entry.names or {}

        local itemName = ResolveItemName(entry.itemID)
        if type(itemName) == "string" and itemName ~= "" then
          local currentStored = entry.names[dataLocale]
          if currentStored ~= itemName then
            entry.names[dataLocale] = itemName
            changed = changed + 1
          end

          if dataLocale == "deDE" then
            entry.nameLocalized = entry.names.deDE or itemName
          else
            entry.nameLocalized = entry.names.deDE or entry.nameLocalized or itemName
          end

          entry.name = entry.names.enUS or entry.nameLocalized or itemName
          entry.baseName = entry.nameLocalized or entry.name
          entry.nameLower = string.lower(entry.name or "")
        end
      end
    end

    if endIndex < total then
      C_Timer.After(0.01, function()
        ProcessBatch(endIndex + 1)
      end)
    else
      if changed > 0 and AMS.SaveSettings then
        AMS.SaveSettings()
      end
    end
  end

  ProcessBatch(1)
end
