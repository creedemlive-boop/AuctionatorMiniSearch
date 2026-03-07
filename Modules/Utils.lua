-- =========================
-- Utils.lua - Utility helpers and shared addon tables
-- =========================


_G["AuctionatorMiniSearch"] = _G["AuctionatorMiniSearch"] or {}
local AMS = _G["AuctionatorMiniSearch"]

-- Shared addon tables
AMS.searchIndex = AMS.searchIndex or {}
AMS.missingItems = AMS.missingItems or {}
AMS.retryCount = {}

-- Constants
AMS.ROW_COUNT = 15
AMS.ROW_HEIGHT = 18
AMS.indexReady = false

-- =========================
-- Money formatting
-- =========================

-- Formats a copper amount as a gold/silver/copper string.
-- Uses Lua standard functions: math.floor and string.format.
function AMS.FormatMoney(copper)
  if type(copper) ~= "number" then
    return "?"
  end

  local gold = math.floor(copper / 10000)
  local silver = math.floor((copper % 10000) / 100)
  local c = copper % 100

  return string.format("%dg %ds %dc", gold, silver, c)
end

-- =========================
-- Row cleanup
-- =========================

-- Clears all UI rows (used by multiple modules).
function AMS.ClearRows(rows)
  for _, row in ipairs(rows) do
    row.text:SetText("")
    row.itemID = nil
    row.itemName = nil
    row.itemLink = nil
    row.price = nil
    row.minPrice = nil
    row.maxPrice = nil
    row.icon:SetTexture(nil)
  end
end
