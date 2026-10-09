-- FrogCamProbe: read-only discovery for a third-person camera mod.
-- Press F7 in a run (frog + mech on screen). Writes FrogCamProbe.log next to this mod folder.
local src = debug.getinfo(1, "S").source or ""
local MOD_DIR = src:match("^@?(.*[\\/])[Ss]cripts[\\/][^\\/]*$") or "Mods\\FrogCamProbe\\"
local LOG = MOD_DIR .. "FrogCamProbe.log"

local lines = {}
local function out(s) lines[#lines + 1] = tostring(s) end
local function flush()
    local f = io.open(LOG, "a")
    if f then f:write(table.concat(lines, "\n"), "\n"); f:close() end
    lines = {}
end

local function valid(o)
    if o == nil then return false end
    local ok, r = pcall(function() return o:IsValid() end)
    return ok and r == true
end
local function name(o)
    if not valid(o) then return "<invalid>" end
    local ok, r = pcall(function() return o:GetFullName() end)
    return ok and tostring(r) or "<err>"
end
local function try(label, fn)
    local ok, r = pcall(fn)
    if ok then return r end
    out("  ! " .. label .. ": " .. tostring(r))
    return nil
end
local function vec(v) if not v then return "nil" end; return string.format("(%.1f, %.1f, %.1f)", v.X, v.Y, v.Z) end
local function rot(r) if not r then return "nil" end; return string.format("(P %.1f, Y %.1f, R %.1f)", r.Pitch, r.Yaw, r.Roll) end

local function hierarchy(obj)
    local chain = {}
    try("hierarchy", function()
        local c = obj:GetClass()
        while valid(c) and #chain < 12 do
            chain[#chain + 1] = c:GetFName():ToString()
            c = c:GetSuperStruct()
        end
    end)
    return table.concat(chain, " -> ")
end

local function actorInfo(prefix, a)
    if not valid(a) then out(prefix .. "<invalid>"); return end
    out(prefix .. name(a))
    out(prefix .. "  class: " .. hierarchy(a))
    out(prefix .. "  loc " .. vec(try("loc", function() return a:K2_GetActorLocation() end))
        .. " rot " .. rot(try("rot", function() return a:K2_GetActorRotation() end)))
    try("owner", function() out(prefix .. "  owner: " .. name(a:GetOwner())) end)
    try("parent", function() out(prefix .. "  attachParent: " .. name(a:GetAttachParentActor())) end)
end

local function listAll(className, fn)
    local all = try("FindAllOf " .. className, function() return FindAllOf(className) end)
    if not all then out("  (none)"); return end
    local n = 0
    for _, o in ipairs(all) do
        if valid(o) and not name(o):find("Default__", 1, true) then
            n = n + 1
            if n <= 40 then fn(o) end
        end
    end
    out("  count=" .. n)
end

local function probe()
    out("")
    out("==================== FrogCamProbe " .. os.date("%Y-%m-%d %H:%M:%S") .. " ====================")

    local pcs = FindAllOf("PlayerController") or {}
    for _, pc in ipairs(pcs) do
        if valid(pc) and not name(pc):find("Default__", 1, true) then
            out("[PlayerController] " .. name(pc))
            out("  class: " .. hierarchy(pc))
            try("ctrlRot", function() out("  controlRotation " .. rot(pc.ControlRotation)) end)
            try("cursor", function() out("  bShowMouseCursor=" .. tostring(pc.bShowMouseCursor)) end)
            try("islocal", function() out("  IsLocalController=" .. tostring(pc:IsLocalController())) end)
            local pawn = try("pawn", function() return pc.Pawn end)
            out("  [Possessed pawn]")
            actorInfo("    ", pawn)
            local pcm = try("pcm", function() return pc.PlayerCameraManager end)
            if valid(pcm) then
                out("  [CameraManager] " .. name(pcm))
                out("    class: " .. hierarchy(pcm))
                try("camloc", function() out("    camLoc " .. vec(pcm:GetCameraLocation()) .. " camRot " .. rot(pcm:GetCameraRotation())) end)
                try("fov", function() out("    FOV " .. tostring(pcm:GetFOVAngle())) end)
                try("vt", function() out("    viewTarget: " .. name(pcm.ViewTarget.Target)) end)
                try("pitch", function() out(string.format("    pitch limits %.1f..%.1f", pcm.ViewPitchMin, pcm.ViewPitchMax)) end)
            end
            try("vtpc", function() out("  PC:GetViewTarget: " .. name(pc:GetViewTarget())) end)
        end
    end

    out("[All Pawns]")
    listAll("Pawn", function(p) actorInfo("  ", p) end)

    out("[CameraComponents]")
    listAll("CameraComponent", function(c)
        out("  " .. name(c))
        try("cc", function()
            out("    owner " .. name(c:GetOwner()) .. " active=" .. tostring(c:IsActive())
                .. " FOV=" .. tostring(c.FieldOfView) .. " usePawnCtrlRot=" .. tostring(c.bUsePawnControlRotation)
                .. " proj=" .. tostring(c.ProjectionMode) .. " ortho=" .. tostring(c.OrthoWidth))
            out("    world " .. vec(c:K2_GetComponentLocation()) .. " " .. rot(c:K2_GetComponentRotation()))
            out("    rel   " .. vec(c.RelativeLocation) .. " " .. rot(c.RelativeRotation))
            out("    parent " .. name(c:GetAttachParent()))
        end)
    end)

    out("[SpringArmComponents]")
    listAll("SpringArmComponent", function(s)
        out("  " .. name(s))
        try("sa", function()
            out("    owner " .. name(s:GetOwner()) .. " armLen=" .. tostring(s.TargetArmLength)
                .. " usePawnCtrlRot=" .. tostring(s.bUsePawnControlRotation)
                .. " inheritP/Y/R=" .. tostring(s.bInheritPitch) .. "/" .. tostring(s.bInheritYaw) .. "/" .. tostring(s.bInheritRoll)
                .. " absRot=" .. tostring(s.bAbsoluteRotation) .. " collide=" .. tostring(s.bDoCollisionTest)
                .. " lag=" .. tostring(s.bEnableCameraLag))
            out("    rel " .. vec(s.RelativeLocation) .. " " .. rot(s.RelativeRotation)
                .. " socketOff " .. vec(s.SocketOffset) .. " targetOff " .. vec(s.TargetOffset))
            out("    parent " .. name(s:GetAttachParent()))
        end)
    end)

    out("[CameraActors]")
    listAll("CameraActor", function(a) actorInfo("  ", a) end)

    out("[GameMode/GameState/World]")
    try("gs", function() for _, g in ipairs(FindAllOf("GameStateBase") or {}) do out("  " .. name(g) .. " :: " .. hierarchy(g)) end end)
    try("gm", function() for _, g in ipairs(FindAllOf("GameModeBase") or {}) do out("  " .. name(g) .. " :: " .. hierarchy(g)) end end)
    try("pstates", function() out("  PlayerStates: " .. #(FindAllOf("PlayerState") or {})) end)

    flush()
    print("[FrogCamProbe] probe written to " .. LOG .. "\n")
end

RegisterKeyBind(Key.F7, function()
    ExecuteInGameThread(function()
        local ok, err = pcall(probe)
        if not ok then out("PROBE ERROR: " .. tostring(err)); flush() end
    end)
end)

print("[FrogCamProbe] loaded - press F7 in a run\n")
