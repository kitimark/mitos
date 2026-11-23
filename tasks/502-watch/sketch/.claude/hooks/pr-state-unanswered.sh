# UNCHECKED SKETCH (#502, PR 3). A fragment, not a file: what replaces pr-state.sh's two jq
# classifiers (`full_thread_unanswered` per PR and `owner_unanswered_by_thread`), as PR 3a left
# them. PR 3 starts only after PR 11, so main's tool runs where the root runs and this path does
# not turn every line to `?` there; question 3a and default 3b decide how pr-state finds that tool. The
# hook already finds main's tool for provenance (`MAIN_TOOL_READY_WAIT=0 main_tool ready ...`,
# `tool_bin`). The fetches stay as they are; only the deciding moves to `mitos-gate watch
# unanswered`, which classifies a post as land does except that typed words stay words (#501), and
# takes its answer apps from `Speech.apps`, so it has no app flag. Any failure is `?` (or null,
# which the summary already shows as `?`): the hook never shows "answered" when it could not
# decide. The only class PR 3 changes against PR 3a's jq is the footer text (`Voice.lean`, class 4).

# Per PR, over the full thread. Prints a JSON list of ids, or "?" as JSON.
full_thread_unanswered_of() {
  local n=$1 out
  [ -n "$tool_bin" ] || { printf '"?"'; return; }
  out=$("$tool_bin" watch unanswered --owner "$owner" \
      --issue-comments "$dir/thread-ic-$n.json" --review-comments "$dir/thread-rc-$n.json" \
      --reviews "$dir/thread-rv-$n.json" </dev/null 2>/dev/null) || { printf '"?"'; return; }
  jq -c --arg n "$n" '.[$n] // []' <<<"$out" 2>/dev/null || printf '"?"'
}

# Repository-wide, from the recent comment pages. Prints {"<thread>":[ids]}, or null.
owner_unanswered_by_thread_of() {
  [ -n "$tool_bin" ] || { printf 'null'; return; }
  "$tool_bin" watch unanswered --owner "$owner" \
    --issue-comments "$dir/icomments.json" --review-comments "$dir/rcomments.json" \
    </dev/null 2>/dev/null || printf 'null'
}

# Two ordering changes in pr-state.sh come with it: the main-tool lookup moves above the per-PR
# loop, and the fetched files keep their raw pages (`--slurp` arrays), which the tool reads.
