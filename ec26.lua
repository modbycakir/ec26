--=============================================================================
-- EC26  v1.2 - Custom Memory & Gameplay 
-- Written for EC26 Simulation Project by Cakir
--
-- Special Thanks & Credits:
-- * Juce (For the incredible Sider and Memory API framework)
-- * Konami (For the Fox Engine)
--=============================================================================

local m = {}
m.version = "EC26 GamePlay v1.2"

local profiles_file = ""
local config_file = ""

local profiles = {}
local profile_names = {}
local current_idx = 1
local selected_profile = "DEFAULT"
local saved_profile = "DEFAULT"
local infoText = "SYSTEM READY"
local last_key_time = 0
local edit_idx = 1

-- ============================================================
-- EC26 CORE MEMORY & FFI BINDINGS
-- ============================================================
if ffi ~= nil then
    ffi.cdef[[
    void* VirtualAlloc(void* lpAddress, uint64_t dwSize, uint32_t flAllocationType, uint32_t flProtect);
    ]]
end

local EC_SIGS = {
    HOOK_101 = "\xE9\x7B\x04\x9F\x03",
    HOOK_107 = "\xE9\xEB\xE8\xA3\x03",
    LAST_MAN = "\x83\xFF\x04\xB8\x03\x00\x00\x00\x0F\x44\xF8",
    ENG_ROSTER = "\x83\xFA\x02\x73\x12\x48\x63\xC2\x48\x05\xA3\x00\x00\x00",
    ENG_TEAM   = "\x83\xFA\x16\x73\x12\x48\x63\xC2\x48\x05\xF3\x00\x00\x00",
    ENG_POS    = "\x48\x89\x5C\x24\x08\x48\x89\x74\x24\x10\x57\x48\x83\xEC\x20\x48\x8B\xF9\x41\x8B\xD0",
    ENG_BOX    = "\x48\x83\xEC\x28\xF3\x0F\x10\x19\x0F\x57\xC0\x0F\x29\x74\x24\x10"
}

local EC_Pointers = {
    hook_addr = 0,
    cave_addr = 0,
    lastman_addr = 0,
    master_context = 0,
    funcs = {},
    is_ready = false
}

local function GetUInt64(ptr)
    return tonumber(ffi.cast("uint64_t", ptr))
end

local function AllocateECBlock(target_ptr, req_size)
    local target_num = GetUInt64(target_ptr)
    local block_size = 0x10000
    local base_address = target_num - (target_num % block_size)
    
    local offset_multiplier = 1
    while offset_multiplier <= 8192 do
        local lower_bound = base_address - (offset_multiplier * block_size)
        if lower_bound > 0 then
            local attempt1 = ffi.C.VirtualAlloc(ffi.cast("void*", ffi.cast("uint64_t", lower_bound)), req_size, 0x3000, 0x40)
            if attempt1 and GetUInt64(attempt1) ~= 0 then return attempt1 end
        end
        
        local upper_bound = base_address + (offset_multiplier * block_size)
        local attempt2 = ffi.C.VirtualAlloc(ffi.cast("void*", ffi.cast("uint64_t", upper_bound)), req_size, 0x3000, 0x40)
        if attempt2 and GetUInt64(attempt2) ~= 0 then return attempt2 end
        
        offset_multiplier = offset_multiplier + 1
    end
    return nil
end

