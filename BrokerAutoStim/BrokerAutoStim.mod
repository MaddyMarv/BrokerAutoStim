return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`BrokerAutoStim` encountered an error loading the Darktide Mod Framework.")

		new_mod("BrokerAutoStim", {
			mod_script       = "BrokerAutoStim/scripts/mods/BrokerAutoStim/BrokerAutoStim",
			mod_data         = "BrokerAutoStim/scripts/mods/BrokerAutoStim/BrokerAutoStim_data",
			mod_localization = "BrokerAutoStim/scripts/mods/BrokerAutoStim/BrokerAutoStim_localization",
		})
	end,
	packages = {},
}

