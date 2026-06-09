#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/lizi-learn/lizi-learn.github.io.git"
BRANCH="_posts"
WORKDIR="${BLOG_POSTS_DIR:-$HOME/github/blog-posts}"
EDITOR_CMD="${EDITOR:-nano}"

usage() {
  cat <<'EOF'
Usage:
  ./posts.sh init
  ./posts.sh list
  ./posts.sh new "文章标题"
  ./posts.sh edit <file.md>
  ./posts.sh publish "提交说明"
  ./posts.sh status
  ./posts.sh pull

Environment:
  BLOG_POSTS_DIR  Local posts working directory. Default: ~/github/blog-posts
  EDITOR          Editor command. Default: nano

Examples:
  ./posts.sh init
  ./posts.sh new "我的第一篇文章"
  ./posts.sh publish "Add first post"
EOF
}

ensure_git() {
  command -v git >/dev/null || { echo "git is required." >&2; exit 1; }
}

ensure_workdir() {
  ensure_git
  if [[ ! -d "$WORKDIR/.git" ]]; then
    echo "Posts workspace not found: $WORKDIR" >&2
    echo "Run: ./posts.sh init" >&2
    exit 1
  fi
}

slugify() {
  local title="$1"
  printf '%s' "$title" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

init_posts() {
  ensure_git
  if [[ -d "$WORKDIR/.git" ]]; then
    git -C "$WORKDIR" fetch origin "$BRANCH"
    git -C "$WORKDIR" checkout "$BRANCH"
    git -C "$WORKDIR" pull --ff-only origin "$BRANCH"
  else
    mkdir -p "$(dirname "$WORKDIR")"
    git clone --branch "$BRANCH" --single-branch "$REPO_URL" "$WORKDIR"
  fi
  echo "Posts workspace ready: $WORKDIR"
}

list_posts() {
  ensure_workdir
  find "$WORKDIR" -maxdepth 1 -type f -name '*.md' -printf '%f\n' | sort
}

new_post() {
  ensure_workdir
  local title="${1:-}"
  if [[ -z "$title" ]]; then
    echo "Title is required." >&2
    exit 1
  fi

  local slug
  slug="$(slugify "$title")"
  if [[ -z "$slug" ]]; then
    slug="post-$(date +%Y%m%d-%H%M%S)"
  fi

  local file="$WORKDIR/${slug}.md"
  if [[ -e "$file" ]]; then
    echo "File already exists: $file" >&2
    exit 1
  fi

  cat > "$file" <<EOF
---
title: $title
date: $(date '+%Y-%m-%d %H:%M:%S')
tags:
---

在这里开始写正文。
EOF

  echo "Created: $file"
  "$EDITOR_CMD" "$file"
}

edit_post() {
  ensure_workdir
  local file="${1:-}"
  if [[ -z "$file" ]]; then
    echo "Markdown file is required." >&2
    exit 1
  fi
  [[ "$file" = /* ]] || file="$WORKDIR/$file"
  if [[ ! -f "$file" ]]; then
    echo "File not found: $file" >&2
    exit 1
  fi
  "$EDITOR_CMD" "$file"
}

publish_posts() {
  ensure_workdir
  local message="${1:-Update blog posts}"
  git -C "$WORKDIR" status --short
  git -C "$WORKDIR" add '*.md'
  if git -C "$WORKDIR" diff --cached --quiet; then
    echo "No post changes to publish."
    exit 0
  fi
  git -C "$WORKDIR" commit -m "$message"
  git -C "$WORKDIR" push origin "$BRANCH"
  echo "Published. GitHub Actions will deploy the blog automatically."
}

case "${1:-}" in
  init)
    init_posts
    ;;
  list)
    list_posts
    ;;
  new)
    shift
    new_post "${1:-}"
    ;;
  edit)
    shift
    edit_post "${1:-}"
    ;;
  publish)
    shift
    publish_posts "${1:-Update blog posts}"
    ;;
  status)
    ensure_workdir
    git -C "$WORKDIR" status --short
    ;;
  pull)
    ensure_workdir
    git -C "$WORKDIR" pull --ff-only origin "$BRANCH"
    ;;
  -h|--help|help|"")
    usage
    ;;
  *)
    echo "Unknown command: $1" >&2
    usage >&2
    exit 1
    ;;
esac
