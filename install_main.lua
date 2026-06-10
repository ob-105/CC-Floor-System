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
  h.write([[
local OWNER = "ob-105"
local REPO = "CC-Floor-System"
local BRANCH = "main"

local function rawUrl(path)
  return string.format("https://raw.githubusercontent.com/%s/%s/%s/%s", OWNER, REPO, BRANCH, path)
end

local function downloadIfPossible(path)
  if not http then
    return false
  end

  local res = http.get(rawUrl(path))
  if not res then
    return false
  end

  local content = res.readAll()
  res.close()

  local out = fs.open(path, "w")
  if not out then
    return false
  end
  out.write(content)
  out.close()
  return true
end

downloadIfPossible("common.lua")
downloadIfPossible("main.lua")

if fs.exists("main.lua") then
  shell.run("main.lua")
else
  print("main.lua missing. Run install_main.lua again.")
end
]])
  h.close()
end

print("CC Floor System - Main Installer")
print("This computer should have a wired modem on bottom.")
print("")

download("common.lua")
download("main.lua")
writeStartup()

print("")
print("Install complete.")
print("Autostart is enabled via /startup.")
print("Reboot or run: shell.run(\"main.lua\")")
