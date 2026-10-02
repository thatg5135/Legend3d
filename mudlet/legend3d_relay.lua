-- Legend3D relay for Mudlet
-- Bridges Mudlet <-> the Legend3D view over a local HTTP link.
--
--   Mudlet -> view : POST /hello   (handshake + current state snapshot)
--                    POST /events  (ordered batch: room, time, media, lines)
--   view -> Mudlet : GET  /commands?s=<session>  (long poll; returns a JSON
--                    list of commands, run through your aliases, or quiet
--                    checks like "equipment" whose output is hidden from you)
--
-- Commands in Mudlet:
--   3d            show link status
--   3d on / off   turn the relay on or off
--
-- Your other scripts are untouched. Commands from the view go through
-- expandAlias(), exactly as if you typed them, so aliases and the mapper's
-- safety checks still apply.

Legend3D = Legend3D or {}
local L = Legend3D

L.VERSION = "0.4.0"
L.config = L.config or {
  host = "127.0.0.1",
  port = 7359,
  flushDelay = 0.05, -- seconds to gather events before sending a batch
  retryDelay = 2,    -- seconds between reconnect attempts
  timeEvery = 240,   -- seconds between quiet "time" checks (moon, date)
  weatherEvery = 120,-- seconds between quiet "weather" checks
  promptPattern = "^><", -- how Legend's prompt line starts (for hiding it)
}

----------------------------------------------------------------------
-- Tear down anything left over from a previous load (safe to reload)
----------------------------------------------------------------------
if L.handlers then
  for _, id in ipairs(L.handlers) do killAnonymousEventHandler(id) end
end
if L.lineTrigger then killTrigger(L.lineTrigger) end
if L.alias then killAlias(L.alias) end
if L.retryTimer then killTimer(L.retryTimer) end
if L.flushTimer then killTimer(L.flushTimer) end
if L.quietTimer then killTimer(L.quietTimer) end

L.handlers = {}
L.lineTrigger, L.alias, L.retryTimer, L.flushTimer = nil, nil, nil, nil
L.quietTimer = nil
L.quiet = nil          -- the background check in progress
L.gagPrompt = false    -- hide the prompt that follows a background check
L.lastQuiet = L.lastQuiet or { time = 0, weather = 0 }
if L.enabled == nil then L.enabled = true end
L.connected = false
L.helloInFlight = false
L.posting = false
L.polling = false
L.queue = {}
L.seq = L.seq or 0
L.session = nil

local function base()
  return string.format("http://%s:%d", L.config.host, L.config.port)
end
local JSON_HEADERS = { ["Content-Type"] = "application/json" }
local function toJSON(t) return yajl.to_string(t) end
local function fromJSON(s) return yajl.to_value(s) end

local function say(msg)
  cecho("<cyan>[Legend3D]<reset> " .. msg .. "\n")
end

local function nextSeq()
  L.seq = L.seq + 1
  return L.seq
end

-- Look up gmcp data whether the server sent lowercase or Capitalized names.
local function gmcpGet(a, b)
  if not gmcp then return nil end
  local t = gmcp[a] or gmcp[a:sub(1, 1):upper() .. a:sub(2)]
  if type(t) ~= "table" then return nil end
  return t[b] or t[b:sub(1, 1):upper() .. b:sub(2)]
end

local function currentRoom() return gmcpGet("room", "info") end

local function currentGameTime()
  local p = gmcpGet("char", "prompt")
  return p and p.t or nil
end

-- Legend's prompt data says who you're fighting ("no one" when nobody).
local function currentFighting()
  local p = gmcpGet("char", "prompt")
  local f = p and p.f
  return type(f) == "string" and f ~= "" and f:lower() ~= "no one"
end

-- The ambient loop playing right now, even if it started before we loaded.
local function currentAmbient()
  if L.lastAmbient then return L.lastAmbient end
  local m = gmcpGet("client", "media")
  local play, stop = m and (m.play or m.Play), m and (m.stop or m.Stop)
  if type(play) == "table" and (play.source == "ambient" or play.tag == "ambient")
    and not (type(stop) == "table" and stop.key == play.key) then
    return play
  end
  return nil
end

-- Health, mana and moves: lowercase is current, uppercase is the maximum.
local function currentVitals()
  local p = gmcpGet("char", "prompt")
  if type(p) ~= "table" then return nil end
  local function num(k) return tonumber(p[k]) end
  local v = { h = num("h"), H = num("H"), m = num("m"), M = num("M"), v = num("v"), V = num("V") }
  if not (v.h or v.m or v.v) then return nil end
  return v
end

