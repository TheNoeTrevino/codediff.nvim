-- Keymaps for the review panel (single hierarchical tree).
local config = require("codediff.config")
local review_state = require("codediff.core.review_state")
local tree_utils = require("codediff.ui.lib.tree_utils")

local M = {}

-- <Space> dispatches by row type: file → toggle viewed, commit → toggle reviewed.
local function on_toggle_check(tree, state, refresh)
  local node = tree:get_node()
  local data = node and node.data
  if not data then
    return
  end
  if data.type == "file" then
    review_state.toggle_commit_file_viewed(state, data.commit_hash, data.path)
    data.viewed = review_state.is_commit_file_viewed(state, data.commit_hash, data.path)
  elseif data.type == "commit" then
    review_state.toggle_commit_reviewed(state, data.hash)
    data.reviewed = review_state.is_commit_reviewed(state, data.hash)
  else
    return
  end
  refresh()
end

-- <CR> dispatches by row type:
--   file   → open diff at commit's parent vs commit
--   commit → toggle expand/collapse
local function on_select(tree, opts, refresh)
  local node = tree:get_node()
  if not node then
    return
  end
  local data = node.data or {}
  if data.type == "commit" then
    if node:is_expanded() then
      node:collapse()
    else
      node:expand()
    end
    refresh()
  elseif data.type == "file" then
    if opts.on_open_diff then
      opts.on_open_diff(node)
    end
  end
end

-- Attach review keymaps to the single review buffer.
--
-- opts:
--   tree         NuiTree
--   bufnr        number
--   winid        number
--   state        table    -- review_state session table
--   refresh      function -- re-renders the tree
--   on_open_diff function -- (node) -> open diff for file node
--   on_close     function -- close the review session
function M.attach(opts)
  local tree    = opts.tree
  local bufnr   = opts.bufnr
  local state   = opts.state
  local refresh = opts.refresh

  local map_options = { noremap = true, silent = true, nowait = true }
  local review_keymaps = config.options.keymaps.review or {}

  if review_keymaps.toggle_viewed then
    vim.keymap.set("n", review_keymaps.toggle_viewed, function()
      on_toggle_check(tree, state, refresh)
    end, vim.tbl_extend("force", map_options, { buffer = bufnr, desc = "Toggle viewed/reviewed" }))
  end

  if review_keymaps.select then
    vim.keymap.set("n", review_keymaps.select, function()
      on_select(tree, opts, refresh)
    end, vim.tbl_extend("force", map_options, { buffer = bufnr, desc = "Select (file: open diff, commit: toggle expand)" }))
  end

  if review_keymaps.close then
    vim.keymap.set("n", review_keymaps.close, function()
      if opts.on_close then
        opts.on_close()
      end
    end, vim.tbl_extend("force", map_options, { buffer = bufnr, desc = "Close review" }))
  end

  -- Fold keymaps (Vim-style: zo/zO/zc/zC/za/zA/zR/zM — commit nodes only).
  tree_utils.setup_fold_keymaps({
    tree = tree,
    keymaps = review_keymaps,
    bufnr = bufnr,
  })
end

return M