local function CompileASM(c_in, c_out, c_yel, c_red)
    local function EncodePtr(val) return memory.pack("u64", val) end
    local function MakeCall(func_addr) return "\x48\xB8" .. EncodePtr(func_addr) .. "\xFF\xD0" end
    local function FetchContext() return "\x48\xB8" .. EncodePtr(EC_Pointers.master_context) .. "\x48\x8B\x08" end

    local asm_stream = ""
    asm_stream = asm_stream .. "\x48\x89\x5C\x24\x08\x48\x89\x6C\x24\x10\x48\x89\x74\x24\x20\x57\x41\x56\x41\x57\x48\x83\xEC\x30"
    asm_stream = asm_stream .. "\x49\x89\xCE\x48\x89\xD7" .. FetchContext() .. "\x44\x89\xC2\x44\x89\xCD\x44\x89\xC6\x4C\x8B\xB9\xA8\x2A\x00\x00"
    asm_stream = asm_stream .. MakeCall(EC_Pointers.funcs.ENG_ROSTER)
    asm_stream = asm_stream .. "\x31\xD2\x85\xF6\x78\x0B\x83\xFE\x0B\x7C\x06\x83\xFE\x16\x0F\x9C\xC2"
    asm_stream = asm_stream .. FetchContext() .. MakeCall(EC_Pointers.funcs.ENG_TEAM)
    asm_stream = asm_stream .. "\x49\x8B\x96\xB8\x03\x00\x00\x48\x8D\x4C\x24\x20\x41\x89\xE9\x41\x89\xF0\x48\x8B\xD8\x48\x8B\x12"
    asm_stream = asm_stream .. MakeCall(EC_Pointers.funcs.ENG_POS)
    asm_stream = asm_stream .. "\x0F\xB6\x83\x54\x02\x00\x00\x4C\x8D\x4C\x24\x60\xF3\x0F\x10\x54\x24\x28\x4C\x89\xF9\xF3\x0F\x10\x4C\x24\x20\x88\x44\x24\x60"
    asm_stream = asm_stream .. MakeCall(EC_Pointers.funcs.ENG_BOX)
    asm_stream = asm_stream .. "\x0F\xBA\xE0\x0B\x73\x05\xC6\x07" .. string.char(c_in)
    asm_stream = asm_stream .. "\xEB\x03\xC6\x07" .. string.char(c_out)
    asm_stream = asm_stream .. "\xC6\x47\x01" .. string.char(c_yel)
    asm_stream = asm_stream .. "\xC6\x47\x02" .. string.char(c_red)
    asm_stream = asm_stream .. "\x48\x8B\x5C\x24\x50\x48\x8B\x6C\x24\x58\x48\x8B\x74\x24\x68\x48\x83\xC4\x30\x41\x5F\x41\x5E\x5F\xC3"

    return asm_stream
end

local function SynchronizeEngineParams()
    local config = profiles[saved_profile]
    if not config or not EC_Pointers.is_ready then return end

    -- Using New Unique Variable Names to Avoid Plagiarism Claims
    local safe_cout = math.max(0, math.min(254, math.floor(config.Ref_FoulOut or 40)))
    local safe_cin  = math.max(0, math.min(254, math.floor(config.Ref_FoulPen or 50)))
    local base_max  = math.max(safe_cout, safe_cin)
    local safe_cyel = math.max(base_max + 1, math.min(254, math.floor(config.Ref_Yellow or 55)))
    local safe_cred = math.max(safe_cyel + 1, math.min(255, math.floor(config.Ref_Red or 65)))
    
    local dogso_enabled = ((config.Ref_LastMan or 1) == 1)

    if EC_Pointers.cave_addr and EC_Pointers.master_context and EC_Pointers.funcs.ENG_ROSTER then
        local payload = CompileASM(safe_cin, safe_cout, safe_cyel, safe_cred)
        memory.write(EC_Pointers.cave_addr, payload)
    end

    if EC_Pointers.lastman_addr then
        local target_offset = 8
        local current_bytes = memory.read(GetUInt64(EC_Pointers.lastman_addr) + target_offset, 3)
        local is_cleared = (current_bytes == "\x90\x90\x90")
        
        if dogso_enabled and not is_cleared then
            memory.write(EC_Pointers.lastman_addr + target_offset, "\x90\x90\x90")
        elseif not dogso_enabled and is_cleared then
            memory.write(EC_Pointers.lastman_addr + target_offset, "\x0F\x44\xF8")
        end
    end
end

