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

local function setupMonitors(config)
  local monitors = {}
  local touchNameToSide = {}

  for _, side in ipairs(common.MONITOR_SIDES) do
    local mapped = config.monitorSides and config.monitorSides[side] or side
    if not peripheral.isPresent(mapped) or peripheral.getType(mapped) ~= "monitor" then
      error("Missing monitor mapping: " .. side .. " -> " .. tostring(mapped))
    end

    local mon = peripheral.wrap(mapped)
    mon.setTextScale(0.5)
    mon.setBackgroundColor(colors.black)
    mon.clear()
    mon.setCursorPos(1, 1)
    monitors[side] = mon
    touchNameToSide[mapped] = side
  end

  return monitors, touchNameToSide
end

local function drawMonitor(mon, rows)
  if type(rows) ~= "table" then
    return
  end

  for y = 1, common.MONITOR_HEIGHT do
    local row = rows[y]
    if row then
      mon.setCursorPos(1, y)
      mon.blit(row.text, row.fg, row.bg)
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
local monitors, touchNameToSide = setupMonitors(config)

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
    monitorWidth = common.MONITOR_WIDTH,
    monitorHeight = common.MONITOR_HEIGHT,
    monitorsPerNode = common.MONITORS_PER_NODE,
  }, common.PROTOCOL)
end

local function sendTouch(target, side, x, y)
  local slot = common.sideToSlot(side)
  if not slot then
    return
  end

  local gx, gy = common.localToGlobal(slot, x, y, config.stackIndex)
  rednet.send(target, {
    kind = "touch",
    protocol = common.PROTOCOL,
    nodeId = nodeId,
    stackIndex = config.stackIndex,
    side = side,
    slot = slot,
    x = x,
    y = y,
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
        if type(msg.rowsBySlot) == "table" then
          for slot = 1, common.MONITORS_PER_NODE do
            local side = common.slotToSide(slot)
            local mon = monitors[side]
            local rows = msg.rowsBySlot[slot]
            drawMonitor(mon, rows)
          end
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
