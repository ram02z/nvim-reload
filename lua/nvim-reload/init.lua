local M = {}

local o = vim.o
local fn = vim.fn
local cmd = vim.cmd

local Path = require('plenary.path')
local scan_dir = require('plenary.scandir').scan_dir


-- Paths to unload Lua modules from
M.lua_reload_dirs = { fn.stdpath('config') }

-- Paths to reload Vim files from
M.vim_reload_dirs = { fn.stdpath('config'), fn.stdpath('data') .. '/site/pack/*/start/*'}

-- External files outside the runtimepaths to source
M.files_reload_external = {}

-- External Lua modules outside the runtimepaths to unload
M.modules_reload_external = {}

-- Modules to exclude from unloading due to incompatibility issues
-- FIXME: nvim-colorizer and nvim-ts-rainbow don't reload
M.modules_reload_excluded = {}

-- Pre-reload hook
M.pre_reload_hook = nil

M.post_reload_hook = nil

local viml_subdirs = {
  'compiler',
  'doc',
  'indent',
  'keymap',
  'lang',
  'plugin',
  'print',
  'spell',
  'syntax',
}

-- Escape lua string for pattern matching
local function escape_str(str)
  local patterns_to_escape = {
    '%^',
    '%$',
    '%(',
    '%)',
    '%%',
    '%.',
    '%[',
    '%]',
    '%*',
    '%+',
    '%-',
    '%?'
  }

  return string.gsub(
  str,
  string.format("([%s])", table.concat(patterns_to_escape)),
  '%%%1'
  )
end

-- Check if path exists
local function path_exists(path)
  return Path:new(path):exists()
end

local function get_runtime_files_in_path(runtimepath)
  local runtime_files = {}

  -- Search each subdirectory listed listed in viml_subdirs of runtimepath for files
  for _, subdir in ipairs(viml_subdirs) do
    local viml_path = string.format("%s/%s", runtimepath, subdir)

    if path_exists(viml_path) then
      local files = scan_dir(viml_path, { search_pattern = '%.n?vim$', hidden = true })

      for _, file in ipairs(files) do
        runtime_files[#runtime_files+1] = file
      end
    end
  end

  return runtime_files
end

local function is_module_excluded(module)
  for _, v in ipairs(M.modules_reload_excluded) do
    if v == module or string.match(module, string.format('^%s%%.', v)) then
      return true
    end
  end
end

local function get_lua_modules_in_path(runtimepath)
  local luapath = string.format("%s/lua", runtimepath)

  if not path_exists(luapath) then
    return {}
  end

  -- Search lua directory of runtimepath for modules
  local modules = scan_dir(luapath, { search_pattern = '%.lua$', hidden = true })

  for i, module in ipairs(modules) do
    -- Remove runtimepath and file extension from module path
    module = string.match(
    module,
    string.format(
    '%s/(.*)%%.lua',
    escape_str(luapath)
    )
    )

    -- Changes slash in path to dot to follow lua module format
    module = string.gsub(module, "/", ".")

    -- If module ends with '.init', remove it.
    module = string.gsub(module, "%.init$", "")

    -- Override previous value with new value
    modules[i] = module
  end

  return modules
end

-- Reload all start plugins
local function reload_runtime_files()
  -- Search each runtime path for files
  for _, runtimepath_suffix in ipairs(M.vim_reload_dirs) do
    -- Expand the globs and get the result as a list
    local paths = fn.glob(runtimepath_suffix, 0, 1)

    for _, path in ipairs(paths) do
      local runtime_files = get_runtime_files_in_path(path)

      for _, file in ipairs(runtime_files) do
        cmd('source ' .. file)
      end
    end
  end

  for _, file in ipairs(M.files_reload_external) do
    cmd('source ' .. file)
  end
end

-- Unload all loaded Lua modules
local function unload_lua_modules()
  -- Search each runtime path for modules
  for _, runtimepath_suffix in ipairs(M.lua_reload_dirs) do
    local paths = fn.glob(runtimepath_suffix, 0, 1)

    for _, path in ipairs(paths) do
      local modules = get_lua_modules_in_path(path)

      for _, module in ipairs(modules) do
        if not is_module_excluded(module) then
          package.loaded[module] = nil
        end
      end
    end
  end

  for _, module in ipairs(M.modules_reload_external) do
    package.loaded[module] = nil
  end
end

function M.Reload()
  -- Run pre-reload hook
  if type(M.pre_reload_hook) == "function" then
    M.pre_reload_hook()
  end

  -- Save path to init file
  local init_path = fn.expand('$MYVIMRC')

  if fn.exists(':LspStop') ~= 0 then
    cmd('LspStop')
  end

  -- Save runtimepath
  local runtimepath = o.runtimepath

  -- Unload lua modules
  unload_lua_modules()

  -- Source init file
  if string.match(init_path, '%.lua$') then
    cmd('luafile ' .. init_path)
  else
    cmd('source ' .. init_path)
  end

  -- Set runtimepath
  o.runtimepath = runtimepath

  -- Reload start plugins
  reload_runtime_files()

  -- Reload all buffers
  -- TODO: Add prompt
  cmd('bufdo edit!')

  -- Run post-reload hook
  if type(M.post_reload_hook) == "function" then
    M.post_reload_hook()
  end
end

return M
