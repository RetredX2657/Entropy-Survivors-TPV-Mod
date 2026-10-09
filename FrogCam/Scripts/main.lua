-- FrogCam bootstrap: logging, hooks and the console command.
-- All camera logic lives in frogcam.lua (reloadable with the console command `frogcam reload`);
-- its state is kept in FROGCAM.S so a reload keeps the current view.
-- Everything runs on the game thread, inside hooks: no RegisterKeyBind / LoopAsync (their callbacks
-- come from UE4SS's own threads).
local src = debug.getinfo(1, "S").source or ""
local MOD_DIR = src:match("^@?(.*[\\/])[Ss]cripts[\\/][^\\/]*$") or "Mods\\FrogCam\\"

FROGCAM = FROGCAM or {}
local A = FROGCAM
A.dir = MOD_DIR
A.S = A.S or {}
A.version = "0.3.0"

local LOG = MOD_DIR .. "FrogCam.log"
-- a fresh log every game launch (main.lua runs once per launch; `frogcam reload` only reruns frogcam.lua)
do local f = io.open(LOG, "w"); if f then f:close() end end
function A.log(msg)
    local f = io.open(LOG, "a")
    if f then f:write(os.date("%H:%M:%S ") .. tostring(msg) .. "\n"); f:close() end
end
function A.valid(o)
    if o == nil then return false end
    local ok, res = pcall(function() return o:IsValid() end)
    return ok and res == true
end
function A.addr(o) local a = nil; pcall(function() a = o:GetAddress() end); return a end
function A.fname(o)
    if not A.valid(o) then return "<invalid>" end
    local ok, r = pcall(function() return o:GetFullName() end)
    return ok and tostring(r) or "<err>"
end

function A.reload()
    local chunk, err = loadfile(MOD_DIR .. "Scripts\\frogcam.lua")
    if not chunk then A.log("reload: " .. tostring(err)); return "ERR " .. tostring(err) end
    local ok, e = pcall(chunk)
    if not ok then A.log("reload run: " .. tostring(e)); return "ERR " .. tostring(e) end
    return "loaded"
end

-- Every hook body goes through here, so an error is logged instead of breaking the game.
local function guarded(name, fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then
            A.S.errs = (A.S.errs or 0) + 1
            if A.S.errs <= 30 then A.log(name .. " ERR at step '" .. tostring(A.S.step) .. "': " .. tostring(err)) end
        end
    end
end

-- "BlueprintGeneratedClass /Game/X/BP_Foo.BP_Foo_C" -> "/Game/X/BP_Foo.BP_Foo_C"
local function classPath(obj)
    local full = A.fname(obj:GetClass())
    return full:match("^%S+%s+(.+)$") or full
end

-- ---------------------------------------------------------------- hooks
-- Blueprint hooks fire after the Blueprint function has run (UE4SS: for non-/Script/ paths the
-- callback is a post-hook).
local hooked = {}
local function hookOnce(path, fn)
    if hooked[path] then return end
    local ok, e = pcall(function() RegisterHook(path, fn) end)
    A.log("hook " .. path .. " ok=" .. tostring(ok) .. (ok and "" or (" " .. tostring(e))))
    if ok then hooked[path] = true end
end

local function hookHero(pawn)
    if not A.valid(pawn) then return end
    local full = A.fname(pawn)
    if not full:find("BP_HeroCharacter_C", 1, true) or full:find("Default__", 1, true) then return end
    local cls = classPath(pawn)
    hookOnce(cls .. ":ReceiveTick", guarded("tick", function(Context, Delta)
        if A.tick then A.tick(Context, Delta) end
    end))
end

local function hookController(pc)
    if not A.valid(pc) then return end
    local full = A.fname(pc)
    if not full:find("ESPlayerController", 1, true) or full:find("Default__", 1, true) then return end
    local cls = classPath(pc)
    -- right after construction the controller still reports its native class, which has none of the
    -- Blueprint events; frogcam.lua calls this again from the hero tick once the Blueprint class shows
    if not cls:find("^/Game/") then return end
    -- the controller keeps ticking while the game is paused: that is where the cursor is handed back
    hookOnce(cls .. ":ReceiveTick", guarded("pcTick", function(Context, Delta)
        if A.pcTick then A.pcTick(Context, Delta) end
    end))
    hookOnce(cls .. ":MenuChanged", guarded("menu", function(Context, InMenu)
        local v = false; pcall(function() v = InMenu:get() end)
        A.S.inMenu = v == true
        A.log("menu open = " .. tostring(A.S.inMenu))
    end))
end

A.hookController = hookController

-- The hero and controller announce themselves when spawned; their Blueprint classes are loaded by then.
-- (FindFirstOf/FindAllOf walk every object in the game, so nothing polls with them.)
pcall(function()
    NotifyOnNewObject("/Script/EntropySurvivors.HeroUnitCharacter", function(obj) pcall(hookHero, obj) end)
end)
pcall(function()
    NotifyOnNewObject("/Script/EntropySurvivors.ESPlayerController", function(obj) pcall(hookController, obj) end)
end)
pcall(function()
    RegisterHook("/Script/Engine.PlayerController:ClientRestart", function(Context, NewPawn)
        pcall(function() hookController(Context:get()) end)
        pcall(function() hookHero(NewPawn:get()) end)
    end)
end)
-- mod loaded while already in a level (hot reload of UE4SS mods)
pcall(function()
    local pc = FindFirstOf("BP_ESPlayerController_C")
    if A.valid(pc) then hookController(pc); pcall(function() hookHero(pc.Pawn) end) end
end)

pcall(function()
    RegisterConsoleCommandGlobalHandler("frogcam", function(FullCommand, Parameters, Ar)
        local out = "?"
        local ok, err = pcall(function()
            local p1 = string.lower(tostring(Parameters[1] or ""))
            if p1 == "reload" then out = A.reload()
            elseif A.command then out = A.command(Parameters) end
        end)
        if not ok then out = "error: " .. tostring(err) end
        pcall(function() if Ar then Ar:Log("[frogcam] " .. tostring(out)) end end)
        A.log("[frogcam] " .. tostring(out))
        return true
    end)
end)

A.log("=== FrogCam " .. A.version .. " " .. A.reload() .. " ===")