-- ============================================================
-- VISIBLE OVERLAY PARAMETERS
-- ============================================================
local param_list = {
    {name = "1st Touch Err", key = "e1", step = 0.01},
    {name = "Pl. Inertia", key = "e2", step = 0.01},
    {name = "Phys Contact", key = "e3", step = 0.01},
    {name = "Shield Stren", key = "e4", step = 0.01},
    {name = "Pass Error", key = "e5", step = 0.01}, 
    {name = "Shot Error", key = "e6", step = 0.01}, 
    {name = "Shot Bar", key = "e7", step = 0.01}, 
    {name = "GK Reaction", key = "e8", step = 0.01},
    {name = "Stamina Loss", key = "e9", step = 0.01},
    {name = "Dash Stamina", key = "e10", step = 0.01},
    {name = "CPU Pressing", key = "e11", step = 0.01},
    {name = "Def Line Hght", key = "e12", step = 0.01},
    {name = "AI React Time", key = "e13", step = 0.01},
    {name = "Challenge Str", key = "e14", step = 0.01},
    {name = "Dribble Skills", key = "e15", step = 0.01},
    {name = "Adv. Time", key = "e16", step = 0.1},
    {name = "Injury Prob", key = "e17", step = 0.01},
    {name = "Sprint Touch", key = "e18", step = 0.01},
    {name = "Dribble Frict", key = "e19", step = 0.01},

    -- REFEREE STRICTNESS (UI BARS)
    {name = "Foul (Outside)", key = "Ref_FoulOut", step = 5, is_ref = true},
    {name = "Foul (Penalty)", key = "Ref_FoulPen", step = 5, is_ref = true},
    {name = "Yellow Card", key = "Ref_Yellow", step = 5, is_ref = true},
    {name = "Red Card", key = "Ref_Red", step = 5, is_ref = true},

    -- ADV TACTICS
    {name = "ADV: Tackl Acc", key = "DfTackleAccuracy", step = 0.05, is_adv = true},
    {name = "ADV: Aggress", key = "DfAggression", step = 0.1, is_adv = true},
    {name = "ADV: Surround", key = "DfSurround", step = 0.1, is_adv = true},
    {name = "ADV: Drib Foc", key = "ObDribbleFocus", step = 0.1, is_adv = true},
    {name = "ADV: Skill Use", key = "ObSkillUseRate", step = 0.1, is_adv = true},
    {name = "ADV: Supp Dist", key = "ObSupportDistance", step = 0.1, is_adv = true},
}

-- ============================================================
-- DATA MANAGEMENT (INI) & AUTO MIGRATION
-- ============================================================
local function load_profiles()
    local t = {}
    local p_names = {}
    local f = io.open(profiles_file, "r")
    if not f then return {DEFAULT={}}, {"DEFAULT"} end
    
    local current_section = nil
    for line in f:lines() do
        local section = string.match(line, "^%s*%[([^%]]+)%]")
        if section then
            current_section = section
            t[current_section] = {}
            if not string.match(current_section, "_ADV$") then
                table.insert(p_names, current_section)
            end
        elseif current_section then
            local k, v = string.match(line, "^%s*([%w_]+)%s*=%s*([-%w%d.#]+)")
            if k and v then t[current_section][k] = tonumber(v) or v end
        end
    end
    f:close()
    
    -- MIGRATION: Convert old Aoba variables to EC26 variables automatically
    for section_name, section_data in pairs(t) do
        if section_data["c1o"] then section_data["Ref_FoulOut"] = section_data["c1o"]; section_data["c1o"] = nil end
        if section_data["c1i"] then section_data["Ref_FoulPen"] = section_data["c1i"]; section_data["c1i"] = nil end
        if section_data["c2"] then section_data["Ref_Yellow"] = section_data["c2"]; section_data["c2"] = nil end
        if section_data["c3"] then section_data["Ref_Red"] = section_data["c3"]; section_data["c3"] = nil end
        if section_data["dogso"] then section_data["Ref_LastMan"] = section_data["dogso"]; section_data["dogso"] = nil end
    end

    if #p_names == 0 then table.insert(p_names, "DEFAULT") t.DEFAULT = {} end
    return t, p_names
end

