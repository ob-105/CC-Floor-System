-- Shared constants and helper utilities for CC-Floor-System.
local common = {}

common.PROTOCOL = "cc_floor_system_v1"
common.DEFAULT_PANEL_WIDTH = 6
common.DEFAULT_PANEL_HEIGHT = 7
-- Backwards compatibility for older scripts that still reference these names.
common.MONITOR_WIDTH = common.DEFAULT_PANEL_WIDTH
common.MONITOR_HEIGHT = common.DEFAULT_PANEL_HEIGHT
common.MONITORS_PER_NODE = 1
common.MAX_NODES = 20

common.MONITOR_SIDES = {
  "top",
}

function common.totalWidth(panelWidth)
  -- Support both old signature totalWidth() and current totalWidth(panelWidth).
  local w = tonumber(panelWidth) or common.DEFAULT_PANEL_WIDTH
  return w * common.MONITORS_PER_NODE
end

function common.totalHeight(panelHeight, nodeCount)
  -- Support both old signature totalHeight(nodeCount) and
  -- current totalHeight(panelHeight, nodeCount).
  local h = tonumber(panelHeight) or common.DEFAULT_PANEL_HEIGHT
  local count = tonumber(nodeCount)
  if count == nil then
    count = tonumber(panelHeight) or 1
    h = common.DEFAULT_PANEL_HEIGHT
  end
  return h * math.max(count, 1)
end

function common.defaultNodeConfig()
  return {
    modemSide = "bottom",
    stackIndex = 1,
    nodeName = nil,
    monitorSides = {
      top = "top",
    },
  }
end

function common.clamp(v, lo, hi)
  if v < lo then
    return lo
  end
  if v > hi then
    return hi
  end
  return v
end

function common.sideToSlot(side)
  for i, v in ipairs(common.MONITOR_SIDES) do
    if v == side then
      return i
    end
  end
  return nil
end

function common.slotToSide(slot)
  return common.MONITOR_SIDES[slot]
end

function common.localToGlobal(slot, localX, localY, stackIndex, panelWidth, panelHeight)
  local w = tonumber(panelWidth) or common.DEFAULT_PANEL_WIDTH
  local h = tonumber(panelHeight) or common.DEFAULT_PANEL_HEIGHT
  local gx = (slot - 1) * w + localX
  local gy = (stackIndex - 1) * h + localY
  return gx, gy
end

function common.globalToLocal(gx, gy, stackIndex, panelWidth, panelHeight)
  local w = tonumber(panelWidth) or common.DEFAULT_PANEL_WIDTH
  local h = tonumber(panelHeight) or common.DEFAULT_PANEL_HEIGHT
  local startY = (stackIndex - 1) * h + 1
  local endY = startY + h - 1
  if gy < startY or gy > endY then
    return nil
  end

  local slot = math.floor((gx - 1) / w) + 1
  if slot < 1 or slot > common.MONITORS_PER_NODE then
    return nil
  end

  local localX = gx - (slot - 1) * w
  local localY = gy - (stackIndex - 1) * h
  return slot, localX, localY
end

function common.makeBlankRows(width, height, ch, fg, bg)
  local rows = {}
  local charRow = string.rep(ch or " ", width)
  local fgRow = string.rep(fg or "0", width)
  local bgRow = string.rep(bg or "f", width)

  for y = 1, height do
    rows[y] = {
      text = charRow,
      fg = fgRow,
      bg = bgRow,
    }
  end

  return rows
end

return common
