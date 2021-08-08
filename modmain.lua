local function GetKeyFromConfig(config)
    local key = GetModConfigData(config, true)
    if key == "no_toggle_key" then
        key = -1
    elseif type(key) == "string" then
        key = GLOBAL.rawget(GLOBAL, key)
    end
    return type(key) == "number" and key or -1
end

local language              = GetModConfigData("Language")
local last_recipe_mode      = GetModConfigData("last_recipe_mode")
local cookpots_num_divisor  = GetModConfigData("cookpots_num_divisor")
local laggy_mode            = GetModConfigData("laggy_mode")

local toggle_key            = GetKeyFromConfig("key")
local key_2                 = GetKeyFromConfig("key_2")
local lastest_recipe_key    = GetKeyFromConfig("last_recipe_key")
local laggy_mode_key        = GetKeyFromConfig("laggy_mode_key")

local laggy_mode_on = laggy_mode == "on"

local ENV = env
GLOBAL.setfenv(1, GLOBAL)

local cooking = require("cooking")

local SLEEP_TIME = FRAMES * 3
local cookware_prefabs = {
    "cookpot",
    "portablecookpot",
    "portablespicer",
    "deluxpot",         -- From Deluxe cooking pot
    "medal_cookpot",    -- From Functional medal
    "archive_cookpot"
}
local cookware_morph = {
    cookpot = {
        "deluxpot",
        "archive_cookpot"
    },
    portablecookpot = {
        "medal_cookpot"
    }
}

local cookingthread
local harvestingthread
local harvestinglist = {}

local lastest_recipe
local lastest_recipe_type

local ismasterchef = false

--from action queue reborn--

local function InGame()
    return ThePlayer and ThePlayer.HUD and not ThePlayer.HUD:HasInputFocus()
end

--from action queue reborn--

local function Say(string)
    if not ThePlayer then return end
    ThePlayer.components.talker:Say(string)
end

local CHINESE_STRING = {
    ["no_backpack"] = "未装备背包",
    ["no_previous_recipe"] = "未找到上次烹饪配方",
    ["unable_cook_last_recipe"] = "无法烹饪上次配方",
    ["start"] = "自动做饭:开启",
    ["stop"] = "自动做饭:关闭",
    ["not_valid_items"] = "物品有误",
    ["no_masterchef"] = "没有大厨标签",
    ["no_portablespicer"] = "未找到调料站",
    ["no_cookpot"] = "未找到烹饪锅",
    ["cant_move_out_items"] = "无法从烹饪锅中移出物品",
    ["harvest_only"] = "材料已用完，进入收获模式",
    ["harvest_only_endless"] = "无尽收获模式启动",
    ["last_recipe"] = "烹饪上个配方",
    ["laggy_mode_on"] = "自动做饭:高延迟模式开启",
    ["laggy_mode_off"] = "自动做饭:高延迟模式关闭",
}

local ENGLISH_STRING = {
    ["no_backpack"] = "Haven't backpack",
    ["no_previous_recipe"] = "No previous cooking recipe found",
    ["unable_cook_last_recipe"] = "Unable to cook lastest recipe",
    ["start"] = "Auto Cooking : On",
    ["stop"] = "Auto Cooking : Off",
    ["not_valid_items"] = "Wrong items",
    ["no_masterchef"] = "Haven't masterchef tag",
    ["no_portablespicer"] = "Didn't find portablespicer",
    ["no_cookpot"] = "Didn't find cookpot",
    ["cant_move_out_items"] = "Can't move out item from cookpot",
    ["harvest_only"] = "Material run out,harvest mode on",
    ["harvest_only_endless"] = "Endless harvest mode on",
    ["last_recipe"] = "Cooking lastest recipe",
    ["laggy_mode_on"] = "Auto Cooking : Laggy Mode On",
    ["laggy_mode_off"] = "Auto Cooking : Laggy Mode Off",
}

local function GetString(stringtype)
    if language == "Chinese" then
        return CHINESE_STRING[stringtype]
    else
        return ENGLISH_STRING[stringtype]
    end
end

local function FormatItemList(items)
    local itemlist = {}
    local amount = 0
    for i, v in ipairs(items) do
        if not itemlist[v.prefab] then
            for ii, vv in ipairs(items) do
                if v.prefab == vv.prefab then
                    amount = amount + 1
                end
            end
            itemlist[v.prefab] = amount
            amount = 0
        end
    end
    return itemlist