-- Walk gmcp by a dotted package name ("char.items.update"), either case.
local function gmcpPath(pkg)
  local t = gmcp
  for part in tostring(pkg):gmatch("[^%.]+") do
    if type(t) ~= "table" then return nil end
    t = t[part] or t[part:lower()] or t[part:sub(1, 1):upper() .. part:sub(2)]
  end
  return t
end

local function snapshot()
  return {
    client = "mudlet",
    version = L.VERSION,
    session = L.session,
    room = currentRoom(),
    time = { game = currentGameTime() },
    status = { fighting = currentFighting() },
    vitals = currentVitals(),
    inventory = gmcpPath("char.inventory"),
    ambient = currentAmbient(),
  }
end

----------------------------------------------------------------------
-- Outgoing events (one ordered queue, sent in batches)
----------------------------------------------------------------------
function L.flush()
  if L.posting or not L.connected or #L.queue == 0 then return end
  local batch = L.queue
  L.queue = {}
  L.posting = true
  postHTTP(toJSON(batch), base() .. "/events", JSON_HEADERS)
end

local function scheduleFlush()
  if L.flushTimer or L.posting then return end
  L.flushTimer = tempTimer(L.config.flushDelay, function()
    L.flushTimer = nil
    L.flush()
  end)
end

function L.push(evType, data)
  if not (L.enabled and L.connected) then return end
  L.queue[#L.queue + 1] = { seq = nextSeq(), type = evType, data = data }
  scheduleFlush()
end

----------------------------------------------------------------------
-- Connection handling
----------------------------------------------------------------------
local function scheduleRetry()
  if not L.enabled or L.retryTimer then return end
  L.retryTimer = tempTimer(L.config.retryDelay, function()
    L.retryTimer = nil
    L.sayHello()
  end)
end

function L.sayHello()
  if not L.enabled or L.connected or L.helloInFlight then return end
  L.session = tostring(os.time()) .. "-" .. tostring(math.random(100000, 999999))
  L.helloInFlight = true
  local mySession = L.session
  -- Safety net: if Mudlet never reports back on this handshake, try again.
  tempTimer(5, function()
    if L.helloInFlight and L.session == mySession and not L.connected then
      L.helloInFlight = false
      scheduleRetry()
    end
  end)
  local hello = { seq = nextSeq(), type = "hello", data = snapshot() }
  postHTTP(toJSON(hello), base() .. "/hello", JSON_HEADERS)
end

local function disconnect(reason)
  local wasConnected = L.connected
  L.connected = false
  L.posting = false
  L.polling = false
  L.queue = {}
  L.session = nil
  if wasConnected then say("link lost (" .. tostring(reason) .. "), retrying quietly") end
  scheduleRetry()
end

function L.startPoll()
  if L.polling or not L.connected then return end
  L.polling = true
  getHTTP(base() .. "/commands?s=" .. L.session)
end

local function isOurs(url, path)
  return type(url) == "string"
    and url:find(base() .. path, 1, true) == 1
end

-- Mudlet's HTTP events don't all pass their arguments in the same order,
-- so pick out our URL wherever it is; the other string is the body/error.
local function splitArgs(...)
  local args = { ... }
  local url, other
  for i = 1, select("#", ...) do
    local a = args[i]
    if type(a) == "string" then
      if not url and a:find(base(), 1, true) == 1 then
        url = a
      elseif not other then
        other = a
      end
    end
  end
  return url, other
end

local function runCommand(c)
  if type(c) ~= "table" then return end
  if c.kind == "resync" then
    L.push("snapshot", snapshot())
    return
  end
  if c.kind == "quiet" and type(c.cmd) == "string" then
    L.quietRequest(c.cmd:gsub("[\r\n]", ""))
    return
  end
  local cmd = c.cmd
  if type(cmd) ~= "string" then return end
  cmd = cmd:gsub("[\r\n]", "")
  if cmd == "" then return end
  expandAlias(cmd, true)
end

----------------------------------------------------------------------
-- HTTP result handlers
----------------------------------------------------------------------
local function onPostDone(_, ...)
  local url = splitArgs(...)
  if isOurs(url, "/hello") then
    L.helloInFlight = false
    if L.enabled and not L.connected then
      L.connected = true
      say("linked to the 3D view")
      L.startPoll()
      L.lastQuiet = { time = 0, weather = os.time() - L.config.weatherEvery + 4 }
    end
  elseif isOurs(url, "/events") then
    L.posting = false
    if #L.queue > 0 then scheduleFlush() end
  end
end

local function onPostError(_, ...)
  local url, err = splitArgs(...)
  if isOurs(url, "/hello") then
    L.helloInFlight = false
    scheduleRetry()
  elseif isOurs(url, "/events") then
    disconnect(err)
  end
end

local function onGetDone(_, ...)
  local url, body = splitArgs(...)
  if not isOurs(url, "/commands") then return end
  -- Ignore replies to a poll from an older session.
  if not (L.session and url:find("s=" .. L.session, 1, true)) then return end
  L.polling = false
  if not (L.enabled and L.connected) then return end
  local ok, cmds = pcall(fromJSON, body or "")
  if ok and type(cmds) == "table" and #cmds > 0 then
    for _, c in ipairs(cmds) do runCommand(c) end
    L.startPoll()
  else
    -- Nothing to do: wait a moment before asking again, so a view that
    -- answers instantly can't make us spin.
    tempTimer(0.1, L.startPoll)
  end
end

local function onGetError(_, ...)
  local url, err = splitArgs(...)
  if not isOurs(url, "/commands") then return end
  if not (L.session and url:find("s=" .. L.session, 1, true)) then return end
  L.polling = false
  disconnect(err)
end

----------------------------------------------------------------------
-- What gets relayed
----------------------------------------------------------------------
local function onRoom()
  local r = currentRoom()
  if r then L.push("room", r) end
end

local function onPrompt()
  local t = currentGameTime()
  if t and t ~= L.lastGameTime then
    L.lastGameTime = t
    L.push("time", { game = t })
  end
  local vit = currentVitals()
  if vit then
    local key = string.format("%s/%s/%s/%s/%s/%s", tostring(vit.h), tostring(vit.H), tostring(vit.m),
      tostring(vit.M), tostring(vit.v), tostring(vit.V))
    if key ~= L.lastVitals then
      L.lastVitals = key
      L.push("vitals", vit)
    end
  end
  local fighting = currentFighting()
  if fighting ~= L.lastFighting then
    L.lastFighting = fighting
    L.push("status", { fighting = fighting })
  end
end

local function onMediaPlay()
  local m = gmcpGet("client", "media")
  local play = m and (m.play or m.Play)
  if type(play) ~= "table" then return end
  if play.source == "ambient" or play.tag == "ambient" then L.lastAmbient = play end
  L.push("media_play", play)
end

local function onMediaStop()
  local m = gmcpGet("client", "media")
  local stop = m and (m.stop or m.Stop)
  if type(stop) ~= "table" then return end
  if L.lastAmbient and stop.key == L.lastAmbient.key then L.lastAmbient = nil end
  L.push("media_stop", stop)
end

local function on(event, fn)
  L.handlers[#L.handlers + 1] = registerAnonymousEventHandler(event, fn)
end

-- Inventory and worn items as Legend sends them, passed on whole.
local function onCharData(event, pkg)
  local name = type(pkg) == "string" and pkg or tostring(event)
  name = name:gsub("^gmcp%.", "")
  local data = gmcpPath(name)
  if data ~= nil then L.push("gmcp", { pkg = name:lower(), data = data }) end
end

-- Legend sends lowercase package names; the Capitalized forms are a fallback.
for _, ev in ipairs({ "gmcp.room.info", "gmcp.Room.Info" }) do on(ev, onRoom) end
for _, ev in ipairs({ "gmcp.char.prompt", "gmcp.Char.Prompt" }) do on(ev, onPrompt) end
for _, ev in ipairs({ "gmcp.client.media.play", "gmcp.Client.Media.Play" }) do on(ev, onMediaPlay) end
for _, ev in ipairs({ "gmcp.client.media.stop", "gmcp.Client.Media.Stop" }) do on(ev, onMediaStop) end
for _, pkg in ipairs({ "char.inventory", "char.items", "char.items.list", "char.items.add",
    "char.items.remove", "char.items.update" }) do
  on("gmcp." .. pkg, onCharData)
  on("gmcp." .. pkg:gsub("(%a)([%w]*)", function(a, b) return a:upper() .. b end), onCharData)
end

on("sysPostHttpDone", onPostDone)
on("sysPostHttpError", onPostError)
on("sysGetHttpDone", onGetDone)
on("sysGetHttpError", onGetError)

-- Every line of MUD output, in order, so the view can find "X is here" lines.
----------------------------------------------------------------------
-- Quiet background checks: "time" (date, moon) and "weather".
-- Their output is hidden from the Mudlet window and passed to Legend3D.
----------------------------------------------------------------------
local function quietBusy()
  if L.quiet or not (L.enabled and L.connected) then return true end
  if L.lastFighting then return true end
  local ok, typed = pcall(getCmdLine)
  if ok and type(typed) == "string" and typed ~= "" then return true end
  return false
end

local function finishQuiet()
  local q = L.quiet
  L.quiet = nil
  if not q then return end
  L.gagPrompt = true
  L.lastQuiet[q.cmd] = os.time()
  if #q.lines > 0 or q.untilPrompt then L.push("quiet", { cmd = q.cmd, lines = q.lines }) end
  if #L.quietWanted > 0 then tempTimer(0.3, L.quietNext) end
end

-- Checks the view asks for (equipment, spells, score...), run one at a time.
L.quietWanted = L.quietWanted or {}
function L.quietRequest(cmd)
  if cmd == "" then return end
  for _, c in ipairs(L.quietWanted) do if c == cmd then return end end
  L.quietWanted[#L.quietWanted + 1] = cmd
  if not L.quiet then L.quietNext() end
end

function L.quietNext()
  if #L.quietWanted == 0 or quietBusy() then return end
  local cmd = table.remove(L.quietWanted, 1)
  L.quietCheck(cmd, true)
end

function L.quietCheck(cmd, untilPrompt)
  if quietBusy() then return false end
  L.quiet = { cmd = cmd, lines = {}, started = os.time(), untilPrompt = untilPrompt }
  send(cmd, false)
  -- never hold the window hostage: give up after 3 seconds
  local mine = L.quiet
  tempTimer(3, function()
    if L.quiet == mine then finishQuiet() end
  end)
  return true
end

local function quietTick()
  L.quietTimer = nil
  if L.enabled and L.connected and #L.quietWanted > 0 and not L.quiet then
    L.quietNext()
  elseif L.enabled and L.connected then
    local now = os.time()
    if now - (L.lastQuiet.time or 0) >= L.config.timeEvery then
      L.quietCheck("time")
    elseif now - (L.lastQuiet.weather or 0) >= L.config.weatherEvery then
      L.quietCheck("weather")
    end
  end
  L.quietTimer = tempTimer(5, quietTick)
end

-- Returns true if this line belongs to a background check (and hides it).
local function quietLine(text)
  local q = L.quiet
  if q then
    local isPromptLine = text:find(L.config.promptPattern) == 1
    if q.untilPrompt then
      -- everything up to the next prompt is the answer
      deleteLine()
      if isPromptLine then
        finishQuiet()
        L.gagPrompt = false
      else
        q.lines[#q.lines + 1] = text
      end
      return true
    end
    if q.cmd == "time" then
      -- everything from "It is ..." down to the dashed line
      if text:find("^%-%-%-%-%-%-%-%-%-%-") then
        deleteLine()
        finishQuiet()
        return true
      end
      if isPromptLine then
        deleteLine()
        finishQuiet()
        L.gagPrompt = false
        return true
      end
      if text ~= "" then q.lines[#q.lines + 1] = text end
      deleteLine()
      return true
    elseif q.cmd == "weather" then
      if text == "" then deleteLine() return true end
      if isPromptLine then
        deleteLine()
        finishQuiet()
        L.gagPrompt = false
        return true
      end
      -- the weather report is one sentence, sometimes wrapped onto a second line
      q.lines[#q.lines + 1] = text
      deleteLine()
      if text:find("[%.!]%s*$") then finishQuiet() end
      return true
    end
  end
  if L.gagPrompt then
    if text == "" or text:find(L.config.promptPattern) == 1 then
      deleteLine()
      if text ~= "" then L.gagPrompt = false end
      return true
    end
    L.gagPrompt = false
  end
  return false
end

L.lineTrigger = tempRegexTrigger("^", function()
  if quietLine(line) then return end
  L.push("line", { text = line, prompt = isPrompt() })
end)
L.quietTimer = tempTimer(5, quietTick)

----------------------------------------------------------------------
-- The 3d alias
----------------------------------------------------------------------
L.alias = tempAlias("^3d(?: (on|off|status))?$", function()
  local arg = matches[2]
  if arg == "on" then
    if L.enabled and L.connected then say("already linked") return end
    L.enabled = true
    L.helloInFlight = false
    if L.retryTimer then killTimer(L.retryTimer) L.retryTimer = nil end
    say("on, looking for the 3D view on port " .. L.config.port)
    L.sayHello()
  elseif arg == "off" then
    L.enabled = false
    if L.retryTimer then killTimer(L.retryTimer) L.retryTimer = nil end
    L.connected, L.polling, L.posting, L.queue, L.session = false, false, false, {}, nil
    say("off")
  else
    local state = not L.enabled and "off"
      or (L.connected and "linked" or "on, waiting for the 3D view")
    say(string.format("v%s, %s (port %d)", L.VERSION, state, L.config.port))
  end
end)

say("relay v" .. L.VERSION .. " loaded. Type 3d for status.")
if L.enabled then L.sayHello() end
