local mod = get_mod("BrokerAutoStim")

local PlayerUnitVisualLoadout = require("scripts/extension_systems/visual_loadout/utilities/player_unit_visual_loadout")

local HUD_ELEMENT_CLASS_NAME = "HudElementBrokerAutoStim"

mod:register_hud_element({
	class_name = HUD_ELEMENT_CLASS_NAME,
	filename = "BrokerAutoStim/scripts/mods/BrokerAutoStim/HudElementBrokerAutoStim",
	use_hud_scale = true,
	visibility_groups = {
		"alive",
		"communication_wheel",
		"tactical_overlay"
	},
	validation_function = function(params)
		return Managers.state.game_mode:game_mode_name() ~= "hub"
	end
})

mod.get_hud_element = function()
	local hud = Managers.ui:get_hud()
	return hud and hud:element(HUD_ELEMENT_CLASS_NAME)
end

local STIMM_SLOT_NAME = "slot_pocketable_small"

local function _debug(message_or_func)
    if not mod:get("enable_debug") then
        return
    end
    local message = type(message_or_func) == "function" and message_or_func() or message_or_func
    mod:echo(message)
end

local AUTO_STIMM_STAGES = {
    NONE = 0,
    SWITCH_TO = 1,
    WAITING_FOR_INJECT = 2,
    SWITCH_BACK = 3,
}

local auto_stimm_stage = AUTO_STIMM_STAGES.NONE
local current_wield_slot = nil
local unwield_to_slot = nil
local last_equipped_slot = nil
local input_request = nil
local stage_start_time = nil

local STAGE_TIMEOUTS = {
    [AUTO_STIMM_STAGES.SWITCH_TO] = 3.0,
    [AUTO_STIMM_STAGES.WAITING_FOR_INJECT] = 5.0,
    [AUTO_STIMM_STAGES.SWITCH_BACK] = 3.0,
}

local combat_start_time = nil
local last_injection_time = nil
local last_combat_time = nil
local auto_stim_enabled = true
local last_combat_ability_cooldown = nil
local combat_ability_just_used = false
local combat_ability_just_ended = false
local combat_ability_active = false
local injection_retry_after_ability = false
local cached_chem_info = nil
local chem_info_cache_time = nil
local push_in_progress = false
local injection_retry_after_push = false
local block_in_progress = false
local injection_retry_after_block = false
local attack_in_progress = false
local injection_retry_after_attack = false
local was_carrying_luggable = false
local injection_retry_after_carrying = false
local reload_in_progress = false
local injection_retry_after_reload = false
local dangerous_enemies_nearby = false
local injection_retry_after_enemies = false
local holding_attack = false
local last_attack_time = nil
local interaction_active_units = {}
local interaction_in_progress = false
local injection_retry_after_interaction = false
local auspex_in_progress = false
local injection_retry_after_auspex = false
local auspex_active_units = {}

local profiles = {}
local is_loading_profile = false

local function _get_default_profile_data()
    return {
        only_with_chemical_dependency = false,
        not_with_stimm_supply = false,
        stim_trigger_mode = "combat_only",
        combat_duration = 5.0,
        out_of_combat_timeout = 5.0
    }
end

local function _initialize_profiles()
    profiles = mod:get("profiles") or {}

    for i = 1, 5 do
        if not profiles[i] then
            profiles[i] = {}
        end
    end

    mod:set("profiles", profiles, false)
end

local function _get_current_profile_data()
    local active_profile = mod:get("active_profile") or 1
    if not profiles[active_profile] then
        profiles[active_profile] = _get_default_profile_data()
    end
    return profiles[active_profile]
end

local function _save_current_settings_to_profile()
    profiles = mod:get("profiles") or {}
    local active_profile = mod:get("active_profile") or 1
    if not profiles[active_profile] then
        profiles[active_profile] = {}
    end

    profiles[active_profile].only_with_chemical_dependency = mod:get("only_with_chemical_dependency")
    profiles[active_profile].not_with_stimm_supply = mod:get("not_with_stimm_supply")
    profiles[active_profile].stim_trigger_mode = mod:get("stim_trigger_mode")
    profiles[active_profile].combat_duration = mod:get("combat_duration")
    profiles[active_profile].out_of_combat_timeout = mod:get("out_of_combat_timeout")

    mod:set("profiles", profiles, false)
end

local function _load_profile_settings(profile_num)
    profiles = mod:get("profiles") or {}

    local profile_has_data = profiles[profile_num] and
        (profiles[profile_num].only_with_chemical_dependency ~= nil or
         profiles[profile_num].not_with_stimm_supply ~= nil or
         profiles[profile_num].stim_trigger_mode ~= nil or
         profiles[profile_num].combat_duration ~= nil or
         profiles[profile_num].out_of_combat_timeout ~= nil)

    is_loading_profile = true

    if profile_has_data then
        local profile_data = profiles[profile_num]

        mod:set("only_with_chemical_dependency", profile_data.only_with_chemical_dependency or false, false)
        mod:set("not_with_stimm_supply", profile_data.not_with_stimm_supply or false, false)

        local trigger_mode = profile_data.stim_trigger_mode or "combat_only"
        mod:set("stim_trigger_mode", trigger_mode, false)

        mod:set("combat_duration", profile_data.combat_duration or 5.0, false)
        mod:set("out_of_combat_timeout", profile_data.out_of_combat_timeout or 5.0, false)
    else
        local default_data = _get_default_profile_data()
        mod:set("only_with_chemical_dependency", default_data.only_with_chemical_dependency, false)
        mod:set("not_with_stimm_supply", default_data.not_with_stimm_supply, false)
        mod:set("stim_trigger_mode", default_data.stim_trigger_mode, false)
        mod:set("combat_duration", default_data.combat_duration, false)
        mod:set("out_of_combat_timeout", default_data.out_of_combat_timeout, false)
    end

    is_loading_profile = false
end

local function _save_to_profile(profile_num)
    profiles = mod:get("profiles") or {}
    if not profiles[profile_num] then
        profiles[profile_num] = {}
    end

    profiles[profile_num].only_with_chemical_dependency = mod:get("only_with_chemical_dependency")
    profiles[profile_num].not_with_stimm_supply = mod:get("not_with_stimm_supply")
    profiles[profile_num].stim_trigger_mode = mod:get("stim_trigger_mode")
    profiles[profile_num].combat_duration = mod:get("combat_duration")
    profiles[profile_num].out_of_combat_timeout = mod:get("out_of_combat_timeout")

    mod:set("profiles", profiles, false)
end

local function _get_trigger_mode_display_name(trigger_mode)
    if trigger_mode == "combat_only" then
        return "Combat Only"
    elseif trigger_mode == "non_combat_only" then
        return "Non-Combat Only"
    elseif trigger_mode == "after_ability_end" then
        return "After Ability"
    elseif trigger_mode == "on_ability_use" then
        return "Before Ability"
    elseif trigger_mode == "always_stim" then
        return "Always Stim"
    end
    return trigger_mode or "Combat Only"