end

--from action queue reborn--

local function IsValidEntity(ent)
    return ent and ent.Transform and ent:IsValid() and not ent:HasTag("INLIMBO")
end

--from action queue reborn--

--local function GetAction(target,pos)
--    if IsValidEntity(target) then
--        local pos = pos or target:GetPosition()
--        local playeractionpicker = ThePlayer.components.playeractionpicker
--        local act = playeractionpicker:GetLeftClickActions(pos, target)
--        return act and act[1]
--    else
--        return false
--    end
--end

local function CanRummageOrHarvest(target,pos)
    if IsValidEntity(target) then
        local pos = pos or target:GetPosition()
        local playeractionpicker = ThePlayer.components.playeractionpicker
        --local actions = playeractionpicker:GetLeftClickActions(pos, target)
        local act
        if not (ThePlayer.replica.rider ~= nil and ThePlayer.replica.rider:IsRiding())
        and target:HasTag("donecooking") then
            act = BufferedAction(ThePlayer, target, ACTIONS.HARVEST)
        elseif target.replica.container and target.replica.container:CanBeOpened()
        and ThePlayer.replica.inventory ~= nil
        and not (ThePlayer.replica.rider ~= nil and ThePlayer.replica.rider:IsRiding()) then
            act = BufferedAction(ThePlayer, target, ACTIONS.RUMMAGE)
        end
        --for _,act in ipairs(actions) do
        --    if act.action == ACTIONS.RUMMAGE or act.action == ACTIONS.HARVEST then
        --        return act
        --    end
        --end
        return act
    else
        return false
    end
end

--from action queue reborn--

local function Wait(time,act)
    repeat
        Sleep(time or SLEEP_TIME)
    until not (ThePlayer.sg and ThePlayer.sg:HasStateTag("moving")) and not ThePlayer:HasTag("moving")
        and (not (act and act.action == ACTIONS.RUMMAGE) or ThePlayer:HasTag("idle") and not ThePlayer.components.playercontroller:IsDoingOrWorking())
    if laggy_mode_on then Sleep(0.3) end
end

local function SendLeftClickAction(act, target, pos)

    local playercontroller = ThePlayer.components.playercontroller
    if playercontroller.ismastersim then
        ThePlayer.components.combat:SetTarget(nil)
        playercontroller:DoAction(act)
        return
    end

    local pos = pos or ThePlayer:GetPosition()
    local function send()
        SendRPCToServer(RPC.LeftClick, act.action.code, pos.x, pos.z, target, true)
    end
    if playercontroller:CanLocomote() then
        act.preview_cb = send
        playercontroller:DoAction(act)
    else
        send()
    end

end

local function SendActionAndWait(act,target,time)
    SendLeftClickAction(act, target)
    Wait(time,act)
end

--from action queue reborn--

local function CheckBackpackItems(backpack)

    if backpack.replica.container:GetItemInSlot(1) and backpack.replica.container:GetItemInSlot(2) then
        if (backpack.replica.container:GetItemInSlot(1):HasTag("spice") and
           backpack.replica.container:GetItemInSlot(2):HasTag("preparedfood") and
           not backpack.replica.container:GetItemInSlot(2):HasTag("spicedfood")) or
           (backpack.replica.container:GetItemInSlot(2):HasTag("spice") and
           backpack.replica.container:GetItemInSlot(1):HasTag("preparedfood") and
           not backpack.replica.container:GetItemInSlot(1):HasTag("spicedfood")) then

            local items = {backpack.replica.container:GetItemInSlot(1),backpack.replica.container:GetItemInSlot(2)}

            return items, "AddSpices"

        elseif backpack.replica.container:GetItemInSlot(3) and backpack.replica.container:GetItemInSlot(4) then
            local items = {}
            for i = 1, 4 do
                if not cooking.IsCookingIngredient(backpack.replica.container:GetItemInSlot(i).prefab) then
                    return false
                end
                table.insert(items,backpack.replica.container:GetItemInSlot(i))
            end

            return items, "AutoCooking"
        end
    end
    return false
end