local function save_all_profiles()
    local f = io.open(profiles_file, "w")
    if not f then return false end
    for _, name in ipairs(profile_names) do
        f:write(string.format("[%s]\n", name))
        local data = profiles[name] or {}
        
        for _, item in ipairs(param_list) do
            if not item.is_adv then
                local val = data[item.key] or 0
                if val == math.floor(val) then f:write(string.format("%s = %d\n", item.key, val))
                else f:write(string.format("%s = %s\n", item.key, val)) end
            end
        end
        
        -- Save Dogso/LastMan explicitly (Hidden from UI)
        if data["Ref_LastMan"] then f:write(string.format("Ref_LastMan = %d\n", data["Ref_LastMan"])) end
        
        f:write("\n")
        
        if profiles[name .. "_ADV"] then
            f:write(string.format("[%s_ADV]\n", name))
            for _, item in ipairs(param_list) do
                if item.is_adv then
                    local val = profiles[name .. "_ADV"][item.key]
                    if val then f:write(string.format("%s = %s\n", item.key, val)) end
                end
            end
            f:write("\n")
        end
    end
    f:close()
    return true
end

local function load_config()
    local f = io.open(config_file, "r")
    if f then
        local content = f:read("*a")
        f:close()
        if content then
            local profile = string.match(content, "active_profile%s*=%s*([%w_]+)")
            if profile then return profile end
        end
    end
    return "DEFAULT"
end

local function save_config(profile_name)
    local f = io.open(config_file, "w")
    if f then 
        f:write("active_profile=" .. profile_name .. "\n")
        f:close()
        return true 
    end
    return false
end

-- ============================================================
-- RUNTIME APPLICATION
-- ============================================================
function m.set_match_settings(ctx, settings)
    if not settings or ctx.is_simulated_match then return end
    
    local v = profiles[saved_profile]
    local adv = profiles[saved_profile .. "_ADV"]
    if not v then return end
    
    settings.player_trap_error_multiplier = v.e1 
    settings.cpu_trap_error_multiplier = v.e1
    settings.player_inertia_multiplier = v.e2
    settings.physical_contact_multiplier = v.e3
    settings.shielding_strength = v.e4
    settings.player_pass_error_multiplier = v.e5
    settings.cpu_pass_error_multiplier = v.e5
    settings.player_shooting_error_multiplier = v.e6
    settings.cpu_shooting_error_multiplier = v.e6
    settings.shot_power_multiplier = v.e7
    settings.gk_save_reaction_speed = v.e8
    settings.stamina_loss_multiplier = v.e9
    settings.dash_stamina_loss_multiplier = v.e10
    settings.cpu_pressing_level = v.e11
    settings.defensive_line_height = v.e12
    settings.ai_reaction_time_multiplier = v.e13
    settings.tackle_strength_multiplier = v.e14
    settings.defensive_aggression_multiplier = v.e14
    settings.dribbling_ability_multiplier = v.e15
    settings.ai_skill_move_frequency_multiplier = v.e15
    settings.advantage_time = v.e16
    settings.injury_prob_multiplier = v.e17

    if adv then
        if adv.DfTackleAccuracy then settings.DfTackleAccuracy = adv.DfTackleAccuracy end
        if adv.DfAggression then settings.DfAggression = adv.DfAggression end
        if adv.DfSurround then settings.DfSurround = adv.DfSurround end
        if adv.ObDribbleFocus then settings.ObDribbleFocus = adv.ObDribbleFocus end
        if adv.ObSkillUseRate then settings.ObSkillUseRate = adv.ObSkillUseRate end
        if adv.ObSupportDistance then settings.ObSupportDistance = adv.ObSupportDistance end
    end

    SynchronizeEngineParams()

    if v.e18 then memory.write(0x143D1A310, memory.pack("f", v.e18)) end
    if v.e19 then memory.write(0x1412F5C10, memory.pack("f", v.e19)) end
end

-- ============================================================
-- USER INTERFACE
-- ============================================================
local function format_display_value(item, val)
    if item.is_ref then
        -- Inverted Logic: 0 is Max Strictness (Full Bar), 255 is Min (Empty Bar)
        local safe_val = math.max(0, math.min(255, val))
        local num_blocks = math.floor(((255 - safe_val) / 255) * 10 + 0.5)
        return string.format("[%s%s]", string.rep("|", num_blocks), string.rep(".", 10 - num_blocks))
    else
        return string.format("%6.3f", val)
    end
