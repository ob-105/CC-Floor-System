local common = require("common")

local CONFIG_PATH = "node_config.lua"
local HEARTBEAT_SECONDS = 2

local function fileExists(path)
  return fs.exists(path) and not fs.isDir(path)
end

local function saveConfig(config)
  local h = fs.open(CONFIG_PATH, "w")
  if not h then
    error("Unable to write " .. CONFIG_PATH)
  end
  h.write("return " .. textutils.serialize(config))
  h.close()
end

local function loadConfig()
  local config = common.defaultNodeConfig()
  if fileExists(CONFIG_PATH) then
    local ok, loaded = pcall(dofile, CONFIG_PATH)
    if ok and type(loaded) == "table" then
      for k, v in pairs(loaded) do
        config[k] = v
      end
    end
  end
  return config
end

local function ensureRednet(modemSide)
  if not peripheral.isPresent(modemSide) then
    error("No modem on side: " .. modemSide)
  end

  local t = peripheral.getType(modemSide)
  if t ~= "modem" then
    error("Peripheral on " .. modemSide .. " is not a modem")
  end

  if not rednet.isOpen(modemSide) then
    rednet.open(modemSide)
  end
end

local function listMonitorNames()
  local names = peripheral.getNames()
  local monitors = {}
  for _, name in ipairs(names) do
    if peripheral.getType(name) == "monitor" then
      monitors[#monitors + 1] = name
    end
  end
  table.sort(monitors)
  return monitors
end

local function isMonitorName(name)
  return type(name) == "string"
    and peripheral.isPresent(name)
    and peripheral.getType(name) == "monitor"
end

local function normalizeMonitorSides(config)
  config.monitorSides = config.monitorSides or {}

  local available = listMonitorNames()
  local used = {}
  local changed = false

  -- Keep valid existing mappings first.
  for _, side in ipairs(common.MONITOR_SIDES) do
    local mapped = config.monitorSides[side]
    if isMonitorName(mapped) and not used[mapped] then
      used[mapped] = true
    else
      if mapped ~= nil then
        changed = true
      end
      config.monitorSides[side] = nil
    end
  end

  -- Fill any missing logical sides with remaining monitors.
  local i = 1
  for _, side in ipairs(common.MONITOR_SIDES) do
    if not config.monitorSides[side] then
      while i <= #available and used[available[i]] do
        i = i + 1
      end
      if i <= #available then
        config.monitorSides[side] = available[i]
        used[available[i]] = true
        changed = true
        i = i + 1
      end
    end
  end

  local complete = true
  for _, side in ipairs(common.MONITOR_SIDES) do
    if not isMonitorName(config.monitorSides[side]) then
      complete = false
      break
    end
  end

  return changed, complete, available
end

local function setupMonitors(config)
  local monitors = {}
  local touchNameToSide = {}
  local panelWidth = nil
  local panelHeight = nil

  for _, side in ipairs(common.MONITOR_SIDES) do
    local mapped = config.monitorSides and config.monitorSides[side] or side
    if not peripheral.isPresent(mapped) or peripheral.getType(mapped) ~= "monitor" then
      error("Missing monitor mapping: " .. side .. " -> " .. tostring(mapped))
    end

    local mon = peripheral.wrap(mapped)
    mon.setTextScale(0.5)
    local w, h = mon.getSize()
    if not panelWidth then
      panelWidth = w
      panelHeight = h
    elseif panelWidth ~= w or panelHeight ~= h then
      error("All mapped monitors must have same size. Mismatch at " .. tostring(mapped) .. ": " .. tostring(w) .. "x" .. tostring(h))
    end
    mon.setBackgroundColor(colors.black)
    mon.clear()
    mon.setCursorPos(1, 1)
    monitors[side] = mon
    touchNameToSide[mapped] = side
  end

  return monitors, touchNameToSide, panelWidth, panelHeight
end

local function drawMonitor(mon, rows, panelHeight)
  if type(rows) ~= "table" then
    return
  end

  for y = 1, panelHeight do
    local row = rows[y]
    if row then
      mon.setCursorPos(1, y)
      mon.blit(row.text, row.fg, row.bg)
    end
  end
end

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function chooseColor(value, palette)
  local idx = math.floor(clamp(value, 0, 0.9999) * #palette) + 1
  return palette[idx]
end

local ripplePalette = {
  colors.black,
  colors.blue,
  colors.cyan,
  colors.lightBlue,
  colors.white,
  colors.yellow,
  colors.orange,
  colors.red,
}

local DEFAULT_RIPPLE_MAX_DISTANCE = 120
local rippleHadEnergy = false

local function min2(a, b)
  if a < b then
    return a
  end
  return b
end

local function reflectedPositions(pos, size)
  local period = size * 2
  return {
    pos - period,
    pos,
    pos + period,
    (period - pos + 1) - period,
    (period - pos + 1),
    (period - pos + 1) + period,
  }
end

local function drawRippleState(mon, msg, stackIndex, localPanelWidth, localPanelHeight)
  local liveCount = math.max(1, math.floor(msg.liveCount or 1))
  local canvasWidth = math.max(1, math.floor(msg.canvasWidth or localPanelWidth))
  local canvasHeight = math.max(1, math.floor(msg.canvasHeight or (localPanelHeight * liveCount)))
  local maxAge = tonumber(msg.maxAge) or 16.0
  local maxSources = math.max(1, math.floor(tonumber(msg.maxSources) or 6))
  local waveSpeed = tonumber(msg.waveSpeed) or 18.0
  local damping = tonumber(msg.damping) or 0.08
  local pulseWidth = tonumber(msg.pulseWidth) or 3.6
  local trailDamping = tonumber(msg.trailDamping) or 0.08
  local impactDecay = tonumber(msg.impactDecay) or 0.9
  local impactStrength = tonumber(msg.impactStrength) or 2.4
  local pixelScale = math.max(1, math.floor(tonumber(msg.pixelScale) or 2))
  local src = type(msg.sources) == "table" and msg.sources or {}

  local sources = {}
  for i = 1, #src do
    if #sources >= maxSources then
      break
    end

    local s = src[i]
    local age = tonumber(s.age) or 0
    if age >= 0 and age < maxAge then
      local sx = tonumber(s.x)
      local sy = tonumber(s.y)
      if sx and sy then
        local ampAge = (tonumber(s.amp) or 1.0) / (1 + age * damping * 3.5)
        if ampAge > 0.0005 then
          local vel = tonumber(s.vel) or 1.0
          local radius = age * waveSpeed * vel
          local localPulseWidth = math.max(0.9, pulseWidth)
          local trailWidth = localPulseWidth * (2.5 + trailDamping * 4)
          local maxReach = radius + math.max(DEFAULT_RIPPLE_MAX_DISTANCE, trailWidth)
          local xImages = reflectedPositions(sx, canvasWidth)
          local yImages = reflectedPositions(sy, canvasHeight)
          sources[#sources + 1] = {
            sx = sx,
            sy = sy,
            xImages = xImages,
            yImages = yImages,
            radius = radius,
            ampAge = ampAge,
            impactAge = (ampAge * impactStrength) / (1 + age * impactDecay * 2),
            pulseWidth = localPulseWidth,
            trailWidth = trailWidth,
            maxReach2 = maxReach * maxReach,
          }
        end
      end
    end
  end

  if #sources == 0 then
    if rippleHadEnergy then
      mon.setBackgroundColor(colors.black)
      mon.clear()
      rippleHadEnergy = false
    end
    return
  end
  rippleHadEnergy = true

  local textConstant = string.rep(" ", localPanelWidth)
  local fgConstant = string.rep("f", localPanelWidth)

  for localYStart = 1, localPanelHeight, pixelScale do
    local localYEnd = math.min(localPanelHeight, localYStart + pixelScale - 1)
    local gy = (liveCount - stackIndex) * localPanelHeight + math.floor((localYStart + localYEnd) / 2)
    local bgRow = {}
    for localXStart = 1, localPanelWidth, pixelScale do
      local localXEnd = math.min(localPanelWidth, localXStart + pixelScale - 1)
      local gx = math.floor((localXStart + localXEnd) / 2)
      local pressure = 0

      for i = 1, #sources do
        local s = sources[i]
        local bestD2 = 1e30
        for xi = 1, #s.xImages do
          local dx = gx - s.xImages[xi]
          local dx2 = dx * dx
          if dx2 <= s.maxReach2 then
            for yi = 1, #s.yImages do
              local dy = gy - s.yImages[yi]
              local d2 = dx2 + dy * dy
              if d2 < bestD2 then
                bestD2 = d2
              end
            end
          end
        end

        local d2 = bestD2
        if d2 <= s.maxReach2 then
          local d = math.sqrt(d2)
          local delta = d - s.radius
          local ad = math.abs(delta)
          local core = 0
          if ad < s.pulseWidth then
            core = 1 - (ad / s.pulseWidth)
          end

          local ring = 0
          if ad < s.trailWidth then
            local env = 1 - (ad / s.trailWidth)
            ring = math.cos(delta * 0.72) * env
          end

          local impact = 0
          if d2 < 49 then
            impact = s.impactAge / (1 + d2 * 0.22)
          end

          pressure = pressure + s.ampAge * (1.1 * core + 0.75 * ring) + impact
        end
      end

      local normalized = clamp((pressure + 1.2) / 2.4, 0, 1)
      local bg = colors.toBlit(chooseColor(normalized, ripplePalette))
      for fillX = localXStart, localXEnd do
        bgRow[fillX] = bg
      end
    end

    local bgString = table.concat(bgRow)
    for localY = localYStart, localYEnd do
      mon.setCursorPos(1, localY)
      mon.blit(textConstant, fgConstant, bgString)
    end
  end
end

local function clearAll(monitors)
  for _, side in ipairs(common.MONITOR_SIDES) do
    local mon = monitors[side]
    mon.setBackgroundColor(colors.black)
    mon.clear()
  end
end

local config = loadConfig()
ensureRednet(config.modemSide)
local changed, complete, available = normalizeMonitorSides(config)
if changed then
  saveConfig(config)
end
if not complete then
  error(
    "Could not map required monitor(s). Found: "
      .. tostring(#available)
      .. " ("
      .. table.concat(available, ", ")
      .. ")"
  )
end
local monitors, touchNameToSide, panelWidth, panelHeight = setupMonitors(config)

local nodeId = os.getComputerID()
local hostname = config.nodeName or ("floor-node-" .. tostring(nodeId))
rednet.host(common.PROTOCOL, hostname)

local function sendHello(target)
  rednet.send(target, {
    kind = "hello",
    protocol = common.PROTOCOL,
    nodeId = nodeId,
    label = os.getComputerLabel(),
    hostname = hostname,
    stackIndex = config.stackIndex,
    panelWidth = panelWidth,
    panelHeight = panelHeight,
    monitorsPerNode = common.MONITORS_PER_NODE,
  }, common.PROTOCOL)
end

local function sendTouch(target, side, x, y)
  local slot = common.sideToSlot(side)
  if not slot then
    return
  end

  local gx, gy = common.localToGlobal(slot, x, y, config.stackIndex, panelWidth, panelHeight)
  rednet.send(target, {
    kind = "touch",
    protocol = common.PROTOCOL,
    nodeId = nodeId,
    stackIndex = config.stackIndex,
    side = side,
    slot = slot,
    x = x,
    y = y,
    panelWidth = panelWidth,
    panelHeight = panelHeight,
    gx = gx,
    gy = gy,
    timestamp = os.epoch("utc"),
  }, common.PROTOCOL)
end

local function heartbeat(target)
  rednet.send(target, {
    kind = "heartbeat",
    protocol = common.PROTOCOL,
    nodeId = nodeId,
    stackIndex = config.stackIndex,
    timestamp = os.epoch("utc"),
  }, common.PROTOCOL)
end

local controllerId = nil
local lastHeartbeat = 0

clearAll(monitors)

while true do
  local now = os.clock()
  if controllerId and (now - lastHeartbeat) >= HEARTBEAT_SECONDS then
    heartbeat(controllerId)
    lastHeartbeat = now
  end

  local event, p1, p2, p3, p4 = os.pullEvent()

  if event == "rednet_message" then
    local sender = p1
    local msg = p2
    local protocol = p3

    if protocol == common.PROTOCOL and type(msg) == "table" then
      if msg.kind == "discover" then
        sendHello(sender)
      elseif msg.kind == "assign" then
        controllerId = sender
        if type(msg.stackIndex) == "number" then
          config.stackIndex = math.max(1, math.floor(msg.stackIndex))
          saveConfig(config)
        end
        sendHello(sender)
      elseif msg.kind == "frame" then
        controllerId = sender
        rippleHadEnergy = false
        if type(msg.rowsBySlot) == "table" then
          for slot = 1, common.MONITORS_PER_NODE do
            local side = common.slotToSide(slot)
            local mon = monitors[side]
            local rows = msg.rowsBySlot[slot]
            drawMonitor(mon, rows, panelHeight)
          end
        end
      elseif msg.kind == "ripple_state" then
        controllerId = sender
        local side = common.slotToSide(1)
        local mon = monitors[side]
        if mon then
          drawRippleState(mon, msg, config.stackIndex, panelWidth, panelHeight)
        end
      elseif msg.kind == "ping" then
        sendHello(sender)
      end
    end
  elseif event == "monitor_touch" then
    local touchName = p1
    local x = p2
    local y = p3
    local side = touchNameToSide[touchName] or touchName

    if controllerId then
      sendTouch(controllerId, side, x, y)
    end
  end
end
