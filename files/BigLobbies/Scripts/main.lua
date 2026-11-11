-- Big Lobbies (Demonologist, UE4SS Lua mod, host side only). Based on "16-Player Lobbies" by YzzSlav (Nexus Mods, Demonologist mod 13).
--   * more than 4 players in the lobby and in the match (16 by default), with extra spawn points on the map
--   * the lobby stays visible in the server list (published as 2/4, "not started")
--   * higher loadout limits for Flashlight / Candle / Sanity Pills / Glass / Crucifix, extra copies stacked in the safe house
--   * the host can start without waiting for every "Ready"
--   * F4 pressed twice within 4 s leaves the match (only when the LateJoin mod is not installed: it has the same key)
--   * a small faded "16-player mod active" line in the bottom-right corner shows that the mod runs
-- Everything can be changed in settings.txt next to the Scripts folder. Nothing is written to disk; the log lines go to
-- ue4ss\UE4SS.log and start with [BigLobbies].
--
-- Performance note: FindAllOf scans every UObject and freezes the game for a moment, so nothing here polls it
-- every second. Work is done from hooks / "new object" notifications, with short bounded retries.
local MOD_VERSION = "1.6.0"
local BASE = "/Game/Furkan/BASE/"

---------------------------------------------------------------- log
-- An identical line repeated within 10 s is collapsed into "(xN)" to keep the log short.
local seenLines, seenCount = {}, 0
local function emit(line)
    print("[BigLobbies] " .. line .. "\n")
end
local function log(fmt, ...)
    local ok, msg = pcall(string.format, fmt, ...)
    if not ok then msg = tostring(fmt) end
    local now = os.time()
    local s = seenLines[msg]
    if s and now - s.t < 10 then s.n = s.n + 1 return end
    if s and s.n > 0 then emit(string.format("  ^ previous line repeated x%d", s.n)) end
    if seenCount > 300 then seenLines, seenCount = {}, 0 end
    if not s then seenCount = seenCount + 1 end
    seenLines[msg] = { t = now, n = 0 }
    emit(msg)
end
emit("==== script loaded v" .. MOD_VERSION .. " " .. os.date("%Y-%m-%d %H:%M:%S") .. " ====")

---------------------------------------------------------------- settings (settings.txt)
-- settings.txt sits in the mod folder (next to Scripts and enabled.txt): "name = value" lines, "#" starts a comment.
-- A missing file or a missing / invalid line keeps the default below. The names and values of the older French settings
-- file (reglages.txt: joueurs_max = 16, oui / non...) are understood too.
local CFG = {
    max_players = 16,                -- max players in the lobby and in the match
    extra_gear = true,               -- raised loadout limits below + extra copies in the safe house
    flashlight = 16, candle = 16, sanity_pills = 16, glass = 4, crucifix = 3,
    start_without_ready = true,      -- the host can press Start without waiting for every "Ready"
    lobby_shown_as_2_of_4 = true,    -- the lobby list shows 2/4 and "not started", so friends can still find and join it
    leave_key = "F4",                -- pressed twice within 4 s: leave the match ("none" = off)
    indicator = "ON",                -- small "mod active" line on screen: ON / ALWAYS / OFF
}
local CFG_ORDER = { "max_players", "extra_gear", "flashlight", "candle", "sanity_pills", "glass", "crucifix",
                    "start_without_ready", "lobby_shown_as_2_of_4", "leave_key", "indicator" }
local CFG_RANGE = { max_players = { 2, 32 }, flashlight = { 1, 32 }, candle = { 1, 32 }, sanity_pills = { 1, 32 }, glass = { 1, 32 }, crucifix = { 1, 32 } }
local CFG_ALIAS = { joueurs_max = "max_players", equipement_en_plus = "extra_gear", lampe_torche = "flashlight", bougie = "candle",
                    pilules = "sanity_pills", verre = "glass", lancer_sans_pret = "start_without_ready",
                    salon_affiche_2_sur_4 = "lobby_shown_as_2_of_4", touche_quitter = "leave_key", indicateur = "indicator" }