local function CheckInventoryItems()

    if not (ThePlayer and ThePlayer.replica.inventory) then return false,false end
    local items = ThePlayer.replica.inventory:GetItems()

    local item_list = {}

    local function CheckNext(slot, counter, spiceorfood)

        for k,item in pairs(items) do
            if k == slot + 1 then
                if spiceorfood then
                    if spiceorfood == "spice" then
                        if item:HasTag("preparedfood") and not item:HasTag("spicedfood") then
                            table.insert(item_list,item)
                            return true
                        end
                    elseif spiceorfood == "preparedfood" then
                        if item:HasTag("spice") then
                            table.insert(item_list,item)
                            return true
                        end
                    end
                elseif cooking.IsCookingIngredient(item.prefab) then
                    local counter = counter + 1
                    if counter == 4 then
                        table.insert(item_list, item)
                        return true
                    elseif CheckNext(k, counter) then
                        table.insert(item_list, item)
                        return item_list
                    end
                end
                return false
            end
        end
        return false
    end

    for slot, item in pairs(items) do
        if cooking.IsCookingIngredient(item.prefab) then
            if CheckNext(slot, 1) then
                table.insert(item_list,item)
                return item_list, "AutoCooking"
            end
        elseif item:HasTag("spice") then
            if CheckNext(slot, 1, "spice") then
                table.insert(item_list,item)
                return item_list, "AddSpices"
            end
        elseif item:HasTag("preparedfood") and not item:HasTag("spicedfood") then
            if CheckNext(slot, 1, "preparedfood") then
                table.insert(item_list,item)
                return item_list, "AddSpices"
            end
        end
    end
    return false
end

local function CheckCookwareItems()
    local item_list = {}
    for container in pairs(ThePlayer.replica.inventory:GetOpenContainers()) do
        if container.replica.container
            and table.contains(cookware_prefabs, container.prefab)
            and container.replica.container.widget.buttoninfo.validfn(container) then

            for slot, item in pairs(container.replica.container:GetItems()) do
                table.insert(item_list, item)
            end
            return item_list, container.prefab == "portablespicer" and "AddSpices" or "AutoCooking", container
        end
    end
end

local function FindCookware(type, actioncheck, cookpots, container, cantcookware)

    local function find(_prefab)
        local cant_tag = {"INLIMBO", "burnt"}
        if not ismasterchef then
            table.insert(cant_tag, "mastercookware")
        end
        return FindEntity(ThePlayer, 25, function(inst)

            if container and not container:IsNear(inst, 4) then return end

            local incookpots = false
            if cookpots then
                for _, v in ipairs(cookpots) do
                    if inst == v then
                        incookpots = true
                        break
                    end
                end
                if not incookpots then return end
            end

            if actioncheck then
                if not CanRummageOrHarvest(inst) then
                    return false
                end
            end

            if cantcookware then
                for _, v in ipairs(cantcookware) do
                    if inst == v then return end
                end
            end
            return inst.prefab == _prefab or table.contains(cookware_morph[_prefab], inst.prefab)
        end, {"stewer"}, cant_tag)
    end

    if type == "cookpot" then
        return find("portablecookpot") or find("cookpot")
    elseif type == "portablespicer" then
        return find("portablespicer")
    end

end

local function GetItemSlot(item)

    if not (ThePlayer and ThePlayer.replica.inventory) then return end

    local function func(prefab)
        for container in pairs(ThePlayer.replica.inventory:GetOpenContainers()) do
            if container.replica.container and not table.contains(cookware_prefabs, container.prefab) then
                local items_container = container.replica.container:GetItems()
                for k,v in pairs(items_container) do
                    if v == item or v.prefab == prefab then
                        return container.replica.container, k
                    end
                end
            end
        end
        for k,v in pairs(ThePlayer.replica.inventory:GetItems()) do
            if v == item or v.prefab == prefab then
                return ThePlayer.replica.inventory, k
            end
        end
        return false
    end

    if func() then
        return func()
    else
        return func(item.prefab)
    end

end

local function HaveEnoughItems(items, no_container, only_containers)
    local items = FormatItemList(items)
    if not (ThePlayer and ThePlayer.replica.inventory and items) then return end
    local itemlist = {}
    local amount = 0

    local function check(container)
        for _, v in pairs(container:GetItems()) do
            for _prefab in pairs(items) do
                if v.prefab == _prefab then
                    if v.replica.stackable then
                        amount = amount + v.replica.stackable:StackSize()
                    else
                        amount = amount + 1
                    end
                    itemlist[_prefab] = itemlist[_prefab] and itemlist[_prefab] + amount or amount
                    amount = 0
                    break
                end
            end
        end
    end

    if only_containers then
        for _, container in ipairs(only_containers) do
            check(container)
        end
    else
        for container in pairs(ThePlayer.replica.inventory:GetOpenContainers()) do
            local container_replica = container.replica.container
            if container_replica and (not no_container or container:HasTag("backpack")) then
                check(container_replica)
            end
        end
        check(ThePlayer.replica.inventory)
    end

    for prefab, item_amount in pairs(items) do
        if not itemlist[prefab] or itemlist[prefab] < item_amount then
            return false
        end
    end
    return true
