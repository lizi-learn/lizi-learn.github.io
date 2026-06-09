#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/lizi-learn/lizi-learn.github.io.git"
BRANCH="_posts"
WORKDIR="${BLOG_POSTS_DIR:-$HOME/github/blog-posts}"
ROOT_DIR="${BLOG_ROOT_DIR:-$HOME/github}"
EDITOR_CMD="${EDITOR:-nano}"

usage() {
  cat <<'EOF'
Usage:
  blog
  blog menu
  blog init
  blog list
  blog new "文章标题"
  blog import <file.md> [title]
  blog edit <file.md>
  blog publish [提交说明]
  blog status
  blog pull
  blog open

Environment:
  BLOG_POSTS_DIR  Local posts working directory. Default: ~/github/blog-posts
  BLOG_ROOT_DIR   Directory opened by plain blog. Default: ~/github
  EDITOR          Editor command. Default: nano

Examples:
  blog
  blog menu
  blog import ~/Downloads/article.md
  blog new "我的第一篇文章"
  blog publish
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
  local slug
  slug="$(printf '%s' "$title" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
  if [[ -z "$slug" ]]; then
    slug="post-$(date +%Y%m%d-%H%M%S)"
  fi
  printf '%s' "$slug"
}

ensure_front_matter() {
  local source_file="$1"
  local title="$2"
  if head -n 1 "$source_file" | grep -qx -- '---'; then
    cat "$source_file"
  else
    cat <<EOF
---
title: $title
date: $(date '+%Y-%m-%d %H:%M:%S')
tags:
---

EOF
    cat "$source_file"
  fi
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

import_post() {
  ensure_workdir
  local source_file="${1:-}"
  local title="${2:-}"
  if [[ -z "$source_file" ]]; then
    echo "Markdown file is required." >&2
    exit 1
  fi
  if [[ ! -f "$source_file" ]]; then
    echo "File not found: $source_file" >&2
    exit 1
  fi
  if [[ "${source_file##*.}" != "md" ]]; then
    echo "Only .md files are supported: $source_file" >&2
    exit 1
  fi

  local basename slug target
  basename="$(basename "$source_file" .md)"
  title="${title:-$basename}"
  slug="$(slugify "$basename")"
  target="$WORKDIR/${slug}.md"
  if [[ -e "$target" ]]; then
    target="$WORKDIR/${slug}-$(date +%Y%m%d-%H%M%S).md"
  fi

  ensure_front_matter "$source_file" "$title" > "$target"
  echo "Imported: $target"
}

open_posts() {
  ensure_workdir
  if command -v xdg-open >/dev/null; then
    xdg-open "$WORKDIR" >/dev/null 2>&1 &
  else
    echo "$WORKDIR"
  fi
}

open_root() {
  mkdir -p "$ROOT_DIR"
  if command -v code >/dev/null; then
    code "$ROOT_DIR" >/dev/null 2>&1 &
  elif command -v xdg-open >/dev/null; then
    xdg-open "$ROOT_DIR" >/dev/null 2>&1 &
  else
    echo "$ROOT_DIR"
  fi
}

menu() {
  init_posts >/dev/null
  while true; do
    cat <<EOF

Blog Manager
1) 新建文章
2) 导入 Markdown 文件
3) 编辑文章
4) 发布
5) 查看文章列表
6) 打开文章目录
7) 同步远端
0) 退出
EOF
    read -r -p "请选择: " choice
    case "$choice" in
      1)
        read -r -p "文章标题: " title
        new_post "$title"
        ;;
      2)
        read -r -e -p "Markdown 文件路径: " source_file
        import_post "$source_file"
        ;;
      3)
        list_posts
        read -r -p "文件名: " file
        edit_post "$file"
        ;;
      4)
        read -r -p "提交说明[Update blog posts]: " message
        publish_posts "${message:-Update blog posts}"
        ;;
      5)
        list_posts
        ;;
      6)
        open_posts
        ;;
      7)
        git -C "$WORKDIR" pull --ff-only origin "$BRANCH"
        ;;
      0)
        exit 0
        ;;
      *)
        echo "无效选择。"
        ;;
    esac
  done
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
  import)
    shift
    import_post "${1:-}" "${2:-}"
    ;;
  open)
    open_posts
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
  menu)
    menu
    ;;
  -h|--help|help)
    usage
    ;;
  "")
    open_root
    ;;
  *)
    echo "Unknown command: $1" >&2
    usage >&2
    exit 1
    ;;
esac
