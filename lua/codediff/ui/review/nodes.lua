-- Node creation and formatting for the review panel.
-- One hierarchical NuiTree: commits at the top level, files as children.
local M = {}

local Tree = require("codediff.ui.lib.tree")
local Line = require("codediff.ui.lib.line")
local review_state = require("codediff.core.review_state")

-- Status symbol table shared with explorer / history.
local STATUS_SYMBOLS = {
  M = { symbol = "M", color = "CodeDiffStatusModified" },
  A = { symbol = "A", color = "CodeDiffStatusAdded" },
  D = { symbol = "D", color = "CodeDiffStatusDeleted" },
  R = { symbol = "R", color = "CodeDiffStatusRenamed" },
}

-- Build commit nodes with their file children attached.
-- commits: array of commit objects from git.get_commit_list
-- files_by_commit: map of commit_hash -> array of file records
-- state: review_state session table
function M.build_commit_nodes(commits, files_by_commit, state)
  files_by_commit = files_by_commit or {}
  state = state or {}
  local commits_state = state.commits or {}
  local nodes = {}

  for _, commit in ipairs(commits) do
    local hash = commit.hash
    local reviewed = commits_state[hash] and commits_state[hash].reviewed or false

    local file_children = {}
    local total_ins, total_del = 0, 0
    for _, file in ipairs(files_by_commit[hash] or {}) do
      local status_info = STATUS_SYMBOLS[file.status] or { symbol = file.status or "?", color = "Normal" }
      total_ins = total_ins + (file.insertions or 0)
      total_del = total_del + (file.deletions or 0)

      file_children[#file_children + 1] = Tree.Node({
        id = "review-file:" .. hash .. ":" .. (file.path or ""),
        text = file.path or "",
        data = {
          type = "file",
          commit_hash = hash,
          path = file.path or "",
          status = file.status or "M",
          status_symbol = status_info.symbol,
          status_color = status_info.color,
          insertions = file.insertions or 0,
          deletions = file.deletions or 0,
          viewed = review_state.is_commit_file_viewed(state, hash, file.path),
        },
      })
    end

    nodes[#nodes + 1] = Tree.Node({
      id = "review-commit:" .. hash,
      text = commit.subject or "",
      data = {
        type = "commit",
        hash = hash,
        short_hash = (hash or ""):sub(1, 8),
        subject = commit.subject or "",
        insertions = commit.insertions or total_ins,
        deletions = commit.deletions or total_del,
        reviewed = reviewed,
      },
    }, file_children)
  end

  return nodes
end

-- Return the NuiLine for a single node.
function M.prepare_node(node)
  local line = Line()
  local data = node.data or {}

  if data.type == "commit" then
    local checkbox = data.reviewed and "✓ " or "☐ "
    local checkbox_hl = data.reviewed and "CodeDiffReviewReviewed" or "NonText"
    line:append(checkbox, checkbox_hl)

    line:append(data.short_hash .. " ", "Identifier")

    local subject = data.subject or ""
    if #subject > 60 then
      subject = subject:sub(1, 59) .. "…"
    end
    if subject == "" then
      subject = "[empty message]"
    end
    local subject_hl = data.reviewed and "CodeDiffReviewReviewed" or "Normal"
    line:append(subject, subject_hl)

    line:append("  ", "Normal")
    line:append("+" .. tostring(data.insertions), "CodeDiffStatInsertions")
    line:append(" ", "Normal")
    line:append("-" .. tostring(data.deletions), "CodeDiffStatDeletions")

  elseif data.type == "file" then
    line:append("  ", "NonText")

    local checkbox = data.viewed and "✓ " or "☐ "
    local checkbox_hl = data.viewed and "CodeDiffReviewViewed" or "NonText"
    line:append(checkbox, checkbox_hl)

    line:append(data.status_symbol .. " ", data.status_color)

    local full_path = data.path or ""
    local filename = full_path:match("([^/]+)$") or full_path
    local directory = full_path:sub(1, -(#filename + 2))

    local path_hl = data.viewed and "CodeDiffReviewViewed" or "Normal"
    if #directory > 0 then
      line:append(directory .. "/", "Comment")
    end
    line:append(filename, path_hl)

    line:append("  ", "Normal")
    line:append("+" .. tostring(data.insertions), "CodeDiffStatInsertions")
    line:append(" ", "Normal")
    line:append("-" .. tostring(data.deletions), "CodeDiffStatDeletions")
  else
    line:append(node.text or "", "Normal")
  end

  return line
end

return M
