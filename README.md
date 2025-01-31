# nvim-torch

A Neovim completion plugin built on top of
[nvim-cmp-kit](https://github.com/hrsh7th/nvim-cmp-kit).

This plugin is currently in **beta** and includes built-in sources for lsp,
path, buffer, and cmdline.

The [nvim-torch](https://github.com/hrsh7th/nvim-torch) is expected to operate
stably, but its customizability currently falls short compared to nvim-cmp.

If you early-adapter, please try it out and provide feedback.

## Why a new completion engine?

I developed a completion engine called
[nvim-cmp](https://github.com/hrsh7th/nvim-cmp), which I believe was a success.
However, it had several issues:

- It was difficult to meet the diverse "visual" requirements of users.
- The source API lacked reusability.
- An increasing number of outdated implementations made maintenance more
  challenging.

Additionally, as Neovim has introduced numerous powerful APIs in recent years.

I believe rewriting the engine will enable more stable behavior.

## How to migrate?

Community sources for [nvim-cmp](https://github.com/hrsh7th/nvim-cmp) are not
supported in nvim-torch.

Therefore, only users relying solely on the lsp, path, buffer, and cmdline
sources can migrate.

To migrate, simply remove your nvim-cmp configuration and install nvim-torch.

## How to install?

For [lazy.vim](https://github.com/folke/lazy.nvim).

```lua
 {
  'hrsh7th/nvim-torch',
  dependencies = {
    'hrsh7th/nvim-cmp-kit' 
  },
  version = '*',
  config = function()
    local torch = require('torch')

    -- for insert-mode completion.
    vim.api.nvim_create_autocmd('FileType', {
      callback = function()
        torch.attach.i(function()
          return torch.preset.i({
            expand_snippet = function(snippet)
              return vim.fn['vsnip#anonymous'](snippet)
            end
          })
        end)
      end
    })

    -- for cmdline-mode completion.
    torch.attach.c(':', function()
      return torch.preset.c()
    end)

    -- character mapping for completion context.
    do
      torch.charmap({ 'i', 'c' }, '<C-Space>', function(ctx)
        ctx.complete({ force = true })
      end)
      torch.charmap('i', '<CR>', function(ctx)
        local selection = ctx.get_selection()
        ctx.commit(selection.index == 0 and 1 or selection.index, { replace = false })
      end)
      torch.charmap({ 'i', 'c' }, '<C-y>', function(ctx)
        local selection = ctx.get_selection()
        ctx.commit(selection.index == 0 and 1 or selection.index, { replace = true })
      end)
      torch.charmap({ 'i', 'c' }, '<C-n>', function(ctx)
        local selection = ctx.get_selection()
        ctx.select(selection.index + 1)
      end)
      torch.charmap({ 'i', 'c' }, '<C-p>', function(ctx)
        local selection = ctx.get_selection()
        ctx.select(selection.index - 1)
      end)
      torch.charmap({ 'i', 'c' }, '<C-p>', function(ctx)
        local selection = ctx.get_selection()
        ctx.select(selection.index - 1)
      end)
    end
  end
}
```

## Why are there separate plugins for nvim-torch and nvim-cmp-kit?

nvim-cmp combines multiple implementations into a single plugin, including the
UI, configuration, key mappings, and completion engine.

Because of this structure, rewriting the plugin required rebuilding the entire
completion engine.

To avoid such situations in the future, we’ve decided to separate the core
completion engine from the user-facing API. This separation ensures that even if
the user-facing API becomes complex, the completion engine remains reusable.

Additionally, since the completion engine is now standalone, it can be used
independently, much like how nui.nvim is designed. Who knows—this separation
might inspire some exciting innovations within the community!