end

local function _show_profile_settings(profile_num)
    profiles = mod:get("profiles") or {}
    local profile_data = profiles[profile_num] or _get_default_profile_data()

    mod:echo("=== Profile " .. profile_num .. " Settings ===")
    mod:echo("Chemical Dependency Only: " .. (profile_data.only_with_chemical_dependency and "Yes" or "No"))
    mod:echo("Not with Stimm Supply: " .. (profile_data.not_with_stimm_supply and "Yes" or "No"))
    mod:echo("Trigger Mode: " .. _get_trigger_mode_display_name(profile_data.stim_trigger_mode or "combat_only"))

    local trigger_mode = profile_data.stim_trigger_mode or "combat_only"
    if trigger_mode == "combat_only" or trigger_mode == "non_combat_only" then
        mod:echo("Combat Duration: " .. string.format("%.1f", profile_data.combat_duration or 5.0) .. "s")
        mod:echo("Out of Combat Timeout: " .. string.format("%.1f", profile_data.out_of_combat_timeout or 5.0) .. "s")
    end
end

local profile_changed_from_hotkey = false

local function _on_profile_changed(old_profile, new_profile, show_notification)
    if is_loading_profile then
        return
    end

    if old_profile and old_profile ~= new_profile then
        _save_to_profile(old_profile)
    end

    is_loading_profile = true
    _load_profile_settings(new_profile)
    is_loading_profile = false

    if show_notification then
        mod:echo("Switched to Profile " .. new_profile)

        if mod:get("show_settings_on_switch") then
            _show_profile_settings(new_profile)
        end
    end
end

mod.cycle_profile = function(keybind_is_pressed)
    if not keybind_is_pressed then
        return
    end

    local current_profile = mod:get("active_profile") or 1
    _save_current_settings_to_profile()

    local max_profiles = mod:get("number_of_profiles_to_cycle") or 5
    max_profiles = math.max(1, math.min(5, max_profiles))

    local next_profile = current_profile + 1
    if next_profile > max_profiles then
        next_profile = 1
    end

    last_active_profile = current_profile
    profile_changed_from_hotkey = true
    mod:set("active_profile", next_profile, true)
end

local last_active_profile = nil

mod.on_setting_changed = function(setting_id)
    if is_loading_profile then
        return
    end

    if setting_id == "active_profile" then
        local new_profile = mod:get("active_profile") or 1
        local old_profile = last_active_profile or 1
        last_active_profile = new_profile

        local show_notification = profile_changed_from_hotkey
        profile_changed_from_hotkey = false

        _on_profile_changed(old_profile, new_profile, show_notification)
    elseif setting_id == "only_with_chemical_dependency" or
           setting_id == "not_with_stimm_supply" or
           setting_id == "stim_trigger_mode" or
           setting_id == "combat_duration" or
           setting_id == "out_of_combat_timeout" then
        _save_current_settings_to_profile()
    elseif setting_id == "show_hud_icon" then
        local hud_element = mod.get_hud_element()
        if hud_element then
            hud_element:set_visible(mod:get("show_hud_icon"))
        end
    elseif setting_id == "hud_icon_size" then
        local hud_element = mod.get_hud_element()
        if hud_element then
            hud_element:set_side_length(mod:get("hud_icon_size"))
        end
    end
end

local function _get_gameplay_time()
    if Managers.time and Managers.time:has_timer("gameplay") then
        return Managers.time:time("gameplay")
    end
    return nil
end

local function _get_player_unit()
    local plr = Managers.player and Managers.player:local_player_safe(1)
    return plr and plr.player_unit
end

local function _is_local_player(unit)
    local player = Managers.player:local_player(1)
    return player and unit == player.player_unit
end

local function _get_archetype()
    local player = Managers.player:local_player_safe(1)
    if player then
        local profile = player:profile()
        if profile then
            return profile.archetype and profile.archetype.name
        end
    end
    return nil
end

local function _has_broker_stim()
    local player_unit = _get_player_unit()
    if not player_unit then
        return false
    end

    local ability_extension = ScriptUnit.has_extension(player_unit, "ability_system")
    if not ability_extension then
        return false
    end

    if not ability_extension:ability_is_equipped("pocketable_ability") then
        return false
    end

    local visual_loadout_extension = ScriptUnit.has_extension(player_unit, "visual_loadout_system")
    if not visual_loadout_extension then
        return false
    end

    return PlayerUnitVisualLoadout.has_weapon_keyword_from_slot(visual_loadout_extension, STIMM_SLOT_NAME, "pocketable_broker_syringe")
end

mod.is_broker_with_stim = function()
    local archetype = _get_archetype()
    if archetype ~= "broker" then
        return false
    end
    return _has_broker_stim()
end

local function _has_chemical_dependency()
    local player_unit = _get_player_unit()
    if not player_unit then
        return false
    end

    local buff_extension = ScriptUnit.has_extension(player_unit, "buff_system")
    if not buff_extension then
        return false
    end

    return buff_extension:has_buff_using_buff_template("broker_keystone_chemical_dependency") or
           (buff_extension._stacking_buffs and buff_extension._stacking_buffs["broker_keystone_chemical_dependency_stack"] ~= nil)
end

local function _has_stimm_supply()
    local player_unit = _get_player_unit()
    if not player_unit then
        return false
    end

    local ability_extension = ScriptUnit.has_extension(player_unit, "ability_system")
    if not ability_extension then
        return false
    end

    if not ability_extension:ability_is_equipped("combat_ability") then
        return false
    end

    local equipped_abilities = ability_extension:equipped_abilities()
    local combat_ability = equipped_abilities and equipped_abilities.combat_ability
    if not combat_ability then
        return false
    end

    return combat_ability.name == "broker_ability_stimm_field"
end

local function _get_chemical_dependency_info()
    local current_time = _get_gameplay_time()
    if cached_chem_info and chem_info_cache_time and current_time and (current_time - chem_info_cache_time) < 0.1 then
        return cached_chem_info
    end

    local player_unit = _get_player_unit()
    if not player_unit then
        cached_chem_info = nil
        chem_info_cache_time = nil
        return nil
    end

    local buff_extension = ScriptUnit.has_extension(player_unit, "buff_system")
    if not buff_extension then
        cached_chem_info = nil
        chem_info_cache_time = nil
        return nil
    end

    local buff_instance = buff_extension._stacking_buffs and buff_extension._stacking_buffs["broker_keystone_chemical_dependency_stack"]
    if not buff_instance then
        cached_chem_info = {
            has_keystone = _has_chemical_dependency(),
            current_stacks = 0,
            max_stacks = 3,
            time_until_stack_decay = nil,
            can_gain_stack = true
        }
        chem_info_cache_time = current_time
        return cached_chem_info
    end

    local current_stacks = buff_instance:stack_count()
    local max_stacks = buff_instance:max_stacks() or 3
    local duration = buff_instance:duration()
    local start_time = buff_instance:start_time()

    if not current_time then
        cached_chem_info = {
            has_keystone = true,
            current_stacks = current_stacks,
            max_stacks = max_stacks,
            time_until_stack_decay = nil,
            can_gain_stack = current_stacks < max_stacks
        }
        chem_info_cache_time = nil
        return cached_chem_info
    end

    local time_until_stack_decay = nil
    if duration and start_time then
        local end_time = start_time + duration
        time_until_stack_decay = math.max(0, end_time - current_time)
    end

    local can_gain_stack = current_stacks < max_stacks

    cached_chem_info = {
        has_keystone = true,
        current_stacks = current_stacks,
        max_stacks = max_stacks,
        time_until_stack_decay = time_until_stack_decay,
        can_gain_stack = can_gain_stack
    }
    chem_info_cache_time = current_time
    return cached_chem_info
