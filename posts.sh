#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/lizi-learn/lizi-learn.github.io.git"
REPO_OWNER="lizi-learn"
REPO_NAME="lizi-learn.github.io"
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
  blog push [提交说明]
  blog pull
  blog delete <编号|文件名>
  blog new "文章标题"
  blog import <file.md> [title]
  blog edit <编号|文件名>
  blog status
  blog open
  blog watch start|stop|status

Environment:
  BLOG_POSTS_DIR  Local posts working directory. Default: ~/github/blog-posts
  BLOG_ROOT_DIR   Directory opened by plain blog. Default: ~/github
  EDITOR          Editor command. Default: nano

Examples:
  blog
  blog menu
  blog import ~/Downloads/article.md
  blog list
  blog delete 1
  blog push

Optional:
  GITHUB_TOKEN     Triggers GitHub Actions deployment after blog push.
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

post_file_by_ref() {
  ensure_workdir
  local ref="$1"
  if [[ -z "$ref" ]]; then
    echo "Post number or file name is required." >&2
    exit 1
  fi

  if [[ "$ref" =~ ^[0-9]+$ ]]; then
    local file
    file="$(find "$WORKDIR" -maxdepth 1 -type f -name '*.md' -printf '%f\n' | sort | sed -n "${ref}p")"
    if [[ -z "$file" ]]; then
      echo "No post with number: $ref" >&2
      exit 1
    fi
    printf '%s/%s' "$WORKDIR" "$file"
  else
    [[ "$ref" = /* ]] || ref="$WORKDIR/$ref"
    if [[ ! -f "$ref" ]]; then
      echo "File not found: $ref" >&2
      exit 1
    fi
    printf '%s' "$ref"
  fi
}

list_posts() {
  ensure_workdir
  local count=0
  while IFS= read -r file; do
    count=$((count + 1))
    printf '%2d. %s\n' "$count" "$file"
  done < <(find "$WORKDIR" -maxdepth 1 -type f -name '*.md' -printf '%f\n' | sort)
  if [[ "$count" -eq 0 ]]; then
    echo "No posts."
  fi
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
  local target
  target="$(post_file_by_ref "${1:-}")"
  "$EDITOR_CMD" "$target"
}

trigger_deploy() {
  if [[ -z "${GITHUB_TOKEN:-}" ]]; then
    echo "Deploy trigger skipped: GITHUB_TOKEN is not set."
    echo "GitHub Pages updates after the next main-branch workflow run."
    return 0
  fi
  if ! command -v curl >/dev/null; then
    echo "Deploy trigger skipped: curl is not installed."
    return 0
  fi

  local code
  code="$(curl -sS -o /tmp/blog-workflow-dispatch.json -w '%{http_code}' \
    -X POST \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/actions/workflows/pages.yml/dispatches" \
    -d '{"ref":"main"}')"
  if [[ "$code" == "204" ]]; then
    echo "Deployment workflow triggered."
  else
    echo "Deploy trigger failed: HTTP $code"
    cat /tmp/blog-workflow-dispatch.json 2>/dev/null || true
  fi
}

push_posts() {
  ensure_workdir
  local message="${1:-Update blog posts}"
  git -C "$WORKDIR" status --short
  git -C "$WORKDIR" add -A -- '*.md'
  if git -C "$WORKDIR" diff --cached --quiet; then
    echo "No post changes to push."
    return 0
  fi
  git -C "$WORKDIR" commit -m "$message"
  git -C "$WORKDIR" push origin "$BRANCH"
  echo "Pushed."
  trigger_deploy
}

pull_posts() {
  ensure_workdir
  git -C "$WORKDIR" pull --ff-only origin "$BRANCH"
}

delete_post() {
  ensure_workdir
  local target
  target="$(post_file_by_ref "${1:-}")"
  rm -f "$target"
  echo "Deleted locally: $(basename "$target")"
  echo "Run 'blog push' to update GitHub."
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
  echo "Imported locally: $target"
  echo "Run 'blog push' to update GitHub."
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

watch_posts() {
  local command="${1:-status}"
  local pid_file="$WORKDIR/.blog-watch.pid"

  case "$command" in
    start)
      init_posts >/dev/null
      if [[ -f "$pid_file" ]] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
        echo "Blog watcher already running: $(cat "$pid_file")"
        return 0
      fi
      (
        cd "$WORKDIR"
        last_state=""
        while true; do
          current_state="$(find . -maxdepth 1 -type f -name '*.md' -printf '%f %T@ %s\n' | sort)"
          if [[ -n "$last_state" && "$current_state" != "$last_state" ]]; then
            sleep 2
            /home/pc/github/lizi-learn.github.io/posts.sh push "Auto update blog posts" >/tmp/blog-watch.log 2>&1 || true
          fi
          last_state="$current_state"
          sleep 5
        done
      ) >/tmp/blog-watch.log 2>&1 &
      echo $! > "$pid_file"
      echo "Blog watcher started: $(cat "$pid_file")"
      echo "Drop or edit .md files in: $WORKDIR"
      ;;
    stop)
      if [[ -f "$pid_file" ]] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
        kill "$(cat "$pid_file")"
        rm -f "$pid_file"
        echo "Blog watcher stopped."
      else
        rm -f "$pid_file"
        echo "Blog watcher is not running."
      fi
      ;;
    status)
      if [[ -f "$pid_file" ]] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
        echo "Blog watcher running: $(cat "$pid_file")"
      else
        echo "Blog watcher is not running."
      fi
      ;;
    *)
      echo "Usage: blog watch start|stop|status" >&2
      exit 1
      ;;
  esac
}

menu() {
  init_posts >/dev/null
  while true; do
    cat <<EOF

Blog Manager
1) 新建文章
2) 导入 Markdown 文件
3) 编辑文章
4) 推送本地到 GitHub
5) 查看文章列表
6) 删除文章
7) 打开文章目录
8) 同步远端
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
        push_posts "${message:-Update blog posts}"
        ;;
      5)
        list_posts
        ;;
      6)
        list_posts
        read -r -p "删除编号或文件名: " ref
        delete_post "$ref"
        ;;
      7)
        open_posts
        ;;
      8)
        pull_posts
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
  push|publish)
    shift
    push_posts "${1:-Update blog posts}"
    ;;
  delete|rm)
    shift
    delete_post "${1:-}"
    ;;
  status)
    ensure_workdir
    git -C "$WORKDIR" status --short
    ;;
  pull)
    pull_posts
    ;;
  watch)
    shift
    watch_posts "${1:-status}"
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
