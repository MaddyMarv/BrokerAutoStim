local mod = get_mod("BrokerAutoStim")

	return {
		name = mod:localize("mod_name"),
		description = mod:localize("mod_description"),
		is_togglable = true,
		options = {
			widgets = {
				{
					setting_id = "keybind_settings",
					type = "group",
					sub_widgets = {
						{
							setting_id      = "toggle_hotkey",
							type            = "keybind",
							default_value   = {},
							keybind_trigger = "pressed",
							keybind_type    = "function_call",
							function_name   = "toggle_auto_stim"
						},
					}
				},
				{
					setting_id = "auto_stim_settings",
					type = "group",
					sub_widgets = {
						{
							setting_id    = "only_with_chemical_dependency",
							type          = "checkbox",
							default_value = false
						},
						{
							setting_id    = "not_with_stimm_supply",
							type          = "checkbox",
							default_value = false
						},
						{
							setting_id      = "stim_trigger_mode",
							type            = "dropdown",
							default_value   = "combat_only",
							options         = {
								{
									text = "stim_trigger_mode_combat_only",
									value = "combat_only"
								},
								{
									text = "stim_trigger_mode_non_combat_only",
									value = "non_combat_only"
								},
								{
									text = "stim_trigger_mode_after_ability",
									value = "after_ability_end"
								},
								{
									text = "stim_trigger_mode_before_ability",
									value = "on_ability_use"
								},
								{
									text = "stim_trigger_mode_always_stim",
									value = "always_stim"
								}
						}
						},
						{
							setting_id      = "combat_duration",
							type            = "numeric",
							default_value   = 5.0,
							range           = { 0.5, 90.0 },
							decimals_number = 1
						},
						{
							setting_id      = "out_of_combat_timeout",
							type            = "numeric",
							default_value   = 5.0,
							range           = { 1.0, 30.0 },
							decimals_number = 1
						},
						{
							setting_id    = "animation_cancel_stim",
							type          = "checkbox",
							default_value = true
						},
					}
				},
				{
					setting_id = "profile_settings",
					type = "group",
					sub_widgets = {
						{
							setting_id      = "active_profile",
							type            = "dropdown",
							default_value   = 1,
							options         = {
								{
									text = "active_profile_1",
									value = 1
								},
								{
									text = "active_profile_2",
									value = 2
								},
								{
									text = "active_profile_3",
									value = 3
								},
								{
									text = "active_profile_4",
									value = 4
								},
								{
									text = "active_profile_5",
									value = 5
								}
							}
						},
						{
							setting_id      = "cycle_profile_hotkey",
							type            = "keybind",
							default_value   = {},
							keybind_trigger = "pressed",
							keybind_type    = "function_call",
							function_name   = "cycle_profile"
						},
						{
							setting_id    = "show_settings_on_switch",
							type          = "checkbox",
							default_value = false
						},
						{
							setting_id      = "number_of_profiles_to_cycle",
							type            = "numeric",
							default_value   = 5,
							range           = { 1, 5 },
							decimals_number = 0
						},
						{
							setting_id = "auto_inject_prevention",
							type = "group",
							sub_widgets = {
								{
									setting_id    = "cancel_on_push_block",
									type          = "checkbox",
									default_value = false
								},
								{
									setting_id    = "cancel_on_attack",
									type          = "checkbox",
									default_value = false
								},
								{
									setting_id      = "attack_cooldown",
									type            = "numeric",
									default_value   = 0.5,
									range           = { 0.1, 4.0 },
									decimals_number = 2
								},
								{
									setting_id    = "cancel_on_carrying",
									type          = "checkbox",
									default_value = false
								},
								{
									setting_id    = "cancel_on_reload",
									type          = "checkbox",
									default_value = false
								},
								{
									setting_id    = "cancel_on_interaction",
									type          = "checkbox",
									default_value = false
								},
								{
									setting_id    = "cancel_on_auspex",
									type          = "checkbox",
									default_value = false
								},
								{
									setting_id    = "cancel_during_ability",
									type          = "checkbox",
									default_value = false
								},
							}
						},
						{
							setting_id = "dangerous_enemy_detection",
							type = "group",
							sub_widgets = {
								{
									setting_id    = "block_nearby_dog",
									type          = "checkbox",
									default_value = false
								},
								{
									setting_id      = "dog_detection_range",
									type            = "numeric",
									default_value   = 15.0,
									range           = { 2.0, 50.0 },
									decimals_number = 1
								},
								{
									setting_id    = "block_nearby_trapper",
									type          = "checkbox",
									default_value = false
								},
								{
									setting_id      = "trapper_detection_range",
									type            = "numeric",
									default_value   = 15.0,
									range           = { 5.0, 50.0 },
									decimals_number = 1
								},
								{
									setting_id    = "block_nearby_burster",
									type          = "checkbox",
									default_value = false
								},
								{
									setting_id      = "burster_detection_range",
									type            = "numeric",
									default_value   = 10.0,
									range           = { 3.0, 30.0 },
									decimals_number = 1
								},
								{
									setting_id    = "block_nearby_crusher",
									type          = "checkbox",
									default_value = false
								},
								{
									setting_id      = "crusher_detection_range",
									type            = "numeric",
									default_value   = 5.0,
									range           = { 5.0, 50.0 },
									decimals_number = 1
								},
								{
									setting_id    = "block_nearby_rager",
									type          = "checkbox",
									default_value = false
								},
								{
									setting_id      = "rager_detection_range",
									type            = "numeric",
									default_value   = 5.0,
									range           = { 5.0, 50.0 },
									decimals_number = 1
								},
							}
						},
					}
				},
				{
					setting_id = "hud_settings",
					type = "group",
					sub_widgets = {
						{
							setting_id    = "show_hud_icon",
							type          = "checkbox",
							default_value = true
						},
				{
					setting_id      = "hud_icon_size",
					type            = "numeric",
					default_value   = 30,
					range           = { 20, 100 },
					decimals_number = 0
				},
					}
				},
				{
					setting_id = "debug_settings",
					type = "group",
					sub_widgets = {
						{
							setting_id    = "enable_debug",
							type          = "checkbox",
							default_value = false
						},
					}
				},
			}
		}
	}
