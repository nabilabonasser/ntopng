--
-- (C) 2019 - ntop.org
--

local dirs = ntop.getDirs()
package.path = dirs.installdir .. "/scripts/lua/modules/?.lua;" .. package.path
require "lua_utils"
require "alert_utils"

local alerts_api = require("alerts_api")
local user_scripts = require("user_scripts")
local alert_consts = require("alert_consts")

local do_trace      = false
local config_alerts = nil
local ifid = nil
local available_modules = nil

-- The function below ia called once (#pragma once)
function setup(str_granularity)
   if(do_trace) then print("alert.lua:setup("..str_granularity..") called\n") end
   ifid = interface.getId()
   local ifname = interface.setActiveInterfaceId(ifid)

   -- Load the check modules
   available_modules = user_scripts.load(user_scripts.script_types.traffic_element, ifid, "interface", str_granularity)

   config_alerts = getInterfaceConfiguredAlertThresholds(ifname, str_granularity, available_modules.modules)
end

-- #################################################################

-- The function below ia called once (#pragma once)
function teardown(str_granularity)
   if(do_trace) then print("alert.lua:teardown("..str_granularity..") called\n") end

   for _, check in pairs(available_modules.modules) do
      if check.teardown then
         check.teardown()
      end
   end
end

-- #################################################################

-- The function below is called once
function checkAlerts(granularity)
   if table.empty(available_modules.hooks[granularity]) then
      if(do_trace) then print("interface:checkAlerts("..granularity.."): no modules, skipping\n") end
      return
   end

   local suppressed_alerts = interface.hasAlertsSuppressed()

   if suppressed_alerts then
      releaseAlerts(granularity)
   end

   local info = interface.getStats()
   local ifid = interface.getId()
   local interface_key   = "iface_"..ifid
   local interface_config = config_alerts[interface_key] or {}
   local global_config = config_alerts["interfaces"] or {}
   local has_configuration = (table.len(interface_config) or table.len(global_config))
   local entity_info = alerts_api.interfaceAlertEntity(ifid)

   if(do_trace) then print("checkInterfaceAlerts()\n") end

   if(has_configuration) then
      for mod_key, hook_fn in pairs(available_modules.hooks[granularity]) do
        local check = available_modules.modules[mod_key]
        local config = interface_config[check.key] or global_config[check.key]

        if((config or check.always_enabled) and (not check.is_alert or not suppressed_alerts)) then
           hook_fn({
              granularity = granularity,
              alert_entity = entity_info,
              entity_info = info,
              alert_config = config,
              check_module = check,
           })
        end
      end
   end

   alerts_api.releaseEntityAlerts(entity_info, interface.getExpiredAlerts(granularity2id(granularity)))
end

-- #################################################################

function releaseAlerts(granularity)
  local ifid = interface.getId()
  local entity_info = alerts_api.interfaceAlertEntity(ifid)

  alerts_api.releaseEntityAlerts(entity_info, interface.getAlerts(granularity))
end