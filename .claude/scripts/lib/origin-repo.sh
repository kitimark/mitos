# shellcheck shell=bash
# Sourced by watch-github.sh and bot-review.sh. The caller defines die().

# Sets $repo to owner/name from the origin URL (https, ssh or proxy form), or calls die. The URL
# is never printed, because it can carry a credential.
origin_repo() {
  local url
  url=$(git -C "${CLAUDE_PROJECT_DIR:-.}" remote get-url origin 2>/dev/null) || die "no origin remote"
  repo=$(sed -E 's#/+$##; s#\.git$##; s#^.*[/:]([^/:]+/[^/:]+)$#\1#' <<<"$url")
  [[ $repo =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "origin is not owner/name"
}
