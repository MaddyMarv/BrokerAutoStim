local mod = get_mod("BrokerAutoStim")

local UIWorkspaceSettings = require("scripts/settings/ui/ui_workspace_settings")
local UIWidget = require("scripts/managers/ui/ui_widget")

local color_enabled = { 255, 255, 255, 255 }
local color_disabled = { 160, 160, 160, 160 }

local ui_definitions = {
	scenegraph_definition = {
		screen = UIWorkspaceSettings.screen,
		broker_auto_stim_container = {
			parent = "screen",
			vertical_alignment = "bottom",
			horizontal_alignment = "right",
			size = { 30, 30 },
			position = {
				-370,
				-135,
				11
			}
		}
	},
	widget_definitions = {
		broker_auto_stim = UIWidget.create_definition({
			{
				style_id = "icon",
				value_id = "icon",
				pass_type = "texture",
				value = "content/ui/materials/icons/weapons/actions/activate",
				style = {
					size = { nil, nil },
				}
			}
		}, "broker_auto_stim_container")
	}
}

local HudElementBrokerAutoStim = class("HudElementBrokerAutoStim", "HudElementBase")

HudElementBrokerAutoStim.init = function(self, parent, draw_layer, start_scale)
	HudElementBrokerAutoStim.super.init(self, parent, draw_layer, start_scale, ui_definitions)
	local enabled = mod.get_auto_stim_enabled and mod.get_auto_stim_enabled() or true
	self:set_enabled_state(enabled)
	self:update_visibility()
	self:set_side_length(mod:get("hud_icon_size") or 30)
end

HudElementBrokerAutoStim.update_visibility = function(self)
	local should_show = mod:get("show_hud_icon") and mod.is_broker_with_stim()
	self._widgets_by_name.broker_auto_stim.style.icon.visible = should_show
end

HudElementBrokerAutoStim.set_visible = function(self, visible)
	if visible then
		self:update_visibility()
	else
		self._widgets_by_name.broker_auto_stim.style.icon.visible = false
	end
end

HudElementBrokerAutoStim.update = function(self, dt, t, ui_renderer, render_settings, input_service)
	HudElementBrokerAutoStim.super.update(self, dt, t, ui_renderer, render_settings, input_service)
	
	if mod:get("show_hud_icon") then
		self:update_visibility()
	end
end

HudElementBrokerAutoStim.set_enabled_state = function(self, enabled)
	self._widgets_by_name.broker_auto_stim.style.icon.color = enabled and color_enabled or color_disabled
end

HudElementBrokerAutoStim.set_side_length = function(self, side_length)
	local widget_size = self._widgets_by_name.broker_auto_stim.style.icon.size
	widget_size[1] = side_length
	widget_size[2] = side_length
end

return HudElementBrokerAutoStim