end

local function TakeOutItemsInCookware(cookware)
    -- If something's in that cookware, take it out
    local container = cookware.replica.container
    while not container:IsEmpty() do
        for i = 1, container:GetNumSlots() do
            if container:GetItemInSlot(i) then
                local has_emptyslot = false
                if ThePlayer.replica.inventory:IsFull() then
                    local backpack = ThePlayer.replica.inventory:GetOverflowContainer()
                    if backpack and not backpack:IsFull() then
                        SendRPCToServer(RPC.MoveItemFromAllOfSlot, i, container.inst, backpack.inst)
                    else
                        Say(GetString("cant_move_out_items"))
                        return false
                    end
                else
                    SendRPCToServer(RPC.MoveItemFromAllOfSlot, i, container.inst)
                end
            end
        end
        Sleep(0)
    end
    return true
end

local function StopCooking()
    Say(GetString("stop"))
    if cookingthread then
        cookingthread:SetList(nil)
    end
    if harvestingthread then
        harvestingthread:SetList(nil)
    end
    cookingthread = nil
    harvestingthread = nil
end

local function HarvestOnly(endless)

    if endless then
        Say(GetString("harvest_only_endless"))
    else
        Say(GetString("harvest_only"))
    end

    harvestingthread = ThePlayer:StartThread(function()

        while ThePlayer:IsValid() do

            local cookware
            if endless then
                cookware = FindEntity(ThePlayer, 25, function(inst)

                    local act = CanRummageOrHarvest(inst)
                    if not (act and act.action == ACTIONS.HARVEST) then
                        return false
                    end

                    return inst and (inst.prefab == "portablespicer" or inst.prefab == "cookpot" or inst.prefab == "portablecookpot")
                end, {"stewer"}, {"INLIMBO", "burnt"})
            else
                local type
                for i,cookware in ipairs(harvestinglist) do
                    if not (cookware and cookware.entity and cookware.entity:IsVisible()) then
                        for i,v in ipairs(harvestinglist) do
                            if v == cookware then
                                table.remove(harvestinglist,i)
                                break
                            end
                        end
                    else
                        local act = CanRummageOrHarvest(cookware)
                        if act and act.action == ACTIONS.RUMMAGE then
                            for i,v in ipairs(harvestinglist) do
                                if v == cookware then
                                    table.remove(harvestinglist,i)
                                    break
                                end
                            end
                        end
                        type = cookware.prefab
                    end
                end
                if #harvestinglist == 0 then StopCooking() return end
                if not type then StopCooking() return end

                cookware = FindEntity(ThePlayer, 25, function(inst)

                    local incookpots = false
                    if harvestinglist then
                        for i,v in ipairs(harvestinglist) do
                            if inst == v then
                                incookpots = true
                                break
                            end
                        end
                        if not incookpots then return false end
                    end

                    local act = CanRummageOrHarvest(inst)
                    if not (act and act.action == ACTIONS.HARVEST) then
                        return false
                    end

                    return type ~= "portablespicer" and inst.prefab ~= "portablespicer"
                        or type == "portablespicer" and inst.prefab == type

                end, {"stewer"}, {"INLIMBO", "burnt"})
            end

            if cookware then
                local act = CanRummageOrHarvest(cookware)
                if act and act.action == ACTIONS.HARVEST then
                    while CanRummageOrHarvest(cookware) and CanRummageOrHarvest(cookware).action == ACTIONS.HARVEST do
                        SendActionAndWait(act,cookware)
                    end
                    --for i,v in ipairs(harvestinglist) do
                    --    if cookware == v then
                    --        table.remove(harvestinglist,i)
                    --        break
                    --    end
                    --end
                    table.removearrayvalue(harvestinglist, cookware)
                else
                    Sleep(0)
                end
            else
                if not endless then
                    local target = harvestinglist and harvestinglist[1]
                    if target and IsValidEntity(target) then
                        if not target:IsNear(ThePlayer, 2) then
                            local pos = target:GetPosition()
                            local act = BufferedAction(ThePlayer, target, ACTIONS.WALKTO, nil, pos)
                            if not ThePlayer:HasTag("moving") and ThePlayer:HasTag("idle") then
                                SendLeftClickAction(act, nil, pos)
                            --From Advanced Controls--
                            ThePlayer:DoTaskInTime(0, function() SendLeftClickAction(act, target, pos) end)
                            --From Advanced Controls--
                            end
                        end
                    end
                end
                Sleep(0)
            end
        end
    end)