local MOD_DIR = (function()
    local ok, info = pcall(debug.getinfo, 1, "S")
    local src = (ok and info and info.source or ""):gsub("^@", "")
    return src:match("^(.*)[\\/]Scripts[\\/][^\\/]+$")
end)()
do
    -- (the relative paths are tried too: the working directory is Binaries\Win64, and io.open may not cope with a game
    -- folder whose name has accents)
    local f, used
    for _, name in ipairs({ "settings.txt", "reglages.txt" }) do
        for _, p in ipairs({ MOD_DIR and (MOD_DIR .. "\\" .. name) or "", "ue4ss\\Mods\\BigLobbies\\" .. name, "Mods\\BigLobbies\\" .. name }) do
            if p ~= "" then f = io.open(p, "r") if f then used = name break end end
        end
        if f then break end
    end
    local applied, bad = 0, {}
    if f then
        for raw in f:lines() do
            local line = raw:gsub("^\239\187\191", ""):gsub("[#;].*$", "")
            local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
            if k then
                k, v = k:lower(), v:lower()
                k = CFG_ALIAS[k] or k
                local def = CFG[k]
                if def == nil then
                    bad[#bad + 1] = k
                elseif type(def) == "boolean" then
                    if v == "yes" or v == "y" or v == "on" or v == "true" or v == "1" or v == "oui" or v == "o" then CFG[k] = true applied = applied + 1
                    elseif v == "no" or v == "n" or v == "off" or v == "false" or v == "0" or v == "non" then CFG[k] = false applied = applied + 1
                    else bad[#bad + 1] = k end
                elseif type(def) == "number" then
                    local n = tonumber(v)
                    if n then
                        local r = CFG_RANGE[k]
                        CFG[k] = math.floor(math.max(r[1], math.min(r[2], n)))
                        applied = applied + 1
                    else bad[#bad + 1] = k end
                else
                    CFG[k] = v:upper()
                    applied = applied + 1
                end
            end
        end
        f:close()
    end
    local IND = { ON = "ON", YES = "ON", Y = "ON", TRUE = "ON", ["1"] = "ON", OUI = "ON", O = "ON",
                  ALWAYS = "ALWAYS", TOUJOURS = "ALWAYS",
                  OFF = "OFF", NO = "OFF", N = "OFF", FALSE = "OFF", ["0"] = "OFF", NONE = "OFF", NON = "OFF", AUCUN = "OFF" }
    if IND[CFG.indicator] then CFG.indicator = IND[CFG.indicator] else bad[#bad + 1] = "indicator" CFG.indicator = "ON" end
    emit(string.format("settings: %s (%d value(s) read%s)", used or "defaults, no settings.txt", applied,
        #bad > 0 and ("; ignored: " .. table.concat(bad, ", ")) or ""))
    local parts = {}
    for _, k in ipairs(CFG_ORDER) do parts[#parts + 1] = k .. "=" .. tostring(CFG[k]) end
    emit("settings: " .. table.concat(parts, " "))
end
local TARGET = CFG.max_players

---------------------------------------------------------------- guarded entry points
-- Everything the game or UE4SS calls into our code - hooks, key binds, new-object callbacks, timers, delayed and game-thread
-- jobs - is wrapped here, once: a Lua error is caught and logged with the source line of the registration call, so it never
-- travels back into the engine.
local KEY_NAMES = {}
pcall(function() for name, value in pairs(Key) do KEY_NAMES[value] = name end end)
local getinfo = type(debug) == "table" and debug.getinfo or nil
local function callSite()                                          -- "main.lua:123": the first Lua frame above the wrapper
    if not getinfo then return "?" end
    for level = 3, 8 do
        local ok, info = pcall(getinfo, level, "Sl")
        if not ok or not info then break end
        if info.short_src and info.short_src ~= "[C]" then
            return (tostring(info.short_src):match("[^\\/]+$") or "?") .. ":" .. tostring(info.currentline)
        end
    end
    return "?"
end
local function guard(kind, label, fn)
    if type(fn) ~= "function" then return fn end
    return function(...)
        local res = table.pack(pcall(fn, ...))
        if res[1] then return table.unpack(res, 2, res.n) end
        local msg = tostring(res[2]):gsub("[\r\n]+", " ")
        emit("ERROR in " .. kind .. " " .. label .. ": " .. msg:sub(1, 200))
        return nil
    end
end

-- ALL Lua RUNS ON THE GAME THREAD. UE4SS's own game-thread delayed actions (LoopInGameThreadWithDelay,
-- ExecuteInGameThreadWithDelay, CancelDelayedAction) run every timer and delayed job from the engine tick, one after the other.
-- The names used below (LoopAsync with "true = stop", ExecuteWithDelay, ExecuteInGameThread) are mapped onto them.
local nLoop, nDelay, nCancel, nGame = rawget(_G, "LoopInGameThreadWithDelay"), rawget(_G, "ExecuteInGameThreadWithDelay"),
    rawget(_G, "CancelDelayedAction"), rawget(_G, "ExecuteInGameThread")
if not (type(nLoop) == "function" and type(nDelay) == "function" and type(nCancel) == "function" and type(nGame) == "function") then
    emit("ERROR: this UE4SS build is too old (no LoopInGameThreadWithDelay). Run INSTALL.bat again to install a recent one. The mod is OFF.")
    return
end
do
    local rawHook, rawNew, rawKey = RegisterHook, NotifyOnNewObject, RegisterKeyBind
    -- A hook on a function whose class is not loaded yet makes UE4SS raise inside its own code, so the function is looked up
    -- first and the call is only made when it exists. (The check is switched off if it cannot find a function that certainly exists.)
    local function exists(path)
        local ok, o = pcall(StaticFindObject, path)
        if not ok or o == nil then return false end
        local okV, v = pcall(function() return o:IsValid() end)
        return okV and v == true
    end
    local PRECHECK = exists("/Script/Engine.GameInstance:ReceiveShutdown")
    emit("RegisterHook precheck (StaticFindObject on the function) is " .. (PRECHECK and "ON" or "OFF: it could not find a function that exists"))
    RegisterHook = function(path, pre, post)
        local label = (tostring(path):match(":([^:]+)$") or tostring(path)) .. "@" .. callSite()
        if PRECHECK and not exists(path) then error("function not loaded yet: " .. tostring(path), 0) end
        if post then return rawHook(path, guard("hook", label, pre), guard("post", label, post)) end
        return rawHook(path, guard("hook", label, pre))                 -- (no explicit nil as the third argument)
    end
    NotifyOnNewObject = function(path, fn)
        local label = (tostring(path):match("([^%./]+)$") or tostring(path)) .. "@" .. callSite()
        return rawNew(path, guard("new", label, fn))
    end
    RegisterKeyBind = function(key, a, b)
        local label = tostring(KEY_NAMES[key] or key) .. "@" .. callSite()
        if type(a) == "function" then return rawKey(key, guard("key", label, a)) end
        return rawKey(key, a, guard("key", label, b))
    end
    LoopAsync = function(ms, fn)
        local g = guard("timer", ms .. "ms@" .. callSite(), fn)
        local handle
        handle = nLoop(ms, function()
            if g() == true and handle ~= nil then pcall(nCancel, handle) end      -- LoopAsync semantics: true = stop
        end)
        return handle
    end
    ExecuteWithDelay = function(ms, fn)
        return nDelay(ms, guard("delay", ms .. "ms@" .. callSite(), fn))
    end
    ExecuteInGameThread = function(fn)
        return nGame(guard("game", "@" .. callSite(), fn))
    end
end

local function pget(obj, name)
    local ok, v = pcall(function() return obj[name] end)
    if not ok or v == nil then return nil end
    if type(v) == "userdata" then
        local ok2, r = pcall(function() return v:get() end)
        if ok2 then return r end
        return nil
    end
    return v
end

local function valid(o) return o ~= nil and o.IsValid and o:IsValid() end

-- UWorld:SpawnActor only accepts plain Lua tables for the location and the rotation (a struct object raises "No overload
-- found"), so every value read from the game is copied into a table first.
local function vecTable(v)
    local ok, t = pcall(function() return { X = v.X or 0, Y = v.Y or 0, Z = v.Z or 0 } end)
    return ok and t or { X = 0, Y = 0, Z = 0 }
end
local function rotTable(r)
    if r == nil then return { Pitch = 0, Yaw = 0, Roll = 0 } end
    local ok, t = pcall(function() return { Pitch = r.Pitch or 0, Yaw = r.Yaw or 0, Roll = r.Roll or 0 } end)
    return ok and t or { Pitch = 0, Yaw = 0, Roll = 0 }
end


-- Travel guard: for a while after the match is started / left, the periodic jobs below do not touch ANY game object. A crash
-- dump (17:54, UE4SS.dll access violation) ended inside "items tick: world:GetFullName": FindFirstOf("World") had returned the
-- old map's world while the game was already tearing it down. Every map change starts from one of the places that call mark().
local TRAVEL = { untilAt = 0 }
function TRAVEL.mark(why, secs)
    local u = os.clock() + (secs or 15)
    if u > TRAVEL.untilAt then TRAVEL.untilAt = u end          -- only ever extends the window, a short mark never cuts a long one
    -- when the last travel STARTED and when its loading screen FINISHED: the item code may start as soon as the loading screen
    -- is over (the map is built) instead of waiting for the whole fixed window; "epoch" counts map changes
    if tostring(why):find("OnLoadingScreenFinished", 1, true) then TRAVEL.loadDoneAt = os.clock() else TRAVEL.startedAt = os.clock() TRAVEL.epoch = (TRAVEL.epoch or 0) + 1 end
end
-- Roster guard: for a few seconds after a player logs in / out, the 3-second STATE snapshot does not read the player list
-- (crash 17:13:51: "STATE snapshot: PlayerArray[2]" while the roster was changing). Separate from TRAVEL on purpose: the
-- late-join code stops when TRAVEL is on, and a join must not stop it.
local ROSTER = { untilAt = 0 }
function ROSTER.mark(why, secs)
    local u = os.clock() + (secs or 4)
    if u > ROSTER.untilAt then ROSTER.untilAt = u end
end
function ROSTER.on() return os.clock() < ROSTER.untilAt end
function TRAVEL.on() return os.clock() < TRAVEL.untilAt end
-- inside the travel window the periodic jobs may still run once the loading screen of THIS travel has been over for 3 s
local function travelOK()
    if not TRAVEL.on() then return true end
    local done, started = TRAVEL.loadDoneAt, TRAVEL.startedAt
    return done ~= nil and (started == nil or done >= started) and os.clock() - done >= 3
end

-- World lookup. Crashes (UE4SS.dll, "items tick: world:GetFullName", address 0x8) came in a lobby, a minute after the map had
-- been reloaded: FindFirstOf("World") can return an OLD world that the game has left but the garbage collector has not freed
-- yet, and reading its name then walks freed memory. So the CURRENT world is taken from objects that live as long as the
-- game does, asked in this order, and the first one that gives a valid world is used (a lookup stops there, nothing else is
-- touched; FindFirstOf is only the last resort):
--   "gi"        GameInstance:GetWorld()  (the game instance lives as long as the game; its world is always the current one)
--   "viewport"  Engine.GameViewport:GetWorld()
--   "find"      FindFirstOf("World")
-- Every change of the way that is used is written to the log as "WORLD used: ...".
local WORLD_METHODS = { "gi", "viewport", "find" }
local giObj, engObj
local worldNames = {}                         -- address -> { full name, time }: a world's name is read once per 10 s at most
pcall(NotifyOnNewObject, "/Script/Engine.World", function() worldNames = {} end)      -- (a new world may reuse an address: no pointer is kept)

local function addrOf(o)
    if not valid(o) then return nil end
    local ok, a = pcall(function() return o:GetAddress() end)
    return ok and a or nil
end

-- the game instance: lives for the whole process, so one lookup is kept (checked with IsValid before every use)
local function getGI()
    if not valid(giObj) then giObj = FindFirstOf("BP_ShiversGameInstance_C") end
    if valid(giObj) then return giObj end
    return nil
end

local function worldVia(method)
    if method == "find" then
        local w = FindFirstOf("World")
        return valid(w) and w or nil
    elseif method == "gi" then
        local gi = getGI()
        if not gi then return nil end
        local ok, w = pcall(function() return gi:GetWorld() end)
        return (ok and valid(w)) and w or nil
    elseif method == "viewport" then
        if not valid(engObj) then engObj = FindFirstOf("GameEngine") end
        if not valid(engObj) then return nil end
        local ok, w = pcall(function() return engObj.GameViewport:GetWorld() end)
        return (ok and valid(w)) and w or nil
    end
end

local lastWorldPick
local function getWorld()
    for _, m in ipairs(WORLD_METHODS) do
        local ok, w = pcall(worldVia, m)
        if ok and w then
            if m ~= lastWorldPick then
                lastWorldPick = m
                log("WORLD used: %s", m)
            end
            return w
        end
    end
    return nil
end
local function worldName(w)                   -- the full name of a world: read at most once per 10 s per world object
    local a = addrOf(w)
    if not a then return nil end
    local c = worldNames[a]
    if c and os.clock() - c[2] < 10 then return c[1] end
    local ok, s = pcall(function() return tostring(w:GetFullName()) end)
    if not ok then return nil end
    worldNames[a] = { s, os.clock() }
    return s
end

local spoofCount = function() return nil end   -- same section: the fake player number while the list spoof is on, else nil

local ENABLED = true
local SPOOF_LIST = CFG.lobby_shown_as_2_of_4

---------------------------------------------------------------- caps on existing objects
local function setGameInstanceCap()
    local gis = FindAllOf("BP_ShiversGameInstance_C")
    if gis then
        for _, gi in ipairs(gis) do
            if valid(gi) and (pget(gi, "MaxPlayers") or 0) < TARGET then gi.MaxPlayers = TARGET end
        end
        return true
    end
end

-- engine GameSession cap (was 16); the game hands TARGET+1 to Steam, so keep it above that
NotifyOnNewObject("/Script/Engine.GameSession", function(gs)
    ExecuteWithDelay(500, function() ExecuteInGameThread(function()
        if ENABLED and valid(gs) and (pget(gs, "MaxPlayers") or 0) < TARGET + 1 then
            gs.MaxPlayers = TARGET + 1
            log("GameSession.MaxPlayers -> %d", TARGET + 1)
        end
    end) end)
end)

---------------------------------------------------------------- extra PlayerStarts on the map
local function addStarts()
    local starts = FindAllOf("PlayerStart")
    if not starts or #starts == 0 then return false end
    local realCount = #starts
    if realCount >= TARGET then return true end
    -- extra starts are copies of the real ones (same rotation and height, a few uu beside them)
    local world = starts[1]:GetWorld()
    local cls = StaticFindObject("/Script/Engine.PlayerStart")
    local OFFS = { { 70, 0 }, { -70, 0 }, { 0, 70 }, { 0, -70 } }
    for i = realCount + 1, TARGET do
        local src = starts[((i - 1) % realCount) + 1]
        local ring = math.floor((i - 1) / realCount)
        local o = OFFS[((ring - 1) % #OFFS) + 1]
        local okL, loc = pcall(function() return src:K2_GetActorLocation() end)
        if okL then
            local pos = { X = loc.X + o[1], Y = loc.Y + o[2], Z = loc.Z + 5 }
            local okR, rot = pcall(function() return src:K2_GetActorRotation() end)
            local okS, a = pcall(function() return world:SpawnActor(cls, pos, rotTable(okR and rot or nil)) end)
            if not (okS and valid(a)) then log("SpawnActor failed: %s", tostring(a)) end
        end
    end
    log("PlayerStarts %d -> %d", realCount, TARGET)
    return true
end

NotifyOnNewObject(BASE .. "GameModes/BaseGameMode/BP_Shivers_InGameMode.BP_Shivers_InGameMode_C", function(mode)
    if not ENABLED then return end
    local tries = 0
    local function attempt()
        tries = tries + 1
        local ok, done = pcall(addStarts)
        if not (ok and done) and tries < 15 then ExecuteWithDelay(1000, function() ExecuteInGameThread(attempt) end) end
    end
    ExecuteWithDelay(500, function() ExecuteInGameThread(attempt) end)          -- (FindAllOf / SpawnActor: game thread only)
    -- the match has started: republish the lobby a little later so the list spoof also covers "started" (the hook on the
    -- publish call rewrites the flag); otherwise Steam keeps showing whatever the game published at match start
    ExecuteWithDelay(10000, function()
        if not (SPOOF_LIST and ENABLED) then return end
        ExecuteInGameThread(function()
            local gi = FindFirstOf("BP_ShiversGameInstance_C")
            if valid(gi) then
                log("match started: republishing the lobby for the list spoof")
                pcall(function() gi:UpdateSession() end)
            end
        end)
    end)
end)

---------------------------------------------------------------- hooks (registered once their classes exist)
local SESSION_HOOKS = {
    { "/Script/SteamCorePro.SteamCoreProCreateSessionExtra:CreateSteamCoreProSessionExtra", 5 },
    { "/Script/SteamCorePro.SteamCoreProCreateSession:CreateSteamCoreProSession", 5 },
    { "/Script/SteamCorePro.SteamCoreProUpdateSession:UpdateSteamCoreProSession", 4 },
}
local AUTO_READY = CFG.start_without_ready      -- "everyone is ready"
local IN_LOBBY_MAP = true    -- set by the state monitor: the ready poll runs only in a safe house (the lobby), never in a match
local pending = {}

-- What the game hands to Steam when it (re)publishes the lobby: every key of the settings map is logged (one line, only
-- when it changed), and while the list spoof (F10) is on, any "match started" key is rewritten to 0 so the lobby list
-- shows the lobby as not started. Keys are matched by name because the exact name is not known yet - read the
-- "published settings" line in debug.log to see it.
local STARTED_WORDS = { "STARTED", "IN_GAME", "INGAME", "PLAYING" }
local lastSettingsLine
-- A crash dump (18:00, in the lobby, last step "publish settings UpdateSteamCoreProSession") ended inside UE4SS while this
-- function walked the whole settings map (ForEach + two native getters per key) on every publish. The full walk now happens
-- ONCE per publish call kind (it finds the "started" key); later calls only write that one key.
local settingsKey = {}          -- label -> name of the "started" key found in that call's map
local settingsSeen = {}
local fastLogged = 0
local function processSettings(mapParam, label)
    local map = mapParam:get()
    local utils = StaticFindObject("/Script/SteamCorePro.Default__SteamUtilities")
    if settingsSeen[label] then
        -- (The first publish of a kind may come without the "started" key - the lobby creation does - and the first version of this
        -- short path then never rewrote any later one, so the lobby showed as "in game" during a match. The key name is known from
        -- the log, so it is always written while the spoof is on; a value 0 for "not started" is harmless in any publish.)
        local key = settingsKey[label] or "IS_IN_GAME_STARTED"
        if SPOOF_LIST and ENABLED then
            local ok, err = pcall(function() map:Add(key, utils:MakeInteger(0)) end)
            if fastLogged < 6 then fastLogged = fastLogged + 1 log("list spoof: %s -> 0 (%s, short path)", key, ok and "ok" or tostring(err)) end
        end
        return
    end
    settingsSeen[label] = true
    local items, fix = {}, {}
    map:ForEach(function(k, v)
        local key = tostring(k:get():ToString())
        local val = "?"
        local okI, num = pcall(function()
            local out = {}
            utils:GetInteger(v:get(), key, out)
            return out.OutValue
        end)
        if okI and num ~= nil then val = tostring(num) end
        local okS, str = pcall(function()
            local out = {}
            utils:GetString(v:get(), key, out)
            return out.OutValue
        end)
        if okS and type(str) == "string" and str ~= "" then val = val .. "/\"" .. str .. "\"" end
        items[#items + 1] = key .. "=" .. val
        local up = key:upper()
        for _, w in ipairs(STARTED_WORDS) do
            if up:find(w, 1, true) and num ~= nil and num ~= 0 then fix[#fix + 1] = key break end
        end
    end)
    settingsKey[label] = fix[1] or settingsKey[label]
    if not settingsKey[label] then
        for _, it in ipairs(items) do
            local k = it:match("^([^=]+)=")
            if k and k:upper() == "IS_IN_GAME_STARTED" then settingsKey[label] = k end
        end
    end
    local line = table.concat(items, ", ")
    if line ~= lastSettingsLine then
        lastSettingsLine = line
        log("published settings (%s): %s", label, line)
    end
    if SPOOF_LIST and ENABLED then
        for _, key in ipairs(fix) do
            local ok, err = pcall(function() map:Add(key, utils:MakeInteger(0)) end)
            log("list spoof: %s -> 0 (%s)", key, ok and "ok" or tostring(err))
        end
    end
end

-- The positions of the "max players" and "settings" parameters are read from the function itself (its parameter names), so a
-- game or plugin update that adds or moves a parameter does not make the hook write the wrong one. The fixed positions of
-- version 1.1.0 stay as the fallback. The parameter list is written to the log once per function.
local function paramPositions(path, maxFallback, settingsFallback)
    local names, maxIdx, setIdx = {}, nil, nil
    pcall(function()
        local fn = StaticFindObject(path)
        if not valid(fn) then return end
        fn:ForEachProperty(function(prop)
            local okn, n = pcall(function() return prop:GetFName():ToString() end)
            n = okn and tostring(n) or "?"
            names[#names + 1] = n
            local low = n:lower()
            if not maxIdx and (low:find("maxplayer", 1, true) or low:find("numpublicconnections", 1, true) or low:find("maxmembers", 1, true)) then maxIdx = #names end
            if not setIdx and low:find("setting", 1, true) then setIdx = #names end
        end)
    end)
    log("%s parameters: %s -> max players #%s, settings #%s", path:match(":(.+)$") or path, #names > 0 and table.concat(names, ", ") or "(not readable)",
        tostring(maxIdx or maxFallback), tostring(setIdx or settingsFallback))
    return maxIdx or maxFallback, setIdx or settingsFallback
end

for _, h in ipairs(SESSION_HOOKS) do
    local path, idxFallback = h[1], h[2]
    pending[#pending + 1] = function()
        local idx, setIdx = idxFallback, 2
        local resolved = false
        RegisterHook(path, function(self, ...)
            if not resolved then resolved = true idx, setIdx = paramPositions(path, idxFallback, 2) end
            local args = { ... }
            pcall(processSettings, args[setIdx], path:match(":(.+)$") or path)
            local p = args[idx]
            local okg, old = pcall(function() return p:get() end)
            if ENABLED and okg and type(old) == "number" then
                log("%s MaxPlayers %d -> %d", path:match(":(.+)$"), old, math.max(old, TARGET))
                if old < TARGET then pcall(function() p:set(TARGET) end) end
            end
        end)
    end
end

pending[#pending + 1] = function()
    RegisterHook(BASE .. "Blueprints/GameInstances/BP_ShiversGameInstance.BP_ShiversGameInstance_C:UpdateCreationSettings",
        function(self, NumberOfMaxPlayers)
            local okg, old = pcall(function() return NumberOfMaxPlayers:get() end)
            if ENABLED and okg and type(old) == "number" and old < TARGET then pcall(function() NumberOfMaxPlayers:set(TARGET) end) end
        end)
end

-- The game changes GameInstance.NumberOfCurrentPlayers by +-1 on every join / leave and publishes it to Steam inside this
-- call (CURRENT_PLAYERS). The game itself also reads that counter, so it must stay the REAL number. While the list spoof is
-- on, the counter is set to fake-1 / fake+1 only for the duration of the call (the game adds or removes one and publishes
-- exactly the fake value), and the real number is put back as soon as the call returns.
local counterHold = { real = nil, delta = 0 }
pending[#pending + 1] = function()
    RegisterHook(BASE .. "Blueprints/GameInstances/BP_ShiversGameInstance.BP_ShiversGameInstance_C:SetNumberOfCurrentPlayers",
        function(self, bNewLoginPlayer)
            counterHold.real = nil
            local fake = spoofCount()
            if not fake then return end
            local okl, login = pcall(function() return bNewLoginPlayer:get() end)
            local gi = self:get()
            if okl and valid(gi) then
                local real = pget(gi, "NumberOfCurrentPlayers")
                if type(real) ~= "number" then return end
                counterHold.real, counterHold.delta = real, login and 1 or -1
                pcall(function() gi.NumberOfCurrentPlayers = login and (fake - 1) or (fake + 1) end)
            end
        end,
        function(self)
            local gi = self:get()
            if counterHold.real ~= nil and valid(gi) then
                local real = math.max(0, counterHold.real + counterHold.delta)
                counterHold.real = nil
                pcall(function() gi.NumberOfCurrentPlayers = real end)
            end
            log("players now %s / max %s", tostring(pget(gi, "NumberOfCurrentPlayers")), tostring(pget(gi, "MaxPlayers")))
        end)
end

-- Loadout screen may hold up to LOADOUT_LIMIT (16) of a tool, but the match only gets the game's own maximum:
-- when the host presses Start, every loadout array is clamped back to the vanilla limit before the map loads.
-- The game's own limits (from the DT_ShopTools dump), with the three tools the host wants raised:
local RAISED_LIMIT = CFG.extra_gear and {
    ["Tools.Flashlight"] = CFG.flashlight, ["Tools.Candle"] = CFG.candle, ["Tools.SanityPills"] = CFG.sanity_pills,
    ["Tools.Glass"] = CFG.glass, ["Tools.Crucifix"] = CFG.crucifix,
} or {}
local GAME_LIMIT = {
    ["Tools.EMF"] = 2, ["Tools.ESG"] = 2, ["Tools.Flashlight"] = 4, ["Tools.GhostPainting"] = 2, ["Tools.Glass"] = 2,
    ["Tools.SpiritBox"] = 2, ["Tools.UvLight"] = 2, ["Tools.Crucifix"] = 2, ["Tools.Thermometer"] = 3,
    ["Tools.SanityPills"] = 4, ["Tools.Candle"] = 4, ["Tools.TripodeCamera"] = 3, ["Tools.Camera"] = 4,
    ["Tools.Fulu"] = 3, ["Tools.BlacksmithHammer"] = 2, ["Tools.SaltBarrier"] = 1, ["Tools.PocketWatch"] = 4,
}
local VANILLA_LIMIT = {}       -- what the loadout is cut to at match start: game limit, or the raised one
for tag, n in pairs(GAME_LIMIT) do VANILLA_LIMIT[tag] = RAISED_LIMIT[tag] or n end
local LIMIT_SPAWNS = true      -- cut every tool back to VANILLA_LIMIT at match start (so leftovers above the limit never spawn)
local F_ELTAG = "ElementTag_4_5835B68E429CD0735A80B186EC80E25F"
local F_ELCOUNT = "Count_5_0F393F2B4B4698AD88B28D8CEFD71537"

local function clampArray(arr, label)
    local seen, clamped = {}, 0
    arr:ForEach(function(_, elem)
        local e = elem:get()
        local okn, name = pcall(function() return e[F_ELTAG].TagName:ToString() end)
        local cnt = e[F_ELCOUNT]
        if okn and type(cnt) == "number" then
            seen[#seen + 1] = name .. "=" .. cnt
            local lim = VANILLA_LIMIT[name]
            if cnt < 0 then e[F_ELCOUNT] = 0 clamped = clamped + 1
            elseif lim and cnt > lim then e[F_ELCOUNT] = lim clamped = clamped + 1 end
        end
    end)
    log("loadout %s: [%s] -> %d clamped", label, table.concat(seen, ", "), clamped)
end

-- how many of each tool the lobby loadout asks for (tag "EMF" -> 5); filled when the match starts, read by the
-- "create the missing copies" step of the item stacking further down
local wantedByTag = {}
local function snapshotWanted()
    wantedByTag = {}
    local gi = getGI()                                 -- (no scan: the game instance is kept, see getGI)
    if not gi then return end
    local parts = {}
    gi.CommonLoadout:ForEach(function(_, elem)
        local e = elem:get()
        local okn, name = pcall(function() return e[F_ELTAG].TagName:ToString() end)
        local cnt = e[F_ELCOUNT]
        if okn and type(cnt) == "number" then
            local short = tostring(name):match("^Tools%.(.+)$")
            if short then wantedByTag[short] = cnt parts[#parts + 1] = short .. "=" .. cnt end
        end
    end)
    log("loadout wanted: %s", table.concat(parts, ", "))
end

-- Runs inside the StartGame hook, i.e. at the very moment the match travel begins - so it does NO scans: the game instance is the
-- kept one (getGI), the lobby game state is the current world's GameState, and the lobby player states are its PlayerArray (only
-- while no join / leave is going on). The same four kinds of array are cut back as before.
local function clampLoadouts()
    if not (LIMIT_SPAWNS and ENABLED) then return end
    local function try(label, getArr)
        local ok, arr = pcall(getArr)
        if ok and arr then
            local ok2, err = pcall(clampArray, arr, label)
            if not ok2 then log("clamp %s failed: %s", label, tostring(err)) end
        end
    end
    local gi = getGI()
    if gi then
        for _, f in ipairs({ "CommonLoadout", "LoadoutLocal", "InitialLoadout" }) do try("GameInstance." .. f, function() return gi[f] end) end
    end
    local world = getWorld()
    local okg, gs = pcall(function() return world.GameState end)
    if okg and valid(gs) then
        try("LobbyGameState.CommonLoadout", function() return gs.CommonLoadout end)
        if not ROSTER.on() then
            local okp, arr = pcall(function() return gs.PlayerArray end)
            local okn, n = pcall(function() return #arr end)
            if okp and okn and type(n) == "number" then
                for i = 1, math.min(n, 16) do
                    local okE, ps = pcall(function() return arr[i] end)
                    if okE and valid(ps) then try("PlayerState" .. i .. ".Loadout", function() return ps.Loadout end) end
                end
            end
        else
            log("loadout clamp: a player is joining / leaving - the per-player loadouts were left alone")
        end
    end
end
-- The lobby loadout limit. When a player adds a tool to the lobby loadout, the host's AddToLoadoutOnServer only asks
-- BPL_Shivers:IsCommonLoadoutFull(tool) - "full" refuses the add. While LOBBY_LOADOUT_UNLIMITED is on, the answer is changed to
-- "not full", so players can add as much as their own menu lets them. (Only the lobby: at match start clampLoadouts cuts every
-- count back to the game's limits, and negative ones to 0, so nothing extra spawns. The player's own menu may have a limit of its
-- own on his computer, which the host cannot change.)
local LOBBY_LOADOUT_UNLIMITED = CFG.extra_gear
local fullAnswers = 0
pending[#pending + 1] = function()
    RegisterHook(BASE .. "Blueprints/Libraries/Function/Gameplay/BPL_Shivers.BPL_Shivers_C:IsCommonLoadoutFull", function() end, function(self, ...)
        if not LOBBY_LOADOUT_UNLIMITED then return end
        local a = { ... }
        local last = a[#a]
        if last == nil then return end
        local okv, v = pcall(function() return last:get() end)
        if okv and v == true then
            local oks = pcall(function() last:set(false) end)
            fullAnswers = fullAnswers + 1
            if fullAnswers <= 8 or fullAnswers % 50 == 0 then log("loadout: IsCommonLoadoutFull said 'full' -> changed to 'not full' (%s), %d time(s)", oks and "ok" or "FAILED", fullAnswers) end
        end
    end)
    log("loadout: IsCommonLoadoutFull hook registered")
end
pending[#pending + 1] = function()
    RegisterHook(BASE .. "Blueprints/GameInstances/BP_ShiversGameInstance.BP_ShiversGameInstance_C:StartGame",
        function() TRAVEL.mark("StartGame") pcall(clampLoadouts) pcall(snapshotWanted) end)      -- clamp first: "wanted" must be the clamped numbers
end

-- Every place where the map can change or a player can come / go. Each hook only starts the travel guard (or the roster
-- guard) and writes one line to debug.log ("guard hook fired: ...") so it is visible which of them really fire. Registered
-- one by one through the same retry list as the other hooks; one that does not exist (or can not be hooked) is tried 30
-- times and then given up with a log line, it never stops the rest.
do
    local GI_P = BASE .. "Blueprints/GameInstances/BP_ShiversGameInstance.BP_ShiversGameInstance_C:"
    local LIB_P = BASE .. "Blueprints/Libraries/Function/Gameplay/BPL_Shivers.BPL_Shivers_C:"
    local GM_P = BASE .. "GameModes/BaseGameMode/"
    local GUARD_HOOKS = {
        -- { path, label, kind ("travel" | "roster"), seconds }
        { "/Script/Shivers.BaseShiversGameMode:ProcessServerTravel", "ProcessServerTravel", "travel", 20 },
        { "/Script/Shivers.BaseShiversGameMode:PostSeamlessTravel", "PostSeamlessTravel", "travel", 8 },
        { "/Script/Shivers.BaseShiversController:PreClientTravel", "PreClientTravel", "travel", 20 },
        { "/Script/Engine.PlayerController:ClientTravelInternal", "ClientTravelInternal", "travel", 20 },
        { "/Script/Engine.PlayerController:ClientTravel", "ClientTravel", "travel", 20 },
        { "/Script/Engine.GameplayStatics:OpenLevel", "OpenLevel", "travel", 20 },
        { "/Script/SteamCorePro.SteamUtilities:ServerTravel", "SteamUtilities.ServerTravel", "travel", 20 },
        { "/Script/Engine.GameModeBase:ReturnToMainMenuHost", "ReturnToMainMenuHost", "travel", 20 },
        { "/Script/Engine.PlayerController:ClientReturnToMainMenuWithTextReason", "ClientReturnToMainMenu", "travel", 20 },
        { "/Script/Engine.PlayerController:ClientWasKicked", "ClientWasKicked", "travel", 20 },
        { GI_P .. "HandleTravelError", "GI.HandleTravelError", "travel", 20 },
        { GI_P .. "HandleNetworkError", "GI.HandleNetworkError", "travel", 20 },
        { GI_P .. "HandleNetworkDisconnect", "GI.HandleNetworkDisconnect", "travel", 20 },
        { GI_P .. "OnLoadingScreenFinished", "GI.OnLoadingScreenFinished", "travel", 6 },
        { LIB_P .. "ShiversLoadMap", "BPL.ShiversLoadMap", "travel", 20 },
        { LIB_P .. "LoadGameMap", "BPL.LoadGameMap", "travel", 20 },
        { LIB_P .. "LoadSafeHouse", "BPL.LoadSafeHouse", "travel", 20 },
        { GM_P .. "BP_ShiversLobbyGameMode_Online.BP_ShiversLobbyGameMode_Online_C:K2_PostLogin", "Lobby.PostLogin", "roster", 4 },
        { GM_P .. "BP_ShiversLobbyGameMode_Online.BP_ShiversLobbyGameMode_Online_C:K2_OnLogout", "Lobby.OnLogout", "roster", 4 },
        { GM_P .. "BP_ShiversGameMode_BaseOnline.BP_ShiversGameMode_BaseOnline_C:K2_PostLogin", "Online.PostLogin", "roster", 4 },
        { GM_P .. "BP_ShiversGameMode_BaseOnline.BP_ShiversGameMode_BaseOnline_C:K2_OnLogout", "Online.OnLogout", "roster", 4 },
    }
    local firedCount = {}
    for _, h in ipairs(GUARD_HOOKS) do
        local path, label, kind, secs = h[1], h[2], h[3], h[4]
        local tries = 0
        pending[#pending + 1] = function()
            tries = tries + 1
            local ok, err = pcall(RegisterHook, path, function()
                firedCount[label] = (firedCount[label] or 0) + 1
                if firedCount[label] <= 5 then log("guard hook fired: %s (%s, %d s)", label, kind, secs) end
                if kind == "roster" then ROSTER.mark(label, secs) else TRAVEL.mark(label, secs) end
            end)
            if ok then return true end
            if tries >= 30 then
                log("guard hook %s: giving up after %d tries (%s)", label, tries, tostring(err))
                return true                        -- true = done (not retried again)
            end
            error(err, 0)                           -- not there yet: stays in the retry list
        end
    end
end

local gameInstanceDone = false
local lastPendingErrors = {}
local function registerPending()
    if not gameInstanceDone then gameInstanceDone = setGameInstanceCap() or false end
    local left, errs = {}, {}
    for _, fn in ipairs(pending) do
        local ok, err = pcall(fn)
        if not ok then left[#left + 1] = fn errs[#errs + 1] = tostring(err):gsub("[\r\n]+", " "):sub(1, 160) end
    end
    pending = left
    lastPendingErrors = errs
    return #pending == 0 and gameInstanceDone      -- true stops the loop
end
-- One status line a minute after load and one at five minutes: which hooks are still waiting (normal for the lobby / match
-- ones until that screen has been opened once; a hook that still waits in a match points at a game update).
local function reportPending(when)
    if #lastPendingErrors == 0 and gameInstanceDone then log("hooks status (%s): everything registered", when) return end
    log("hooks status (%s): %d waiting, game instance cap %s", when, #lastPendingErrors, gameInstanceDone and "set" or "NOT set yet")
    for i = 1, math.min(#lastPendingErrors, 12) do log("  waiting: %s", lastPendingErrors[i]) end
end
ExecuteWithDelay(60000, function() ExecuteInGameThread(function() reportPending("1 min") end) end)
ExecuteWithDelay(300000, function() ExecuteInGameThread(function() reportPending("5 min") end) end)
-- Retried on the GAME thread (RegisterHook / FindAllOf look game objects up: from the timer thread they raced with the map loading - every crash of the
-- fresh-start sessions fell on a map load while such a retry was running): every 2 s for the first minute, then every 10 s, until all are in.
local regTries, regDone = 0, false
LoopAsync(2000, function()
    if regDone then return true end
    regTries = regTries + 1
    if regTries > 30 and regTries % 5 ~= 0 then return false end
    ExecuteInGameThread(function() if not regDone and registerPending() then regDone = true end end)
    return false
end)

---------------------------------------------------------------- state monitor (no hooks on game functions: crash-safe)
-- Logs one "STATE" line whenever the map, the number of controllers or the list of players changes, so a join, a kick
-- or a map change shows up with its time. Runs on the game thread every 3 s; F3 forces a line.
do
    local lastSig = ""
    local mismatch = 0
    -- A crash dump (18:17, access violation inside UE4SS, last step "STATE snapshot: ps:GetPlayerName") came 83 s after a
    -- player had been killed, while a player was probably leaving: IsValid() was still true for his PlayerState but calling
    -- a function on it read freed memory. So a name is asked for ONCE per PlayerState (by its address) and kept; the
    -- every-3-seconds job no longer calls anything on a PlayerState it has seen before, and no longer reads bIsReady.
    local lastMapName = nil
    local function snapshot(tag, force)
        local world = getWorld()
        local map = "?"
        if valid(world) then
            local wn = worldName(world)
            map = wn and (wn:match("%.([^%.:]+)$") or "?") or "?"
        end
        local playerCount = 0                    -- how many PlayerStates the game has: only the LENGTH of PlayerArray is read
        local pcCount = 1
        lastMapName = map
        if map ~= "?" then IN_LOBBY_MAP = map:lower():find("safehouse", 1, true) ~= nil end
        local okg, gsv = pcall(function() return world.GameState end)
        if okg and valid(gsv) then
            -- (The elements themselves are no longer touched: crashes came from reading the PlayerStates one by one -
            -- GetAddress / GetPlayerName on an element while a player was joining or leaving: 17:13, 18:17, 18:58.)
            local okp, arr = pcall(function() return gsv.PlayerArray end)
            local okl, n = pcall(function() return #arr end)
            if okp and okl and type(n) == "number" then playerCount = n end
        end
        local okd, nd = pcall(function() return world.NetDriver end)
        if okd and valid(nd) then
            local okc, cc = pcall(function() return #nd.ClientConnections end)
            if okc and type(cc) == "number" then pcCount = 1 + cc end
        end
        local gi = getGI()
        -- The game's own player counter (GameInstance.NumberOfCurrentPlayers) drifts (it went to -2 after dropped joins) and
        -- the lobby then refuses to start ("at least 2 players needed"). If it is negative, or - with other players
        -- connected - disagrees with the number of PlayerStates on two ticks in a row (6 s, so map changes do not trigger it),
        -- it is set to the real number. Alone, the game's own value is left as it is (unless negative).
        local cnt = gi and pget(gi, "NumberOfCurrentPlayers")
        local target = playerCount
        local wrong = type(cnt) == "number" and (cnt < 0 or (playerCount >= 2 and cnt ~= playerCount))
        if ENABLED and gi and wrong and playerCount > 0 then
            mismatch = mismatch + 1
            if mismatch >= 2 then
                log("player counter repaired: %d -> %d", cnt, target)
                pcall(function() gi.NumberOfCurrentPlayers = target end)
                mismatch = 0
            end
        else
            mismatch = 0
        end
        local line = string.format("STATE map=%s controllers=%d players=%d gi=%s/%s",
            map, pcCount, playerCount,
            gi and tostring(pget(gi, "NumberOfCurrentPlayers")) or "?", gi and tostring(pget(gi, "MaxPlayers")) or "?")
        if force or line ~= lastSig then lastSig = line log("%s%s", force and "(" .. tag .. ") " or "", line) end
    end
    local function onGameThread(fn)
        if ExecuteInGameThread then ExecuteInGameThread(fn) else fn() end
    end
    LoopAsync(3000, function() onGameThread(function() if not TRAVEL.on() and not ROSTER.on() then pcall(snapshot, "tick", false) end end) return false end)
    -- (Nothing is read from the new controller here: it is called while the object is still being built, often in the middle of
    -- the match travel, and the two crashes of 25.10 02:40 / 02:42 both happened right there after the host pressed Start.
    -- This used to call c:GetFullName() on it just to put the name into the log.)
    pcall(NotifyOnNewObject, BASE .. "Blueprints/Controller/BP_ShiversController.BP_ShiversController_C", function()
        log("player controller created")
    end)
end

---------------------------------------------------------------- loadout display in the safe house: stack extra copies
-- The safe house shows the chosen loadout as tool actors laid out one after another (steps of 20-40 uu in Y). With more
-- copies than the game planned (e.g. 3 EMF instead of 2) the extra ones had no place and fell through the floor.
-- Here every copy of a tool after the first one is moved onto the first copy's position, with its collision and
-- physics off so the stack does not push itself apart. In safe-house maps always, in a match only during the first
-- MATCH_WINDOW seconds (the loadout layout); clampLoadouts is off (LIMIT_SPAWNS) so all copies really exist.
-- No spawn hook: NotifyOnNewObject + a delayed move on the game thread.
do
    local STACK_ITEMS = CFG.extra_gear
    local spawning = false       -- true while we create a copy ourselves: its "new object" callback must do nothing
    local TOOL_CLASS = BASE .. "Blueprints/Tools/BaseTool/BP_Tool.BP_Tool_C"
    local byClass = {}           -- class name -> list of tool actors already seen
    local curMap, mapSince = nil, 0
    local MATCH_WINDOW = 45      -- seconds after the map appeared: the loadout is being laid out
    local SETTLE = 1             -- seconds to leave a freshly loaded map alone (crashes happened while it was loading)
    local MAX_CREATED = 120      -- never create more than this many copies per match
    local pending = {}           -- tools reported by NotifyOnNewObject; nothing is done with them inside the callback
    local processed = 0
    -- Top-up trigger: only tools that belong to the loadout count (a class the loadout asks for). A stray tool such as
    -- BP_Spray_C appears ~6 s BEFORE the loadout and used to start the top-up too early ("created 0", never again).
    local lastLoadoutAt, loadoutSeen, lastEnsuredSeen, passes, madeTotal = 0, 0, 0, 0, 0
    local tagFor                  -- defined below, used by processObj

    local heldSkipped = 0
    -- A tool a player holds (attached to his character / has a ToolUser) must NOT be moved: the PICKPROBE log showed our stack
    -- code "stacking" such a tool (actorAttachedTo=BP_PlayerCharacter, toolUser=BP_PlayerCharacter) onto the pile, so it hung
    -- away from the hand until the game put it back, and it was also used as the reference position for the extra copies (in
    -- mid-air, at hand height). Held tools are only counted, never moved and never used as the reference.
    local function isHeld(a)
        local okA, p = pcall(function() return a:GetAttachParentActor() end)
        if okA and valid(p) then return true end
        local okU, u = pcall(function() return a.ToolUser end)
        if okU and valid(u) then return true end
        return false
    end
    local itemsMayRun = travelOK                    -- (defined at the top: the loading screen of this travel has been over for 3 s)

    local function processObj(obj, safe, createdAt)
        if not valid(obj) then return end
        local okc, cname = pcall(function() return obj:GetClass():GetFullName() end)
        if not okc then return end
        -- tools that a player holds sit at (0,0,0): not part of the layout, leave them alone
        local okp, pos = pcall(function() return obj:K2_GetActorLocation() end)
        if not okp or not pos then return end
        if math.abs(pos.X) + math.abs(pos.Y) + math.abs(pos.Z) < 1 then return end
        processed = processed + 1
        if not safe and tagFor(cname) then
            loadoutSeen = loadoutSeen + 1
            lastLoadoutAt = math.max(lastLoadoutAt, createdAt or os.clock())      -- the time the tool was CREATED, not processed
        end
        if not safe then
            log("match tool spawn: %s at %.0f,%.0f,%.0f", tostring(cname):match("([^%./:]+)$") or cname, pos.X, pos.Y, pos.Z)
        end
        local list = byClass[cname] or {}
        byClass[cname] = list
        -- first still-alive copy of this tool = the reference position
        local first
        for _, a in ipairs(list) do
            if valid(a) and a ~= obj and not isHeld(a) then first = a break end
        end
        list[#list + 1] = obj
        if #list > 40 then table.remove(list, 1) end
        if isHeld(obj) then                              -- held by a player: counted above, but left exactly where it is
            heldSkipped = heldSkipped + 1
            if heldSkipped <= 6 then log("items: %s is held by a player - not moved", tostring(cname):match("([^%./:]+)$") or cname) end
            return
        end
        if not first then return end
        local okl, loc = pcall(function() return first:K2_GetActorLocation() end)
        if not okl or loc == nil then return end
        pcall(function() obj:K2_SetActorLocation({ X = loc.X, Y = loc.Y, Z = loc.Z }, false, {}, true) end)
        pcall(function() obj.RootComponent:SetSimulatePhysics(false) end)      -- collision stays on so each copy can be picked up
        log("stacked a copy of %s on the first one (%d copies)", tostring(cname):match("([^%./:]+)$") or cname, #list)
    end

    -- The game only creates as many copies as it has places for (2 EMF although 16 were chosen). Once the layout is
    -- done, create the missing ones ourselves, on the position of the first copy. Once per match map.
    local ensuredFor
    tagFor = function(cname)
        local lc = tostring(cname):lower()
        local best, bestLen
        for tag in pairs(wantedByTag) do
            local t = tag:lower()
            if lc:find(t, 1, true) and (not bestLen or #t > bestLen) then best, bestLen = tag, #t end
        end
        return best
    end
    local queue = {}
    local function ensureCounts(world)
        for cname, list in pairs(byClass) do
            local tag = tagFor(cname)
            local want = tag and wantedByTag[tag]
            local alive, first = 0, nil
            for _, a in ipairs(list) do
                if valid(a) then
                    alive = alive + 1
                    if not first and not isHeld(a) then first = a end      -- the reference position is a tool lying in the world
                end
            end
            if want and first and alive < want then
        local okl, loc = pcall(function() return first:K2_GetActorLocation() end)
                local okr, rot = pcall(function() return first:K2_GetActorRotation() end)
                if okl and loc then
                    local missing = math.min(want - alive, 15)
                    for _ = 1, missing do
                        queue[#queue + 1] = { cls = first:GetClass(), loc = vecTable(loc),
                                              rot = rotTable(okr and rot or nil), tag = tag, list = list }
                    end
                    log("queued %d missing %s (wanted %d, game made %d)", missing, tag, want, alive)
                end
            end
        end
        -- a few copies per 100 ms tick (80 in one frame crashed the game), and a hard cap per match.
        -- The world is not kept between ticks as an object: only its address is, and every tick asks for the current world
        -- again - when the address differs (map change) or a travel window is open, the rest of the queue is dropped.
        local worldAddr = addrOf(world)
        LoopAsync(100, function()
            local function make()
                local w = travelOK() and getWorld() or nil
                if not w or addrOf(w) ~= worldAddr then queue = {} return end
                world = w
                for _ = 1, 5 do
                    local item = table.remove(queue, 1)
                    if not item or madeTotal >= MAX_CREATED then break end
                    spawning = true
                    local oks, a = pcall(function() return world:SpawnActor(item.cls, item.loc, item.rot) end)
                    spawning = false
                    if oks and a ~= nil then
                        madeTotal = madeTotal + 1
                        pcall(function() a.RootComponent:SetSimulatePhysics(false) end)
                        item.list[#item.list + 1] = a
                    end
                end
            end
            if #queue == 0 or madeTotal >= MAX_CREATED then
                queue = {}
                log("created %d missing copies in total (this map)", madeTotal)
                return true
            end
            if ExecuteInGameThread then ExecuteInGameThread(make) else make() end
            return false
        end)
    end

    -- Everything happens here, once a second on the game thread, and only when the map has been loaded for a while.
    local function tick()
        if not itemsMayRun() then return end
        if not STACK_ITEMS or not ENABLED then return end
        local world = getWorld()
        if not valid(world) then return end
        local name = worldName(world)
        if not name then return end
        if name ~= curMap then
            curMap, mapSince, byClass, processed = name, os.time(), {}, 0
            lastLoadoutAt, loadoutSeen, lastEnsuredSeen, passes, madeTotal = 0, 0, 0, 0, 0
            queue = {}
            return
        end
        if os.time() - mapSince < SETTLE then return end
        local safe = name:lower():find("safehouse", 1, true) ~= nil
        if safe then pending = {} return end                 -- (the lobby display is only cosmetic: leave it alone)
        if not safe and os.time() - mapSince > MATCH_WINDOW + SETTLE then
            pending = {}
            return
        end
        local n, stale = 0, 0
        while #pending > 0 and n < 25 do
            local ent = table.remove(pending, 1)
            n = n + 1
            if ent.ep ~= (TRAVEL.epoch or 0) then stale = stale + 1          -- reported before the latest map change: the object may be gone
            else pcall(processObj, ent.obj, safe, ent.t) end
        end
        if stale > 0 then log("items: %d tool(s) from before the map change dropped without being touched", stale) end
        -- match: when no new tool appeared for a second, top the counts up (once per map)
        -- (up to 3 passes per map: loadout tools that arrive late are picked up by the next pass)
        if not safe and #pending == 0 and #queue == 0 and loadoutSeen > lastEnsuredSeen and passes < 3
           and os.clock() - lastLoadoutAt >= 1 then               -- 1 s after the last loadout tool was created (was 2 s after it was processed)
            lastEnsuredSeen = loadoutSeen
            passes = passes + 1
            log("top-up pass %d: %d loadout tools seen so far", passes, loadoutSeen)
            pcall(ensureCounts, world)
        end
    end
    LoopAsync(1000, function()
        if ExecuteInGameThread then ExecuteInGameThread(function() pcall(tick) end) else pcall(tick) end
        return false
    end)

    pcall(NotifyOnNewObject, TOOL_CLASS, function(obj)
        if spawning then return end          -- our own copy: already on the right spot
        -- (creation time kept for the top-up trigger; the map-change counter kept so that a tool of an OLD map is never touched later)
        if #pending < 500 then pending[#pending + 1] = { obj = obj, t = os.clock(), ep = TRAVEL.epoch or 0 } end
    end)
end


---------------------------------------------------------------- ready counter repair (lobby start button)
local function readyCounterTarget(totalPlayers, readyFlags)
    local gi = FindFirstOf("BP_ShiversGameInstance_C")
    local c = gi and pget(gi, "NumberOfCurrentPlayers")
    if type(c) ~= "number" then c = totalPlayers end
    if readyFlags >= totalPlayers then return c end
    return math.max(0, math.min(readyFlags, c - 1))
end

local function syncReadyCounter()
    local pss = FindAllOf("BP_Shivers_LobbyPlayerState_C")
    local modes = FindAllOf("BP_ShiversLobbyGameMode_Online_C")
    if not pss or not modes or not modes[1] or not valid(modes[1]) then return end
    local ready = 0
    for _, ps in ipairs(pss) do if valid(ps) and pget(ps, "bIsReady") == true then ready = ready + 1 end end
    local target = readyCounterTarget(#pss, ready)
    if pget(modes[1], "NumberOfReadyPlayers") ~= target then
        log("ready counter repaired: %s -> %d (flags %d/%d)", tostring(pget(modes[1], "NumberOfReadyPlayers")), target, ready, #pss)
        modes[1].NumberOfReadyPlayers = target
    end
end

---------------------------------------------------------------- "everyone is ready" (always on)
-- Sets bIsReady on every lobby PlayerState and fixes the server's ready counter that CanGameStart checks. The start button
-- compares the lobby's ready counter with GameInstance.NumberOfCurrentPlayers (the fake 2 of the list display), so the
-- counter is written relative to THAT number. The poll runs on the game thread, only in the lobby (safe house) map and
-- never during a map change.
local function readyAll()
    local pss = FindAllOf("BP_Shivers_LobbyPlayerState_C")
    if not pss then return end
    local ready = 0
    for _, ps in ipairs(pss) do
        if valid(ps) and pget(ps, "bIsReady") ~= true then
            pcall(function() ps:SetIsReady(true) end)
            -- SetIsReady does not stick on some clients' player states (log: ready=[true,true,true,false]): set the flag directly
            if pget(ps, "bIsReady") ~= true then pcall(function() ps.bIsReady = true end) end
        end
        if valid(ps) and pget(ps, "bIsReady") == true then ready = ready + 1 end
    end
    local modes = FindAllOf("BP_ShiversLobbyGameMode_Online_C")
    local target = readyCounterTarget(#pss, ready)
    if modes and modes[1] and valid(modes[1]) and pget(modes[1], "NumberOfReadyPlayers") ~= target then
        modes[1].NumberOfReadyPlayers = target
    end
end
LoopAsync(2000, function()
    if AUTO_READY and IN_LOBBY_MAP and not TRAVEL.on() then
        ExecuteInGameThread(function() if AUTO_READY and IN_LOBBY_MAP then pcall(readyAll) end end)
    end
    return false
end)
pending[#pending + 1] = function()
    RegisterHook(BASE .. "GameModes/BaseGameMode/BP_ShiversGameMode_BaseOnline.BP_ShiversGameMode_BaseOnline_C:CanGameStart",
        function() end,
        function(self, CanStartGame)
            if AUTO_READY then pcall(function() CanStartGame:set(true) end) end
        end)
end
for _, fn in ipairs({ "StartButtonOnClicked", "CheckIfReadyPlayers" }) do
    pending[#pending + 1] = function()
        RegisterHook("/Game/UI/MainMenu/WBP_Lobby.WBP_Lobby_C:" .. fn, function()
            if AUTO_READY then pcall(readyAll) elseif ENABLED then pcall(syncReadyCounter) end
        end)
    end
end

---------------------------------------------------------------- lobby LIST display (F10)
-- Other players' lobby browser reads CURRENT_PLAYERS / MAX_PLAYERS, which the game stores in
-- GameInstance.SessionExtraSettings through UpdateSessionExtraSettings(Key, Value) and publishes with UpdateSession.
-- After the game writes those two keys we overwrite them with small fake numbers, so the list shows free room.
-- The real join limit is the Steam slot count set above, so people can still enter.
local SHOW_MAX = 4          -- capacity shown in the list
local SHOW_CURRENT = 2    -- the list always shows exactly this many players, whatever the real count
local function fakeCurrent(real)
    return SHOW_CURRENT
end
local GI = BASE .. "Blueprints/GameInstances/BP_ShiversGameInstance.BP_ShiversGameInstance_C"
local busy = false

local function overwrite(gi, key, number)
    local utils = StaticFindObject("/Script/SteamCorePro.Default__SteamUtilities")
    local setting = utils:MakeInteger(number)
    gi:UpdateSessionExtraSettings(key, setting)
end

-- The list shows what the game publishes from GameInstance.NumberOfCurrentPlayers, so the spoof is the counter itself
-- (see the SetNumberOfCurrentPlayers hook and the UpdateSession hook below). Writing into the settings map sent to
-- Steam (TMap:Add) made friends see "0/4" or "Full" and was removed.
spoofCount = function()
    if SPOOF_LIST and ENABLED then return fakeCurrent(nil) end
    return nil
end

local spoofPending = {
    function()
        log("list spoof hook registered")
        RegisterHook(GI .. ":UpdateSessionExtraSettings", function() end, function(self, Key)
            if busy then return end
            local okk, key = pcall(function() return Key:get():ToString() end)
            if not (SPOOF_LIST and ENABLED) then return end
            if not okk or (key ~= "CURRENT_PLAYERS" and key ~= "MAX_PLAYERS") then return end
            local gi = self:get()
            local value = (key == "MAX_PLAYERS") and SHOW_MAX or fakeCurrent(pget(gi, "NumberOfCurrentPlayers"))
            busy = true
            local ok, err = pcall(overwrite, gi, key, value)
            busy = false
            log("list spoof %s=%d -> %s", key, value, ok and "ok" or tostring(err))
        end)
    end,
    -- The game republishes the lobby (join / leave / map change) through GameInstance:UpdateSession WITHOUT going through
    -- UpdateSessionExtraSettings, so the hook above never fires for it (no "list spoof CURRENT_PLAYERS" line in debug.log
    -- ever) and the fake numbers were replaced by the real ones (friends saw 4/4, later 0/4 after the counter drifted).
    -- Write the fake numbers into the settings map right before every publish.
    function()
        -- The game publishes CURRENT_PLAYERS from GameInstance.NumberOfCurrentPlayers (friends saw "0 players" while that
        -- counter had drifted to 0 / -2), and republishes by itself on every join / leave WITHOUT calling UpdateSession
        -- (see the SetNumberOfCurrentPlayers hook). During any publish through UpdateSession the counter holds the fake
        -- number, and the real one is put back as soon as the call returns (the game reads that counter too).
        local held = nil
        RegisterHook(GI .. ":UpdateSession", function(self)
            held = nil
            if busy or not (SPOOF_LIST and ENABLED) then return end
            local okg, gi = pcall(function() return self:get() end)
            if not (okg and valid(gi)) then return end
            local real = pget(gi, "NumberOfCurrentPlayers")
            if type(real) == "number" and real ~= fakeCurrent(real) then
                held = real
                pcall(function() gi.NumberOfCurrentPlayers = fakeCurrent(real) end)
            end
        end, function(self)
            if held == nil then return end
            local real = held
            held = nil
            local okg, gi = pcall(function() return self:get() end)
            if okg and valid(gi) then pcall(function() gi.NumberOfCurrentPlayers = real end) end
            log("lobby published with %d player(s) shown, real counter %d kept", fakeCurrent(real), real)
        end)
        log("list spoof pre-publish hook registered")
    end,
}
local spoofDone = false
LoopAsync(2000, function()                                   -- (the registrations run on the game thread)
    if spoofDone then return true end
    ExecuteInGameThread(function()
        if spoofDone then return end
        local left = {}
        for _, fn in ipairs(spoofPending) do if not pcall(fn) then left[#left + 1] = fn end end
        spoofPending = left
        if #left == 0 then spoofDone = true end
    end)
    return false
end)

---------------------------------------------------------------- tool loadout limits (F6)
-- DT_ShopTools holds one row per tool; ItemLoadoutLimit is how many of it fit in the loadout.
-- F6 prints every row to the log and raises the limit to LOADOUT_LIMIT. (Host side; clients keep their own table.)
local LOADOUT_LIMIT = 16
local DT_PATH = "/Game/Tugrul/Blueprints/Item/DT_ShopTools.DT_ShopTools"
local F_LIMIT = "ItemLoadoutLimit_29_0441D4334FED280A9C9429A6B0A31B77"
local F_PRICE = "ItemPrice_17_885280F3480ED791E4E5E985AC777049"
local F_TAG = "ItemTag_26_6B9BFBAD4FEA632417CAE6A493B8B1EC"
local loggedRows = {}
local function patchLoadoutLimits(verbose)
    local dt = StaticFindObject(DT_PATH)
    if not valid(dt) then
        if verbose then log("DT_ShopTools not loaded yet (open the shop / loadout screen once)") end
        return false
    end
    local rows, changed = 0, 0
    local ok, err = pcall(function()
        dt:ForEachRow(function(rowName, row)
            rows = rows + 1
            local limit = pget(row, F_LIMIT)
            local name = tostring(rowName)
            if type(rowName) == "userdata" then
                local okn, s = pcall(function() return rowName:ToString() end)
                if okn and s then name = tostring(s) end
            end
            -- log the ORIGINAL limit once per row (also on the automatic pass), so the game's own values are on record
            if verbose or not loggedRows[name] then
                loggedRows[name] = true
                log("tool row %s price=%s limit=%s", name, tostring(pget(row, F_PRICE)), tostring(limit))
            end
            -- raised tools get their raised limit, every other tool its own game limit (this also puts back rows that an
            -- earlier version of the mod had raised to 16 in memory)
            local want = VANILLA_LIMIT[name]
            if want and type(limit) == "number" and limit ~= want then
                row[F_LIMIT] = want
                changed = changed + 1
            end
        end)
    end)
    if not ok then log("DT_ShopTools ForEachRow failed: %s", tostring(err)) return false end
    log("DT_ShopTools: %d rows, %d limits set (Flashlight/Candle 16, Glass 4, the rest default)", rows, changed)
    return rows > 0
end
-- also patch automatically once the table has been loaded (bounded retries, no polling forever)
local limitTries = 0
local limitDone = false
LoopAsync(5000, function()                                   -- (the table is read and written on the game thread)
    if limitDone then return true end
    limitTries = limitTries + 1
    ExecuteInGameThread(function()
        local ok, done = pcall(patchLoadoutLimits, false)
        if ok and done then limitDone = true end
    end)
    return limitTries >= 60
end)

---------------------------------------------------------------- leave in the van without waiting for everybody (F4 x2)
-- The LateJoin mod has the same key (with the late-joiner fixes). Two mods on one key would run twice, so this copy only exists when LateJoin is not installed.
local function lateJoinInstalled()
    -- the Mods folder is found from this script's own path (...\Mods\<this mod>\Scripts\main.lua), so no install path is hard-coded
    local src = debug.getinfo(1, "S").source or ""
    local mods = src:gsub("^@", ""):match("^(.*)[\\/][^\\/]+[\\/]Scripts[\\/][^\\/]+$")
    if not mods then return false end
    local function read(p) local f = io.open(p, "rb") if not f then return nil end local s = f:read("*a") or "" f:close() return s end
    if read(mods .. "\\LateJoin\\enabled.txt") then return true end
    local list = read(mods .. "\\mods.txt")
    return list ~= nil and list:find("LateJoin%s*:%s*1") ~= nil
end
local LEAVE_NAME = CFG.leave_key
local LEAVE_OFF = LEAVE_NAME == "NONE" or LEAVE_NAME == "OFF" or LEAVE_NAME == "AUCUNE" or LEAVE_NAME == "NON" or LEAVE_NAME == ""
local LEAVE_KEY = not LEAVE_OFF and type(Key) == "table" and Key[LEAVE_NAME] or nil
if LEAVE_OFF then
    log("leave key: off (settings.txt)")
elseif LEAVE_KEY == nil then
    log("leave key: unknown key name '%s' in settings.txt (examples: F4, F7, END, DEL) - off", tostring(LEAVE_NAME))
elseif LEAVE_NAME == "F4" and lateJoinInstalled() then
    log('F4 x2: LateJoin is installed, it handles the key')
else
    -- F4 = leave the match NOW, without the van and without waiting for anybody (press twice within 4 s to confirm).
    -- It runs the last step of the van's own flow: the host's controller asks the server to end the game for the van
    -- interaction (the same call the confirmation window makes after "ReturnToLobby").
    local armedAt = 0
    -- The handler used to call FindAllOf / RequestEndGameServer / ReturnToLobby straight from the key-press thread, in parallel
    -- with the game thread. The 39 exits of one evening: 6 froze inside that call (only on three maps), 33 did not. Now the
    -- whole body runs on the game thread, like the other keys (F3, F6, F8, F9).
    log("leave key: %s pressed twice within 4 s", LEAVE_NAME)
    RegisterKeyBind(LEAVE_KEY, function() ExecuteInGameThread(function()
        local now = os.time()
        if now - armedAt > 4 then
            armedAt = now
            log("leave: armed, press %s again within 4 s", LEAVE_NAME)
            return
        end
        armedAt = 0
        TRAVEL.mark("F4 leave", 25)
        log("leave: step 1, looking for the van")
        local inter = FindFirstOf("BP_EndGameExitInteraction_C")
        local gp = StaticFindObject("/Script/Engine.Default__GameplayStatics")
        if not valid(inter) then
            log("leave: no van interaction in this level (are you in a match?)")
            return
        end
        log("leave: step 2, local controller")
        local pc = gp:GetPlayerController(inter, 0)
        if not valid(pc) then log("leave: no local controller") return end
        -- Both times the game froze inside the call below (22:24 and 00:08, no further log line, for every player)
        -- somebody in the match was already dead; the one call that worked (19:49) had nobody dead. So refuse then.
        local deadCount, total = 0, 0
        local pss = FindAllOf("BP_Shivers_InGamePlayerState_C")
        if pss then
            for _, ps in ipairs(pss) do
                if valid(ps) then
                    total = total + 1
                    if pget(ps, "IsPlayerDead") == true then deadCount = deadCount + 1 end
                end
            end
        end
        -- A late joiner has a plain PlayerState (no dead flag), so the count above misses him when he is dead. Every dead
        -- player has a spectator body, so count those too: the van path (RequestEndGameServer) froze the game three times
        -- (22:24, 00:08, 02:52) whenever somebody in the match was dead.
        local specs = FindAllOf("BP_SpectatorCharacter_C")
        local specCount = 0
        if specs then for _, sp in ipairs(specs) do if valid(sp) then specCount = specCount + 1 end end end
        if specCount > deadCount then deadCount = specCount end
        log("leave: step 3, dead players %d of %d (spectator bodies: %d)", deadCount, total, specCount)
        if deadCount > 0 then
            -- With dead players the van path froze the game. The game ends a match by itself when everybody is dead,
            -- and the function that does the ending is GameInstance:EndGame(): use that one directly instead.
            -- GameInstance:EndGame() returned at once and changed nothing (3 calls, 01:00-01:01, no map change), so
            -- use the in-game state's own ReturnToLobby() instead (the game state is what ends a match).
            local gs = FindFirstOf("BP_Shivers_InGameState_C")
            if not valid(gs) then log("leave: no in-game state") return end
            log("leave: step 4b, %d dead -> calling InGameState:ReturnToLobby() (experimental)", deadCount)
            local oke, erre = pcall(function() gs:ReturnToLobby() end)
            log("leave: ReturnToLobby() -> %s", oke and "returned" or tostring(erre))
            return
        end
        log("leave: step 4, calling RequestEndGameServer")
        pcall(function() inter.ShiversController = pc end)
        local ok, err = pcall(function() pc:RequestEndGameServer(inter) end)
        log("leave: RequestEndGameServer -> %s", ok and "called" or tostring(err))
        if not ok then
            local ok2, err2 = pcall(function() inter:RequestEndGame("ReturnToLobby") end)
            log("leave: RequestEndGame(ReturnToLobby) -> %s", ok2 and "called" or tostring(err2))
            ok = ok2
        end
    end) end)
end


---------------------------------------------------------------- on-screen badge
-- A small, faded line in the bottom-right corner ("16-player mod active") shows that the mod runs. It is a TextBlock added
-- to the game's own crosshair HUD widget, the one widget that is in the viewport in the safe house and in a match alike (an
-- empty UserWidget cannot be created from Lua: the class is abstract). It never takes clicks (HitTestInvisible).
-- The safe-house TV menus also get "| 16-player mod" after the game's version number.
-- settings.txt "indicator": ON = in the safe house, and the first 20 s of a match; ALWAYS = always; OFF = off.
do
    local MODE = CFG.indicator
    local LABEL = string.format("%d-player mod active", TARGET)
    local MATCH_SHOW = 20                     -- seconds the badge stays in a match (MODE ON)
    local HIT_TEST_INVISIBLE, COLLAPSED = 3, 1                -- ESlateVisibility
    local H_RIGHT, V_BOTTOM = 3, 3                            -- EHorizontalAlignment::HAlign_Right, EVerticalAlignment::VAlign_Bottom
    local label, host = nil, nil
    local lastEpoch, epochAt, tries, tvDone, hidden = -1, 0, 0, false, false

    local function alive()
        if not (valid(label) and valid(host)) then return false end
        local ok, inv = pcall(function() return host:IsInViewport() end)
        return ok and inv == true
    end

    local function attach()
        local hud = FindFirstOf("WBP_Crosshair_C")
        if not valid(hud) then return false, "no crosshair widget yet" end
        local tree = hud.WidgetTree
        local root = valid(tree) and tree.RootWidget or nil
        if not valid(root) then return false, "crosshair has no root panel" end
        local t = StaticConstructObject(StaticFindObject("/Script/UMG.TextBlock"), tree)
        if not valid(t) then return false, "TextBlock not created" end
        t:SetText(FText(LABEL))
        pcall(function() t:SetColorAndOpacity({ SpecifiedColor = { R = 1, G = 1, B = 1, A = 0.5 }, ColorUseRule = 0 }) end)
        pcall(function() t:SetShadowOffset({ X = 1, Y = 1 }) end)
        pcall(function() t:SetShadowColorAndOpacity({ R = 0, G = 0, B = 0, A = 0.6 }) end)
        pcall(function() t:SetVisibility(HIT_TEST_INVISIBLE) end)
        local okC, isCanvas = pcall(function() return root:IsA(StaticFindObject("/Script/UMG.CanvasPanel")) end)
        local how
        if okC and isCanvas then
            local slot = root:AddChildToCanvas(t)
            pcall(function() slot:SetAnchors({ Minimum = { X = 1, Y = 1 }, Maximum = { X = 1, Y = 1 } }) end)
            pcall(function() slot:SetAlignment({ X = 1, Y = 1 }) end)
            pcall(function() slot:SetPosition({ X = -18, Y = -12 }) end)
            pcall(function() slot:SetAutoSize(true) end)
            pcall(function() slot:SetZOrder(100) end)
            how = "canvas"
        else
            local slot = root:AddChild(t)
            pcall(function() slot:SetHorizontalAlignment(H_RIGHT) end)
            pcall(function() slot:SetVerticalAlignment(V_BOTTOM) end)
            pcall(function() slot:SetPadding({ Left = 0, Top = 0, Right = 18, Bottom = 12 }) end)
            how = "panel"
        end
        -- the TextBlock's default font is 24 pt: scaled down from its bottom-right corner
        pcall(function() t:SetRenderTransformPivot({ X = 1, Y = 1 }) end)
        pcall(function() t:SetRenderScale({ X = 0.6, Y = 0.6 }) end)
        label, host = t, hud
        return true, how
    end

    local function markTV()
        local tvs = FindAllOf("WBP_SmartTVTopInfo_C")
        if not tvs then return false end
        local n = 0
        for _, tv in ipairs(tvs) do
            local okT, txt = pcall(function() return tv.VerTxt end)
            if okT and valid(txt) then
                local okS, s = pcall(function() return txt:GetText():ToString() end)
                if okS and type(s) == "string" and s ~= "" and not s:find("-player mod", 1, true) then
                    pcall(function() txt:SetText(FText(s .. "  |  " .. TARGET .. "-player mod")) end)
                    n = n + 1
                end
            end
        end
        if n > 0 then log("badge: version text of %d TV menu(s) marked", n) end
        return true
    end

    if MODE == "OFF" then
        log("badge: off (settings.txt)")
    else
        LoopAsync(3000, function()
            if not travelOK() then return false end
            local ep = TRAVEL.epoch or 0
            if ep ~= lastEpoch then lastEpoch, epochAt, tries, tvDone, hidden, label, host = ep, os.clock(), 0, false, false, nil, nil end
            local inMatch = not IN_LOBBY_MAP
            local expired = inMatch and MODE ~= "ALWAYS" and os.clock() - epochAt > MATCH_SHOW
            if IN_LOBBY_MAP and not tvDone then tvDone = markTV() end
            if alive() then
                if expired and not hidden then
                    hidden = true
                    pcall(function() label:SetVisibility(COLLAPSED) end)
                end
                return false
            end
            if label ~= nil then label, host, tries = nil, nil, 0 end      -- the HUD was rebuilt (respawn, spectator...): add it again
            if expired or tries >= 6 then return false end                   -- (at most 6 lookups per map: FindFirstOf scans the objects)
            tries = tries + 1
            local ok, done, how = pcall(attach)
            if ok and done then log("badge: shown (%s, %s)", how, inMatch and "match" or "safe house")
            elseif tries == 6 then log("badge: not shown on this map (%s)", ok and tostring(how or done) or tostring(done)) end
            return false
        end)
    end
end

log("loaded (target %d players)", TARGET)
