-- FrogCam: third-person chase camera for Entropy Survivors.
-- Loaded by main.lua (and again by `frogcam reload`); state lives in FROGCAM.S so a reload keeps the view.
--
-- How it works
--   view   : a CameraActor of our own becomes the view target while FrogCam is on, placed behind the hero
--            along the mouse-look yaw. The game's BP_GlobalTrackingCamera keeps running untouched, so
--            spawning / off-screen logic that relies on it is unaffected.
--   aim    : the game aims the frog at the mouse cursor (deprojected through the active view). The cursor
--            (the game's crosshair widget, so it doubles as the reticle) is parked every frame on the
--            screen position of a ground point straight ahead of the hero, so the game's own aiming code
--            points the frog where the camera looks.
--   look   : mouse movement is read as the distance the cursor moved from where it was parked.
--   move   : nothing to do: the game builds WASD input from the active view's rotation, so with our camera
--            as the view target, W already walks where the camera looks.
local A = FROGCAM
local S = A.S
local log, valid, addr = A.log, A.valid, A.addr

local CFG = A.dir .. "FrogCam.cfg"
local DEFAULTS = {
    dist = 700.0,       -- camera distance behind the pivot
    height = 300.0,     -- pivot height above the hero's centre (higher = can look up a little further)
    shoulder = 0.0,     -- sideways pivot offset (+ = right)
    fov = 75.0,
    sens = 0.12,        -- degrees per mouse pixel
    invert = 0,         -- 1 = invert mouse Y
    pmin = -60.0,       -- lowest camera pitch (looking down)
    pmax = 30.0,        -- highest camera pitch; in practice looking up stops sooner, see upMax in the tick
    retlow = 0.9,       -- safety net: lowest the (hidden) cursor may go on screen (fraction of the height);
                        -- reaching it stops the camera tilting further up
    retcenter = 1,      -- 1 = always draw the reticle mid-screen, 0 = draw it where the cursor really is
    aimmin = 250.0,     -- the aim point never comes closer to the hero than this
    aimmax = 3000.0,    -- ... nor goes farther
    aimz = 182.0,       -- height of the game's aim plane above the hero's centre (measured)
    hpmove = 1,         -- 1 = show the health bar at a fixed screen spot, 0 = where the game puts it
    hpx = 0.25,         -- health bar screen position, fraction of the width (0 = left edge)
    hpy = 0.85,         -- ... and of the height (0 = top edge)
    hint = 1,           -- 1 = show the key hint at the top of the screen when FrogCam switches on
    freekey = "LeftControl", -- hold to free the mouse pointer (an Unreal key name, e.g. LeftControl, Tab, B)
    debug = 0,          -- 1 = write a status line to FrogCam.log once a second (for troubleshooting)
}
local CFG_ORDER = { "dist", "height", "shoulder", "fov", "sens", "invert", "pmin", "pmax", "retlow", "retcenter", "aimmin", "aimmax", "aimz", "hpmove", "hpx", "hpy", "hint", "freekey", "debug" }
local DIST_PRESETS = { 450.0, 700.0, 1100.0 }

S.cfg = S.cfg or {}
for k, v in pairs(DEFAULTS) do if S.cfg[k] == nil then S.cfg[k] = v end end
S.yaw = S.yaw or 0.0
S.pitch = S.pitch or -18.0
S.frame = S.frame or 0
if S.on == nil then S.on = true end

local function clamp(v, lo, hi) if v < lo then return lo end; if v > hi then return hi end; return v end
local function wrap(a) while a > 180 do a = a - 360 end; while a < -180 do a = a + 360 end; return a end

-- settings are numbers, except the few whose default is a string (key names)
local function setCfg(k, v)
    if DEFAULTS[k] == nil or v == nil then return false end
    if type(DEFAULTS[k]) == "string" then
        if not tostring(v):match("^[%w_]+$") then return false end
        S.cfg[k] = tostring(v)
    else
        local n = tonumber(v); if n == nil then return false end
        S.cfg[k] = n
    end
    return true
end
local function loadCfg()
    local f = io.open(CFG, "r"); if not f then return end
    for line in f:lines() do
        local k, v = line:match("^%s*([%w_]+)%s*=%s*(%S+)")
        if k then setCfg(k, v) end
    end
    f:close()
end
local function saveCfg()
    local f = io.open(CFG, "w"); if not f then return end
    for _, k in ipairs(CFG_ORDER) do
        local v = S.cfg[k]
        f:write(k .. "=" .. (type(v) == "number" and string.format("%.4f", v) or tostring(v)) .. "\n")
    end
    f:close()
end
if not S.cfgLoaded then loadCfg(); S.cfgLoaded = true end

local function lib(path)
    local o = StaticFindObject(path)
    if not valid(o) then error("not found: " .. path) end
    return o
end

-- ---------------------------------------------------------------- keys (polled on the game thread)
local function keyDown(pc, name)
    S.keys = S.keys or {}
    local k = S.keys[name]
    if k == nil then k = { KeyName = FName(name) }; S.keys[name] = k end
    return pc:IsInputKeyDown(k) == true
end
local function keyPressed(pc, name)
    S.keyState = S.keyState or {}
    local was = S.keyState[name]
    local down = keyDown(pc, name)
    S.keyState[name] = down
    return down and was == false        -- nil on the first poll: a key already held is ignored
end

-- ---------------------------------------------------------------- camera actor
local function ensureCamera(pawn)
    if valid(S.camActor) then return S.camActor end
    local l = pawn:K2_GetActorLocation()
    local cam = pawn:GetWorld():SpawnActor(lib("/Script/Engine.CameraActor"), { X = l.X, Y = l.Y, Z = l.Z + 500 }, { Pitch = S.pitch, Yaw = S.yaw, Roll = 0 })
    if not valid(cam) then error("could not spawn camera") end
    local comp = cam.CameraComponent
    comp.bConstrainAspectRatio = false
    comp.FieldOfView = S.cfg.fov
    S.camActor = cam
    log("camera spawned: " .. A.fname(cam))
    return cam
end

local function isGameCamera(o)
    return valid(o) and A.fname(o):find("BP_GlobalTrackingCamera", 1, true) ~= nil
end

-- The health bar is drawn where the hero's PlayerHealthCompass component projects on screen. Seen from
-- above that is just below the hero; seen from behind it lands on the HUD ring around the mech's feet.
-- While FrogCam is on, the component is moved every frame to a point just in front of our camera that
-- projects to a fixed screen spot (hpx, hpy as fractions of the screen), so the bar sits there like a HUD.
-- `cam` is our camera this frame ({x,y,z,pitch,yaw,fov}); nil restores the game's placement.
local function placeHealthBar(pawn, cam)
    local comp = nil; pcall(function() comp = pawn.PlayerHealthCompass end)
    if not valid(comp) then return end
    if cam and S.cfg.hpmove ~= 0 and S.vw then
        if S.hpRel == nil then
            local r = comp.RelativeLocation; S.hpRel = { X = r.X, Y = r.Y, Z = r.Z }
            pcall(function() log("health bar compass: edge " .. tostring(comp.EdgePercent)) end)
        end
        local depth = 300.0
        local focal = (S.vw / 2) / math.tan(math.rad(cam.fov) / 2)
        local side = (S.cfg.hpx * S.vw - S.vw / 2) / focal * depth
        local up = -(S.cfg.hpy * S.vh - S.vh / 2) / focal * depth
        local p, y = math.rad(cam.pitch), math.rad(cam.yaw)
        local fx, fy, fz = math.cos(p) * math.cos(y), math.cos(p) * math.sin(y), math.sin(p)
        local rx, ry = -math.sin(y), math.cos(y)
        local ux, uy, uz = -math.sin(p) * math.cos(y), -math.sin(p) * math.sin(y), math.cos(p)
        comp:K2_SetWorldLocation({
            X = cam.x + fx * depth + rx * side + ux * up,
            Y = cam.y + fy * depth + ry * side + uy * up,
            Z = cam.z + fz * depth + uz * up }, false, {}, true)
    elseif S.hpRel ~= nil then
        comp:K2_SetRelativeLocation(S.hpRel, false, {}, true)
        S.hpRel = nil
    end
end

-- The reticle is the game's software mouse cursor (Widget_CrosshairMouseCursor, kept by the game
-- instance), drawn wherever the cursor is. The cursor itself has to sit on the aim point, which is often
-- not mid-screen; the widget is shifted by the difference so the reticle is always drawn at the centre.
-- (sx, sy) = where the cursor really is, in viewport pixels; nil puts the reticle back on the cursor.
local function placeReticle(pc, sx, sy)
    if not valid(S.reticle) then
        S.reticle = nil
        -- the cursor widget's own offset is ignored when it is drawn as the cursor; its content box (and
        -- everything in it) is shifted instead
        pcall(function()
            local w = lib("/Script/Engine.Default__GameplayStatics"):GetGameInstance(pc).MouseCursor
            S.reticle = w.ScaleBox_0
            if not valid(S.reticle) then S.reticle = w end
            log("reticle widget: " .. A.fname(S.reticle))
        end)
        if not valid(S.reticle) then S.reticle = nil; return end
    end
    if sx and S.cfg.retcenter ~= 0 then
        -- widget offsets are in UI units, the cursor in pixels: divide by the UI (DPI) scale
        local scale = 1.0
        pcall(function() scale = lib("/Script/UMG.Default__WidgetLayoutLibrary"):GetViewportScale(pc) end)
        if not scale or scale <= 0 then scale = 1.0 end
        S.reticle:SetRenderTranslation({ X = (S.vw / 2 - sx) / scale, Y = (S.vh / 2 - sy) / scale })
        S.reticleShifted = true
    elseif S.reticleShifted then
        S.reticle:SetRenderTranslation({ X = 0, Y = 0 })
        S.reticleShifted = false
    end
