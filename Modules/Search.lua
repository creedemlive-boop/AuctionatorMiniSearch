-- =========================
-- Search.lua - Search logic and result rendering
-- =========================

local AMS = _G["AuctionatorMiniSearch"]
local L = AMS.L
local LIVE_PRICE_REFRESH_SECONDS = 10

local function GetMinSearchLength()
  local configured = AMS.settings and tonumber(AMS.settings.minSearchLength) or 2
  if configured < 1 then
    return 1
  end
  if configured > 6 then
    return 6
  end
  return configured
end

local function IsLiveSearchEnabled()
  if not AMS.settings then
    return true
  end
  return AMS.settings.liveSearch ~= false
end

local function IsAnalysisSuffixEnabled()
  if not AMS.settings then
    return true
  end
  return AMS.settings.showAnalysisSuffix ~= false
end

local function StripLegacyItemLevelSuffix(name)
  if type(name) ~= "string" or name == "" then
    return name
  end

  return string.gsub(name, "%s*%([iI][lL][vV][lL]?%s*%d+%)$", "")
end

local function GetActiveLocale()
  if AMS.GetCurrentLocale then
    return AMS.GetCurrentLocale()
  end
  return "enUS"
end

local function GetEntryDisplayName(entry)
  if type(entry) ~= "table" then
    return ""
  end

  local activeLocale = GetActiveLocale()
  local namesByLocale = type(entry.names) == "table" and entry.names or nil
  local preferred
  local fallback

  if activeLocale == "deDE" then
    preferred = (namesByLocale and namesByLocale.deDE) or entry.nameLocalized or entry.baseName
    fallback = (namesByLocale and namesByLocale.enUS) or entry.nameEN or entry.name
  else
    preferred = (namesByLocale and namesByLocale.enUS) or entry.nameEN or entry.name
    fallback = (namesByLocale and namesByLocale.deDE) or entry.nameLocalized or entry.baseName
  end

  local displayName = StripLegacyItemLevelSuffix(preferred)
  if not displayName or displayName == "" then
    displayName = StripLegacyItemLevelSuffix(fallback)
  end
  if not displayName or displayName == "" then
    local numericItemID = tonumber(entry.itemID)
    if numericItemID then
      displayName = L("FALLBACK_ITEM_FMT", numericItemID)
    else
      displayName = ""
    end
  end

  return displayName
end

local function EntryMatchesQuery(entry, query)
  if type(entry) ~= "table" then
    return false
  end

  local activeLocale = GetActiveLocale()
  local namesByLocale = type(entry.names) == "table" and entry.names or nil
  local primary
  local secondary
  local tertiary

  if activeLocale == "deDE" then
    primary = (namesByLocale and namesByLocale.deDE) or entry.nameLocalized or entry.baseName
    if not primary or primary == "" then
      secondary = (namesByLocale and namesByLocale.enUS) or entry.nameEN or entry.name
    end
    tertiary = entry.name
  else
    primary = (namesByLocale and namesByLocale.enUS) or entry.nameEN or entry.name
    if not primary or primary == "" then
      secondary = (namesByLocale and namesByLocale.deDE) or entry.nameLocalized or entry.baseName
    end
    tertiary = entry.nameLocalized or entry.baseName
  end

  if type(primary) == "string" and primary ~= "" and string.find(string.lower(primary), query, 1, true) then
    return true
  end

  if type(secondary) == "string" and secondary ~= "" and string.find(string.lower(secondary), query, 1, true) then
    return true
  end

  if type(tertiary) == "string" and tertiary ~= "" and string.find(string.lower(tertiary), query, 1, true) then
    return true
  end

  if namesByLocale then
    for _, localeName in pairs(namesByLocale) do
      if type(localeName) == "string" and localeName ~= "" and string.find(string.lower(localeName), query, 1, true) then
        return true
      end
    end
  end

  return false
end

local function BuildSafeRowItemLink(entry)
  if type(entry) ~= "table" then
    return nil
  end

  local itemID = tonumber(entry.itemID)
  if not itemID then
    return nil
  end

  if type(entry.itemLink) == "string" and entry.itemLink ~= "" then
    if string.match(entry.itemLink, "^|Hitem:") then
      return entry.itemLink
    end

    if string.match(entry.itemLink, "^item:") then
      return entry.itemLink
    end

    local idFromLink = string.match(entry.itemLink, "^item:(%d+)")
    if idFromLink then
      return entry.itemLink
    end
  end

  return "item:" .. tostring(itemID)
end

local function GetAnalysisMeta(itemID)
  AMS.analysisCache = AMS.analysisCache or {}

  if AMS.analysisCache[itemID] then
    return AMS.analysisCache[itemID]
  end

  local meta = {
    exact = nil,
    age = nil,
  }

  if AMS.auctionatorAPI then
    if type(AMS.auctionatorAPI.IsAuctionDataExactByItemID) == "function" then
      local okExact, resultExact = pcall(AMS.auctionatorAPI.IsAuctionDataExactByItemID, "AuctionatorMiniSearch", itemID)
      if okExact then
        meta.exact = resultExact
      end
    end

    if type(AMS.auctionatorAPI.GetAuctionAgeByItemID) == "function" then
      local okAge, resultAge = pcall(AMS.auctionatorAPI.GetAuctionAgeByItemID, "AuctionatorMiniSearch", itemID)
      if okAge then
        meta.age = resultAge
      end
    end
  end

  AMS.analysisCache[itemID] = meta
  return meta
end

local function BuildAnalysisSuffix(itemID)
  local meta = GetAnalysisMeta(itemID)
  local parts = {}

  if meta.age ~= nil then
    table.insert(parts, L("AGE_DAYS_FMT", meta.age))
  end

  if #parts == 0 then
    return ""
  end

  return " [" .. table.concat(parts, " | ") .. "]"
