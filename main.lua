local common = require("common")

local MODEM_SIDE = "bottom"
local FRAME_SECONDS = 0.08
local DISCOVER_SECONDS = 2.0
local NODE_TIMEOUT_SECONDS = 8.0

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
  for i, node in ipairs(live) do
    local target = i
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

local function reflectedPositions(pos, size)
  local list = {}
  local period = size * 2
  for k = -1, 1 do
    local base = pos + k * period
    list[#list + 1] = base
    list[#list + 1] = (period - pos + 1) + k * period
  end
  return list
end

local function reflectedDistance(x, y, sx, sy, w, h)
  local minD = 1e9
  local xs = reflectedPositions(sx, w)
  local ys = reflectedPositions(sy, h)

  for _, ix in ipairs(xs) do
    for _, iy in ipairs(ys) do
      local dx = x - ix
      local dy = y - iy
      local d = math.sqrt(dx * dx + dy * dy)
      if d < minD then
        minD = d
      end
    end
  end

  return minD
end

demos.ripple = {
  name = "Ripple",
  state = { sources = {} },
  onTouch = function(self, x, y, _w, _h)
    self.state.sources[#self.state.sources + 1] = {
      x = x,
      y = y,
      t0 = now(),
      amp = 1.0,
    }
  end,
  update = function(self, _dt, _w, _h)
    local t = now()
    local keep = {}
    for _, s in ipairs(self.state.sources) do
      if (t - s.t0) < 7 then
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

local demoOrder = { "ripple", "life", "plasma" }
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
end

local function splitRowsForNode(globalRows, stackIndex, panelWidth, panelHeight)
  local rowsBySlot = {}
  for slot = 1, common.MONITORS_PER_NODE do
    rowsBySlot[slot] = {}
    local x0 = (slot - 1) * panelWidth + 1
    local x1 = x0 + panelWidth - 1

    for localY = 1, panelHeight do
      local gy = (stackIndex - 1) * panelHeight + localY
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
  for _, node in ipairs(activeNodes()) do
    local panelWidth = node.panelWidth or common.DEFAULT_PANEL_WIDTH
    local panelHeight = node.panelHeight or common.DEFAULT_PANEL_HEIGHT
    rednet.send(node.id, {
      kind = "frame",
      rowsBySlot = splitRowsForNode(globalRows, node.stackIndex, panelWidth, panelHeight),
    }, common.PROTOCOL)
  end
end

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

    local x = msg.gx
    local y = msg.gy
    local liveCount = #activeNodes()
    local panelWidth, panelHeight = getPanelDimensions()
    local w = common.totalWidth(panelWidth)
    local h = common.totalHeight(panelHeight, liveCount)
    if type(x) == "number" and type(y) == "number" and x >= 1 and x <= w and y >= 1 and y <= h then
      local demo = demos[demoOrder[currentDemo]]
      demo.onTouch(demo, x, y, w, h)
    end
  end
end

math.randomseed(os.epoch("utc"))
renderStatus()
discover()

local tickTimer = os.startTimer(FRAME_SECONDS)
local discoverTimer = os.startTimer(DISCOVER_SECONDS)
local statusTimer = os.startTimer(1)
local lastFrameTime = now()

while true do
  local event, p1, p2, p3 = os.pullEvent()

  if event == "timer" and p1 == tickTimer then
    ensureAssignments()

    local liveCount = #activeNodes()
    local panelWidth, panelHeight = getPanelDimensions()
    local w = common.totalWidth(panelWidth)
    local h = common.totalHeight(panelHeight, liveCount)

    local frameNow = now()
    local dt = frameNow - lastFrameTime
    lastFrameTime = frameNow

    local buf = makeBuffer(w, h)
    local demo = demos[demoOrder[currentDemo]]
    demo.update(demo, dt, w, h)
    demo.render(demo, buf, w, h)

    local rows = bufferToRows(buf, w, h)
    broadcastFrame(rows)

    tickTimer = os.startTimer(FRAME_SECONDS)
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
