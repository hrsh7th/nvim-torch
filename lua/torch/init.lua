local kit = require('cmp-kit.kit')
local Async = require('cmp-kit.kit.Async')
local Keymap = require('cmp-kit.kit.Vim.Keymap')
local CompletionService = require('cmp-kit.core.CompletionService')
local misc = require('torch.misc')

---@class torch.ServiceRegistration
---@field public service cmp-kit.core.CompletionService
---@field public dispose fun()

---@class torch.Charmap
---@field public mode ('i' | 'c')[]
---@field public char string
---@field public callback fun(ctx: torch.CharmapContext)

---@class torch.CharmapContext
---@field public prevent fun(callback: fun())
---@field public is_menu_visible fun(): boolean
---@field public complete fun(option?: { force?: boolean })
---@field public get_selection fun(): cmp-kit.core.Selection
---@field public select fun(index: integer, preselect?: boolean)
---@field public commit fun(index: integer, option?: { replace?: boolean })
---@field public fallback fun()

---@class torch.preset.InsertModeOption
---@field public expand_snippet? cmp-kit.core.ExpandSnippet
---@field public sync_mode? fun(): boolean
---@field public view? cmp-kit.core.View
---@field public sorter? cmp-kit.core.Sorter
---@field public matcher? cmp-kit.core.Matcher
---@field public disable_providers? { lsp_completion?: true, path?: true, buffer?: true }

---@class torch.preset.CmdlineModeOption
---@field public sync_mode? fun(): boolean
---@field public view? cmp-kit.core.View
---@field public sorter? cmp-kit.core.Sorter
---@field public matcher? cmp-kit.core.Matcher
---@field public disable_providers? { cmdline?: true, path?: true, buffer?: true }

---@class torch.Config
---@field public auto boolean
---@field public expand_snippet? cmp-kit.core.ExpandSnippet

local torch = {}

local private = {
  ---The attached services for buffer.
  ---@type table<integer, torch.ServiceRegistration>
  attached_i = {},
  ---The attached services for cmdtype.
  ---@type table<string, torch.ServiceRegistration>
  attached_c = {},
  ---Onetime completion.
  ---@type torch.ServiceRegistration?
  onetime = nil,
  ---The charmaps.
  ---@type torch.Charmap[]
  charmaps = {},

  ---The config.
  config = {
    auto = true,
  },
}

---Setup char mapping.
do
  vim.on_key(function(_, typed)
    local mode = vim.api.nvim_get_mode().mode

    -- find charmap.
    local charmap = vim.iter(private.charmaps):find(function(charmap)
      return vim.tbl_contains(charmap.mode, mode) and typed == charmap.char
    end)
    if not charmap then
      return
    end

    -- check service conditions.
    local service = torch.get_service()
    if not service then
      return
    end

    -- remove typeahead.
    while true do
      local c = vim.fn.getcharstr(0)
      if c == '' then
        break
      end
    end

    -- create charmap context.
    local ctx ---@type torch.CharmapContext
    ctx = {
      prevent = function(callback)
        local resume = service:prevent()
        callback()
        resume()
      end,
      is_menu_visible = function()
        return service:is_menu_visible()
      end,
      get_selection = function()
        return service:get_selection()
      end,
      complete = function(option)
        service:complete(option):await()
      end,
      select = function(index, preselect)
        service:select(index, preselect):await()
      end,
      commit = function(index, option)
        local match = torch.get_service():get_match_at(index)
        if match then
          service:commit(match.item, option):await()
        else
          ctx.fallback()
        end
      end,
      fallback = function()
        Keymap.send({ { keys = typed, remap = true } }):await()
      end,
    }

    Async.run(function()
      charmap.callback(ctx)
    end)

    return ''
  end, vim.api.nvim_create_namespace('torch'), {})
end

---Setup insert-mode.
do
  local rev = 0
  misc.autocmd('TextChangedI', {
    callback = function()
      local service = torch.get_service()
      if service then
        service:complete()
      end
    end
  })
  misc.autocmd('CursorMovedI', {
    callback = function()
      local service = torch.get_service()
      if service then
        service:matching()
      end
    end
  })
  misc.autocmd('ModeChanged', {
    callback = function()
      rev = rev + 1
      local c = rev
      vim.schedule(function()
        if c ~= rev then
          return
        end
        if vim.api.nvim_get_mode().mode ~= 'i' then
          for _, service_and_dispose in pairs(private.attached_i) do
            service_and_dispose.service:clear()
          end
        end
      end)
    end
  })
end

---Setup cmdline-mode.
do
  local rev = 0
  misc.autocmd('CmdlineChanged', {
    callback = function()
      rev = rev + 1
      local c = rev
      vim.schedule(function()
        if c ~= rev then
          return
        end
        local service = torch.get_service()
        if service then
          service:complete()
        end
      end)
    end
  })
  misc.autocmd('ModeChanged', {
    callback = function()
      rev = rev + 1
      local c = rev
      vim.schedule(function()
        if c ~= rev then
          return
        end
        local is_not_cmdline = vim.api.nvim_get_mode().mode ~= 'c'
        for cmdtype, service_and_dispose in pairs(private.attached_c) do
          if is_not_cmdline or vim.fn.getcmdtype() ~= cmdtype then
            service_and_dispose.service:clear()
          end
        end
      end)
    end
  })
end

---Setup.
---@param config torch.Config|{}
function torch.setup(config)
  private.config = kit.merge(config, private.config)
end

