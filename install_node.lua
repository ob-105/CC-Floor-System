local OWNER = "ob-105"
local REPO = "CC-Floor-System"
local BRANCH = "main"

if not http then
  error("HTTP API is disabled. Enable it in ComputerCraft config.")
end

local function rawUrl(path)
  return string.format("https://raw.githubusercontent.com/%s/%s/%s/%s", OWNER, REPO, BRANCH, path)
end

local function download(path)
  local url = rawUrl(path)
  print("Downloading " .. path)
  local res = http.get(url)
  if not res then
    error("Failed to download: " .. path)
  end

  local content = res.readAll()
  res.close()

  local h = fs.open(path, "w")
  if not h then
    error("Failed to write: " .. path)
  end
  h.write(content)
  h.close()
end

local function writeStartup()
  local h = fs.open("startup", "w")
  h.writeLine("shell.run(\"node.lua\")")
  h.close()
end

local function askNumber(prompt, default)
  while true do
    write(prompt)
    local s = read()
    if s == "" then
      return default
    end
    local n = tonumber(s)
    if n and n >= 1 and n <= 20 then
      return math.floor(n)
    end
    print("Enter a number from 1 to 20.")
  end
end

local function detectMonitors()
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

local function writeConfig(stackIndex, monitorSides)
  local label = os.getComputerLabel()
  local config = {
    modemSide = "bottom",
    stackIndex = stackIndex,
    nodeName = label and ("node-" .. label) or nil,
    monitorSides = monitorSides,
  }

  local h = fs.open("node_config.lua", "w")
  h.write("return " .. textutils.serialize(config))
  h.close()
end

print("CC Floor System - Node Installer")
print("This computer should have:")
print("- access to at least 4 advanced monitors")
print("- 1 wired modem on bottom")
print("")

local stackIndex = askNumber("Stack index for this node [1]: ", 1)
local monitors = detectMonitors()
if #monitors < 4 then
  error("Found " .. tostring(#monitors) .. " monitor peripherals. Need at least 4.")
end

local monitorSides = {
  front = monitors[1],
  left = monitors[2],
  back = monitors[3],
  right = monitors[4],
}

print("Using monitor mapping:")
print("front -> " .. monitorSides.front)
print("left  -> " .. monitorSides.left)
print("back  -> " .. monitorSides.back)
print("right -> " .. monitorSides.right)

download("common.lua")
download("node.lua")
writeConfig(stackIndex, monitorSides)
writeStartup()

print("")
print("Install complete.")
print("Autostart is enabled via /startup.")
print("Reboot or run: shell.run(\"node.lua\")")