end

local function _get_effective_combat_duration()
    local base_duration = mod:get("combat_duration")
    local chem_info = _get_chemical_dependency_info()

    if not chem_info or not chem_info.has_keystone then
        return base_duration
    end

    if chem_info.can_gain_stack then
        return base_duration
    end

    if chem_info.time_until_stack_decay then
        local injection_animation_time = 2.0
        local time_before_decay = math.max(0, chem_info.time_until_stack_decay - injection_animation_time)
        return math.max(base_duration, time_before_decay)
    end

    return base_duration
end

local function _mark_combat_started()
    local current_time = _get_gameplay_time()
    if not current_time then
        return
    end

    last_combat_time = current_time

    if not combat_start_time then
        combat_start_time = current_time
        _debug(function() return "Combat started! Has stim: " .. tostring(_has_broker_stim()) end)
    end
end

local function _is_in_combat()
    if not last_combat_time then
        return false
    end

    local current_time = _get_gameplay_time()
    if not current_time then
        return false
    end

    local time_since_combat = current_time - last_combat_time
    local combat_timeout = mod:get("out_of_combat_timeout")

    return time_since_combat <= combat_timeout
end

local function _can_use_stim()
    local player_unit = _get_player_unit()
    if not player_unit then
        return false
    end

    local ability_extension = ScriptUnit.has_extension(player_unit, "ability_system")
    if not ability_extension then
        return false
    end

    return ability_extension:can_use_ability("pocketable_ability")
end

local function _get_combat_ability_cooldown()
    local player_unit = _get_player_unit()
    if not player_unit then
        return nil
    end

    local ability_extension = ScriptUnit.has_extension(player_unit, "ability_system")
    if not ability_extension then
        return nil
    end

    if not ability_extension:ability_is_equipped("combat_ability") then
        return nil
    end

    return ability_extension:remaining_ability_cooldown("combat_ability")
end

local function _is_combat_ability_active(allow_on_ability_use)
    if not mod:get("cancel_during_ability") then
        return false
    end

    if allow_on_ability_use and mod:get("stim_trigger_mode") == "on_ability_use" and combat_ability_just_used then
        return false
    end

    return combat_ability_active == true
end

local function _reset_auto_stimm_state()
    auto_stimm_stage = AUTO_STIMM_STAGES.NONE
    stage_start_time = nil
    input_request = nil
    unwield_to_slot = nil
    injection_retry_after_push = false
    injection_retry_after_block = false
    injection_retry_after_attack = false
    injection_retry_after_carrying = false
    injection_retry_after_reload = false
    injection_retry_after_enemies = false
    injection_retry_after_interaction = false
    injection_retry_after_ability = false
    injection_retry_after_auspex = false
end

local function _reset_all_state()
    _reset_auto_stimm_state()
    combat_start_time = nil
    last_injection_time = nil
    last_combat_time = nil
    last_combat_ability_cooldown = nil
    combat_ability_just_used = false
    combat_ability_just_ended = false
    combat_ability_active = false
    current_wield_slot = nil
    cached_chem_info = nil
    chem_info_cache_time = nil
    push_in_progress = false
    block_in_progress = false
    attack_in_progress = false
    was_carrying_luggable = false
    reload_in_progress = false
    dangerous_enemies_nearby = false
    holding_attack = false
    last_attack_time = nil
    table.clear(interaction_active_units)
    table.clear(auspex_active_units)
    interaction_in_progress = false
    auspex_in_progress = false
end

local function _check_stage_timeout()
    if auto_stimm_stage == AUTO_STIMM_STAGES.NONE then
        return false
    end

    if not stage_start_time then
        return false
    end

    local current_time = _get_gameplay_time()
    if not current_time then
        return false
    end

    local timeout = STAGE_TIMEOUTS[auto_stimm_stage]
    if not timeout then
        return false
    end

    local time_in_stage = current_time - stage_start_time
    if time_in_stage >= timeout then
        _debug(function()
            local stage_name = auto_stimm_stage == AUTO_STIMM_STAGES.SWITCH_TO and "SWITCH_TO"
                or auto_stimm_stage == AUTO_STIMM_STAGES.WAITING_FOR_INJECT and "WAITING_FOR_INJECT"
                or auto_stimm_stage == AUTO_STIMM_STAGES.SWITCH_BACK and "SWITCH_BACK"
                or "UNKNOWN"
            return string.format("Stage timeout! Resetting from %s after %.2f seconds", stage_name, time_in_stage)
        end)
        _reset_auto_stimm_state()
        return true
    end

    return false
end

local function _is_weapon_switching()
    local player_unit = _get_player_unit()
    if not player_unit then
        return false
    end

    local unit_data_extension = ScriptUnit.has_extension(player_unit, "unit_data_system")
    if not unit_data_extension or type(unit_data_extension) ~= "table" or not unit_data_extension.read_component then
        return false
    end

    local weapon_action_component = unit_data_extension:read_component("weapon_action")
    if not weapon_action_component then
        return false
    end

    local current_action_name = weapon_action_component.current_action_name
    return current_action_name == "action_wield" or current_action_name == "action_unwield" or
           current_action_name == "action_unwield_to_previous" or current_action_name == "action_unwield_to_specific"
end

local function _is_weapon_template_valid(slot_name)
    if not slot_name then
        return false
    end

    local player_unit = _get_player_unit()
    if not player_unit then
        return false
    end

    local visual_loadout_extension = ScriptUnit.has_extension(player_unit, "visual_loadout_system")
    if not visual_loadout_extension then
        return false
    end

    local success, weapon_template = pcall(function()
        return visual_loadout_extension:weapon_template_from_slot(slot_name)
    end)

    if not success then
        return false
    end

    return weapon_template ~= nil
end

