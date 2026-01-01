# IfBossThenPants (Vanilla WoW 1.12)

## What is it?
A mob-event-based gear automation addon for World of Warcraft 1.12.1. It automates equipment swapping based on specific combat triggers, supporting both standard clients (Name matching) and SuperWoW clients (GUID matching).

## What does it do?
It monitors **Mob Death** and **Target Change** events. When a matching Mob Name or GUID is detected, it equips specified items to specified slots.
*   **In Combat:** The swap is queued and executes immediately upon leaving combat.
*   **Out of Combat:** The swap happens instantly.
*   **Optimization:** It checks equipped items first. If the item is already in the correct slot, no action is taken.

## Use Cases
*   **Resistance Gear:** Automatically equip resistance items when targeting specific mobs.
*   **Item Swapping:** Equip items like "Carrot on a Stick" instantly when a boss dies.
*   **Weapon Swapping:** Switch weapons based on the specific enemy you are targeting.

## Usage & Commands

All commands start with `/ibtp`.

### 1. The "Identifier"
When adding rules, you must identify the mob. You can do this in three ways:
1.  **Name:** Type the name manually (e.g., `Ragnaros`).
2.  **GUID:** Type the hex ID manually (e.g., `0xF130000123`).
3.  **Target:** Type the word `target` while targeting an enemy.
    *   *Standard Client:* Saves the target's Name.
    *   *SuperWoW:* Saves the target's GUID (allows you to distinguish between mobs with the same name).

### 2. Scenario A: Swap on Death
Triggers when the mob dies. Useful for equipping travel gear after a boss or swapping trinkets between trash packs.

```bash
# Syntax
/ibtp adddeath [Identifier] - [Item Name] - [Slot (Optional)]

# Example: Equip "Carrot on a Stick" to trinket slot 1 (13) when Ragnaros dies
/ibtp adddeath Ragnaros - Carrot on a Stick - 13

# Example (SuperWoW): Target a specific mob and equip "Hand of Justice" when it dies
/ibtp adddeath target - Hand of Justice
```

### 3. Scenario B: Swap on Target
Triggers immediately when you click or tab to a specific unit.

```bash
# Syntax
/ibtp addtarget [Identifier] - [Item Name] - [Slot (Optional)]

# Example: Equip "Draconian Deflector" to Offhand when targeting "Baron Geddon"
/ibtp addtarget Baron Geddon - Draconian Deflector - 17
```

### 4. Removal & Lists

```bash
# List all active rules
/ibtp list

# Remove a rule (Must match the Name/GUID exactly as listed)
/ibtp remdeath Ragnaros - Carrot on a Stick
/ibtp remtarget Baron Geddon - Draconian Deflector
```

## Advanced: Manual Configuration
You can edit the database directly by closing the game and opening: `WTF\Account\<AccName>\<ServerName>\<CharName>\SavedVariables\IfBossThenPants.lua`.

```lua
IfBossThenPantsDB = {
    ["onMobDeath"] = {
        ["ragnaros"] = {
            { ["name"] = "Carrot on a Stick", ["slot"] = 13 }
        }
    },
    ["onTarget"] = {
        ["0xf130008f5e026920"] = { -- SuperWoW GUID example
            { ["name"] = "Draconian Deflector", ["slot"] = 17 }
        }
    }
}
```

## Slot IDs
You can use the slot number ID or the alias.

| Slot Name | ID | Alias |
| :--- | :--- | :--- |
| **Head** | 1 | head |
| **Neck** | 2 | neck |
| **Shoulder** | 3 | shoulder |
| **Back** | 15 | cloak |
| **Chest** | 5 | chest |
| **Wrist** | 9 | wrist |
| **Hands** | 10 | hands |
| **Waist** | 6 | waist |
| **Legs** | 7 | legs |
| **Feet** | 8 | feet |
| **Finger 1** | 11 | ring1 |
| **Finger 2** | 12 | ring2 |
| **Trinket 1** | 13 | trinket1 |
| **Trinket 2** | 14 | trinket2 |
| **Main Hand** | 16 | mainhand, mh |
| **Off Hand** | 17 | offhand, oh, shield |
| **Ranged** | 18 | ranged |

## GUIDs
You can find some mob guids for popular raids [here](https://github.com/MarcelineVQ/AutoMarker/blob/master/NPCList.lua).
