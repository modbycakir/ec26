local m = {}
m.version = " - Emre Cakir Tactical AI (Thanks alldynamicmentalitymoders and gokhanugurlu)"

-- ==========================================================
-- FL26 / PES 21 
-- ==========================================================
local MENTALITY_AOB = '\x8B\xC3\x41\x0F\x4F\xC6\x89\x81\xA4\xB8\x00\x00\x3B\xDD'
local CAVE_AOB = string.rep('\xCC', 32)

local original_addr, cave_addr, cave_num, original_num = nil, nil, nil, nil
local active_mentality_val = 2
local info_text = "WAITING FOR MATCH... / ОЖИДАНИЕ МАТЧА..."
local last_check_time = 0

-- 
local AUTO_AI_ACTIVE = true
local MANUAL_MENTALITY = 2

local status_texts = {
    [0] = "0 - PARK THE BUS / АВТОБУС",
    [1] = "1 - DEFENSIVE / ЗАЩИТА",
    [2] = "2 - BALANCED / БАЛАНС",
    [3] = "3 - OFFENSIVE / АТАКА",
    [4] = "4 - ALL-OUT ATTACK (KAMIKAZE!)"
}

-- ==========================================================
-- SIDER MEMORY HELPERS
-- ==========================================================
local function ptr_to_num(ptr)
    local str = tostring(ptr)
    local hex = string.match(str, "0x(%x+)")
    if hex then
        local result = 0
        for i = 1, #hex do
            local digit = tonumber(string.sub(hex, i, i), 16)
            result = result * 16 + digit
        end
        return result
    end
    return nil
end

local function int_to_bytes(n)
    if n < 0 then n = n + 0x100000000 end
    local b1 = n % 256
    local b2 = math.floor(n / 256) % 256
    local b3 = math.floor(n / 65536) % 256
    local b4 = math.floor(n / 16777216) % 256
    return string.char(b1, b2, b3, b4)
end

local function set_intervention(active, value)
    if not cave_num or not original_num then return end
    local return_addr = original_num + 8
    local code
    if active then
        code = '\xB8' .. string.char(value) .. '\x00\x00\x00' .. '\x89\x81\xA4\xB8\x00\x00' .. '\x3B\xDD' .. '\xE9' .. int_to_bytes(return_addr - (cave_num + 18))
    else
        code = '\x89\x81\xA4\xB8\x00\x00' .. '\x3B\xDD' .. '\xE9' .. int_to_bytes(return_addr - (cave_num + 13))
    end
    memory.write(cave_addr, code)
end

-- ==========================================================
-- [ EMRE CAKIR ] AUTOMATIC 
-- ==========================================================
local function calculate_auto_mentality(minute, diff)
    if diff <= -2 then return 4 end
    
    if minute >= 75 then
        if diff == -1 then return 4 
        elseif diff > 0 then return 0 
        else return 2 end
    end
    
    if minute >= 60 then
        if diff == -1 then return 3 
        elseif diff > 0 then return 1 
        else return 2 end
    end
    
    if diff > 1 then return 0 
    elseif diff == 1 then return 1 
    elseif diff == -1 then return 3 
    else return 2 end
end

-- ==========================================================
-- MAIN ENGINE (Her saniye maçı okur)
-- ==========================================================
function m.main_logic(ctx)
    local now = os.clock()
    if now - last_check_time < 1.0 then return end
    last_check_time = now

    local stats = match.stats()
    
    if not stats then
        info_text = "WAITING FOR MATCH... / ОЖИДАНИЕ МАТЧА..."
        set_intervention(false, -1)
        return 
    end

    if AUTO_AI_ACTIVE then
        local ai_goals = stats.away_score
        local player_goals = stats.home_score
        local minute = stats.clock_minutes
        local score_diff = ai_goals - player_goals

        active_mentality_val = calculate_auto_mentality(minute, score_diff)
        info_text = "AUTO MODE RUNNING / АВТОМАТИЧЕСКИЙ РЕЖИМ"
    else
        active_mentality_val = MANUAL_MENTALITY
        info_text = "MANUAL MODE ACTIVE / РУЧНОЙ РЕЖИМ"
    end
    
    set_intervention(true, active_mentality_val)
end

-- ==========================================================
-- EMRE CAKIR DASHBOARD (SIDER OVERLAY)
-- ==========================================================
function m.overlay_on(ctx)
    local mode_str = AUTO_AI_ACTIVE and "AUTO (AI / ИИ ЛОГИКА)" or "MANUAL (YOUR CONTROL / ВАШ КОНТРОЛЬ)"
    local ment_str = status_texts[active_mentality_val] or "UNKNOWN / НЕИЗВЕСТНО"

    return string.format(
        "======================================================================\n" ..
        "              EMRE CAKIR TACTICAL AI MANAGER                  \n" ..
        "======================================================================\n" ..
        " [ AI DIRECTOR STATUS / СТАТУС ИИ-МЕНЕДЖЕРА ]\n" ..
        " Control Mode     : %-18s \n" ..
        " Active Mentality : %-18s \n" ..
        "----------------------------------------------------------------------\n" ..
        " [ HOTKEYS / ГОРЯЧИЕ КЛАВИШИ ]\n" ..
        " [9] Auto/Manual Toggle (Авто/Ручной)\n" ..
        " [PageUp] Attack +1 (Атака +1) | [PageDown] Defend -1 (Защита -1)\n" ..
        "======================================================================\n" ..
        " STATUS / СТАТУС: %s\n",
        mode_str, ment_str, info_text
    )
end

-- ==========================================================
--  (HOTKEYS)
-- ==========================================================
function m.key_down(ctx, vkey)
    if vkey == 0x39 then 
        AUTO_AI_ACTIVE = not AUTO_AI_ACTIVE
        if not AUTO_AI_ACTIVE then
            MANUAL_MENTALITY = active_mentality_val 
        end
        return true
    end
    
    if not AUTO_AI_ACTIVE then
        if vkey == 0x21 then 
            MANUAL_MENTALITY = math.min(4, MANUAL_MENTALITY + 1)
            return true
        elseif vkey == 0x22 then 
            MANUAL_MENTALITY = math.max(0, MANUAL_MENTALITY - 1)
            return true
        end
    end
end

-- ==========================================================
-- INIT
-- ==========================================================
function m.init(ctx)
    local aob = memory.search_process(MENTALITY_AOB)
    if aob then
        original_addr = aob + 6
        original_num = ptr_to_num(original_addr)
        
        cave_addr = memory.search_process(CAVE_AOB) or memory.search_process(string.rep('\x00', 32))
        
        if cave_addr then
            cave_num = ptr_to_num(cave_addr)
            set_intervention(false, -1)
            
            memory.write(original_addr, '\xE9' .. int_to_bytes(cave_num - (original_num + 5)) .. '\x90\x90\x90')
            
            info_text = "Memory Injection Successful / Память успешно изменена."
        else
            info_text = "ERROR: Cave Address Not Found! / ОШИБКА: Cave не найден!"
        end
    else
        info_text = "ERROR: AOB Not Found! / ОШИБКА: AOB не найден!"
    end

    ctx.register("overlay_on", m.overlay_on)
    ctx.register("key_down", m.key_down)
    ctx.register("livecpk_make_key", m.main_logic)
end

return m