local DANGEROUS_BREEDS = {
    chaos_poxwalker_bomber = {
        range_setting = "burster_detection_range",
        enabled_setting = "block_nearby_burster"
    },
    renegade_netgunner = {
        range_setting = "trapper_detection_range",
        enabled_setting = "block_nearby_trapper"
    },
    chaos_hound = {
        range_setting = "dog_detection_range",
        enabled_setting = "block_nearby_dog"
    },
    chaos_ogryn_executor = {
        range_setting = "crusher_detection_range",
        enabled_setting = "block_nearby_crusher"
    },
    renegade_executor = {
        range_setting = "crusher_detection_range",
        enabled_setting = "block_nearby_crusher"
    },
    renegade_berzerker = {
        range_setting = "rager_detection_range",
        enabled_setting = "block_nearby_rager"
    },
    cultist_berzerker = {
        range_setting = "rager_detection_range",
        enabled_setting = "block_nearby_rager"
    }
}

local function _is_currently_blocking()
    if not mod:get("cancel_on_push_block") then
        return false
    end

    local player_unit = _get_player_unit()
    if not player_unit then
        return false
    end

    local unit_data_extension = ScriptUnit.has_extension(player_unit, "unit_data_system")
    if not unit_data_extension or type(unit_data_extension) ~= "table" or not unit_data_extension.read_component then
        return false
    end

    local block_component = unit_data_extension:read_component("block")
    if not block_component then
        return false
    end

    return block_component.is_blocking == true
end

local function _is_currently_attacking()
    if not mod:get("cancel_on_attack") then
        return false
    end

    local current_time = _get_gameplay_time()
    if not current_time then
        return false
    end

    local attack_cooldown = mod:get("attack_cooldown") or 0.5

    if holding_attack then
        last_attack_time = current_time
        return true
    end

    local player_unit = _get_player_unit()
    if player_unit then
        local weapon_extension = ScriptUnit.has_extension(player_unit, "weapon_system")
        if weapon_extension and weapon_extension._action_handler then
            local running_action_name = weapon_extension._action_handler:running_action_name("weapon_action")
            if running_action_name and
               (string.find(running_action_name, "action_melee") == 1 or
                string.find(running_action_name, "action_shoot") == 1) then
                last_attack_time = current_time
                return true
            end
        end
    end

    if last_attack_time then
        local time_since_attack = current_time - last_attack_time
        if time_since_attack < attack_cooldown then
            return true
        else
            last_attack_time = nil
        end
    end

    return false
end

local function _is_carrying_luggable()
    if not mod:get("cancel_on_carrying") then
        return false
    end

    local player_unit = _get_player_unit()
    if not player_unit then
        return false
    end

    local unit_data_extension = ScriptUnit.has_extension(player_unit, "unit_data_system")
    if not unit_data_extension or type(unit_data_extension) ~= "table" or not unit_data_extension.read_component then
        return false
    end

    local inventory_component = unit_data_extension:read_component("inventory")
    if not inventory_component then
        return false
    end

    local held_luggable = inventory_component.slot_luggable
    return held_luggable and held_luggable ~= "not_equipped"
end

local function _is_using_auspex()
    if not mod:get("cancel_on_auspex") then
        return false
    end

    local player_unit = _get_player_unit()
    if not player_unit then
        return false
    end

    if auspex_active_units[player_unit] then
        return true
    end

    local unit_data_extension = ScriptUnit.has_extension(player_unit, "unit_data_system")
    if not unit_data_extension or type(unit_data_extension) ~= "table" or not unit_data_extension.read_component then
        return false
    end

    local scanning_component = unit_data_extension:read_component("scanning")
    if scanning_component and scanning_component.is_active then
        return true
    end

    local character_state_component = unit_data_extension:read_component("character_state")
    if character_state_component and character_state_component.state_name == "minigame" then
        return true
    end

    local minigame_state = unit_data_extension:read_component("minigame_character_state")
    if minigame_state and minigame_state.pocketable_device_active then
        return true
    end

    return false
end

local function _is_interacting()
    if not mod:get("cancel_on_interaction") then
        return false
    end

    local player_unit = _get_player_unit()
    if not player_unit then
        return false
    end

    if interaction_active_units[player_unit] then
        return true
    end

    local unit_data_extension = ScriptUnit.has_extension(player_unit, "unit_data_system")
    if not unit_data_extension or type(unit_data_extension) ~= "table" or not unit_data_extension.read_component then
        return false
    end

    local interaction_component = unit_data_extension:read_component("interaction")
    if not interaction_component then
        return false
    end

    local InteractionSettings = require("scripts/settings/interaction/interaction_settings")
    local interaction_states = InteractionSettings.states
    local state = interaction_component.state

    if state == interaction_states.is_interacting then
        local interaction_type = interaction_component.type
        if interaction_type then
            local interaction_templates = require("scripts/settings/interaction/interaction_templates")
            local template = interaction_templates[interaction_type]
            if template and template.duration and template.duration > 0 then
                return true
            end
        end
    end

    return false
end

local function _is_currently_reloading()
    if not mod:get("cancel_on_reload") then
        return false
    end

    local player_unit = _get_player_unit()
    if not player_unit then
        return false
    end

    local weapon_extension = ScriptUnit.has_extension(player_unit, "weapon_system")
    if not weapon_extension or not weapon_extension._action_handler then
        return false
    end

    local running_action_name = weapon_extension._action_handler:running_action_name("weapon_action")
    if not running_action_name then
        return false
    end

    return running_action_name == "action_reload"
end

local function _has_nearby_dangerous_enemies()
    local player_unit = _get_player_unit()
    if not player_unit then
        return false
    end

    if not Unit.alive(player_unit) or not Unit.world(player_unit) then
        return false
    end

    local broadphase_system = Managers.state.extension and Managers.state.extension:system("broadphase_system")
    local broadphase = broadphase_system and broadphase_system.broadphase
    if not broadphase then
        return false
    end

    local side_system = Managers.state.extension and Managers.state.extension:system("side_system")
    local side = side_system and side_system.side_by_unit[player_unit]
    if not side then
        return false
    end

    local from_pos = Unit.world_position(player_unit, 1)
    local enemy_side_names = side:relation_side_names("enemy")
    local Breed = require("scripts/utilities/breed")

    for breed_name, breed_data in pairs(DANGEROUS_BREEDS) do
        if mod:get(breed_data.enabled_setting) then
            local scan_radius = mod:get(breed_data.range_setting) or 15.0
            if scan_radius > 0 then
                local results = {}
                local count = broadphase.query(broadphase, from_pos, scan_radius, results, enemy_side_names)

                if count and count > 0 then
                    for i = 1, count do
                        local unit = results[i]
                        if Unit.alive(unit) then
                            local breed = Breed.unit_breed_or_nil(unit)
                            if breed and breed.name == breed_name then
                                _debug(function() return string.format("Dangerous enemy detected nearby: %s (%.1fm)", breed_name, scan_radius) end)
                                return true
                            end
                        end
                    end
                end
            end
        end
    end

    return false
end