end

local function FillCookware(cookware, items, cookpots)
    local harvesting_cookware = nil
    local harvest_cookware = nil
    repeat
        for i, v in ipairs(items) do

            if harvesting_cookware
                and harvesting_cookware:IsNear(cookware, 4)
                and CanRummageOrHarvest(harvest_cookware)
                and CanRummageOrHarvest(harvest_cookware).action == ACTIONS.HARVEST then

                harvest_cookware = harvesting_cookware
            else
                harvest_cookware = FindCookware(cookpots and "cookpot" or "portablespicer", true, cookpots, cookware, {cookware})
            end
            if harvest_cookware then
                local act = CanRummageOrHarvest(harvest_cookware)
                if act and act.action == ACTIONS.HARVEST then
                    SendLeftClickAction(act, harvest_cookware)
                end
                harvesting_cookware = harvest_cookware
            end

            local container, slot = GetItemSlot(v)
            if container then
                if cookware.prefab == "portablespicer" then
                    container:MoveItemFromAllOfSlot(slot, cookware)
                else
                    while not cookware.replica.container:GetItemInSlot(i) do
                        container:MoveItemFromAllOfSlot(slot, cookware)
                        Sleep(0)
                    end
                end
            end
        end
        Sleep(0)
    until HaveEnoughItems(items, nil, {cookware.replica.container})
    -- cookware.replica.container:IsFull()
end

