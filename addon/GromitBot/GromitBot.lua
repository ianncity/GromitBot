GromitBotTelemetry = GromitBotTelemetry or {}

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_LEVEL_UP")
frame:RegisterEvent("UNIT_HEALTH")
frame:RegisterEvent("UNIT_POWER_UPDATE")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
frame:RegisterEvent("BAG_UPDATE_DELAYED")
frame:RegisterEvent("PLAYER_XP_UPDATE")

local function round2(value)
  if value == nil then
    return nil
  end
  return math.floor((value * 10000) + 0.5) / 10000
end

local function getBagFillPct()
  local slots = 0
  local used = 0

  for bag = 0, 4 do
    local num = C_Container.GetContainerNumSlots(bag)
    slots = slots + num
    for slot = 1, num do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info ~= nil then
        used = used + 1
      end
    end
  end

  if slots == 0 then
    return 0
  end

  return (used / slots) * 100
end

local function getMapPos()
  local mapId = C_Map.GetBestMapForUnit("player")
  if not mapId then
    return nil, nil
  end

  local pos = C_Map.GetPlayerMapPosition(mapId, "player")
  if not pos then
    return nil, nil
  end

  local x, y = pos:GetXY()
  return round2(x), round2(y)
end

local function updateTelemetry()
  local mapX, mapY = getMapPos()

  GromitBotTelemetry.name = UnitName("player") or "Unknown"
  GromitBotTelemetry.zone = GetRealZoneText() or "Unknown"
  GromitBotTelemetry.level = UnitLevel("player") or 1
  GromitBotTelemetry.xp = UnitXP("player") or 0
  GromitBotTelemetry.hp = UnitHealth("player") or 0
  GromitBotTelemetry.mana = UnitPower("player", 0) or 0
  GromitBotTelemetry.bagFillPct = math.floor(getBagFillPct() + 0.5)
  GromitBotTelemetry.mapX = mapX
  GromitBotTelemetry.mapY = mapY
  GromitBotTelemetry.updatedAt = time()
end

frame:SetScript("OnEvent", function()
  updateTelemetry()
end)

SLASH_GROMITBOT1 = "/gromit"
SlashCmdList.GROMITBOT = function()
  updateTelemetry()
  DEFAULT_CHAT_FRAME:AddMessage("GromitBot telemetry refreshed")
end
