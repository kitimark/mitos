full_thread_unanswered_of() {
  local n=$1 out
  [ -n "$tool_bin" ] || { printf '"?"'; return; }
  out=$("$tool_bin" watch unanswered --owner "$owner" \
      --issue-comments "$dir/thread-ic-$n.json" --review-comments "$dir/thread-rc-$n.json" \
      --reviews "$dir/thread-rv-$n.json" </dev/null 2>/dev/null) || { printf '"?"'; return; }
  jq -c --arg n "$n" '.[$n] // []' <<<"$out" 2>/dev/null || printf '"?"'
}

owner_unanswered_by_thread_of() {
  [ -n "$tool_bin" ] || { printf 'null'; return; }
  "$tool_bin" watch unanswered --owner "$owner" \
    --issue-comments "$dir/icomments.json" --review-comments "$dir/rcomments.json" \
    </dev/null 2>/dev/null || printf 'null'
}
