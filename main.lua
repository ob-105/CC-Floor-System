local common = require("common")

local MODEM_SIDE = "bottom"
local MIN_FRAME_SECONDS = 0.08
local MAX_FRAME_SECONDS = 0.35
local DISCOVER_SECONDS = 2.0
local NODE_TIMEOUT_SECONDS = 8.0
local MAX_RIPPLE_SOURCES = 12
local RIPPLE_MAX_AGE = 16.0
local RIPPLE_WAVE_SPEED = 18.0
local RIPPLE_DAMPING = 0.08
local RIPPLE_PULSE_WIDTH = 3.6
local RIPPLE_FREQ = 0.9
local RIPPLE_TRAIL_DAMPING = 0.08
local RIPPLE_IMPACT_DECAY = 0.9
local RIPPLE_IMPACT_STRENGTH = 2.4
local RIPPLE_PIXEL_SCALE = 4

if not peripheral.isPresent(MODEM_SIDE) or peripheral.getType(MODEM_SIDE) ~= "modem" then
  error("Main computer needs a modem on side: " .. MODEM_SIDE)
end
if not rednet.isOpen(MODEM_SIDE) then
  rednet.open(MODEM_SIDE)
end

local colorBlit = {}
for i = 0, 15 do
  local c = 2 ^ i
  colorBlit[i] = colors.toBlit(c)
end

local function blitOfColor(c)
  return colors.toBlit(c)
