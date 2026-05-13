-- UI rendering for review panel (create split, tree, keymaps)
local M = {}

local Tree = require("codediff.ui.lib.tree")
local Split = require("codediff.ui.lib.split")
local config = require("codediff.config")
local nodes_module = require("codediff.ui.review.nodes")
local keymaps_module = require("codediff.ui.review.keymaps")

-- Build the on_file_select callback.
-- Diff is taken against the file's commit's parent (commit~1 vs commit)
-- so the user sees exactly what that commit changed.
local function make_file_select_handler(git_root)
  return function(file_data)
    local file_path = file_data.path
    local commit_hash = file_data.commit_hash
    if not file_path or file_path == "" or not commit_hash then
      return
    end

    vim.schedule(function()
      local view = require("codediff.ui.view")
      local tabpage = vim.api.nvim_get_current_tabpage()

      ---@type SessionConfig
      local session_config = {
        mode = "review",
        git_root = git_root,
        original_path = file_path,
        modified_path = file_path,
        original_revision = commit_hash .. "^",
        modified_revision = commit_hash,
      }

      view.update(tabpage, session_config, false)
    end)
  end
end

-- Create review panel: single horizontal split with one hierarchical tree
-- where commits are top-level nodes and files are children.
-- opts: { git_root, commits, files_by_commit, state }
function M.create(opts)
  opts = opts or {}
  local commits = opts.commits or {}
  local files_by_commit = opts.files_by_commit or {}
  local state = opts.state or {}

  local review_config = config.options.review or {}
  local position = review_config.position or "bottom"
  local size = position == "bottom" and (review_config.height or 15) or (review_config.width or 40)

  local split = Split({
    relative = "editor",
    position = position,
    size = size,
    buf_options = {
      modifiable = false,
      readonly = true,
      filetype = "codediff-review",
    },
    win_options = {
      number = false,
      relativenumber = false,
      cursorline = true,
      wrap = false,
      signcolumn = "no",
      foldcolumn = "0",
    },
  })
  split:mount()
  pcall(vim.api.nvim_buf_set_name, split.bufnr, "CodeDiff Review")

  local tree_nodes = nodes_module.build_commit_nodes(commits, files_by_commit, state)

  local tree = Tree({
    bufnr = split.bufnr,
    nodes = tree_nodes,
    prepare_node = function(node)
      return nodes_module.prepare_node(node)
    end,
  })

  for _, node in ipairs(tree_nodes) do
    if node.data and node.data.type == "commit" then
      node:expand()
    end
  end

  tree:render()

  local review = {
    split = split,
    bufnr = split.bufnr,
    winid = split.winid,
    tree = tree,
    state = state,
  }

  review.on_file_select = make_file_select_handler(opts.git_root)

  local function refresh_fn()
    tree:render()
  end

  local function close_fn()
    pcall(function() split:unmount() end)
  end

  keymaps_module.attach({
    tree    = tree,
    bufnr   = split.bufnr,
    winid   = split.winid,
    state   = state,
    refresh = refresh_fn,
    on_open_diff = function(node)
      if node and node.data and node.data.type == "file" then
        review.on_file_select(node.data)
      end
    end,
    on_close = close_fn,
  })

  return review
end

return M