end

-- =========================
-- Main search function
-- =========================

-- Executes a query against the index and writes matching rows to the UI.
-- GetItemIcon is a WoW API function.
-- Runs a full-text query against the in-memory index and updates visible rows.
function AMS.PerformSearch(query)
  if not AMS.indexReady then
    AMS.ClearRows(AMS.rows)
    AMS.statusText:SetText(L("STATUS_INDEX_BUILDING"))
    return
  end

  if #AMS.searchIndex == 0 then
    AMS.rows[1].text:SetText(L("STATUS_NO_DATA_INDEXED"))
    AMS.statusText:SetText(L("STATUS_NO_DATA"))
    return
  end

  query = string.lower(query)
  local index = 1
  local totalMatches = 0

  -- First pass: count total matches.
  for _, entry in ipairs(AMS.searchIndex) do
    if EntryMatchesQuery(entry, query) then
      totalMatches = totalMatches + 1
    end
  end

  -- Second pass: render matching entries.
  for _, entry in ipairs(AMS.searchIndex) do
    if EntryMatchesQuery(entry, query) then
      if not AMS.rows[index] then break end

      if AMS.auctionatorAPI and type(AMS.auctionatorAPI.GetAuctionPriceByItemID) == "function" then
        local now = time()
        local shouldRefreshLivePrice = (entry.lastLivePriceCheckAt or 0) + LIVE_PRICE_REFRESH_SECONDS <= now

        if shouldRefreshLivePrice then
          local ok, latestPrice = pcall(AMS.auctionatorAPI.GetAuctionPriceByItemID, "AuctionatorMiniSearch", entry.itemID)
          entry.lastLivePriceCheckAt = now
          if ok and type(latestPrice) == "number" and latestPrice > 0 then
            entry.price = latestPrice
          end
        end
      end

      local analysisSuffix = BuildAnalysisSuffix(entry.itemID)
      local displayName = GetEntryDisplayName(entry)

      local minPrice = tonumber(entry.minPrice)
      local maxPrice = tonumber(entry.maxPrice)
      local priceText = AMS.FormatMoney(entry.price)
      if minPrice and maxPrice and minPrice > 0 and maxPrice > minPrice then
        priceText = L("PRICE_RANGE_PREFIX") .. AMS.FormatMoney(minPrice) .. L("PRICE_RANGE_TO") .. AMS.FormatMoney(maxPrice)
      end

      AMS.rows[index].text:SetText(displayName .. " – " .. priceText .. analysisSuffix)
      AMS.rows[index].itemID = entry.itemID
      AMS.rows[index].itemName = displayName
      AMS.rows[index].itemLink = BuildSafeRowItemLink(entry)
      AMS.rows[index].price = entry.price
      AMS.rows[index].minPrice = minPrice
      AMS.rows[index].maxPrice = maxPrice
      AMS.rows[index].icon:SetTexture(C_Item.GetItemIconByID(entry.itemID)) -- WoW API
      AMS.rows[index]:Show()

      index = index + 1
      if index > #AMS.rows then break end
    end
  end

  -- Clear remaining rows.
  for i = index, #AMS.rows do
    AMS.rows[i].text:SetText("")
    AMS.rows[i].itemID = nil
    AMS.rows[i].itemName = nil
    AMS.rows[i].itemLink = nil
    AMS.rows[i].price = nil
    AMS.rows[i].minPrice = nil
    AMS.rows[i].maxPrice = nil
    AMS.rows[i].icon:SetTexture(nil)
  end

  -- Update status text.
  if index == 1 then
    AMS.statusText:SetText(L("STATUS_NO_MATCHES"))
  else
    local statusMsg = L("STATUS_MATCHES_FOUND_FMT", (index - 1))
    if totalMatches > #AMS.rows then
      statusMsg = statusMsg .. L("STATUS_MATCHES_TOTAL_FMT", totalMatches)
    end
    AMS.statusText:SetText(statusMsg)
  end
end

-- =========================
-- Input handling
-- =========================

AMS.searchBox:SetScript("OnEnterPressed", function(self)
  local minSearchLength = GetMinSearchLength()
  local text = self:GetText()
  if text and string.len(text) >= minSearchLength then
    AMS.PerformSearch(text)
  else
    AMS.ClearRows(AMS.rows)
  end
  if not AMS.settings or AMS.settings.keepFocusOnEnter ~= true then
    self:ClearFocus()
  end
end)

AMS.searchBox:SetScript("OnTextChanged", function(self)
  local minSearchLength = GetMinSearchLength()
  local text = self:GetText()

  if not IsLiveSearchEnabled() then
    if AMS.indexReady and (not text or string.len(text) < minSearchLength) then
      AMS.ClearRows(AMS.rows)
    end
    return
  end

  if AMS.indexReady and text and string.len(text) >= minSearchLength then
    AMS.PerformSearch(text)
  elseif AMS.indexReady then
    AMS.ClearRows(AMS.rows)
  end
end)

AMS.searchBox:SetScript("OnEscapePressed", function(self)
  self:ClearFocus()
end)

AMS.searchButton:SetScript("OnClick", function()
  local minSearchLength = GetMinSearchLength()
  local text = AMS.searchBox:GetText()
  if text and string.len(text) >= minSearchLength then
    AMS.PerformSearch(text)
  else
    AMS.ClearRows(AMS.rows)
  end
end)

if AMS.searchIconButton then
  AMS.searchIconButton:SetScript("OnClick", function()
    local minSearchLength = GetMinSearchLength()
    local text = AMS.searchBox:GetText()
    if text and string.len(text) >= minSearchLength then
      AMS.PerformSearch(text)
    else
      AMS.ClearRows(AMS.rows)
    end
  end)
end