local function AutoCooking(items, cookpots)

    cookingthread = ThePlayer:StartThread(function()

        while ThePlayer:IsValid() do
            local cookware
            for container in pairs(ThePlayer.replica.inventory:GetOpenContainers()) do
                if container.replica.container and container.replica.container.type == "cooker" then
                    cookware = container
                    if HaveEnoughItems(items, nil, {cookware.replica.container}) then
                        repeat
                            SendRPCToServer(RPC.DoWidgetButtonAction, ACTIONS.COOK.code, cookware, ACTIONS.COOK.mod_name)
                            Sleep(0)
                        until not CanRummageOrHarvest(cookware) or CanRummageOrHarvest(cookware).action ~= ACTIONS.RUMMAGE
                        if not table.contains(harvestinglist, cookware) then table.insert(harvestinglist, cookware) end
                    end
                    break
                end
            end

            local opend_container
            if not HaveEnoughItems(items) then
                HarvestOnly()
                return
            elseif not HaveEnoughItems(items, true) then
                for container, v in pairs(ThePlayer.replica.inventory:GetOpenContainers()) do
                    if container.replica.container and container.replica.container.type == "chest" then
                        opend_container = container
                        break
                    end
                end
            end

            cookware = cookware and cookware.replica.container:IsOpenedBy(ThePlayer) and cookware or FindCookware(cookpots and "cookpot" or "portablespicer", true, cookpots, opend_container)
            if not cookware then
                repeat
                    Sleep(0)
                    cookware = FindCookware(cookpots and "cookpot" or "portablespicer", true, cookpots, opend_container)
                    local target
                    for i, v in ipairs(harvestinglist) do
                        if v and v.entity and v.entity:IsVisible() and not (CanRummageOrHarvest(v) and CanRummageOrHarvest(v).action == ACTIONS.RUMMAGE) then
                            target = v
                            break
                        else
                            table.remove(harvestinglist, i)
                            break
                        end
                    end
                    if target and IsValidEntity(target) then
                        if not target:IsNear(ThePlayer, 2) then
                            local pos = target:GetPosition()
                            local act = BufferedAction(ThePlayer, target, ACTIONS.WALKTO, nil, pos)
                            if not ThePlayer:HasTag("moving") then
                                --From Advanced Controls--
                                SendLeftClickAction(act, nil, pos)
                                ThePlayer:DoTaskInTime(0, function() SendLeftClickAction(act, target, pos) end)
                                --From Advanced Controls--
                            end
                        end
                    end
                until cookware
            end

            local act = CanRummageOrHarvest(cookware)

            if act then
                if act.action == ACTIONS.RUMMAGE then

                    if not HaveEnoughItems(items) then
                        HarvestOnly()
                        return
                    end

                    while not cookware.replica.container:IsOpenedBy(ThePlayer) do
                        SendActionAndWait(act, cookware)
                    end

                    if not HaveEnoughItems(items) then
                        HarvestOnly()
                        return
                    end

                    --for i, v in ipairs(harvestinglist) do
                    --    if v == cookware then
                    --        table.remove(harvestinglist,i)
                    --    end
                    --end
                    table.removearrayvalue(harvestinglist, cookware) -- Use the function written in util.lua instead

                    if not TakeOutItemsInCookware(cookware) then return end
                    FillCookware(cookware, items, cookpots)

                    repeat
                        SendRPCToServer(RPC.DoWidgetButtonAction, ACTIONS.COOK.code, cookware, ACTIONS.COOK.mod_name)
                        Sleep(0)
                    until not CanRummageOrHarvest(cookware) or CanRummageOrHarvest(cookware).action ~= ACTIONS.RUMMAGE

                    --local contains = false
                    --for i, v in ipairs(harvestinglist) do
                    --    if v == cookware then
                    --        contains = true
                    --        break
                    --    end
                    --end
                    --if not contains then
                    --    table.insert(harvestinglist,cookware)
                    --end
                    if not table.contains(harvestinglist, cookware) then table.insert(harvestinglist, cookware) end -- Use the function written in util.lua instead

                elseif act.action == ACTIONS.HARVEST then
                    while CanRummageOrHarvest(cookware) and CanRummageOrHarvest(cookware).action == ACTIONS.HARVEST do
                        SendActionAndWait(act, cookware)
                    end

                    --for i,v in ipairs(harvestinglist) do
                    --    if cookware == v then
                    --        table.remove(harvestinglist,i)
                    --        break
                    --    end
                    --end
                    table.removearrayvalue(harvestinglist, cookware) -- Use the function written in util.lua instead

                else
                    Sleep(0)
                end
            else
                Sleep(0)
            end
        end
    end)
end

local function fn(is_last_recipe)

    if not InGame() then return end
    if ThePlayer:HasTag("playerghost") then return end

    if not is_last_recipe and (cookingthread or harvestingthread) then StopCooking() return end

    local overflow = ThePlayer.replica.inventory:GetOverflowContainer()
    local backpack = overflow and overflow.inst
    --if not (backpack and backpack.replica.container) then Say(GetString("no_backpack")) return end

    local items
    local type
    if is_last_recipe then
        type = is_last_recipe
        items = lastest_recipe
    else
        items, type = CheckCookwareItems()
        if not items then
            if backpack and backpack.replica.container then
                items, type = CheckBackpackItems(backpack)
            end
            if not items then
                --Say(GetString("not_valid_items"))
                items, type = CheckInventoryItems()
                if not items then HarvestOnly(true) return end
            end
        end

        Say(GetString("start"))
    end

    ismasterchef = ThePlayer:HasTag("masterchef")
    if type == "AddSpices" then
        -- if ThePlayer:HasTag("masterchef") then
            if not FindCookware("portablespicer") then
                local str = ismasterchef and "no_portablespicer" or "no_masterchef"
                Say(GetString(str))
                return false
            end
            lastest_recipe = items
            lastest_recipe_type = type
            AutoCooking(items)
            return true
        -- else
        --     Say(GetString("no_masterchef"))
        --     return false
        -- end
    elseif type == "AutoCooking" then

        local cookpot = FindCookware("cookpot")
        local cookingtime = 0
        if cookpot then
            local items_prefab = {}
            for i, v in ipairs(items) do
                items_prefab[i] = items[i].prefab
            end
            local food, cookingtime = cooking.CalculateRecipe(cookpot.prefab, items_prefab)
            if cookpot.prefab == "portablecookpot" then
                cookingtime = TUNING.BASE_COOK_TIME * cookingtime * TUNING.PORTABLE_COOK_POT_TIME_MULTIPLIER
            elseif cookpot.prefab == "medal_cookpot" and TUNING_MEDAL and TUNING_MEDAL.PORTABLE_COOK_POT_TIME_MULTIPLIER then  -- For Functional Medal Mod
                cookingtime = TUNING.BASE_COOK_TIME * cookingtime * TUNING_MEDAL.PORTABLE_COOK_POT_TIME_MULTIPLIER
            else
                cookingtime = TUNING.BASE_COOK_TIME * cookingtime
            end
            local cookpot_num = math.ceil(cookingtime / cookpots_num_divisor) + 1
            local cookpots = {}
            local firstcookpot = cookpot
            table.insert(cookpots, firstcookpot)
            local cookpot
            for i = 1, cookpot_num do
                cookpot = FindEntity(firstcookpot, 25, function(inst)
                    return not table.contains(cookpots, inst)
                        and (
                            inst.prefab == firstcookpot.prefab or
                            table.contains(cookware_morph[firstcookpot.prefab], inst.prefab)
                        )
                end, {"stewer"}, {"INLIMBO", "burnt"})
                if cookpot then
                    table.insert(cookpots, cookpot)
                else
                    break
                end
            end
            lastest_recipe = items
            lastest_recipe_type = type
            AutoCooking(items, cookpots)
            return true
        else
            Say(GetString("no_cookpot"))
            return false
        end
    end

