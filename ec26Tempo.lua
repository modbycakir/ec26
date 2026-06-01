local m = {}
m.version = "ec26 Tempo"
local hex = memory.hex

local tempo_file = ""
local current_tempo = 0.0
local infoText = "GLOBAL TEMPO READY"
local last_key_time = 0

local object_addr
local game_speed_addr

local function speed_value_from_game_speed(game_speed)
    return 1000000 / (54 + game_speed * 3)
end

local function load_global_tempo()
    local f = io.open(tempo_file, "r")
    if f then
        local val = f:read("*a")
        f:close()
        return tonumber(val) or 0.0
    end
    return 0.0
end

local function save_global_tempo()
    local f = io.open(tempo_file, "w")
    if f then
        f:write(string.format("%0.2f", current_tempo))
        f:close()
        return true
    end
    return false
end

local function apply_tempo_to_memory()
    if not game_speed_addr then return end
    local value = speed_value_from_game_speed(current_tempo)
    memory.write(game_speed_addr, memory.pack("d", value))
end

local function get_game_speed_addr()
    local mpointer = memory.unpack("i64", memory.read(object_addr, 8))
    if mpointer == 0 then return nil end
    local loc = mpointer + 0x50
    local mpointer2 =  memory.unpack("i64", memory.read(loc), 8)
    if mpointer2 == 0 then return nil end
    return mpointer2 + 0x38
end

function m.overlay_on(ctx)
    if not game_speed_addr then
        game_speed_addr = get_game_speed_addr()
    end
    
    local out = "========================================================================\n"
    out = out .. "        EC 26 MATCH TEMPO     \n"
    out = out .. "========================================================================\n"
    out = out .. string.format(" GLOBAL MATCH TEMPO : >>> %5.2f <<< \n", current_tempo)
    out = out .. "------------------------------------------------------------------------\n"
    out = out .. " [-] : SLOW DOWN  |  [+] : SPEED UP \n"
    out = out .. " [NUM ENTER]/[+] : SAVE TEMPO  |  [NUM 0] : RELOAD TEMPO \n"
    out = out .. "========================================================================\n"
    out = out .. " STATUS: " .. infoText
    
    return out
end

function m.key_down(ctx, vkey)
    local now = os.clock()
    if now - last_key_time < 0.15 then return end
    last_key_time = now

    if vkey == 0xBD then
        current_tempo = current_tempo - 0.05
        apply_tempo_to_memory()
        infoText = "TEMPO ADJUSTED (UNSAVED)"
    elseif vkey == 0xBB then
        current_tempo = current_tempo + 0.05
        apply_tempo_to_memory()
        infoText = "TEMPO ADJUSTED (UNSAVED)"
    elseif vkey == 0x0D or vkey == 0x6B then
        if save_global_tempo() then
            infoText = "GLOBAL TEMPO SAVED!"
        end
    elseif vkey == 0x60 then
        current_tempo = load_global_tempo()
        apply_tempo_to_memory()
        infoText = "TEMPO RELOADED"
    end
end

local function on_set_teams(ctx, home)
    current_tempo = load_global_tempo()
    game_speed_addr = get_game_speed_addr()
    if game_speed_addr then
        apply_tempo_to_memory()
    end
end

function m.init(ctx)
    tempo_file = ctx.sider_dir .. "modules\\ec26_GlobalTempo.txt"

    local pattern1 = "\xf2\x0f\x5e\xce\x48\x8b\x01\xff\x50\x30"
    local loc = memory.search_process(pattern1)
    if not loc then error("ec26Tempo: pattern 1 not found") end
    local signed_offset = memory.unpack("i32", memory.read(loc - 4, 4))
    object_addr = loc + signed_offset

    local pattern2 = "\x41\x0f\x28\xc9\xf2\x0f\x5e\xc8\xf2\x0f\x11\x4e\x38"
    loc = memory.search_process(pattern2)
    if not loc then error("ec26Tempo: pattern 2 not found") end
    memory.write(loc + 8, "\x90\x90\x90\x90\x90")

    current_tempo = load_global_tempo()

    ctx.register("set_teams", on_set_teams)
    ctx.register("overlay_on", m.overlay_on)
    ctx.register("key_down", m.key_down)
end

return m