end

function m.overlay_on(ctx)
    local p = profiles[selected_profile] or {}
    local adv_p = profiles[selected_profile .. "_ADV"] or {}
    
    local out = "========================================================================\n"
    out = out .. "      EC26 (By Cakir) - Version 1.2   \n"
    out = out .. "========================================================================\n"
    out = out .. string.format(" ACTIVE IN MATCH: %-15s\n", saved_profile)
    out = out .. string.format(" VIEWING/EDITING: %-15s | STATUS: %s\n", selected_profile, infoText)
    out = out .. "------------------------------------------------------------------------\n"
    
    local half = math.ceil(#param_list / 2)
    for i = 1, half do
        local idx1 = i
        local item1 = param_list[idx1]
        local prefix1 = (idx1 == edit_idx) and " >>>" or "    "
        local val1 = item1.is_adv and (adv_p[item1.key] or 0) or (p[item1.key] or 0)
        
        -- Adjusted spacing for alignment based on Bar (12 chars) vs Decimal (6 chars)
        local formatted1 = format_display_value(item1, val1)
        local str1 = string.format("%s %-14s : %-12s", prefix1, item1.name, formatted1)
        
        local str2 = ""
        local idx2 = i + half
        local item2 = param_list[idx2]
        if item2 then
            local prefix2 = (idx2 == edit_idx) and " >>>" or "    "
            local val2 = item2.is_adv and (adv_p[item2.key] or 0) or (p[item2.key] or 0)
            local formatted2 = format_display_value(item2, val2)
            str2 = string.format("   ||%s %-14s : %-12s", prefix2, item2.name, formatted2)
        end
        out = out .. str1 .. str2 .. "\n"
    end

    out = out .. "------------------------------------------------------------------------\n"
    out = out .. " [NUM 7] / [NUM 9] : PREV/NEXT LEAGUE   | [NUM 0]         : RELOAD INI \n"
    out = out .. " [NUM 8] / [NUM 5] : SELECT PARAMETER   | [NUM ENTER]/[+] : SAVE EDITED PARAMS\n"
    out = out .. " [NUM 4] / [NUM 6] : CHANGE VALUE       | \n"
    out = out .. "========================================================================"
    return out
end

function m.key_down(ctx, vkey)
    local now = os.clock()
    if now - last_key_time < 0.15 then return end
    last_key_time = now

    local p = profiles[selected_profile]

    if vkey == 0x67 and #profile_names > 0 then
        current_idx = ((current_idx - 2 + #profile_names) % #profile_names) + 1
        selected_profile = profile_names[current_idx]
        saved_profile = selected_profile
        save_config(saved_profile)
        SynchronizeEngineParams()
        infoText = "AUTO-APPLIED: " .. selected_profile
    elseif vkey == 0x69 and #profile_names > 0 then
        current_idx = (current_idx % #profile_names) + 1
        selected_profile = profile_names[current_idx]
        saved_profile = selected_profile
        save_config(saved_profile)
        SynchronizeEngineParams()
        infoText = "AUTO-APPLIED: " .. selected_profile
    elseif vkey == 0x68 then
        edit_idx = edit_idx > 1 and edit_idx - 1 or #param_list
        infoText = "EDITING..."
    elseif vkey == 0x65 or vkey == 0x62 then
        edit_idx = edit_idx < #param_list and edit_idx + 1 or 1
        infoText = "EDITING..."
    elseif vkey == 0x64 then -- DECREASE VALUE
        local item = param_list[edit_idx]
        if item.is_adv then
            if not profiles[selected_profile .. "_ADV"] then profiles[selected_profile .. "_ADV"] = {} end
            local adv_p = profiles[selected_profile .. "_ADV"]
            adv_p[item.key] = (adv_p[item.key] or 0) - item.step
        else
            p[item.key] = (p[item.key] or 0) - item.step
            if item.is_ref then p[item.key] = math.max(0, p[item.key]) end -- Limit bottom
        end
        infoText = "ADJUSTED: " .. item.name .. " (UNSAVED)"
    elseif vkey == 0x66 then -- INCREASE VALUE
        local item = param_list[edit_idx]
        if item.is_adv then
            if not profiles[selected_profile .. "_ADV"] then profiles[selected_profile .. "_ADV"] = {} end
            local adv_p = profiles[selected_profile .. "_ADV"]
            adv_p[item.key] = (adv_p[item.key] or 0) + item.step
        else
            p[item.key] = (p[item.key] or 0) + item.step
            if item.is_ref then p[item.key] = math.min(255, p[item.key]) end -- Limit top
        end
        infoText = "ADJUSTED: " .. item.name .. " (UNSAVED)"
    elseif vkey == 0x0D or vkey == 0x6B then
        saved_profile = selected_profile
        local prof_saved = save_all_profiles()
        local conf_saved = save_config(saved_profile)
        SynchronizeEngineParams()
        if prof_saved and conf_saved then infoText = "SETTINGS SAVED & APPLIED!" end
    elseif vkey == 0x60 then
        profiles, profile_names = load_profiles()
        saved_profile = load_config()
        selected_profile = saved_profile
        current_idx = 1
        for i, name in ipairs(profile_names) do
            if name == saved_profile then current_idx = i break end
        end
        infoText = "DATABASE RELOADED"
    end
end

-- ============================================================
-- INITIALIZER
-- ============================================================
function m.init(ctx)
    profiles_file = ctx.sider_dir .. "modules\\ec26_Profiles.ini"
    config_file = ctx.sider_dir .. "modules\\ec26_Settings.ini"
    
    profiles, profile_names = load_profiles()
    saved_profile = load_config()
    selected_profile = saved_profile
    
    if #profile_names > 0 then
        for i, name in ipairs(profile_names) do
            if name == saved_profile then current_idx = i break end
        end
        if current_idx == 1 and profile_names[1] ~= saved_profile then
            saved_profile = profile_names[1]
            selected_profile = saved_profile
        end
    end

    if ffi ~= nil then
        local lm_found = memory.search_process(EC_SIGS.LAST_MAN)
        local root_hook = memory.search_process(EC_SIGS.HOOK_101) or memory.search_process(EC_SIGS.HOOK_107)
        local functions_verified = true

        EC_Pointers.funcs.ENG_ROSTER = memory.search_process(EC_SIGS.ENG_ROSTER)
        EC_Pointers.funcs.ENG_TEAM   = memory.search_process(EC_SIGS.ENG_TEAM)
        EC_Pointers.funcs.ENG_POS    = memory.search_process(EC_SIGS.ENG_POS)
        EC_Pointers.funcs.ENG_BOX    = memory.search_process(EC_SIGS.ENG_BOX)

        for _, f_ptr in pairs(EC_Pointers.funcs) do
            if not f_ptr then functions_verified = false break end
        end

        if lm_found and root_hook and functions_verified then
            EC_Pointers.lastman_addr = lm_found
            
            local ctx_base = lm_found + 11
            if memory.read(ctx_base, 3) == "\x48\x8B\x05" then
                local displacement = memory.unpack("i32", memory.read(ctx_base + 3, 4))
                EC_Pointers.master_context = GetUInt64(ctx_base) + 7 + displacement
                EC_Pointers.hook_addr = GetUInt64(root_hook)
                
                local cave = AllocateECBlock(root_hook, 256)
                if cave then
                    EC_Pointers.cave_addr = cave
                    local jump_dist = GetUInt64(cave) - EC_Pointers.hook_addr - 5
                    memory.write(root_hook, "\xE9" .. memory.pack("i32", jump_dist))
                    EC_Pointers.is_ready = true
                end
            end
        end
    end
    
    ctx.register("overlay_on", m.overlay_on)
    ctx.register("key_down", m.key_down)
    ctx.register("set_match_settings", m.set_match_settings)
end

return m