local function _start_auto_inject()
    if not _has_broker_stim() then
        return false
    end

    if not _can_use_stim() then
        return false
    end

    if _is_weapon_switching() then
        return false
    end

    if not _is_weapon_template_valid(STIMM_SLOT_NAME) then
        return false
    end

    if _has_nearby_dangerous_enemies() then
        _debug("Dangerous enemies nearby, blocking injection")
        dangerous_enemies_nearby = true
        injection_retry_after_enemies = true
        return false
    end

    if _is_currently_blocking() then
        _debug("Currently blocking, preventing injection")
        return false
    end

    if _is_currently_attacking() then
        _debug("Currently attacking, preventing injection")
        attack_in_progress = true
        injection_retry_after_attack = true
        return false
    end

    if _is_carrying_luggable() then
        _debug("Currently carrying luggage, preventing injection")
        was_carrying_luggable = true
        injection_retry_after_carrying = true
        return false
    end

    if _is_currently_reloading() then
        _debug("Currently reloading, preventing injection")
        reload_in_progress = true
        injection_retry_after_reload = true
        return false
    end

    if _is_interacting() then
        _debug("Currently interacting, preventing injection")
        interaction_in_progress = true
        injection_retry_after_interaction = true
        return false
    end

    if _is_using_auspex() then
        _debug("Currently using auspex, preventing injection")
        auspex_in_progress = true
        injection_retry_after_auspex = true
        return false
    end

    if _is_combat_ability_active(true) then
        _debug("Combat ability is active, preventing injection")
        injection_retry_after_ability = true
        return false
    end

    local current_time = _get_gameplay_time()
    if current_wield_slot == STIMM_SLOT_NAME then
        auto_stimm_stage = AUTO_STIMM_STAGES.WAITING_FOR_INJECT
        stage_start_time = current_time
        _debug("Stim already wielded, waiting for auto-inject...")
    else
        if not _is_weapon_template_valid(current_wield_slot) then
            return false
        end
        if current_wield_slot and current_wield_slot ~= STIMM_SLOT_NAME then
            last_equipped_slot = current_wield_slot
            unwield_to_slot = current_wield_slot
        end
        auto_stimm_stage = AUTO_STIMM_STAGES.SWITCH_TO
        stage_start_time = current_time
        _debug("Wielding stim for auto-inject...")
    end

    return true
end

mod.get_auto_stim_enabled = function()
    return auto_stim_enabled
end

mod.toggle_auto_stim = function(keybind_is_pressed)
    if not keybind_is_pressed then
        return
    end

    auto_stim_enabled = not auto_stim_enabled
    mod:echo("Auto-stim " .. (auto_stim_enabled and "enabled" or "disabled"))

    local hud_element = mod.get_hud_element()
    if hud_element then
        hud_element:set_enabled_state(auto_stim_enabled)
    end
end

