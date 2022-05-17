local function GetKeyFromConfig(config)
    local key = GetModConfigData(config, true)
    if key == "no_toggle_key" then
        key = -1
    elseif type(key) == "string" then
        key = GLOBAL.rawget(GLOBAL, key)
    end
    return type(key) == "number" and key or -1
end

local language              = GetModConfigData("language")
local speedy_mode           = GetModConfigData("speedy_mode")
local cookpots_num_divisor  = GetModConfigData("cookpots_num_divisor")
local laggy_mode            = GetModConfigData("laggy_mode")

local key_2                 = GetKeyFromConfig("key_2")

local laggy_mode_on = laggy_mode == "on"

local ENV = env
GLOBAL.setfenv(1, GLOBAL)

local cooking = require("cooking")

local SEASONING = "seasoning"
local COOKING = "cooking"

local STEWER_RANGE = 25
local AUTO_CLOSE_RANGE = 4
local SLEEP_TIME = FRAMES * 3

local COOKWARE_MUSTTAGS = {"stewer"}
local COOKWARE_CANTTAGS = {"INLIMBO", "burnt"}
local NO_MASTERCHEF_CANTTAGS = {"INLIMBO", "burnt", "mastercookware"}

local supported_cookwares = {
    "cookpot",
    "portablecookpot",
    "portablespicer",
    "archive_cookpot",
    "deluxpot",         -- From Deluxe cooking pot
    "medal_cookpot",    -- From Functional medal
}
local cookware_morph = {
    cookpot = {
        "portablecookpot",
        "deluxpot",
        "archive_cookpot"
    },
    portablecookpot = {
        "medal_cookpot"
    }
}
for _, v in ipairs(cookware_morph.portablecookpot) do
    table.insert(cookware_morph.cookpot, v)
end

local ac_thread
local harvestinglist = {}

local last_recipe
local last_recipe_type
local ismasterchef
local should_harvest

-- From ActionQueue Reborn
local function InGame()
    return ThePlayer and ThePlayer.HUD and not ThePlayer.HUD:HasInputFocus()
end

local function AddKeyUpHandlerForConfig(config, fn)
    local key = GetKeyFromConfig(config)
    if key ~= -1 then
        return TheInput:AddKeyUpHandler(key, function()
            if InGame() then
                fn()
            end
        end)
    end
end

local function Say(str)
    local talker = ThePlayer and ThePlayer.components.talker
    if talker then
        talker:Say(str)
    end
end

local AC_STRINGS = {
    ["no_previous_recipe"] = "No previous cooking recipe found",
    -- ["unable_cook_last_recipe"] = "Unable to cook last recipe",
    ["start"] = "Auto Cooking : On",
    ["stop"] = "Auto Cooking : Off",
    ["no_masterchef"] = "Don't have masterchef tag",
    ["no_portablespicer"] = "Didn't find portablespicer",
    ["no_cookpot"] = "Didn't find cookpot",
    ["cant_move_out_items"] = "Can't move out item from cookpot",
    ["harvest_only"] = "Materials run out, Harvest Mode On",
    ["harvest_only_endless"] = "Endless Harvest Mode On",
    ["last_recipe"] = "Cooking last recipe",
    ["laggy_mode_on"] = "Auto Cooking : Laggy Mode On",
    ["laggy_mode_off"] = "Auto Cooking : Laggy Mode Off",
}

