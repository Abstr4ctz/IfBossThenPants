# IfBossThenPants (Vanilla WoW 1.12)

## What is it?
A mob-event-based gear automation addon for World of Warcraft 1.12.1. It automates equipment swapping based on specific combat triggers, supporting both standard clients (Name matching) and SuperWoW clients (GUID matching).

It supports equipping **Individual Items** or full **Gear Sets** via integration with **ItemRack** and **Outfitter**.

## What does it do?
It monitors **Mob Death** and **Target Change** events. When a matching Mob Name or GUID is detected, it equips specified items or sets.
*   **In Combat:** The swap is usually queued and executes immediately upon leaving combat.
    *   *Exception:* Individual Weapons (Main/Off/Ranged) can be forced to swap during combat using the optional combat flag.
    *   *Note:* Full Gear Sets are **always** queued until combat ends.
*   **While Dead/Ghost:** Swaps are queued and execute immediately upon resurrection.
*   **Out of Combat:** The swap happens instantly.

## Use Cases
*   **Resistance Gear:** Automatically equip resistance items when targeting specific mobs.
*   **Item Swapping:** Equip items like "Carrot on a Stick" instantly when a boss dies.
*   **Weapon Swapping:** Switch weapons mid-combat (requires explicit config) or out of combat based on the specific enemy you are targeting.

## Usage & Commands

All commands start with `/ibtp`.

### 1. General Controls

```bash
# Enable or Disable the addon
# When disabled, no events are scanned and no gear is swapped.
/ibtp toggle

# List all active rules
/ibtp list
```

### 2. The "Identifier"
When adding rules, you must identify the mob. You can do this in three ways:
1.  **Name:** Type the name manually (e.g., `Ragnaros`).
2.  **GUID:** Type the hex ID manually (e.g., `0xF130000123`).
3.  **Target:** Type the word `target` while targeting an enemy.
    *   *Standard Client:* Saves the target's Name.
    *   *SuperWoW:* Saves the target's GUID (allows you to distinguish between mobs with the same name).

### 3. Scenario A: Swap on Death
Triggers when the mob dies. Useful for equipping regen gear after a boss or swapping trinkets between trash packs.

**Syntax:** `/ibtp adddeath [Identifier] - [Content] - [Slot (Optional)]`

```bash
# Example 1: Equip "Carrot on a Stick" to trinket slot 1 (13) when Ragnaros dies
/ibtp adddeath Ragnaros - Carrot on a Stick - 13

# Example 2: Equip an ItemRack set named "SpeedSet" when Ragnaros dies
/ibtp adddeath Ragnaros - ItemRack(SpeedSet)

# Example 3 (SuperWoW): Target a specific mob and equip "Hand of Justice" when it dies
/ibtp adddeath target - Hand of Justice
```

### 4. Scenario B: Swap on Target
Triggers immediately when you click or tab to a specific unit.

**Syntax:** `/ibtp addtarget [Identifier] - [Content] - [Slot (Optional)]`

```bash
# Example 1: Equip "Draconian Deflector" to Offhand when targeting "Baron Geddon"
/ibtp addtarget Baron Geddon - Draconian Deflector - 17

# Example 2: Equip an Outfitter set named "FireResist" when targeting "Baron Geddon"
/ibtp addtarget Baron Geddon - Outfitter(FireResist)
```

### 5. In-Combat Weapon Swapping (Optional)
By default, the addon queues swaps until you leave combat or resurrect. You can force an **immediate** swap during combat by adding `- combat` to the end of the command.

**Restrictions:**
*   You must specify the slot ID.
*   The slot ID must be **16** (Main Hand), **17** (Off Hand/Shield), or **18** (Ranged).
*   **Gear Sets cannot be swapped in combat.**

```bash
# Syntax
/ibtp addtarget [Identifier] - [Item Name] - [Slot] - combat

# Example: Equip "Thunderfury" immediately when Ragnaros dies, even if in combat
/ibtp adddeath Ragnaros - Thunderfury - 16 - combat
```

### 6. Removal

```bash
# Remove a rule (Must match the Name/GUID exactly as listed)
/ibtp remdeath Ragnaros - Carrot on a Stick
/ibtp remdeath Ragnaros - ItemRack(SpeedSet)
```

## ⚠️ Important: Mixing Sets & Items
You can theoretically assign a Gear Set **and** a specific Item to the same event, but **this is not recommended due to GCD issues.**

If you mix them:
1.  The Addon will attempt to equip the **Set** first.
2.  It will then attempt to equip the **Individual Item**.

## Advanced: Manual Configuration
You can edit the database directly by closing the game and opening: `WTF\Account\<AccName>\<ServerName>\<CharName>\SavedVariables\IfBossThenPants.lua`.

**Note:** New fields (`type` and `addon`) were added in v1.3 to support Gear Sets.

```lua
IfBossThenPantsDB = {
    ["enabled"] = true,
    ["onMobDeath"] = {
        -- Example 1: Standard Item (Name match)
        ["ragnaros"] = {
            { 
                ["name"] = "Carrot on a Stick", 
                ["slot"] = 13, 
                ["combat"] = false 
            }
        },
        -- Example 2: ItemRack Set (GUID match)
        ["0xf1300021560167f6"] = {
            { 
                ["name"] = "SpeedSet", 
                ["type"] = "set", 
                ["addon"] = "itemrack", 
                ["combat"] = false 
            }
        }
    },
    ["onTarget"] = {
        -- Example 3: Combat Weapon Swap (GUID match)
        ["0xf130008f5e026920"] = { 
            { 
                ["name"] = "Thunderfury", 
                ["slot"] = 16, 
                ["combat"] = true 
            }
        }
    }
}
```

## Slot IDs
You can use the slot number ID or the alias. Note that Slot IDs are ignored when equipping full Sets.

| Slot Name | ID | Alias | Combat Swap? |
| :--- | :--- | :--- | :--- |
| **Head** | 1 | head | No |
| **Neck** | 2 | neck | No |
| **Shoulder** | 3 | shoulder | No |
| **Back** | 15 | cloak | No |
| **Chest** | 5 | chest | No |
| **Wrist** | 9 | wrist | No |
| **Hands** | 10 | hands | No |
| **Waist** | 6 | waist | No |
| **Legs** | 7 | legs | No |
| **Feet** | 8 | feet | No |
| **Finger 1** | 11 | ring1 | No |
| **Finger 2** | 12 | ring2 | No |
| **Trinket 1** | 13 | trinket1 | No |
| **Trinket 2** | 14 | trinket2 | No |
| **Main Hand** | 16 | mainhand, mh | **Yes** |
| **Off Hand** | 17 | offhand, oh, shield | **Yes** |
| **Ranged** | 18 | ranged | **Yes** |

## GUIDs
You can find some mob guids for popular raids [here](https://github.com/MarcelineVQ/AutoMarker/blob/master/NPCList.lua).