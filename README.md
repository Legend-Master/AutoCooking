# Auto Cooking

A Don't Starve Together mod for auto cooking

## Features

- Press start button to start auto cooking by using 2/4 slots of items from cookpot/seasoning station/backpack/inventory
- Pressing start button when don't have enough items, it will go in to "endless harvest mode" which will harvest all cookpots/seasoning stations near you endlessly
- You could stop the cooking by simply using any movement, primary, secondary, attack, or action key, just like the way you cancel the action queue from Action Queue Reborn
- It will remember the cooking material and fill the cookpot/seasoning station by using materials from any of opened containers
- It will select just enough cookpots for cooking to avoid using too many cookpots (Just because that looks so stupid, e.g. You want to cook some icecreams, and you got 20 cookpots, it will eventually only use the last 4 cookpots...)
- Press "Lastest Recipe Key" to cook lastest recipe you ever did
- If you're realy laggy, try to use "Laggy Mode", but it still has chance to open and close the cookpot over and over again

## Configable Options

- Language: Auto / English / Simplified Chinese
- Key to start the cooking (Default: F5)
- Action Key 2, this key + click on cookware to start (Default: Off)
- Key to start the cooking lastest recipe (Default: Home)
- Integrated Key, start cooking items from opened cookware or lastest cooking recipe / endless harvest mode (Default: Off)
- Ultra Fast Mode (Default: Off)
- Num of Cookpots
- Laggy mode: Off / On / In-game button (Default: Off)
- If you choose "In-game button" from "Laggy Mode", you can give it a key to toggle laggy mode in game (Default: Right Shift)

## Known Issues

- When you hold something on you mouse, it will pause the cooking, and I have no idea how to fix it since you can't do a rummage action when you have the activeitem (& It wouldn't start cooking when something is on you mouse)

## For Modders

I don't really wanna make too much of modded cookware supports for this mod
since over all, a lot of decisions are made based on the vanilla game,
and may not suit for modded cookwares.

But if you got something similar to the vanilla and want to make a support for this mod,
you could do the following in your mod (e.g.):

```lua
local cookware_morphs = {
    cookpot = { -- What morph is it (one of [cookpot, portablecookpot, portablespicer])
        deluxpot = true, -- Your cookware name
    }
}
```

Do this if you're on mod env

```lua
local AUTO_COOKING_COOKWARES = GLOBAL.rawget(GLOBAL, "AUTO_COOKING_COOKWARES") or {}
GLOBAL.AUTO_COOKING_COOKWARES = AUTO_COOKING_COOKWARES
```

Or this if you're on GLOBAL env

```lua
AUTO_COOKING_COOKWARES = rawget(_G, "AUTO_COOKING_COOKWARES") or {}
```

Do this at the end

```lua
for base, morphs in pairs(cookware_morphs) do
    AUTO_COOKING_COOKWARES[base] = shallowcopy(morphs, AUTO_COOKING_COOKWARES[base])
end
```

---

Special Thanks：秋一(Civi) for testing and suggesting those amazing ideas