end

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function chooseColor(value, tableColors)
  local idx = math.floor(clamp(value, 0, 0.9999) * #tableColors) + 1
  return tableColors[idx]
end

local function now()
  return os.clock()
end

local nodes = {}

local function activeNodes()
  local t = now()
  local result = {}
  for id, node in pairs(nodes) do
    if (t - node.lastSeen) <= NODE_TIMEOUT_SECONDS then
      result[#result + 1] = node
    end
  end
  table.sort(result, function(a, b)
    if a.stackIndex == b.stackIndex then
      return a.id < b.id
    end
    return a.stackIndex < b.stackIndex
  end)
  return result
end

local function getPanelDimensions()
  local live = activeNodes()
  if #live > 0 then
    return live[1].panelWidth or common.DEFAULT_PANEL_WIDTH, live[1].panelHeight or common.DEFAULT_PANEL_HEIGHT
  end
  return common.DEFAULT_PANEL_WIDTH, common.DEFAULT_PANEL_HEIGHT
end

local function ensureAssignments()
  local live = activeNodes()
  local used = {}
  local maxIndex = math.max(1, #live)

  -- Preserve node-provided stack indices when unique. Resolve only collisions.
  for _, node in ipairs(live) do
    local target = math.max(1, math.floor(node.stackIndex or 1))
    if target > maxIndex or used[target] then
      local fallback = 1
      while fallback <= maxIndex and used[fallback] do
        fallback = fallback + 1
      end
      target = fallback
    end

    used[target] = true
    if node.stackIndex ~= target then
      node.stackIndex = target
      rednet.send(node.id, {
        kind = "assign",
        stackIndex = target,
      }, common.PROTOCOL)
    end
  end
end

local function discover()
  rednet.broadcast({ kind = "discover" }, common.PROTOCOL)
end

local function frameInterval(nodeCount, demoKey)
  local interval = MIN_FRAME_SECONDS + (math.max(nodeCount, 1) - 1) * 0.01
  if demoKey == "ripple" then
    interval = interval + 0.01
  end
  if demoKey == "life" then
    interval = interval + 0.02
  end
  if interval > MAX_FRAME_SECONDS then
    interval = MAX_FRAME_SECONDS
  end
  return interval
end

local demos = {}

local function makeBuffer(width, height)
  local buf = {}
  for y = 1, height do
    buf[y] = {}
    for x = 1, width do
      buf[y][x] = {
        text = " ",
        fg = colors.white,
        bg = colors.black,
      }
    end
  end
  return buf
end

local function bufferToRows(buf, width, height)
  local rows = {}
  for y = 1, height do
    local textRow = {}
    local fgRow = {}
    local bgRow = {}
    for x = 1, width do
      local cell = buf[y][x]
      textRow[x] = cell.text
      fgRow[x] = blitOfColor(cell.fg)
      bgRow[x] = blitOfColor(cell.bg)
    end
    rows[y] = {
      text = table.concat(textRow),
      fg = table.concat(fgRow),
      bg = table.concat(bgRow),
    }
  end
  return rows
end

local ripplePalette = {
  colors.black,
  colors.gray,
  colors.lightBlue,
  colors.cyan,
  colors.blue,
  colors.purple,
  colors.blue,
  colors.cyan,
  colors.lightBlue,
}

local function reflectedDistance(x, y, sx, sy, w, h)
  local mirrorX = (2 * w - sx + 1)
  local mirrorY = (2 * h - sy + 1)
  local dxA = math.abs(x - sx)
  local dxB = math.abs(x - mirrorX)
  local dyA = math.abs(y - sy)
  local dyB = math.abs(y - mirrorY)
  local dx = math.min(dxA, dxB)
  local dy = math.min(dyA, dyB)
  return math.sqrt(dx * dx + dy * dy)
end

demos.ripple = {
  name = "Ripple",
  state = { sources = {} },
  onTouch = function(self, x, y, _w, _h)
    if #self.state.sources >= MAX_RIPPLE_SOURCES then
      table.remove(self.state.sources, 1)
    end
    self.state.sources[#self.state.sources + 1] = {
      x = x,
      y = y,
      t0 = now(),
      amp = 1.25,
      vel = 1.0,
    }
  end,
  update = function(self, _dt, _w, _h)
    local t = now()
    local keep = {}
    for _, s in ipairs(self.state.sources) do
      if (t - s.t0) < RIPPLE_MAX_AGE then
        keep[#keep + 1] = s
      end
    end
    self.state.sources = keep
  end,
  render = function(self, buf, w, h)
    local t = now()
    for y = 1, h do
      for x = 1, w do
        local v = 0.08
        for _, s in ipairs(self.state.sources) do
          local age = t - s.t0
          local d = reflectedDistance(x, y, s.x, s.y, w, h)
          local wave = math.sin(d * 1.12 - age * 5.2)
          local decay = math.exp(-d * 0.08) * math.exp(-age * 0.22)
          v = v + wave * decay * s.amp
        end
        local cell = buf[y][x]
        local normalized = clamp((v + 1.15) / 2.3, 0, 1)
        cell.bg = chooseColor(normalized, ripplePalette)
        cell.fg = colors.white
        cell.text = " "
      end
    end
  end,
}

local lifePaletteAlive = {
  colors.black,
  colors.green,
  colors.lime,
}

local function blankLifeGrid(w, h)
  local g = {}
  for y = 1, h do
    g[y] = {}
    for x = 1, w do
      g[y][x] = math.random() < 0.24
    end
  end
  return g
end

local function lifeCount(grid, w, h, x, y)
  local count = 0
  for dy = -1, 1 do
    for dx = -1, 1 do
      if not (dx == 0 and dy == 0) then
        local nx = x + dx
        local ny = y + dy
        if nx >= 1 and nx <= w and ny >= 1 and ny <= h and grid[ny][nx] then
          count = count + 1
        end
      end
    end
  end
  return count
end

demos.life = {
  name = "Game Of Life",
  state = { grid = nil, accum = 0 },
  onTouch = function(self, x, y, w, h)
    if not self.state.grid or #self.state.grid ~= h then
      self.state.grid = blankLifeGrid(w, h)
    end
    self.state.grid[y][x] = not self.state.grid[y][x]
  end,
  update = function(self, dt, w, h)
    if not self.state.grid or #self.state.grid ~= h then
      self.state.grid = blankLifeGrid(w, h)
      self.state.accum = 0
    end

    self.state.accum = self.state.accum + dt
    if self.state.accum < 0.22 then
      return
    end
    self.state.accum = 0

    local old = self.state.grid
    local new = {}
    for y = 1, h do
      new[y] = {}
      for x = 1, w do
        local n = lifeCount(old, w, h, x, y)
        local alive = old[y][x]
        if alive then
          new[y][x] = (n == 2 or n == 3)
        else
          new[y][x] = (n == 3)
        end
      end
    end

    self.state.grid = new
  end,
  render = function(self, buf, w, h)
    local g = self.state.grid
    if not g then return end

    for y = 1, h do
      for x = 1, w do
        local cell = buf[y][x]
        if g[y][x] then
          local shade = ((x + y + math.floor(now() * 8)) % #lifePaletteAlive) + 1
          cell.bg = lifePaletteAlive[shade]
          cell.fg = colors.white
          cell.text = " "
        else
          cell.bg = colors.black
          cell.fg = colors.gray
          cell.text = " "
        end
      end
    end
  end,
}

local plasmaPalette = {
  colors.black,
  colors.blue,
  colors.lightBlue,
  colors.cyan,
  colors.green,
  colors.lime,
  colors.yellow,
  colors.orange,
  colors.red,
}

demos.plasma = {
  name = "Plasma",
  state = {},
  onTouch = function(_self, _x, _y, _w, _h)
  end,
  update = function(_self, _dt, _w, _h)
  end,
  render = function(_self, buf, w, h)
    local t = now()
    for y = 1, h do
      for x = 1, w do
        local v = math.sin((x * 0.35) + t)
          + math.sin((y * 0.22) - t * 1.2)
          + math.sin(((x + y) * 0.18) + t * 0.65)
        local normalized = (v + 3) / 6
        local cell = buf[y][x]
        cell.bg = chooseColor(normalized, plasmaPalette)
        cell.fg = colors.white
        cell.text = " "
      end
    end
  end,
}

local linePalette = {
  colors.black,
  colors.gray,
  colors.lightGray,
  colors.white,
  colors.lightBlue,
  colors.cyan,
}

demos.line = {
  name = "Bottom To Top Line",
  state = { y = 1, frac = 0 },
  onTouch = function(_self, _x, _y, _w, _h)
  end,
  update = function(self, dt, _w, h)
    local speed = math.max(1, h / 3)
    self.state.frac = self.state.frac + (dt * speed)

    while self.state.frac >= 1 do
      self.state.frac = self.state.frac - 1
      self.state.y = self.state.y - 1
      if self.state.y < 1 then
        self.state.y = h
      end
    end

    if self.state.y > h then
      self.state.y = h
    end
  end,
  render = function(self, buf, w, h)
    local y = self.state.y
    if y < 1 or y > h then
      y = h
      self.state.y = y
    end

    for row = 1, h do
      local distance = math.abs(row - y)
      local colorIndex = math.min(distance + 1, #linePalette)
      local bg = linePalette[colorIndex]

      for x = 1, w do
        local cell = buf[row][x]
        cell.bg = bg
        cell.fg = colors.white
        cell.text = " "
      end
    end
  end,
}

local demoOrder = { "line", "ripple", "life", "plasma" }
local currentDemo = 1

local function renderStatus()
  term.setBackgroundColor(colors.black)
  term.clear()
  term.setCursorPos(1, 1)
  term.setTextColor(colors.cyan)
  print("CC Floor System - Main Controller")
  term.setTextColor(colors.lightGray)
  local live = activeNodes()
  local panelWidth, panelHeight = getPanelDimensions()
  print("Nodes online: " .. tostring(#live) .. " / " .. tostring(common.MAX_NODES))
  print("Panel chars per side: " .. tostring(panelWidth) .. " x " .. tostring(panelHeight))
  print("Canvas chars: " .. tostring(common.totalWidth(panelWidth)) .. " x " .. tostring(common.totalHeight(panelHeight, #live)))
  print("")
  print("Demos (press key):")
  for i, key in ipairs(demoOrder) do
    local marker = (i == currentDemo) and ">" or " "
    print(marker .. " " .. tostring(i) .. ") " .. demos[key].name)
  end
  print("")
  print("Keys: 1.." .. tostring(#demoOrder) .. " switch demo, R rediscover")
  print("Stack convention: 1 = bottom, higher numbers go upward")
end

local function splitRowsForNode(globalRows, stackIndex, panelWidth, panelHeight, liveCount)
  local rowsBySlot = {}
  for slot = 1, common.MONITORS_PER_NODE do
    rowsBySlot[slot] = {}
    local x0 = (slot - 1) * panelWidth + 1
    local x1 = x0 + panelWidth - 1

    for localY = 1, panelHeight do
      local gy = (liveCount - stackIndex) * panelHeight + localY
      local row = globalRows[gy]

      rowsBySlot[slot][localY] = {
        text = row.text:sub(x0, x1),
        fg = row.fg:sub(x0, x1),
        bg = row.bg:sub(x0, x1),
      }
    end
  end

  return rowsBySlot
end

local function broadcastFrame(globalRows)
  local live = activeNodes()
  local liveCount = #live
  for _, node in ipairs(live) do
    local panelWidth = node.panelWidth or common.DEFAULT_PANEL_WIDTH
    local panelHeight = node.panelHeight or common.DEFAULT_PANEL_HEIGHT
    rednet.send(node.id, {
      kind = "frame",
      rowsBySlot = splitRowsForNode(globalRows, node.stackIndex, panelWidth, panelHeight, liveCount),
    }, common.PROTOCOL)
  end
end

local function broadcastRippleState(live, panelWidth, panelHeight, sources)
  local liveCount = #live
  local payload = {
    kind = "ripple_state",
    liveCount = liveCount,
    panelWidth = panelWidth,
    panelHeight = panelHeight,
    canvasWidth = common.totalWidth(panelWidth),
    canvasHeight = common.totalHeight(panelHeight, liveCount),
    maxAge = RIPPLE_MAX_AGE,
    maxSources = MAX_RIPPLE_SOURCES,
    waveSpeed = RIPPLE_WAVE_SPEED,
    damping = RIPPLE_DAMPING,
    pulseWidth = RIPPLE_PULSE_WIDTH,
    freq = RIPPLE_FREQ,
    trailDamping = RIPPLE_TRAIL_DAMPING,
    impactDecay = RIPPLE_IMPACT_DECAY,
    impactStrength = RIPPLE_IMPACT_STRENGTH,
    pixelScale = RIPPLE_PIXEL_SCALE,
    sources = sources,
  }

  for _, node in ipairs(live) do
    rednet.send(node.id, payload, common.PROTOCOL)
  end
end

local function getRippleSourcesForBroadcast()
  local state = demos.ripple.state
  local t = now()
  local out = {}
  for i = 1, #state.sources do
    local s = state.sources[i]
    local age = t - s.t0
    if age < RIPPLE_MAX_AGE then
      out[#out + 1] = {
        x = s.x,
        y = s.y,
        age = age,
        amp = s.amp,
        vel = s.vel,
      }
    end
  end
  return out
end

local lastRippleBroadcastCount = -1

local function handleNodeMessage(sender, msg)
  if type(msg) ~= "table" then
    return
  end

  if msg.kind == "hello" then
    nodes[sender] = nodes[sender] or { id = sender }
    local n = nodes[sender]
    n.id = sender
    n.label = msg.label
    n.hostname = msg.hostname
    n.stackIndex = math.max(1, math.floor(msg.stackIndex or 1))
    n.panelWidth = math.max(1, math.floor(msg.panelWidth or common.DEFAULT_PANEL_WIDTH))
    n.panelHeight = math.max(1, math.floor(msg.panelHeight or common.DEFAULT_PANEL_HEIGHT))
    n.lastSeen = now()
    ensureAssignments()
  elseif msg.kind == "heartbeat" then
    if nodes[sender] then
      nodes[sender].lastSeen = now()
    end
  elseif msg.kind == "touch" then
    if nodes[sender] then
      nodes[sender].lastSeen = now()
    end

    local liveCount = #activeNodes()
    local panelWidth, panelHeight = getPanelDimensions()
    local w = common.totalWidth(panelWidth)
    local h = common.totalHeight(panelHeight, liveCount)

    local slot = math.max(1, math.floor(msg.slot or 1))
    local localX = math.max(1, math.floor(msg.x or 1))
    local localY = math.max(1, math.floor(msg.y or 1))
    local x = (slot - 1) * panelWidth + localX
    local y = (liveCount - nodes[sender].stackIndex) * panelHeight + localY

    if type(x) == "number" and type(y) == "number" and x >= 1 and x <= w and y >= 1 and y <= h then
      local demo = demos[demoOrder[currentDemo]]
      demo.onTouch(demo, x, y, w, h)
    end
  end
end

math.randomseed(os.epoch("utc"))
renderStatus()
discover()

local tickTimer = os.startTimer(frameInterval(#activeNodes(), demoOrder[currentDemo]))
local discoverTimer = os.startTimer(DISCOVER_SECONDS)
local statusTimer = os.startTimer(1)
local lastFrameTime = now()

while true do
  local event, p1, p2, p3 = os.pullEvent()

  if event == "timer" and p1 == tickTimer then
    ensureAssignments()

    local live = activeNodes()
    local liveCount = #live
    local panelWidth, panelHeight = getPanelDimensions()
    local w = common.totalWidth(panelWidth)
    local h = common.totalHeight(panelHeight, liveCount)

    local frameNow = now()
    local dt = frameNow - lastFrameTime
    lastFrameTime = frameNow

    local demoKey = demoOrder[currentDemo]
    local demo = demos[demoKey]
    demo.update(demo, dt, w, h)

    if demoKey == "ripple" then
      local sources = getRippleSourcesForBroadcast()
      if #sources > 0 or lastRippleBroadcastCount ~= 0 then
        broadcastRippleState(live, panelWidth, panelHeight, sources)
        lastRippleBroadcastCount = #sources
      end
    else
      lastRippleBroadcastCount = -1
      local buf = makeBuffer(w, h)
      demo.render(demo, buf, w, h)
      local rows = bufferToRows(buf, w, h)
      broadcastFrame(rows)
    end

    tickTimer = os.startTimer(frameInterval(liveCount, demoKey))
  elseif event == "timer" and p1 == discoverTimer then
    discover()
    discoverTimer = os.startTimer(DISCOVER_SECONDS)
  elseif event == "timer" and p1 == statusTimer then
    renderStatus()
    statusTimer = os.startTimer(1)
  elseif event == "rednet_message" then
    local sender = p1
    local msg = p2
    local protocol = p3
    if protocol == common.PROTOCOL then
      handleNodeMessage(sender, msg)
    end
  elseif event == "char" then
    if p1 == "r" or p1 == "R" then
      discover()
    else
      local n = tonumber(p1)
      if n and n >= 1 and n <= #demoOrder then
        currentDemo = n
      end
    end
  end
end