---Get the current service.
---@return cmp-kit.core.CompletionService?
function torch.get_service()
  if private.onetime then
    return private.onetime.service
  end

  if vim.api.nvim_get_mode().mode == 'i' then
    local v = private.attached_i[vim.api.nvim_get_current_buf()]
    return v and v.service
  else
    local v = private.attached_c[vim.fn.getcmdtype()]
    return v and v.service
  end
end

torch.attach = {}

---Attach a service to buffer.
---@param setup fun(service: cmp-kit.core.CompletionService): fun()[]
function torch.attach.i(setup)
  local bufnr = vim.api.nvim_get_current_buf()
  local attached = private.attached_i[bufnr]
  if attached then
    attached.dispose()
  end

  local service = CompletionService.new({
    expand_snippet = private.config.expand_snippet,
  })
  local disposes = setup(service)
  private.attached_i[bufnr] = {
    service = service,
    dispose = function()
      for _, dispose in ipairs(disposes) do
        dispose()
      end
    end,
  }
end

---Attach a service to cmdtype.
---@param setup fun(service: cmp-kit.core.CompletionService): fun()[]
function torch.attach.c(cmdtype, setup)
  local attached = private.attached_i[cmdtype]
  if attached then
    attached.dispose()
  end

  local service = CompletionService.new({})
  local disposes = setup(service)
  private.attached_c[cmdtype] = {
    service = service,
    dispose = function()
      for _, dispose in ipairs(disposes) do
        dispose()
      end
    end,
  }
end

---Do onetime completion.
---@param option { force?: boolean }
---@param setup fun(service: cmp-kit.core.CompletionService): fun()[]
function torch.onetime(option, setup)
  local current_service = torch.get_service()
  if current_service then
    current_service:clear()
  end

  local service = CompletionService.new({})
  local disposes = setup(service)
  private.onetime = {
    service = service,
    dispose = function()
      for _, dispose in ipairs(disposes) do
        dispose()
      end
      service:dispose()
      private.onetime = nil
    end,
  }

  service:complete(option):next(function()
    if service:is_menu_visible() then
      service:on_menu_hide(function()
        private.onetime.dispose()
      end)
    else
      private.onetime.dispose()
    end
  end)
end

torch.preset = {}

---Create preset service for insert-mode.
---@param service cmp-kit.core.CompletionService
---@param opts? torch.preset.InsertModeOption
---@return fun()[]
function torch.preset.i(service, opts)
  opts = opts or {}
  opts.disable_providers = opts.disable_providers or {}

  local bufnr = vim.api.nvim_get_current_buf()
  local disposes = {}

  -- lsp.completion.
  if not opts.disable_providers.lsp_completion then
    local attached = {} --[[@type table<integer, fun()>]]
    -- attach.
    local function attach()
      for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
        if attached[client.id] then
          attached[client.id]()
        end
        attached[client.id] = service:register_source(
          require('cmp-kit.ext.source.lsp.completion')({
            client = client --[[@as vim.lsp.Client]],
          }), {
            group = 1,
            priority = 100
          })
      end
    end
    table.insert(disposes, misc.autocmd('InsertEnter', {
      callback = attach
    }))
    table.insert(disposes, misc.autocmd('LspAttach', {
      callback = attach
    }))

    -- detach.
    table.insert(disposes, misc.autocmd('LspDetach', {
      callback = function(e)
        if attached[e.data.client_id] then
          attached[e.data.client_id]()
          attached[e.data.client_id] = nil
        end
      end
    }))
  end

  -- path.
  if not opts.disable_providers.path then
    service:register_source(require('cmp-kit.ext.source.path')(), {
      group = 10,
    })
  end

  -- buffer.
  if not opts.disable_providers.buffer then
    service:register_source(require('cmp-kit.ext.source.buffer')({
      keyword_pattern = [[\k\+]],
      min_keyword_length = 3,
    }), {
      group = 100,
      dedup = true,
    })
  end

  return disposes
end

---Create preset service for cmdline-mode.
---@param service cmp-kit.core.CompletionService
---@param opts? torch.preset.CmdlineModeOption
---@return fun()[]
function torch.preset.c(service, opts)
  opts = opts or {}
  opts.disable_providers = opts.disable_providers or {}

  -- path.
  if not opts.disable_providers.path then
    service:register_source(require('cmp-kit.ext.source.path')(), {
      group = 1,
    })
  end

  -- cmdline.
  if not opts.disable_providers.cmdline then
    service:register_source(require('cmp-kit.ext.source.cmdline')(), {
      group = 10,
    })
  end

  -- buffer.
  if not opts.disable_providers.buffer then
    service:register_source(require('cmp-kit.ext.source.buffer')({
      keyword_pattern = [[\k\+]],
      min_keyword_length = 3,
    }), {
      group = 100,
      dedup = true,
    })
  end

  return {}
end

---Setup character mapping.
---@param mode 'i' | 'c' | ('i' | 'c')[]
---@param char string
---@param callback fun(ctx: torch.CharmapContext)
function torch.charmap(mode, char, callback)
  local l = 0
  local i = 1
  local n = false
  while i <= #char do
    local c = char:sub(i, i)
    if c == '<' then
      n = true
    elseif c == '\\' then
      i = i + 1
    else
      if n then
        if c == '>' then
          n = false
          l = l + 1
        end
      else
        l = l + 1
      end
    end
    i = i + 1
  end

  if l > 1 then
    error('multiple key sequence is not supported')
  end

  table.insert(private.charmaps, {
    mode = kit.to_array(mode),
    char = vim.keycode(char),
    callback = callback,
  })
end

return torch