mod.update = function(dt)
    if not auto_stim_enabled then
        return
    end

    if push_in_progress then
        local player_unit = _get_player_unit()
        if player_unit then
            local weapon_extension = ScriptUnit.has_extension(player_unit, "weapon_system")
            if weapon_extension and weapon_extension._action_handler then
                local running_action_name = weapon_extension._action_handler:running_action_name("weapon_action")
                if running_action_name ~= "action_push" then
                    push_in_progress = false
                    if injection_retry_after_push then
                        _debug("Push finished, retrying injection")
                        injection_retry_after_push = false
                        local current_time = _get_gameplay_time()
                        if current_time then
                            last_injection_time = nil
                        end
                    end
                end
            else
                push_in_progress = false
            end
        else
            push_in_progress = false
        end
    end

    if block_in_progress then
        local player_unit = _get_player_unit()
        if player_unit then
            local weapon_extension = ScriptUnit.has_extension(player_unit, "weapon_system")
            if weapon_extension and weapon_extension._action_handler then
                local running_action_name = weapon_extension._action_handler:running_action_name("weapon_action")
                if running_action_name ~= "action_block" then
                    block_in_progress = false
                    if injection_retry_after_block then
                        _debug("Block finished, retrying injection")
                        injection_retry_after_block = false
                        local current_time = _get_gameplay_time()
                        if current_time then
                            last_injection_time = nil
                        end
                    end
                end
            else
                block_in_progress = false
            end
        else
            block_in_progress = false
        end
    end

    if attack_in_progress then
        if not _is_currently_attacking() then
            attack_in_progress = false
            if injection_retry_after_attack then
                _debug("Attack finished, retrying injection")
                injection_retry_after_attack = false
                local current_time = _get_gameplay_time()
                if current_time then
                    last_injection_time = nil
                end
            end
        end
    end

    if was_carrying_luggable then
        if not _is_carrying_luggable() then
            was_carrying_luggable = false
            if injection_retry_after_carrying then
                _debug("No longer carrying luggage, retrying injection")
                injection_retry_after_carrying = false
                local current_time = _get_gameplay_time()
                if current_time then
                    last_injection_time = nil
                end
            end
        end
    end

    if reload_in_progress then
        local player_unit = _get_player_unit()
        if player_unit then
            local weapon_extension = ScriptUnit.has_extension(player_unit, "weapon_system")
            if weapon_extension and weapon_extension._action_handler then
                local running_action_name = weapon_extension._action_handler:running_action_name("weapon_action")
                if running_action_name ~= "action_reload" then
                    reload_in_progress = false
                    if injection_retry_after_reload then
                        _debug("Reload finished, retrying injection")
                        injection_retry_after_reload = false
                        local current_time = _get_gameplay_time()
                        if current_time then
                            last_injection_time = nil
                        end
                    end
                end
            else
                reload_in_progress = false
            end
        else
            reload_in_progress = false
        end
    end

    if dangerous_enemies_nearby then
        if not _has_nearby_dangerous_enemies() then
            dangerous_enemies_nearby = false
            if injection_retry_after_enemies then
                _debug("Dangerous enemies moved out of range, retrying injection")
                injection_retry_after_enemies = false
                local current_time = _get_gameplay_time()
                if current_time then
                    last_injection_time = nil
                end
            end
        end
    end

    if interaction_in_progress then
        if not _is_interacting() then
            interaction_in_progress = false
            if injection_retry_after_interaction then
                _debug("Interaction finished, retrying injection")
                injection_retry_after_interaction = false
                local current_time = _get_gameplay_time()
                if current_time then
                    last_injection_time = nil
                end
            end
        end
    end

    if auspex_in_progress then
        if not _is_using_auspex() then
            auspex_in_progress = false
            if injection_retry_after_auspex then
                _debug("Auspex finished, retrying injection")
                injection_retry_after_auspex = false
                local current_time = _get_gameplay_time()
                if current_time then
                    last_injection_time = nil
                end
            end
        end
    end

    if combat_ability_active then
        local current_combat_ability_cooldown = _get_combat_ability_cooldown()
        if current_combat_ability_cooldown and current_combat_ability_cooldown > 0 then
            combat_ability_active = false
            if injection_retry_after_ability then
                _debug("Combat ability finished, retrying injection")
                injection_retry_after_ability = false
                local current_time = _get_gameplay_time()
                if current_time then
                    last_injection_time = nil
                end
            end
        end
    end

    if auto_stimm_stage ~= AUTO_STIMM_STAGES.NONE then
        if auto_stimm_stage == AUTO_STIMM_STAGES.WAITING_FOR_INJECT then
            if _is_currently_blocking() then
                _debug("Blocking detected during injection countdown, canceling")
                injection_retry_after_block = true
                _reset_auto_stimm_state()
                return
            end
            if _is_currently_attacking() then
                _debug("Attacking detected during injection countdown, canceling")
                attack_in_progress = true
                injection_retry_after_attack = true
                _reset_auto_stimm_state()
                return
            end
            if _is_carrying_luggable() then
                _debug("Carrying luggage detected during injection countdown, canceling")
                was_carrying_luggable = true
                injection_retry_after_carrying = true
                _reset_auto_stimm_state()
                return
            end
            if _is_currently_reloading() then
                _debug("Reloading detected during injection countdown, canceling")
                reload_in_progress = true
                injection_retry_after_reload = true
                _reset_auto_stimm_state()
                return
            end
            if _is_interacting() then
                _debug("Interaction detected during injection countdown, canceling")
                interaction_in_progress = true
                injection_retry_after_interaction = true
                _reset_auto_stimm_state()
                return
            end
            if _is_using_auspex() then
                _debug("Auspex detected during injection countdown, canceling")
                auspex_in_progress = true
                injection_retry_after_auspex = true
                _reset_auto_stimm_state()
                return
            end
            if _has_nearby_dangerous_enemies() then
                _debug("Dangerous enemies detected during injection countdown, canceling")
                dangerous_enemies_nearby = true
                injection_retry_after_enemies = true
                _reset_auto_stimm_state()
                return
            end
            if _is_combat_ability_active(false) then
                _debug("Combat ability detected during injection countdown, canceling")
                combat_ability_active = true
                injection_retry_after_ability = true
                _reset_auto_stimm_state()
                return
            end
        end
        _check_stage_timeout()
        return
    end

    local chem_info = _get_chemical_dependency_info()
    local has_chemical_dependency = chem_info and chem_info.has_keystone

    if mod:get("only_with_chemical_dependency") and not has_chemical_dependency then
        return
    end

    if mod:get("not_with_stimm_supply") and _has_stimm_supply() then
        return
    end

    local current_combat_ability_cooldown = _get_combat_ability_cooldown()
    if last_combat_ability_cooldown ~= nil and current_combat_ability_cooldown ~= nil then
        if last_combat_ability_cooldown == 0 and current_combat_ability_cooldown > 0 then
            combat_ability_just_ended = true
            combat_ability_active = false
            _debug("Combat ability cooldown started")
        end
    end
    last_combat_ability_cooldown = current_combat_ability_cooldown

    local effective_duration = _get_effective_combat_duration()
    local in_combat = _is_in_combat()
    local stim_trigger_mode = mod:get("stim_trigger_mode")

    local should_process = false
    if stim_trigger_mode == "on_ability_use" then
        should_process = combat_ability_just_used
    elseif stim_trigger_mode == "after_ability_end" then
        should_process = combat_ability_just_ended
    elseif stim_trigger_mode == "combat_only" then
        should_process = in_combat and combat_start_time ~= nil
    elseif stim_trigger_mode == "non_combat_only" then
        should_process = not in_combat
    elseif stim_trigger_mode == "always_stim" then
        should_process = true
    end

    if should_process then
        local current_time = _get_gameplay_time()
        if not current_time then
            return
        end

        local time_since_last_injection = last_injection_time and (current_time - last_injection_time) or math.huge
        local time_in_combat = combat_start_time and (current_time - combat_start_time) or 0

        local should_check_injection = false
        if stim_trigger_mode == "on_ability_use" or stim_trigger_mode == "after_ability_end" then
            should_check_injection = true
        elseif stim_trigger_mode == "always_stim" then
            should_check_injection = time_since_last_injection >= effective_duration
        elseif stim_trigger_mode == "combat_only" then
            if not last_injection_time then
                should_check_injection = time_in_combat >= effective_duration
            else
                should_check_injection = time_since_last_injection >= effective_duration
            end
        elseif stim_trigger_mode == "non_combat_only" then
            if not last_injection_time then
                should_check_injection = true
            else
                local cooldown = mod:get("out_of_combat_timeout") or 5.0
                should_check_injection = time_since_last_injection >= cooldown
            end
        end

        if should_check_injection then
            local has_stim = _has_broker_stim()

            if chem_info and chem_info.has_keystone then
                _debug(function()
                    local time_until_decay_str = chem_info.time_until_stack_decay and string.format("%.2f", chem_info.time_until_stack_decay) or "N/A"
                    return string.format("Duration reached! Time since last: %.2f Effective: %.2f Stacks: %d/%d Time until decay: %s",
                        time_since_last_injection, effective_duration, chem_info.current_stacks, chem_info.max_stacks, time_until_decay_str)
                end)
            else
                _debug(function() return "Duration reached! Time since last: " .. string.format("%.2f", time_since_last_injection) .. " Has stim: " .. tostring(has_stim) end)
            end

            if has_stim then
                if not _is_weapon_template_valid(STIMM_SLOT_NAME) then
                    _debug("Stim template not ready yet, waiting...")
                else
                    local can_use = _can_use_stim()
                    if not can_use then
                        _debug("Stim is on cooldown, waiting...")
                    elseif not chem_info or chem_info.can_gain_stack or (chem_info.time_until_stack_decay and chem_info.time_until_stack_decay <= 2.0) then
                        _debug("Starting auto-inject!")
                        if _start_auto_inject() then
                            last_injection_time = current_time
                            if stim_trigger_mode == "on_ability_use" or stim_trigger_mode == "after_ability_end" then
                                combat_ability_just_used = false
                                combat_ability_just_ended = false
                            end
                        end
                    else
                        _debug(function() return string.format("Waiting for Chemical Dependency stack to decay (%.2f seconds remaining)...", chem_info.time_until_stack_decay) end)
                    end
                end
            else
                _debug("No broker stim found!")
            end
        end
    elseif not in_combat and stim_trigger_mode ~= "always_stim" and stim_trigger_mode ~= "non_combat_only" then
        if combat_start_time then
            _debug("Combat ended")
        end
        combat_start_time = nil
        if stim_trigger_mode == "combat_only" then
            last_injection_time = nil
        end
        last_combat_time = nil
    end
end


mod:hook_safe(CLASS.AttackReportManager, "add_attack_result", function(func, self, damage_profile, attacked_unit, attacking_unit, attack_direction, hit_world_position, hit_weakspot, damage,
                                                                       attack_result, attack_type, damage_efficiency, ...)
    if _is_local_player(attacking_unit) or _is_local_player(attacked_unit) then
        _mark_combat_started()
    end
end)