end

-- ---------------------------------------------------------------- on-screen hint
-- A line of text at the top of the screen telling players how to get the mouse pointer back (hub pop-ups
-- need it) and the other keys. Shown when FrogCam first switches on and after F5 turns it back on.
-- Built from Lua like AscentFPS's widgets: a UserWidget with its own WidgetTree, a CanvasPanel and a
-- TextBlock. (PrintString's on-screen text is compiled out of shipping builds.)
local VIS_COLLAPSED, VIS_HIT_TEST_INVISIBLE = 1, 3
local HINT_SECONDS = 8.0
if S.hintPending == nil then S.hintPending = true end

-- "LeftControl" -> "LEFT CONTROL"
local function keyLabel(name)
    return (tostring(name):gsub("(%l)(%u)", "%1 %2"):upper())
end
local function hintText()
    return "FROGCAM   -   hold " .. keyLabel(S.cfg.freekey) .. " for the mouse pointer   |   F5  top-down view   |   F6  camera distance"
end

local function buildHint(pc)
    local gi = lib("/Script/Engine.Default__GameplayStatics"):GetGameInstance(pc)
    if not valid(gi) then error("no game instance") end
    S.hintN = (S.hintN or 0) + 1
    local w = StaticConstructObject(lib("/Script/UMG.UserWidget"), gi, FName("FrogCam_Hint_" .. S.hintN))
    local tree = StaticConstructObject(lib("/Script/UMG.WidgetTree"), w, FName("FrogCam_Tree"))
    w.WidgetTree = tree
    local canvas = StaticConstructObject(lib("/Script/UMG.CanvasPanel"), tree, FName("FrogCam_Canvas"))
    tree.RootWidget = canvas
    local tb = StaticConstructObject(lib("/Script/UMG.TextBlock"), canvas, FName("FrogCam_HintText"))
    tb.Font.Size = 16
    local c = tb.ColorAndOpacity.SpecifiedColor                       -- the game's gold hint colour
    c.R = 1.0; c.G = 0.78; c.B = 0.15; c.A = 1.0
    tb.ShadowOffset.X = 1.5; tb.ShadowOffset.Y = 1.5
    tb.ShadowColorAndOpacity.R = 0; tb.ShadowColorAndOpacity.G = 0; tb.ShadowColorAndOpacity.B = 0; tb.ShadowColorAndOpacity.A = 0.9
    -- layout is written into the slot before the Slate widget exists
    local slot = canvas:AddChildToCanvas(tb)
    local ld = slot.LayoutData
    ld.Anchors.Minimum.X = 0.5; ld.Anchors.Minimum.Y = 0.07; ld.Anchors.Maximum.X = 0.5; ld.Anchors.Maximum.Y = 0.07
    ld.Alignment.X = 0.5; ld.Alignment.Y = 0.0
    ld.Offsets.Left = 0; ld.Offsets.Top = 0; ld.Offsets.Right = 100; ld.Offsets.Bottom = 30
    slot.bAutoSize = true
    tb:SetText(FText(hintText()))
    w:SetVisibility(VIS_COLLAPSED)
    w:AddToViewport(-40)       -- under the game's own menus
    return w
end

local function showHint(pc)
    if S.cfg.hint == 0 then return end
    if not (valid(S.hint) and S.hint:IsInViewport() == true) then
        if (S.hintFails or 0) >= 3 then return end
        local ok, r = pcall(buildHint, pc)
        if not ok then S.hintFails = (S.hintFails or 0) + 1; log("hint: " .. tostring(r)); return end
        S.hint = r
    end
    S.hint:SetRenderOpacity(1.0)
    S.hint:SetVisibility(VIS_HIT_TEST_INVISIBLE)
    S.hintLeft = HINT_SECONDS
end

local function hideHint()
    S.hintLeft = nil
    if valid(S.hint) then S.hint:SetVisibility(VIS_COLLAPSED) end
end

local function tickHint(dt)
    if not S.hintLeft then return end
    S.hintLeft = S.hintLeft - dt
    if S.hintLeft <= 0 then hideHint()
    elseif S.hintLeft < 1.0 and valid(S.hint) then S.hint:SetRenderOpacity(S.hintLeft) end   -- fade out
end

-- hand the view back to the game
local function deactivate(pc, why)
    if not S.active then return end
    S.active = false; S.look = false; S.lastMX = nil
    log("off (" .. tostring(why) .. ")")
    pcall(hideHint)
    if valid(pc) then
        pcall(function() placeHealthBar(pc.Pawn, nil) end)
        pcall(placeReticle, pc, nil, nil)
        pcall(function()
            local cur = pc.PlayerCameraManager.ViewTarget.Target
            if valid(S.camActor) and addr(cur) == addr(S.camActor) then
                local back = isGameCamera(S.gameCam) and S.gameCam or FindFirstOf("BP_GlobalTrackingCamera_C")
                if valid(back) then pc:SetViewTargetWithBlend(back, 0.25, 0, 0.0, false) end
            end
        end)
    end
end

-- world point -> viewport pixels for a camera at (cx,cy,cz) with pitch/yaw (deg) and horizontal FOV
local function project(px, py, pz, cam, vw, vh)
    local p, y = math.rad(cam.pitch), math.rad(cam.yaw)
    local fx, fy, fz = math.cos(p) * math.cos(y), math.cos(p) * math.sin(y), math.sin(p)
    local rx, ry = -math.sin(y), math.cos(y)
    local ux, uy, uz = -math.sin(p) * math.cos(y), -math.sin(p) * math.sin(y), math.cos(p)
    local dx, dy, dz = px - cam.x, py - cam.y, pz - cam.z
    local depth = dx * fx + dy * fy + dz * fz
    if depth < 1.0 then return nil end
    local side = dx * rx + dy * ry
    local up = dx * ux + dy * uy + dz * uz
    local focal = (vw / 2) / math.tan(math.rad(cam.fov) / 2)
    return vw / 2 + side / depth * focal, vh / 2 - up / depth * focal
end

-- ---------------------------------------------------------------- controller tick (also runs while paused)
function A.pcTick(Context, Delta)
    local pc = Context:get()
    if not valid(pc) then return end
    if pc:IsLocalPlayerController() ~= true then return end
    S.pc = pc
    S.wall = os.clock()

    if keyPressed(pc, "F5") then
        S.on = not S.on
        log("FrogCam " .. (S.on and "on" or "off") .. " (F5)")
        if S.on then S.hintPending = true else deactivate(pc, "F5") end
    end
    if keyPressed(pc, "F6") then
        local idx = 1
        for i, d in ipairs(DIST_PRESETS) do if math.abs(d - S.cfg.dist) < 1 then idx = i end end
        S.cfg.dist = DIST_PRESETS[idx % #DIST_PRESETS + 1]
        saveCfg()
        log("distance = " .. S.cfg.dist)
    end

    if not S.active then return end
    -- the hero stopped ticking without a pause (death, level change): give the view back
    local paused = false
    pcall(function() paused = lib("/Script/Engine.Default__GameplayStatics"):IsGamePaused(pc) == true end)
    if not paused and S.heroT and S.wall - S.heroT > 0.5 then deactivate(pc, "hero gone"); return end
    -- menus / pause: the pointer is the player's again (no more parking it on the aim point)
    if paused or S.inMenu or pc.bPauseMenuUp == true then
        if S.look then S.look = false; S.lastMX = nil end
        placeReticle(pc, nil, nil)      -- the drawn pointer must match the real one for clicking menus
    end
end

-- ---------------------------------------------------------------- hero tick
local function debugLine(pawn, sx, sy)
    if S.cfg.debug == 0 or S.wall - (S.dbgT or -1) < 1.0 then return end
    S.dbgT = S.wall
    local ly, vel = "?", "?"
    pcall(function() ly = string.format("%.1f", pawn.LOCALONLY_Yaw) end)
    if not S.armLogged then         -- once: where the frog's aim arrow sits, to check the aimz setting
        S.armLogged = true
        pcall(function()
            local z0 = pawn:K2_GetActorLocation().Z
            log(string.format("aim arrow %.1f, frog root %.1f above the hero's centre (aimz = %.1f)",
                pawn.AimArrow:K2_GetComponentLocation().Z - z0, pawn.FrogRoot:K2_GetComponentLocation().Z - z0, S.cfg.aimz))
        end)
    end
    pcall(function()
        local v = pawn:GetVelocity()
        local speed = math.sqrt(v.X * v.X + v.Y * v.Y)
        vel = speed < 10 and "still" or string.format("%.0f at %.1f deg", speed, math.deg(math.atan(v.Y, v.X)))
    end)
    log(string.format("cam yaw %.1f pitch %.1f | frog aim %s, %.0f ahead | moving %s | cursor %s,%s | reassert %d | look %s",
        S.yaw, S.pitch, ly, S.aimAhead or 0, vel, tostring(sx and math.floor(sx)), tostring(sy and math.floor(sy)),
        S.reassert or 0, tostring(S.look)))
end

function A.tick(Context, Delta)
    S.step = "start"
    local pawn = Context:get()
    if not valid(pawn) then return end
    local pc = nil; pcall(function() pc = pawn.Controller end)
    if not valid(pc) or pc:IsLocalPlayerController() ~= true then return end
    S.frame = S.frame + 1
    S.wall = os.clock()
    S.heroT = S.wall
    if addr(pawn) ~= S.pawnAddr then
        S.pawnAddr = addr(pawn); S.camActor = nil; S.active = false; S.lastMX = nil; S.hpRel = nil
        log("hero: " .. A.fname(pawn))
    end
    if addr(pc) ~= S.pcHookedAddr and A.hookController then
        S.pcHookedAddr = addr(pc)
        A.hookController(pc)
    end
    local pcm = pc.PlayerCameraManager
    if not valid(pcm) then return end

    -- single player only
    S.step = "coop"
    if S.wall - (S.coopT or -1) > 2.0 then
        S.coopT = S.wall
        local n = 1
        pcall(function() n = pawn:GetWorld().GameState.PlayerArray:GetArrayNum() end)
        local coop = n > 1
        if coop ~= S.coop then log("players = " .. n .. (coop and " - FrogCam is off in co-op" or "")) end
        S.coop = coop
    end
    if not S.on or S.coop then deactivate(pc, S.coop and "co-op" or "off"); return end

    -- only take over from the game's own camera; anything else (cutscene, death cam) is left alone
    S.step = "viewtarget"
    local vt = pcm.ViewTarget.Target
    local cam = ensureCamera(pawn)
    if not (valid(vt) and addr(vt) == addr(cam)) then
        if not isGameCamera(vt) then deactivate(pc, "other view target"); return end
        S.gameCam = vt
        if not S.active then
            -- start looking the way the game's camera looks
            pcall(function() S.yaw = vt.Camera:K2_GetComponentRotation().Yaw end)
            log("on")
        else
            S.reassert = (S.reassert or 0) + 1
        end
        pc:SetViewTargetWithBlend(cam, S.active and 0.0 or 0.3, 0, 0.0, false)
        S.active = true
    end
    S.active = true

    -- look
    S.step = "look"
    if S.wall - (S.vpT or -1) > 0.5 then
        S.vpT = S.wall
        local sz = {}; pc:GetViewportSize(sz, {})
        if type(sz.SizeX) == "number" and sz.SizeX > 0 then S.vw, S.vh = sz.SizeX, sz.SizeY end
    end
    local wl = lib("/Script/UMG.Default__WidgetLayoutLibrary")
    local focused = pc:GetMousePosition({}, {}) == true
    -- holding the free key (freekey, Left Ctrl by default) frees the pointer: hub pop-ups such as "Change
    -- Class - OPEN MENU" are clicked with it but do not count as a menu, so nothing else lets go of it
    local freed = keyDown(pc, S.cfg.freekey)
    local look = S.vw ~= nil and focused and not freed and not S.inMenu and pc.bPauseMenuUp ~= true
    if look ~= S.look then S.look = look; S.lastMX = nil end
    if look then
        local m = wl:GetMousePositionOnPlatform()
        if S.lastMX ~= nil then
            local inv = S.cfg.invert ~= 0 and -1 or 1
            S.yaw = wrap(S.yaw + (m.X - S.lastMX) * S.cfg.sens)
            S.pitch = clamp(S.pitch - (m.Y - S.lastMY) * S.cfg.sens * inv, S.cfg.pmin, S.cfg.pmax)
        end
    end

    S.step = "place"
    local loc = pawn:K2_GetActorLocation()
    local dt = 0.016; pcall(function() dt = Delta:get() end)
    S.step = "hint"
    if S.hintPending then S.hintPending = false; showHint(pc) end
    tickHint(dt)
    S.step = "place"
    -- this tick runs before the character moves this frame: lead by one frame of velocity
    local v = pawn:GetVelocity()
    local bx, by, bz = loc.X + v.X * dt, loc.Y + v.Y * dt, loc.Z
    local yr = math.rad(S.yaw)
    local dx, dy = math.cos(yr), math.sin(yr)
    -- The game turns the cursor into an aim point by meeting it with a flat plane at the frog's gun height
    -- (measured: ~182 above the hero's centre), and that only works while the camera is above the plane:
    -- from below it the frog aims backwards whatever the cursor does. So aim points are chosen on the
    -- plane, and looking up is limited to where the camera is still PLANE_GAP above it.
    -- The game's own aiming also breaks down on long, nearly flat cursor rays (it seems to look only so
    -- far along the ray), so the aim point is kept within MAX_RAY of the camera and the ray to it dips at
    -- least MIN_DIP degrees.
    local planeZ = bz + S.cfg.aimz
    local PLANE_GAP, MAX_RAY, TAN_DIP = 30.0, 3000.0, math.tan(math.rad(1.5))
    local pivZ = bz + S.cfg.height
    local function camHeightOk(pitch)
        local pr = math.rad(pitch)
        local above = pivZ - math.sin(pr) * S.cfg.dist - planeZ
        local reach = math.cos(pr) * S.cfg.dist + S.cfg.aimmin        -- camera -> nearest aim point
        return above >= PLANE_GAP and reach <= MAX_RAY and above >= TAN_DIP * reach
    end
    if not camHeightOk(S.pitch) then
        local lo, hi = S.cfg.pmin, S.pitch                             -- highest pitch that still works
        for _ = 1, 16 do local mid = (lo + hi) / 2; if camHeightOk(mid) then lo = mid else hi = mid end end
        S.pitch = lo
    end

    -- The camera for a given pitch, and the aim point it gives: where the screen centre meets the aim
    -- plane, kept straight ahead of the hero between aimmin and aimmax (the reticle is drawn mid-screen
    -- regardless, see placeReticle).
    local function view(pitch)
        local pr = math.rad(pitch)
        local fx, fy, fz = math.cos(pr) * dx, math.cos(pr) * dy, math.sin(pr)
        local pivX = bx - dy * S.cfg.shoulder
        local pivY = by + dx * S.cfg.shoulder
        local dist = S.cfg.dist
        local c = { x = pivX - fx * dist, y = pivY - fy * dist, z = pivZ - fz * dist,
                    pitch = pitch, yaw = S.yaw, fov = S.cfg.fov }
        local back = (bx - c.x) * dx + (by - c.y) * dy                -- camera -> hero, along the view
        local far = math.min(S.cfg.aimmax, MAX_RAY - back, (c.z - planeZ) / TAN_DIP - back)
        far = math.max(far, S.cfg.aimmin)
        local ahead = far
        if math.abs(fz) > 0.001 then
            local t = (planeZ - c.z) / fz                    -- centre ray -> aim plane
            if t > 0 then
                local hx, hy = c.x + fx * t - bx, c.y + fy * t - by
                ahead = clamp(hx * dx + hy * dy, S.cfg.aimmin, far)
            end
        end
        local ax, ay = bx + dx * ahead, by + dy * ahead
        local sx, sy = nil, nil
        if S.vw then sx, sy = project(ax, ay, planeZ, c, S.vw, S.vh) end
        return c, ahead, ax, ay, sx, sy
    end

    local c, ahead, ax, ay, sx, sy = view(S.pitch)
    -- Safety net: the cursor has to stay on screen. Should the aim point ever sink past the retlow line
    -- the camera stops tilting up instead (so moving the mouse back down responds at once - no dead zone).
    if S.vh then
        local lim = S.cfg.retlow * S.vh
        local focal = (S.vw / 2) / math.tan(math.rad(S.cfg.fov) / 2)
        -- the camera drops as it tilts up, which moves the aim point on screen too: a few passes settle it
        for _ = 1, 4 do
            if sy ~= nil and sy <= lim + 1 then break end
            local hd = (ax - c.x) * dx + (ay - c.y) * dy
            local e = math.deg(math.atan(planeZ - c.z, hd)) -- the aim point's angle from the camera
            local pmax = e + math.deg(math.atan(lim - S.vh / 2, focal))
            if pmax >= S.pitch then break end
            S.pitch = clamp(pmax, S.cfg.pmin, S.cfg.pmax)
            c, ahead, ax, ay, sx, sy = view(S.pitch)
        end
    end
    S.aimAhead = ahead

    cam:K2_SetActorLocationAndRotation({ X = c.x, Y = c.y, Z = c.z }, { Pitch = c.pitch, Yaw = c.yaw, Roll = 0 }, false, {}, true)
    local comp = cam.CameraComponent
    if comp.FieldOfView ~= S.cfg.fov then comp.FieldOfView = S.cfg.fov end
    S.step = "health bar"
    placeHealthBar(pawn, c)

    -- park the cursor (the reticle) on the aim point
    S.step = "aim"
    if look then
        if sx == nil then sx, sy = S.vw / 2, S.cfg.retlow * S.vh end
        sx = clamp(sx, 2, S.vw - 3); sy = clamp(sy, 2, S.vh - 3)
        pc:SetMouseLocation(math.floor(sx + 0.5), math.floor(sy + 0.5))
        local r = wl:GetMousePositionOnPlatform()      -- the reference is re-read after the warp, never assumed
        S.lastMX, S.lastMY = r.X, r.Y
    else
        sx, sy = nil, nil
    end
    S.step = "reticle"
    placeReticle(pc, sx, sy)

    debugLine(pawn, sx, sy)
    S.step = "done"
end

-- ---------------------------------------------------------------- console: frogcam <name> <value>
function A.command(p)
    local a1 = string.lower(tostring(p[1] or ""))
    if a1 == "reset" then for k, v in pairs(DEFAULTS) do S.cfg[k] = v end; saveCfg(); return "reset"
    elseif a1 == "toggle" then S.on = not S.on; if not S.on and valid(S.pc) then deactivate(S.pc, "console") end; return "on=" .. tostring(S.on)
    elseif DEFAULTS[a1] ~= nil then
        if p[2] ~= nil and setCfg(a1, p[2]) then
            saveCfg()
            if a1 == "freekey" then hideHint(); if valid(S.hint) then S.hint:RemoveFromParent() end; S.hint = nil end   -- rebuilt with the new key name
        end
        return a1 .. "=" .. tostring(S.cfg[a1])
    end
    local t = {}
    for _, k in ipairs(CFG_ORDER) do t[#t + 1] = k .. "=" .. tostring(S.cfg[k]) end
    return table.concat(t, " ") .. " | frogcam <name> <value>, frogcam reset, frogcam toggle (F5), frogcam reload"
end