local LOC_STRINGS = {
    chinese_s = {
        ["no_previous_recipe"] = "未找到上次烹饪配方",
        -- ["unable_cook_last_recipe"] = "无法烹饪上个配方",
        ["start"] = "自动做饭:开启",
        ["stop"] = "自动做饭:关闭",
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
}

if language == "auto" then
    local langs = {
        zh = "chinese_s",
        chs = "chinese_s",
    }
    language = langs[LanguageTranslator.defaultlang]
end

if LOC_STRINGS[language] then
    AC_STRINGS = LOC_STRINGS[language]
end

local function GetString(stringtype)
    return AC_STRINGS[stringtype]
end

local function FormatItemsAmount(items)
    local itemlist = {}
    for _, v in ipairs(items) do
        if not itemlist[v.prefab] then
            itemlist[v.prefab] = 1
        else
            itemlist[v.prefab] = itemlist[v.prefab] + 1
        end
    end
    return itemlist
end

-- From ActionQueue Reborn
local function IsValidEntity(ent)
    return ent and ent.Transform and ent:IsValid() and not ent:HasTag("INLIMBO")
end

local function GetClosestTarget(ents, test_fn)
    local x, y, z = ThePlayer.Transform:GetWorldPosition()

    local mindistsq, target
    for _, ent in ipairs(ents) do
        if test_fn == nil or test_fn(ent) then
            local curdistsq = ent:GetDistanceSqToPoint(x, y, z)
            if not mindistsq or curdistsq < mindistsq then
                mindistsq = curdistsq
                target = ent
            end
        end
    end

    return target
end

local function IsCookwareMorph(base, prefab)
    return base == prefab
        or table.contains(cookware_morph[base], prefab)
end

-- Sigh, why inventory_replica.GetOpenContainers not checking isopen...
local function GetOpenContainers()
    if ThePlayer.components.inventory ~= nil then
        return ThePlayer.components.inventory.opencontainers

    elseif ThePlayer.HUD ~= nil then
        local containers = {}
        for k, v in pairs(ThePlayer.HUD.controls.containers) do
            if v ~= nil and v.inst.entity:IsVisible() and v.isopen and k:IsValid() then -- Check isopen
                containers[k] = true
            end
        end
        local overflow = ThePlayer.replica.inventory:GetOverflowContainer()
        if overflow and overflow.inst then
            containers[overflow.inst] = true
        end
        return containers

    else
        return {}

    end
end

local function CanHarvest(target)
    return should_harvest and target:HasTag("donecooking")
end

local function CanRummage(target)
    return target.replica.container
        and target.replica.container:CanBeOpened()
end

-- From ActionQueue Reborn
local function Wait(act)
    repeat
        Sleep(SLEEP_TIME)
    until not (ThePlayer.sg and ThePlayer.sg:HasStateTag("moving")) and not ThePlayer:HasTag("moving")
        and (not (act and act.action == ACTIONS.RUMMAGE) or ThePlayer:HasTag("idle") and not ThePlayer.components.playercontroller:IsDoingOrWorking())
    if laggy_mode_on then Sleep(0.3) end
end

local function SendLeftClickAction(act, target)

    local playercontroller = ThePlayer.components.playercontroller
    if playercontroller.ismastersim then
        ThePlayer.components.combat:SetTarget(nil)
        playercontroller:DoAction(act)
        return
    end

    local pos = act:GetActionPoint() or ThePlayer:GetPosition()
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

local function SendActionAndWait(act, target)
    SendLeftClickAction(act, target)
    Wait(act)
end

local function CheckBackpackItems(backpack)

    local slot_1 = backpack:GetItemInSlot(1)
    local slot_2 = backpack:GetItemInSlot(2)

    if slot_1 and slot_2 then
        if (
            slot_1:HasTag("spice")
            and slot_2:HasTag("preparedfood") and not slot_2:HasTag("spicedfood")
        ) or (
            slot_2:HasTag("spice")
            and slot_1:HasTag("preparedfood") and not slot_1:HasTag("spicedfood")
        ) then

            return {slot_1, slot_2}, SEASONING
        else
            local items = {}
            for i = 1, 4 do
                local item = backpack:GetItemInSlot(i)
                if not (item and cooking.IsCookingIngredient(item.prefab)) then
                    return
                end
                table.insert(items, item)
            end
            return items, COOKING
        end
    end
end

local function CheckInventoryItems()

    local items = ThePlayer.replica.inventory:GetItems()

    local item_list = {}

    local function CheckNext(slot, counter, spiceorfood)

        for k, item in pairs(items) do
            if k == slot + 1 then
                if spiceorfood then
                    if spiceorfood == "spice" then
                        if item:HasTag("preparedfood") and not item:HasTag("spicedfood") then
                            table.insert(item_list, item)
                            return true
                        end
                    elseif spiceorfood == "preparedfood" then
                        if item:HasTag("spice") then
                            table.insert(item_list, item)
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
                table.insert(item_list, item)
                return item_list, COOKING
            end
        elseif item:HasTag("spice") then
            if CheckNext(slot, 1, "spice") then
                table.insert(item_list, item)
                return item_list, SEASONING
            end
        elseif item:HasTag("preparedfood") and not item:HasTag("spicedfood") then
            if CheckNext(slot, 1, "preparedfood") then
                table.insert(item_list, item)
                return item_list, SEASONING
            end
        end
    end
    return false
end

local function CheckCookwareItems()
    local item_list = {}
    for container in pairs(GetOpenContainers()) do
        if container.replica.container
            and table.contains(supported_cookwares, container.prefab)
            and container.replica.container.widget.buttoninfo.validfn(container) then

            for slot, item in pairs(container.replica.container:GetItems()) do
                table.insert(item_list, item)
            end
            return item_list, IsCookwareMorph("portablespicer", container.prefab) and SEASONING or COOKING, container
        end
    end
end

local function find_cookware(prefab, canttags)
    return FindEntity(ThePlayer, STEWER_RANGE, function(inst)
        return IsCookwareMorph(prefab, inst.prefab)
    end, COOKWARE_MUSTTAGS, canttags)
end

local function GetStartCookware(cookware_type)
    local canttags = ismasterchef and COOKWARE_CANTTAGS or NO_MASTERCHEF_CANTTAGS
    if cookware_type == COOKING then
        return find_cookware("portablecookpot", canttags) or find_cookware("cookpot", canttags)
    elseif cookware_type == SEASONING then
        return find_cookware("portablespicer", canttags)
    end
end

local function GetClosestValidCookware(cookwares, actioncheck, container, cant_cookwares)
    return GetClosestTarget(cookwares, function(inst)
        return not (
            container and not container:IsNear(inst, AUTO_CLOSE_RANGE) -- Check this to prevents us from closing the opened container when try to go to another one
            or actioncheck and not (CanHarvest(inst) or CanRummage(inst))
            or cant_cookwares and table.contains(cant_cookwares, inst)
        )
    end)
end

local function GetDefaultCheckingContainers(inv_only)
    local inventory = ThePlayer.replica.inventory
    local containers = { inventory:GetActiveItem(), inventory }
    if inv_only then
        table.insert(containers, inventory:GetOverflowContainer())
    else
        for container in pairs(GetOpenContainers()) do
            if not table.contains(supported_cookwares, container.prefab) then
                local container_replica = container.replica.container
                if container_replica then
                    table.insert(containers, container_replica)
                end
            end
        end
    end
    return containers
end

local function HaveEnoughItems(items, containers)

    items = FormatItemsAmount(items)
    containers = containers or GetDefaultCheckingContainers()

    local item_amount = {}
    for k in pairs(items) do
        item_amount[k] = 0
    end

    local function try_add(item)
        local prefab = item.prefab
        if items[prefab] then
            if item.replica.stackable then
                item_amount[prefab] = item_amount[prefab] + item.replica.stackable:StackSize()
            else
                item_amount[prefab] = item_amount[prefab] + 1
            end
        end
    end

    for _, container in orderedPairs(containers) do
        if type(container) == "table" then
            if container.is_a and container:is_a(EntityScript) then
                try_add(container)
            elseif container.GetItems then
                local items = container:GetItems()
                for _, v in orderedPairs(items) do
                    try_add(v)
                end
            end
        end
    end

    for prefab, amount in pairs(items) do
        if item_amount[prefab] < amount then
            return false
        end
    end
    return true

end

local function GetItemSlot(item)
    local item_valid = item:IsValid() and item.replica.inventoryitem and item.replica.inventoryitem:IsHeldBy(ThePlayer)
    local final_container, final_slot
    for _, container in orderedPairs(GetDefaultCheckingContainers()) do
        if type(container) == "table" and container.GetItems then
            local items = container:GetItems()
            for k, v in orderedPairs(items) do
                -- If given item is valid and we can find it's slot, return it
                if item_valid and v == item or not item_valid and v.prefab == item.prefab then
                    items.__orderedIndex = nil
                    return container, k
                -- If we can't, try to cache the item with same prefab/type
                elseif not final_container and v.prefab == item.prefab then
                    final_container, final_slot = container, k
                end
            end
        end
    end
    return final_container, final_slot
end

-- For Ultra Fast Mode
local function GetItems(required_items)
    required_items = shallowcopy(required_items)
    local final_steps = {}
    for _, container in orderedPairs(GetDefaultCheckingContainers()) do
        if type(container) == "table" and container.GetItems then
            local items = container:GetItems()
            for slot, item in orderedPairs(items) do
                if required_items[item.prefab] then
                    local steps = item.replica.stackable and math.min(item.replica.stackable:StackSize(), required_items[item.prefab]) or 1
                    for i = 1, steps do
                        table.insert(final_steps, {container = container.inst, slot = slot})
                    end
                    required_items[item.prefab] = required_items[item.prefab] - steps
                    if required_items[item.prefab] == 0 then
                        required_items[item.prefab] = nil
                    end
                    if IsTableEmpty(required_items) then
                        items.__orderedIndex = nil
                        return final_steps
                    end
                end
            end
        end
    end
    return IsTableEmpty(required_items) and final_steps or nil
end

local function TakeOutItemsInCookware(cookware)
    -- If something's in that cookware, take it out
    local container = cookware.replica.container
    while not (cookware:IsValid() and container:IsEmpty()) do
        for i = 1, container:GetNumSlots() do
            if container:GetItemInSlot(i) then
                if ThePlayer.replica.inventory:IsFull() then
                    local backpack = ThePlayer.replica.inventory:GetOverflowContainer()
                    if backpack and not backpack:IsFull() then
                        SendRPCToServer(RPC.MoveItemFromAllOfSlot, i, cookware, backpack.inst)
                    else
                        Say(GetString("cant_move_out_items"))
                        return false
                    end
                else
                    SendRPCToServer(RPC.MoveItemFromAllOfSlot, i, cookware)
                end
            end
        end
        Sleep(SLEEP_TIME)
    end
    return true
end

local function StopCooking()
    if ac_thread then
        Say(GetString("stop"))
        ac_thread:SetList(nil)
        ac_thread = nil
    end
end

local MAX_HARVEST_DIST = 64
local function GetHarvestTarget()
    for i = #harvestinglist, 1, -1 do
        local cookware = harvestinglist[i]
        -- A valid harvest target should be valid & cooking/donecooking/can't be opened & not too far away
        if not (
            IsValidEntity(cookware)
            and not CanRummage(cookware)
            and ThePlayer:IsNear(cookware, MAX_HARVEST_DIST)
        ) then
            table.remove(harvestinglist, i)
        end
    end

    local harvestable_cookwares = {}
    for _, cookware in ipairs(harvestinglist) do
        if CanHarvest(cookware) then
            table.insert(harvestable_cookwares, cookware)
        end
    end
    if #harvestable_cookwares > 0 then
        return GetClosestTarget(harvestable_cookwares), true
    else
        return harvestinglist[1]
    end
end

local function DoHarvest(target, single)
    local act = BufferedAction(ThePlayer, target, ACTIONS.HARVEST)
    if single then
        SendLeftClickAction(act, target)
    else
        repeat
            SendActionAndWait(act, target)
        until not CanHarvest(target)
        table.removearrayvalue(harvestinglist, target)
    end
end

local function DoRummage(target)
    local act = BufferedAction(ThePlayer, target, ACTIONS.RUMMAGE)
    while not (target.replica.container and target.replica.container:IsOpenedBy(ThePlayer)) do
        SendActionAndWait(act, target)
    end
    table.removearrayvalue(harvestinglist, target)
end

local function TryWalkTo(target)
    if target and not target:IsNear(ThePlayer, 2) then
        local pos = target:GetPosition()
        local act = BufferedAction(ThePlayer, target, ACTIONS.WALKTO, nil, pos)
        if not ThePlayer:HasTag("moving") and ThePlayer:HasTag("idle") then
            SendLeftClickAction(act)
            ThePlayer:DoTaskInTime(0, function() SendLeftClickAction(act, target) end) -- From Advanced Controls
        end
    end
end

local function find_endless_target(inst)
    return table.contains(supported_cookwares, inst.prefab)
        and CanHarvest(inst)
end

local function HarvestOnly(endless)

    local function harvest_thread()
        while ThePlayer:IsValid() do
            if endless then
                local target = FindEntity(ThePlayer, STEWER_RANGE, find_endless_target, COOKWARE_MUSTTAGS, COOKWARE_CANTTAGS)
                if target then
                    DoHarvest(target)
                else
                    Sleep(SLEEP_TIME)
                end
            else
                local target, can_harvest = GetHarvestTarget()
                if not target then break end
                if can_harvest then
                    DoHarvest(target)
                else
                    TryWalkTo(target)
                    Sleep(SLEEP_TIME)
                end
            end
        end
        StopCooking()
    end

    Say(GetString(endless and "harvest_only_endless" or "harvest_only"))

    should_harvest = true

    if ac_thread then
        harvest_thread()
    else
        ac_thread = ThePlayer:StartThread(harvest_thread)
    end
end

local function DoButtonFn(container, single)
    local container_replica = container.replica.container
    if single then
        container_replica.widget.buttoninfo.fn(container, ThePlayer)
        return
    end

    while container:IsValid() and container_replica:IsOpenedBy(ThePlayer) do
        container_replica.widget.buttoninfo.fn(container, ThePlayer)
        Sleep(SLEEP_TIME)
    end

    -- Well, doing this is because opener & can open changes can happen at different time on client...
    while container:IsValid() and container_replica:CanBeOpened() do
        Sleep(SLEEP_TIME)
    end

    if not table.contains(harvestinglist, container) then
        table.insert(harvestinglist, container)
    end
end

local harvesting_cookware
local function ShouldKeepHarvertTarget()
    return harvesting_cookware
        and harvesting_cookware:IsValid()
        and CanHarvest(harvesting_cookware)
end

local function TryHarvestWhenFilling(cookware, cookwares)
    if not should_harvest then return end
    local harvest_cookware
    if ShouldKeepHarvertTarget() and harvesting_cookware:IsNear(cookware, AUTO_CLOSE_RANGE) then
        harvest_cookware = harvesting_cookware
    else
        harvest_cookware = GetClosestValidCookware(cookwares, true, cookware, {cookware})
    end
    if harvest_cookware then
        harvesting_cookware = harvest_cookware
        DoHarvest(harvest_cookware, true)
    end
end

local function DoFillUpAndCook(cookware, items, cookwares)
    local container_replica = cookware.replica.container
    repeat
        if speedy_mode then
            TryHarvestWhenFilling(cookware, cookwares)

            local steps = GetItems(FormatItemsAmount(items))
            if steps then
                for _, data in ipairs(steps) do
                    if data.container == ThePlayer then
                        SendRPCToServer(RPC.MoveInvItemFromAllOfSlot, data.slot, cookware)
                    else
                        SendRPCToServer(RPC.MoveItemFromAllOfSlot, data.slot, data.container, cookware)
                    end
                end
                DoButtonFn(cookware, true)
            end
            Sleep(SLEEP_TIME)
        else
            for i, v in ipairs(items) do
                TryHarvestWhenFilling(cookware, cookwares)

                local container, slot = GetItemSlot(v)
                if container then
                    if IsCookwareMorph("portablespicer", cookware.prefab) then
                        container:MoveItemFromAllOfSlot(slot, cookware)
                        Sleep(SLEEP_TIME)

                    elseif not container_replica:GetItemInSlot(i) then
                        repeat
                            container:MoveItemFromAllOfSlot(slot, cookware)
                            Sleep(SLEEP_TIME)
                        until cookware:IsValid() and container_replica:GetItemInSlot(i)

                    else
                        Sleep(SLEEP_TIME)

                    end
                else
                    Sleep(SLEEP_TIME)
                end
            end
        end
    until not cookware:IsValid()
        or not container_replica:IsOpenedBy(ThePlayer)
        or HaveEnoughItems(items, {container_replica})
    -- cookware.replica.container:IsFull()
    DoButtonFn(cookware)

    if ShouldKeepHarvertTarget() then
        DoHarvest(harvesting_cookware)
    end
    harvesting_cookware = nil
end

local function AutoCooking(items, cookwares)

    ac_thread = ThePlayer:StartThread(function()

        while ThePlayer:IsValid() do
            local cookware
            for container in pairs(GetOpenContainers()) do
                local container_replica = container.replica.container
                if container_replica and container_replica.type == "cooker" then
                    if HaveEnoughItems(items, {container_replica}) then
                        DoButtonFn(container)
                    else
                        cookware = container
                    end
                    break
                end
            end

            -- Check if we need to keep a container open to have enough items to cook
            local opened_container
            if not HaveEnoughItems(items, GetDefaultCheckingContainers(true)) then
                for container in pairs(GetOpenContainers()) do
                    local container_replica = container.replica.container
                    if container_replica and container_replica.type == "chest" then
                        local containers = table.insert(GetDefaultCheckingContainers(true), container_replica)
                        if HaveEnoughItems(items, containers) then
                            opened_container = container
                            break
                        end
                    end
                end
                if not opened_container then break end
            end

            cookware = cookware or GetClosestValidCookware(cookwares, true, opened_container)
            if not cookware then
                repeat
                    TryWalkTo(GetHarvestTarget())
                    Sleep(SLEEP_TIME)
                    cookware = GetClosestValidCookware(cookwares, true, opened_container)
                until cookware
            end

            if CanRummage(cookware) then
                if not HaveEnoughItems(items) then break end
                DoRummage(cookware)
                if not HaveEnoughItems(items) then break end

                if not TakeOutItemsInCookware(cookware) then
                    StopCooking()
                    return
                end
                DoFillUpAndCook(cookware, items, cookwares)

            elseif CanHarvest(cookware) then
                DoHarvest(cookware)

            else -- Not possible?
                Sleep(SLEEP_TIME)

            end

        end

        HarvestOnly()
        -- Will be stopped from harvest part
        -- StopCooking()
    end)
end

local function GetStartingItems(use_last_recipe)
    if use_last_recipe then
        return last_recipe, last_recipe_type
    end
    -- Cookware -> Backpack -> Inventory
    local items, cooking_type, cookware = CheckCookwareItems()
    if not items then
        local overflow = ThePlayer.replica.inventory:GetOverflowContainer()
        if overflow then
            items, cooking_type = CheckBackpackItems(overflow)
        end
        if not items then
            return CheckInventoryItems()
        end
    end
    return items, cooking_type, cookware
end

local function GetStartingCookwares(first_cookware, items, cooking_type)

    local cookwares = { first_cookware }
    local target_prefab = first_cookware.prefab
    local x, _, z = first_cookware.Transform:GetWorldPosition()
    local ents = TheSim:FindEntities(x, 0, z, STEWER_RANGE, COOKWARE_MUSTTAGS, ismasterchef and COOKWARE_CANTTAGS or NO_MASTERCHEF_CANTTAGS)

    if not should_harvest or cooking_type ~= COOKING or TheInput:IsKeyDown(KEY_SHIFT) then
        for _, ent in ipairs(ents) do
            if IsCookwareMorph(target_prefab, ent.prefab) then
                table.insert(cookwares, ent)
            end
        end
        return cookwares
    end

    local item_prefabs = {}
    for i, v in ipairs(items) do
        item_prefabs[i] = items[i].prefab
    end
    local _, cookingtime = cooking.CalculateRecipe(target_prefab, item_prefabs)
    cookingtime = cookingtime * TUNING.BASE_COOK_TIME

    if target_prefab == "portablecookpot" then
        cookingtime = cookingtime * TUNING.PORTABLE_COOK_POT_TIME_MULTIPLIER

    elseif target_prefab == "medal_cookpot" and rawget(_G, TUNING_MEDAL) and TUNING_MEDAL.PORTABLE_COOK_POT_TIME_MULTIPLIER then  -- For Functional Medal Mod
        cookingtime = cookingtime * TUNING_MEDAL.PORTABLE_COOK_POT_TIME_MULTIPLIER

    end

    local needed_num = math.ceil(cookingtime / cookpots_num_divisor) + 1
    local cur_num = 0
    for _, ent in ipairs(ents) do
        if IsCookwareMorph(target_prefab, ent.prefab) then
            table.insert(cookwares, ent)
            cur_num = cur_num + 1
            if cur_num == needed_num then
                break
            end
        end
    end
    return cookwares

end

local function Start(use_last_recipe, override_data)

    if ac_thread then StopCooking() return end

    local items, cooking_type, start_cookware
    if override_data then
        items, cooking_type, start_cookware = unpack(override_data)
    else
        items, cooking_type, start_cookware = GetStartingItems(use_last_recipe)
    end

    if not items then
        HarvestOnly(true)
        return
    end

    if not use_last_recipe then
        Say(GetString("start"))
    end

    ismasterchef = ThePlayer:HasTag("masterchef")
    should_harvest = not TheInput:IsKeyDown(KEY_CTRL)

    local first_cookware = start_cookware or GetStartCookware(cooking_type)

    if first_cookware then
        last_recipe, last_recipe_type = items, cooking_type
        AutoCooking(items, GetStartingCookwares(first_cookware, items, cooking_type))

    elseif cooking_type == SEASONING then
        Say(GetString(ismasterchef and "no_portablespicer" or "no_masterchef"))

    elseif cooking_type == COOKING then
        Say(GetString("no_cookpot"))

    end

end

local containers = require("containers")
local params = containers.params
for _, v in ipairs(supported_cookwares) do
    local OldWidgetFn = params[v] and params[v].widget and params[v].widget.buttoninfo and params[v].widget.buttoninfo.fn
    if OldWidgetFn then
        params[v].widget.buttoninfo.fn = function(inst, ...)
            if not ac_thread then
                local items = inst.replica.container and inst.replica.container:GetItems()
                if items and type(items) == "table" then
                    last_recipe = {}
                    last_recipe_type = IsCookwareMorph("portablespicer", inst.prefab) and SEASONING or COOKING
                    for slot, item in pairs(items) do
                        table.insert(last_recipe, item)
                    end
                end
            end
            return OldWidgetFn(inst, ...)
        end
    end
end

-- From ActionQueue Reborn

local interrupt_controls = {}
local mouse_controls = { [CONTROL_PRIMARY] = true, [CONTROL_SECONDARY] = true }
for control = CONTROL_ATTACK, CONTROL_MOVE_RIGHT do
    interrupt_controls[control] = true
end

local PlayerController = require("components/playercontroller")

local on_control = PlayerController.OnControl
function PlayerController:OnControl(control, down, ...)
    if down and InGame() then
        local mouse_control = mouse_controls[control]
        local interrupt_control = interrupt_controls[control]
        if ac_thread then
            if interrupt_control or mouse_control and not TheInput:GetHUDEntityUnderMouse() then
                StopCooking()
            end
        elseif key_2 ~= -1 and control == CONTROL_PRIMARY and TheInput:IsKeyDown(key_2) then
            local ent = TheInput:GetWorldEntityUnderMouse()
            if ent and table.contains(supported_cookwares, ent.prefab) and IsValidEntity(ent) then
                Start()
                return
            end
        end
    end
    return on_control(self, control, down, ...)
end

ENV.AddComponentPostInit("playercontroller", function(self)
    if self.inst == ThePlayer then
        self.inst:ListenForEvent("aqp_threadstart", StopCooking) -- For AttackQueue Plus
    end
end)

AddKeyUpHandlerForConfig("key", Start)

AddKeyUpHandlerForConfig("last_recipe_key", function()

    if not last_recipe then
        Say(GetString("no_previous_recipe"))
        return
    end
    if ac_thread then StopCooking() return end

    if not HaveEnoughItems(last_recipe) then
        -- Say(GetString("unable_cook_last_recipe"))
        HarvestOnly(true)
        return
    end

    Say(GetString("last_recipe"))
    Start(true)
end)

AddKeyUpHandlerForConfig("integrated_key", function()

    if ac_thread then StopCooking() return end

    local items, cooking_type, cookware = CheckCookwareItems()
    if items then
        Say(GetString("start"))
        Start(true, {items, cooking_type, cookware})

    elseif last_recipe and HaveEnoughItems(last_recipe) then
        Say(GetString("last_recipe"))
        Start(true)

    else
        HarvestOnly(true)

    end
end)

if laggy_mode == "in_game" then
    AddKeyUpHandlerForConfig("laggy_mode_key", function()
        laggy_mode_on = not laggy_mode_on
        Say(GetString(laggy_mode_on and "laggy_mode_on" or "laggy_mode_off"))
    end)
end
