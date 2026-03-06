-- ============================================================
-- utils.lua — Shared helpers used across all GromitBot modules
-- ============================================================

GB_Utils = {}

-- ---- Random float in [lo, hi] ------------------------------
function GB_Utils.RandFloat(lo, hi)
    return lo + math.random() * (hi - lo)
end

-- ---- Gaussian (normal) random via Box-Muller ---------------
-- Returns a value normally distributed around `mean` with `stddev`.
-- Soft-clamped to ±2.5 sigma to avoid extreme outliers.
function GB_Utils.GaussRand(mean, stddev)
    local u1 = math.max(1e-9, math.random())
    local u2 = math.random()
    local z  = math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
    local v  = mean + stddev * z
    local lo = mean - 2.5 * stddev
    local hi = mean + 2.5 * stddev
    return math.max(lo, math.min(hi, v))
end

-- ---- Gaussian interval sampler — Gaussian centred on midpoint -------
-- Returns a sample within [lo, hi] using ~18 % of range as 1 sigma.
function GB_Utils.GaussInterval(lo, hi)
    local mid = (lo + hi) * 0.5
    local sd  = (hi - lo) * 0.18
    return math.max(lo, math.min(hi, GB_Utils.GaussRand(mid, sd)))
end

-- ---- Round to n decimal places -----------------------------
function GB_Utils.Round(v, n)
    local m = 10 ^ (n or 0)
    return math.floor(v * m + 0.5) / m
end

-- ---- Distance (2-D, ignoring Z) ----------------------------
function GB_Utils.Dist2D(x1, y1, x2, y2)
    local dx = x1 - x2
    local dy = y1 - y2
    return math.sqrt(dx * dx + dy * dy)
end

-- ---- Distance 3-D ------------------------------------------
function GB_Utils.Dist3D(x1, y1, z1, x2, y2, z2)
    local dx = x1 - x2
    local dy = y1 - y2
    local dz = z1 - z2
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- ---- Clamp -------------------------------------------------
function GB_Utils.Clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- ---- Schedule a callback after `delay` seconds using OnUpdate
-- Returns a cancel function.
function GB_Utils.After(delay, fn)
    local elapsed = 0
    local frame = CreateFrame("Frame")
    local cancelled = false
    frame:SetScript("OnUpdate", function()
        if cancelled then frame:Hide(); return end
        elapsed = elapsed + arg1           -- OnUpdate arg1 = deltaTime in 1.12
        if elapsed >= delay then
            frame:Hide()
            if not cancelled then fn() end
        end
    end)
    frame:Show()
    return function() cancelled = true end
end

-- ---- Debug print (only when GB_Config.debug is true) -------
function GB_Utils.Debug(msg)
    if GromitBotConfig and GromitBotConfig.debug then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[GromitBot]|r " .. tostring(msg))
    end
end

function GB_Utils.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ffff[GromitBot]|r " .. tostring(msg))
end

-- ---- Deep copy of a table ----------------------------------
function GB_Utils.DeepCopy(orig)
    local copy
    if type(orig) == "table" then
        copy = {}
        for k, v in pairs(orig) do copy[GB_Utils.DeepCopy(k)] = GB_Utils.DeepCopy(v) end
        setmetatable(copy, GB_Utils.DeepCopy(getmetatable(orig)))
    else
        copy = orig
    end
    return copy
end

-- ---- Trim whitespace from string ---------------------------
function GB_Utils.Trim(s)
    return s:match("^%s*(.-)%s*$")
end

-- ---- Word-wrap a string to maxLen chars --------------------
function GB_Utils.WrapText(s, maxLen)
    if #s <= maxLen then return s end
    return s:sub(1, maxLen - 3) .. "..."
end

-- ---- Simple set ------------------------------------------ -
function GB_Utils.Set(list)
    local s = {}
    for _, v in ipairs(list) do s[v] = true end
    return s
end