mod:hook_safe(CLASS.PlayerUnitWeaponExtension, "on_slot_wielded", function(self, slot_name, ...)
    if self._player == Managers.player:local_player(1) then
        if slot_name ~= STIMM_SLOT_NAME then
            last_equipped_slot = slot_name
        end
        current_wield_slot = slot_name
        if auto_stimm_stage == AUTO_STIMM_STAGES.SWITCH_BACK then
            local target_slot = unwield_to_slot or last_equipped_slot
            if input_request and (not target_slot or slot_name == target_slot) then
                _reset_auto_stimm_state()
                _debug("Switched back, injection complete")
            end
        elseif auto_stimm_stage == AUTO_STIMM_STAGES.SWITCH_TO and slot_name == STIMM_SLOT_NAME then
            local current_time = _get_gameplay_time()
            auto_stimm_stage = AUTO_STIMM_STAGES.WAITING_FOR_INJECT
            stage_start_time = current_time
            _debug("Stim wielded, waiting for auto-inject...")
        end
    end
end)

mod:hook_safe(CLASS.ActionHandler, "start_action", function(self, id, action_objects, action_name, action_params, action_settings, used_input, ...)
    if _get_player_unit() == self._unit then
        if id == "combat_ability_action" then
            combat_ability_just_used = true
            combat_ability_active = true
            _debug("Combat ability button pressed - action starting")
        end

        if action_name == "action_push" and mod:get("cancel_on_push_block") then
            push_in_progress = true
            local player_unit = _get_player_unit()
            local injection_running = false
            if player_unit then
                local weapon_extension = ScriptUnit.has_extension(player_unit, "weapon_system")
                if weapon_extension and weapon_extension._action_handler then
                    local running_action_name = weapon_extension._action_handler:running_action_name("weapon_action")
                    injection_running = running_action_name == "action_use_self"
                end
            end

            if auto_stimm_stage == AUTO_STIMM_STAGES.WAITING_FOR_INJECT or auto_stimm_stage == AUTO_STIMM_STAGES.SWITCH_TO then
                _debug("Push detected during injection attempt, canceling and will retry after push")
                injection_retry_after_push = true
                _reset_auto_stimm_state()
            elseif auto_stimm_stage == AUTO_STIMM_STAGES.SWITCH_BACK or injection_running then
                if injection_running then
                    _debug("Push detected during injection, attempting to cancel (may be uninterruptible)")
                    local t = _get_gameplay_time()
                    if t and player_unit then
                        local weapon_extension = ScriptUnit.has_extension(player_unit, "weapon_system")
                        if weapon_extension then
                            weapon_extension:stop_action("push_interrupt", nil, t)
                        end
                    end
                end
                injection_retry_after_push = true
                _reset_auto_stimm_state()
            end
        end

        if action_name == "action_block" and mod:get("cancel_on_push_block") then
            block_in_progress = true
            local player_unit = _get_player_unit()
            local injection_running = false
            if player_unit then
                local weapon_extension = ScriptUnit.has_extension(player_unit, "weapon_system")
                if weapon_extension and weapon_extension._action_handler then
                    local running_action_name = weapon_extension._action_handler:running_action_name("weapon_action")
                    injection_running = running_action_name == "action_use_self"
                end
            end

            if auto_stimm_stage == AUTO_STIMM_STAGES.WAITING_FOR_INJECT or auto_stimm_stage == AUTO_STIMM_STAGES.SWITCH_TO then
                _debug("Block detected during injection attempt, canceling and will retry after block")
                injection_retry_after_block = true
                _reset_auto_stimm_state()
            elseif auto_stimm_stage == AUTO_STIMM_STAGES.SWITCH_BACK or injection_running then
                if injection_running then
                    _debug("Block detected during injection, attempting to cancel (may be uninterruptible)")
                    local t = _get_gameplay_time()
                    if t and player_unit then
                        local weapon_extension = ScriptUnit.has_extension(player_unit, "weapon_system")
                        if weapon_extension then
                            weapon_extension:stop_action("block_interrupt", nil, t)
                        end
                    end
                end
                injection_retry_after_block = true
                _reset_auto_stimm_state()
            end
        end

        if action_name == "action_wield" then
            local slot_name = self._inventory_component.wielded_slot
            if slot_name ~= STIMM_SLOT_NAME then
                last_equipped_slot = slot_name
            end
        end

        if auto_stimm_stage == AUTO_STIMM_STAGES.SWITCH_BACK and (action_name == "action_unwield_to_previous" or action_name == "action_wield") and used_input ~= "quick_wield" then
            local target_slot = unwield_to_slot or last_equipped_slot
            input_request = target_slot == "slot_secondary" and "wield_2"
                or target_slot == "slot_grenade_ability" and "grenade_ability_pressed"
                or "wield_1"
            unwield_to_slot = input_request == "wield_1" and "slot_primary"
                or input_request == "wield_2" and "slot_secondary"
                or input_request == "grenade_ability_pressed" and "slot_grenade_ability"
                or nil
        elseif auto_stimm_stage == AUTO_STIMM_STAGES.WAITING_FOR_INJECT and current_wield_slot == STIMM_SLOT_NAME and action_name == "action_use_self" then
            local current_time = _get_gameplay_time()
            auto_stimm_stage = AUTO_STIMM_STAGES.SWITCH_BACK
            stage_start_time = current_time
            last_injection_time = current_time

            if mod:get("animation_cancel_stim") then
                _debug("Auto-inject detected! Canceling animation and switching back")
                local target_slot = unwield_to_slot or last_equipped_slot
                if target_slot then
                    input_request = target_slot == "slot_secondary" and "wield_2"
                        or target_slot == "slot_grenade_ability" and "grenade_ability_pressed"
                        or "wield_1"
                    unwield_to_slot = input_request == "wield_1" and "slot_primary"
                        or input_request == "wield_2" and "slot_secondary"
                        or input_request == "grenade_ability_pressed" and "slot_grenade_ability"
                        or nil
                end
            else
                _debug("Auto-inject detected! Will switch back after injection completes")
            end
        end
    end
end)

local _input_action_hook = function(func, self, action_name)
    local val = func(self, action_name)

    if mod:get("cancel_on_attack") then
        if action_name == "action_one_hold" or action_name == "action_one_pressed" then
            holding_attack = val or false
        elseif action_name == "action_one_release" then
            holding_attack = false
        elseif action_name == "action_two_hold" or action_name == "action_two_pressed" then
            if val then
                holding_attack = true
            end
        elseif action_name == "action_two_release" then
            if not func(self, "action_one_hold") then
                holding_attack = false
            end
        end
    end

    return input_request and action_name == input_request
        or auto_stimm_stage == AUTO_STIMM_STAGES.SWITCH_TO and action_name == "wield_4"
        or val
end
mod:hook(CLASS.InputService, "_get", _input_action_hook)
mod:hook(CLASS.InputService, "_get_simulate", _input_action_hook)

