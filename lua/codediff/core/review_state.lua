-- Persistence layer for CodeDiff Review Mode.
-- Tracks per-(commit, file) viewed state and per-commit reviewed state for a
-- (git_root, base_ref, target_ref) triple.
--
-- On-disk schema (version 2):
-- {
--   version   = 2,
--   git_root  = "/abs/path/to/repo",
--   base_ref  = "main",
--   target_ref = "feature",
--   commit_files = {
--     ["deadbeef..."] = {
--       ["path/to/foo.lua"] = { viewed = true },
--       ...
--     },
--     ...
--   },
--   commits = {
--     ["deadbeef..."] = { reviewed = true },
--     ...
--   }
-- }
--
-- Storage path:
--   vim.fn.stdpath("data") .. "/codediff/reviews/<slug>.json"
-- where <slug> is a human-readable, filename-safe concat of
-- git_root + "__" + base_ref + "__" + target_ref.

local M = {}

local SCHEMA_VERSION = 2

-- Replace any character that is not alphanumeric, dash, or dot with "_".
-- Slashes (path separators in git_root and refs like "origin/main") become "_".
local function sanitize(s)
  return s:gsub("[^%w%.%-]", "_")
end

-- Derive the storage path for a given triple.
-- Returns: full absolute path to the JSON file.
local function storage_path(git_root, base_ref, target_ref)
  local slug = sanitize(git_root) .. "__" .. sanitize(base_ref) .. "__" .. sanitize(target_ref)
  -- Trim leading underscores that arise from a leading "/" in git_root.
  slug = slug:gsub("^_+", "")
  return vim.fn.stdpath("data") .. "/codediff/reviews/" .. slug .. ".json"
end

-- Build a fresh empty state table for the given triple.
local function empty_state(git_root, base_ref, target_ref)
  return {
    version = SCHEMA_VERSION,
    git_root = git_root,
    base_ref = base_ref,
    target_ref = target_ref,
    commit_files = {},
    commits = {},
    -- Derived field (not persisted): storage path cached for save().
    _path = storage_path(git_root, base_ref, target_ref),
  }
end

-- Persist state to disk.
-- Creates the parent directory if necessary.
function M.save(state)
  local path = state._path
  if not path then
    -- Defensive: re-derive if somehow missing.
    path = storage_path(state.git_root, state.base_ref, state.target_ref)
    state._path = path
  end

  local dir = vim.fn.fnamemodify(path, ":h")
  vim.fn.mkdir(dir, "p")

  -- Encode. Exclude internal fields that start with "_".
  local to_persist = {
    version = state.version,
    git_root = state.git_root,
    base_ref = state.base_ref,
    target_ref = state.target_ref,
    commit_files = state.commit_files,
    commits = state.commits,
  }

  local ok, encoded = pcall(vim.fn.json_encode, to_persist)
  if not ok then
    -- Should never happen, but don't crash the plugin.
    return
  end

  vim.fn.writefile({ encoded }, path)
end

-- Load state for (git_root, base_ref, target_ref) from disk.
-- Returns a raw state table without invalidation applied.
-- Callers should prefer M.load() which also runs invalidation.
local function load_raw(git_root, base_ref, target_ref)
  local path = storage_path(git_root, base_ref, target_ref)

  if vim.fn.filereadable(path) == 0 then
    return empty_state(git_root, base_ref, target_ref)
  end

  local lines = vim.fn.readfile(path)
  if not lines or #lines == 0 then
    return empty_state(git_root, base_ref, target_ref)
  end

  local json_str = table.concat(lines, "\n")
  local ok, decoded = pcall(vim.fn.json_decode, json_str)
  if not ok or type(decoded) ~= "table" then
    -- Corrupt file → start fresh.
    return empty_state(git_root, base_ref, target_ref)
  end

  -- Ensure required fields are present. Drop any pre-v2 `files` field — the
  -- old global-by-path viewed state does not translate to the new per-commit
  -- model, so we start the commit_files map fresh on migration.
  decoded.version = SCHEMA_VERSION
  decoded.git_root = decoded.git_root or git_root
  decoded.base_ref = decoded.base_ref or base_ref
  decoded.target_ref = decoded.target_ref or target_ref
  decoded.commit_files = decoded.commit_files or {}
  decoded.commits = decoded.commits or {}
  decoded.files = nil

  -- Attach the storage path as an internal field so save() works without args.
  decoded._path = path

  return decoded
end

-- Load review state for (git_root, base_ref, target_ref).
-- Async signature is preserved so callers can pass a callback, but no I/O is
-- performed beyond the synchronous file read.
function M.load(git_root, base_ref, target_ref, callback)
  callback(load_raw(git_root, base_ref, target_ref))
end

-- Toggle the viewed state for a file under a specific commit.
function M.toggle_commit_file_viewed(state, commit_hash, path)
  local bucket = state.commit_files[commit_hash] or {}
  state.commit_files[commit_hash] = bucket

  local entry = bucket[path] or {}
  bucket[path] = entry
  entry.viewed = not entry.viewed

  M.save(state)
end

-- Toggle the reviewed state for a commit.
-- Plain boolean flip; no hash tracking needed for commits.
function M.toggle_commit_reviewed(state, commit_hash)
  local entry = state.commits[commit_hash] or {}
  state.commits[commit_hash] = entry

  entry.reviewed = not entry.reviewed

  M.save(state)
end

-- Returns true if `path` under `commit_hash` is currently marked as viewed.
function M.is_commit_file_viewed(state, commit_hash, path)
  local bucket = state.commit_files[commit_hash]
  if not bucket then
    return false
  end
  local entry = bucket[path]
  return entry ~= nil and entry.viewed == true
end

-- Returns true if the commit identified by `commit_hash` is marked reviewed.
function M.is_commit_reviewed(state, commit_hash)
  local entry = state.commits[commit_hash]
  return entry ~= nil and entry.reviewed == true
end

return M