end

--from action queue reborn--

local interrupt_controls = {}
local mouse_controls = { [CONTROL_PRIMARY] = true, [CONTROL_SECONDARY] = true }
for control = CONTROL_ATTACK, CONTROL_MOVE_RIGHT do
    interrupt_controls[control] = true
end

AddComponentPostInit("playercontroller", function(self)
    if self.inst ~= ThePlayer then return end

    local PlayerControllerOnControl = self.OnControl
    self.OnControl = function(self, control, down, ...)
        local mouse_control = mouse_controls[control]
        local interrupt_control = interrupt_controls[control]
        if down and InGame() then
            if interrupt_control or mouse_control and not (key_2 and TheInput:IsKeyDown(key_2)) and not TheInput:GetHUDEntityUnderMouse() then
                if cookingthread or harvestingthread then
                    StopCooking()
                end
            end

            if mouse_control and key_2 and TheInput:IsKeyDown(key_2) then
                local ent = TheInput:GetWorldEntityUnderMouse()
                if not (cookingthread or harvestingthread) and not TheInput:GetHUDEntityUnderMouse()
                        and ent and table.contains(cookware_prefabs, ent.prefab) and IsValidEntity(ent) then
                    fn()
                    return
                end
            end
        end
        return PlayerControllerOnControl(self, control, down, ...)
    end
end)

--from action queue reborn--

if last_recipe_mode == "last" then
    local containers = require("containers")
    local params = containers.params
    for _, v in ipairs(cookware_prefabs) do
        local OldWidgetFn = params[v] and params[v].widget and params[v].widget.buttoninfo and params[v].widget.buttoninfo.fn
        if OldWidgetFn then
            params[v].widget.buttoninfo.fn = function(inst, ...)
                local items = inst.replica.container and inst.replica.container:GetItems()
                if items and type(items) == "table" then
                    lastest_recipe = {}
                    lastest_recipe_type = inst.prefab == "portablespicer" and "AddSpices" or "AutoCooking"
                    for slot, item in pairs(items) do
                        table.insert(lastest_recipe, item)
                    end
                end
                return OldWidgetFn(inst, ...)
            end
        end
    end
end

TheInput:AddKeyUpHandler(toggle_key, fn)
TheInput:AddKeyUpHandler(lastest_recipe_key, function()

    if not InGame() then return end
    if ThePlayer:HasTag("playerghost") then return end

    if not lastest_recipe then
        Say(GetString("no_previous_recipe"))
        return
    end
    if cookingthread or harvestingthread then return end

    if not HaveEnoughItems(lastest_recipe) then
        --Say(GetString("unable_cook_last_recipe"))
        HarvestOnly(true)
        return
    end

    Say(GetString("last_recipe"))
    fn(lastest_recipe_type)
end)

if laggy_mode == "in_game" then
    TheInput:AddKeyUpHandler(laggy_mode_key, function()
        if not InGame() then return end
        laggy_mode_on = not laggy_mode_on
        Say(GetString(laggy_mode_on and "laggy_mode_on" or "laggy_mode_off"))
    end)
end
