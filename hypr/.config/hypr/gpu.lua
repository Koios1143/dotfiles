-- Hardware-adaptive GPU power tuning — safe to ship in a portable dotfiles repo.
--
-- On a hybrid LAPTOP (an integrated Intel/AMD GPU that drives the built-in eDP panel,
-- plus a discrete NVIDIA GPU), this steers the compositor at the iGPU via
-- AQ_DRM_DEVICES and forces glvnd to load only Mesa's EGL vendor, so the NVIDIA dGPU
-- is left completely untouched and can drop to RTD3/D3cold. Two reasons that matters:
--   * AQ_DRM_DEVICES restricts which DRM node aquamarine opens (colon-free path only —
--     a PCI by-path can't be used, its colons are the list separator).
--   * __EGL_VENDOR_LIBRARY_FILENAMES stops libglvnd from loading NVIDIA's EGL just to
--     enumerate devices, which would otherwise open /dev/nvidia* and pin the dGPU awake.
--
-- On ANY other host it returns nothing, so the same config is portable:
--   * single-GPU machine                         -> no NVIDIA, skip
--   * NVIDIA-primary desktop (monitor on the dGPU, no connected eDP) -> skip, so we
--     never blank a desktop by forcing it onto an unused iGPU
--   * pure-AMD / pure-Intel                       -> no NVIDIA, skip
--
-- Nothing here is hard-coded to this machine: the iGPU's card node is resolved by PCI
-- vendor id at runtime (card numbering isn't stable), and the Mesa vendor JSON is only
-- referenced if it actually exists. All probing is pcall-guarded, so a failure (e.g. a
-- Lua build without `io`) degrades to a no-op and can never crash the compositor.

local function line(path)
  local f = io.open(path, "r"); if not f then return nil end
  local s = f:read("l"); f:close(); return s
end

local function exists(path)
  local f = io.open(path, "r"); if f then f:close(); return true end
  return false
end

-- Treat an iGPU as "the laptop's display GPU" only if it has a connected eDP (the
-- built-in panel). This is what separates a hybrid laptop from an NVIDIA desktop.
local function drives_panel(idx)
  for j = 1, 4 do
    if line("/sys/class/drm/card" .. idx .. "-eDP-" .. j .. "/status") == "connected" then
      return true
    end
  end
  return false
end

local function detect()
  local igpu_idx, nvidia_idx, gpus = nil, nil, 0
  for i = 0, 9 do
    local vendor = line("/sys/class/drm/card" .. i .. "/device/vendor")
    if vendor then
      gpus = gpus + 1
      if vendor == "0x10de" then                                  -- NVIDIA
        if nvidia_idx == nil then nvidia_idx = i end              -- first NVIDIA GPU
      elseif (vendor == "0x8086" or vendor == "0x1002") and igpu_idx == nil then
        igpu_idx = i                                              -- first Intel/AMD GPU
      end
    end
  end
  return igpu_idx, nvidia_idx, gpus
end

-- External displays follow EnvyControl's mode. On this class of laptop the HDMI (and
-- often DP) port is muxed to the dGPU, so the power-saving default above hides it:
-- aquamarine never opens the NVIDIA node, so the port never shows in `hyprctl monitors`.
--
-- Policy: mirror EnvyControl.
--   integrated -> power-save: dGPU is off (its PCI device is removed), nothing to open.
--   hybrid / nvidia -> open the NVIDIA node too, so the muxed HDMI/DP ports light up.
-- Switching EnvyControl mode already requires a reboot, so Hyprland re-runs this on the
-- next login and the two stay in sync automatically -- no manual toggle needed.
--
-- Tradeoff: in hybrid mode this keeps the NVIDIA node open even with nothing plugged in,
-- which blocks its RTD3 deep sleep. For maximum battery, switch EnvyControl to integrated.
-- When EnvyControl isn't installed we fall back to the power-saving default (steer to the
-- iGPU), so this file stays portable across machines. All probing is pcall-guarded.
local function envycontrol_mode()
  local ok, mode = pcall(function()
    local p = io.popen("envycontrol --query 2>/dev/null")
    if not p then return nil end
    local out = (p:read("a") or ""):lower()
    p:close()
    if out:match("integrated") then return "integrated" end
    if out:match("nvidia")     then return "nvidia"     end
    if out:match("hybrid")     then return "hybrid"     end
    return nil
  end)
  return ok and mode or nil
end

-- Returns a table of env vars to apply, or an empty table if this host shouldn't be tuned.
return function()
  local ok, idx, nvidia_idx, gpus = pcall(detect)
  if not ok or idx == nil or nvidia_idx == nil or gpus < 2 then return {} end
  if not drives_panel(idx) then return {} end           -- not a laptop panel on the iGPU

  local mode = envycontrol_mode()
  local want_dgpu = (mode == "hybrid" or mode == "nvidia")

  -- Intel stays first in the list => it remains the primary render device and drives the
  -- eDP panel. The NVIDIA node is appended only as an extra output for the muxed ports.
  local drm = "/dev/dri/card" .. idx
  if want_dgpu then drm = drm .. ":/dev/dri/card" .. nvidia_idx end

  local env = { AQ_DRM_DEVICES = drm }

  -- The Mesa-only EGL vendor filter keeps glvnd from touching NVIDIA's EGL just to
  -- enumerate devices (which would pin the dGPU awake). Drop it when the dGPU is wanted:
  -- there we intentionally keep it active, and hiding its vendor can keep the muxed
  -- output from coming up.
  local mesa = "/usr/share/glvnd/egl_vendor.d/50_mesa.json"
  if not want_dgpu and exists(mesa) then env["__EGL_VENDOR_LIBRARY_FILENAMES"] = mesa end
  return env
end
