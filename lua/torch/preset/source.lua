local misc = require('torch.misc')

local preset_source = {}

---Create insert mode sources for preset.
---@class torch.preset.source.InsertModePresetOption
---@field public disable_providers? { lsp_completion?: true, calc?: true, path?: true, buffer?: true }
---@param opts? torch.preset.source.InsertModePresetOption
---@return fun(service: cmp-kit.core.CompletionService): fun()[]
function preset_source.i(opts)
  ---@type fun(service: cmp-kit.core.CompletionService): fun()[]
  return function(service)
    opts = opts or {}
    opts.disable_providers = opts.disable_providers or {}

    local bufnr = vim.api.nvim_get_current_buf()
    local disposes = {}

    -- calc.
    if not opts.disable_providers.calc then
      service:register_source(require('cmp-kit.ext.source.calc')(), {
        group = 1,
      })
    end

    -- path.
    if not opts.disable_providers.path then
      service:register_source(require('cmp-kit.ext.source.path')(), {
        group = 1,
      })
    end

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
              group = 10,
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

    -- buffer.
    if not opts.disable_providers.buffer then
      service:register_source(require('cmp-kit.ext.source.buffer')({
        min_keyword_length = 3,
        label_details = {
          description = 'buffer'
        }
      }), {
        group = 100,
        dedup = true,
      })
    end

    return disposes
  end
end

---Create cmdline mode sources for preset.
---@class torch.preset.source.CmdlineModePresetOption
---@field public disable_providers? { cmdline?: true, calc?: true, path?: true, buffer?: true }
---@param opts? torch.preset.source.CmdlineModePresetOption
---@return fun(service: cmp-kit.core.CompletionService): fun()[]
function preset_source.c(opts)
  ---@type fun(service: cmp-kit.core.CompletionService): fun()[]
  return function(service)
    opts = opts or {}
    opts.disable_providers = opts.disable_providers or {}

    -- calc.
    if not opts.disable_providers.calc then
      service:register_source(require('cmp-kit.ext.source.calc')(), {
        group = 1,
      })
    end

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
        min_keyword_length = 3,
      }), {
        group = 100,
        dedup = true,
      })
    end

    return {}
  end
end

return preset_source