mod:hook("InteracteeSystem", "rpc_interaction_started", function(func, self, ...)
    func(self, ...)

    local arg_count = select('#', ...)
    if arg_count >= 5 then
        local channel_id = select(1, ...)
        local unit_id = select(2, ...)
        local is_level_unit = select(3, ...)
        local game_object_id = select(4, ...)
        local interaction_input_type = select(5, ...)

        local interactor_unit = Managers.state.unit_spawner:unit(game_object_id)
        local interactee_unit = Managers.state.unit_spawner:unit(unit_id, is_level_unit)

        if interactor_unit and interactee_unit then
            local extension = self._unit_to_extension_map[interactee_unit]
            if extension then
                local interaction_type = extension._active_interaction_type
                if not interaction_type or interaction_type == "none" then
                    interaction_type = extension:interaction_type()
                end

                if interaction_type and interaction_type ~= "none" then
                    local interaction_templates = require("scripts/settings/interaction/interaction_templates")
                    local template = interaction_templates[interaction_type]
                    if template and template.duration and template.duration > 0 then
                        if interactor_unit ~= nil then
                            interaction_active_units[interactor_unit] = {
                                type = interaction_type,
                                interactee_unit = interactee_unit
                            }
                        end
                    end
                end
            end
        end
    end
end)

mod:hook("InteracteeSystem", "rpc_interaction_stopped", function(func, self, ...)
    func(self, ...)

    local arg_count = select('#', ...)
    if arg_count >= 4 then
        local channel_id = select(1, ...)
        local unit_id = select(2, ...)
        local is_level_unit = select(3, ...)

        local interactee_unit = Managers.state.unit_spawner:unit(unit_id, is_level_unit)
        if interactee_unit then
            local extension = self._unit_to_extension_map[interactee_unit]

            local interactor_unit = nil
            if extension then
                interactor_unit = extension._interactor_unit

                if not interactor_unit then
                    local uds = ScriptUnit.has_extension(interactee_unit, "unit_data_system") and ScriptUnit.extension(interactee_unit, "unit_data_system")
                    if type(uds) == "table" and uds.read_component then
                        local interactee_component = uds:read_component("interactee")
                        if interactee_component then
                            interactor_unit = interactee_component.interactor_unit
                        end
                    end
                end

                if not interactor_unit then
                    for tracked_unit, data in pairs(interaction_active_units) do
                        if data and data.interactee_unit == interactee_unit then
                            interactor_unit = tracked_unit
                            break
                        end
                    end
                end
            end

            if interactor_unit ~= nil and interaction_active_units[interactor_unit] ~= nil then
                interaction_active_units[interactor_unit] = nil
            end
        end
    end
end)

mod:hook("InteracteeExtension", "started", function(func, self, interactor_unit, interaction_input_type)
    func(self, interactor_unit, interaction_input_type)

    if interactor_unit then
        local interaction_type = self._active_interaction_type
        if not interaction_type or interaction_type == "none" then
            interaction_type = self:interaction_type()
        end

        if interaction_type and interaction_type ~= "none" then
            local interaction_templates = require("scripts/settings/interaction/interaction_templates")
            local template = interaction_templates[interaction_type]
            if template and template.duration and template.duration > 0 then
                interaction_active_units[interactor_unit] = {
                    type = interaction_type,
                    interactee_unit = self._unit
                }
            end
        end
    end
end)

mod:hook("InteracteeExtension", "stopped", function(func, self, result)
    local interactor_unit = self._interactor_unit
    func(self, result)

    if interactor_unit ~= nil and interaction_active_units[interactor_unit] ~= nil then
        interaction_active_units[interactor_unit] = nil
    end
end)

mod:hook("PlayerInteracteeExtension", "started", function(func, self, interactor_unit, interaction_input_type)
    func(self, interactor_unit, interaction_input_type)

    if interactor_unit then
        local interaction_type = self:interaction_type()
        if interaction_type and interaction_type ~= "none" then
            local interaction_templates = require("scripts/settings/interaction/interaction_templates")
            local template = interaction_templates[interaction_type]
            if template and template.duration and template.duration > 0 then
                interaction_active_units[interactor_unit] = {
                    type = interaction_type,
                    interactee_unit = self._unit
                }
            end
        end
    end
end)

mod:hook("PlayerInteracteeExtension", "stopped", function(func, self, result)
    local interactor_unit = self._interactor_unit
    func(self, result)

    if interactor_unit ~= nil and interaction_active_units[interactor_unit] ~= nil then
        interaction_active_units[interactor_unit] = nil
    end
end)

mod:hook("InteractorExtension", "cancel_interaction", function(func, self, t)
    local interactor_unit = self._unit

    if interactor_unit ~= nil and interaction_active_units[interactor_unit] ~= nil then
        interaction_active_units[interactor_unit] = nil
    end

    func(self, t)
end)

mod:hook("InteractorExtension", "reset_interaction", function(func, self, reset_focus_unit)
    local interactor_unit = self._unit

    if interactor_unit ~= nil and interaction_active_units[interactor_unit] ~= nil then
        interaction_active_units[interactor_unit] = nil
    end

    func(self, reset_focus_unit)
end)

mod:hook_safe(CLASS.AuspexScanningEffects, "_run_searching_sfx_loop", function(self)
    if self and self._owner_unit then
        auspex_active_units[self._owner_unit] = true
    end
end)

mod:hook_safe(CLASS.AuspexScanningEffects, "_stop_scan_units_effects", function(self)
    if self and self._owner_unit then
        auspex_active_units[self._owner_unit] = false
    end
end)

mod:hook_safe(CLASS.AuspexScanningEffects, "unwield", function(self)
    if self and self._owner_unit then
        auspex_active_units[self._owner_unit] = false
    end
end)

mod:hook_safe(CLASS.AuspexEffects, "wield", function(self)
    if self and self._fx_extension and self._fx_extension._unit then
        auspex_active_units[self._fx_extension._unit] = true
    end
end)

mod:hook_safe(CLASS.AuspexEffects, "unwield", function(self)
    if self and self._fx_extension and self._fx_extension._unit then
        auspex_active_units[self._fx_extension._unit] = false
    end
end)

mod.on_game_state_changed = function(status, state_name)
    if status == "enter" and state_name == "StateGameplay" then
        _reset_all_state()
        local hud_element = mod.get_hud_element()
        if hud_element then
            hud_element:set_enabled_state(auto_stim_enabled)
        end
    end
end

Managers.event:register(mod, "player_unit_spawned", function(player)
    if player == Managers.player:local_player(1) then
        _reset_all_state()
    end
end)

mod.on_all_mods_loaded = function()
    if Managers.package then
        Managers.package:load("packages/ui/views/inventory_background_view/inventory_background_view", mod.name, nil, true)
    end
end

_initialize_profiles()
local active_profile = mod:get("active_profile") or 1
if not active_profile or active_profile < 1 or active_profile > 5 then
    active_profile = 1
    mod:set("active_profile", active_profile, false)
end
last_active_profile = active_profile
is_loading_profile = true
_load_profile_settings(active_profile)
is_loading_profile = false



