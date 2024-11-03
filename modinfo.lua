name = "Auto Cooking"
description = ""
author = "Tony"
version = "2.2.5"
icon_atlas = "modicon.xml"
icon = "modicon.tex"
dst_compatible = true
client_only_mod = true
all_clients_require_mod = false

api_version = 10

-- Make sure we load after other mods to hook their containers data
-- 100,000
priority = -100000

local boolean = {{description = "Yes", data = true}, {description = "No", data = false}}
local string = ""
local keys = { -- from STRINGS.UI.CONTROLSSCREEN.INPUTS[1] of strings.lua, need to match constants.lua too.
    "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12", "Print", "ScrolLock", "Pause",
    "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
    "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
    "Escape", "Tab", "CapsLock", "LShift", "LCtrl", "LAlt", "Space", "RAlt", "RCtrl", "Period", "Slash", "RShift",
    "Minus", "Equals", "Backspace", "LeftBracket", "RightBracket", "Backslash", "Semicolon", "Enter",
    "Up", "Down", "Left", "Right", "Insert", "Delete", "Home", "End", "PageUp", "PageDown", -- navigation
    "Num 0", "Num 1", "Num 2", "Num 3", "Num 4", "Num 5", "Num 6", "Num 7", "Num 8", "Num 9", -- numberic keypad
    "Num Period", "Num Divide", "Num Multiply", "Num Minus", "Num Plus",
    "Disabled",
}
-- Make visible in the modinfo object, keybind_magic.lua uses this
keylist = {}
for i = 1, #keys do
    local key = keys[i]
    keylist[i] = {description = key, data = "KEY_" .. key:gsub("^Num ", "KP_"):upper()}
end

configuration_options =
{
    {
        name = "language",
        hover = "Choose your language\n选择您使用的语言",
        label = "Language",
        options =
        {
            {description = "Auto", data = "auto", hover = "Auto detect, may not work"},
            {description = "English", data = "english", hover = "English"},
            {description = "简体中文", data = "chinese_s", hover = "Simplified Chinese"},
        },
        default = "auto",
    },
    {
        name = "key",
        hover = "Key to start cooking\n启动做饭的按键",
        label = "Action Key",
        options = keylist,
        default = "KEY_F5"
    },
    {
        name = "key_2",
        hover = "Key to start cooking(This Key + Click The Cookpot)\n启动做饭的按键（该按键 + 点击锅子）",
        label = "Action Key 2",
        options = keylist,
        default = "KEY_DISABLED"
    },
    {
        name = "last_recipe_key",
        hover = "Key to start lastest cooking recipe\n开始做上一次配方的按键",
        label = "Lastest Recipe Key",
        options = keylist,
        default = "KEY_HOME"
    },
    {
        name = "integrated_key",
        hover = "Key to start cooking items from opened cookware or lastest cooking recipe\n开始做打开容器内物品或者上一次配方的按键",
        label = "Integrated Key",
        options = keylist,
        default = "KEY_DISABLED"
    },
    {
        name = "speedy_mode",
        hover = "Ultra fast filling speed\n究极快的填充速度",
        label = "Ultra Fast Mode",
        options = boolean,
        default = false,
    },
    {
        name = "cookpots_num_divisor",
        hover = "Select more or lesser cookpots\n选择更多或更少的烹饪锅",
        label = "Num of Cookpots",
        options =
        {
            {description = "Lesser", data = 2.5, hover = "Select lesser cookpots"},
            {description = "Default", data = 2, hover = "Select default num cookpots"},
            {description = "More", data = 1.5, hover = "Select more cookpots"},
        },
        default = 2
    },
    {
        name = "laggy_mode",
        hover = "If you are really laggy, pls turn this on\n如果很卡的话再开",
        label = "Laggy Mode",
        options =
        {
            {description = "Off", data = "off", hover = "Always off"},
            {description = "On", data = "on", hover = "Always on"},
            {description = "In Game Button", data = "in_game", hover = "Toggleable in game"},
        },
        default = "off"
    },
    {
        name = "laggy_mode_key",
        hover = "Key to toggle laggy mode\n切换卡顿模式的按键",
        label = "Laggy Mode Toggle Key",
        options = keylist,
        default = "KEY_RSHIFT"
    }
}

for i = 1, #configuration_options do
    local opt = configuration_options[i]
    if opt.options == keylist then
        opt.is_keylist = true
    end
end
