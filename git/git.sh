#!/usr/bin/env bash
set -euo pipefail

RED=$(printf '\033[0;31m')
GREEN=$(printf '\033[0;32m')
YELLOW=$(printf '\033[0;33m')
CYAN=$(printf '\033[0;36m')
NC=$(printf '\033[0m')

AKTOOLS_DIR="${AKTOOLS_DIR:-$HOME/.aktools}"
mkdir -p "$AKTOOLS_DIR"

WATCH_REGISTRY="$AKTOOLS_DIR/.git-watch"
WATCH_LOG="$AKTOOLS_DIR/git-watch.log"
ERROR_NOTIFY_COOLDOWN="$AKTOOLS_DIR/.git-watch-error-notify.lock"
GIT_CONFIG_FILE="$AKTOOLS_DIR/git.conf"

DEFAULT_GIT_KEY_PATH="$HOME/.ssh/github"
DEFAULT_WATCH_DELAY=5
DEFAULT_ERROR_COOLDOWN=600

CRON_JOB="@reboot sleep 60 && GIT_SSH_COMMAND=\"ssh -i ~/.ssh/github -o IdentitiesOnly=yes\" $HOME/.aktools/modules/git.sh sync-all"

load_git_config() {
    GIT_KEY_PATH="${GIT_KEY_PATH:-$DEFAULT_GIT_KEY_PATH}"
    WATCH_DELAY="${WATCH_DELAY:-$DEFAULT_WATCH_DELAY}"
    ERROR_COOLDOWN="${ERROR_COOLDOWN:-$DEFAULT_ERROR_COOLDOWN}"

    if [[ -f "$GIT_CONFIG_FILE" ]]; then
        while IFS='=' read -r key value; do
            [[ -z "$key" || "$key" == \#* ]] && continue
            key=$(echo "$key" | tr -d ' ')
            value=$(echo "$value" | tr -d ' ')
            case "$key" in
                git_key_path) GIT_KEY_PATH="$value" ;;
                watch_delay) WATCH_DELAY="$value" ;;
                error_cooldown) ERROR_COOLDOWN="$value" ;;
            esac
        done < "$GIT_CONFIG_FILE"
    fi
}

save_git_config() {
    cat > "$GIT_CONFIG_FILE" <<EOF
# aktools git configuration
git_key_path=${GIT_KEY_PATH}
watch_delay=${WATCH_DELAY}
error_cooldown=${ERROR_COOLDOWN}
EOF
}

log(){ echo -e "${CYAN}➜${NC} $*"; }
ok(){ echo -e "${GREEN}✔${NC} $*"; }
warn(){ echo -e "${YELLOW}!${NC} $*"; }
error_exit(){ echo -e "${RED}✘ Error: $1${NC}" >&2; exit 1; }

load_git_config

# ─────────────────────────────────────────────
# SSH SETUP
# ─────────────────────────────────────────────

setup_github_ssh_auth() {
    if [[ -f "$GIT_KEY_PATH" ]]; then
        export GIT_SSH_COMMAND="ssh -i $GIT_KEY_PATH -o IdentitiesOnly=yes"
        return 0
    fi

    error_exit "SSH key not found at '$GIT_KEY_PATH'. Run 'aktools git bootstrap' or set git_key_path in $GIT_CONFIG_FILE"
}

get_host_distro() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo "$ID"
    else
        echo "fedora"
    fi
}

distrobox_exists() {
    local name="$1"
    command -v distrobox &>/dev/null && distrobox list 2>/dev/null | grep -q "^${name} "
}

ensure_distrobox_installed() {
    if command -v distrobox &>/dev/null; then
        return 0
    fi

    log "distrobox not found. Attempting to install..."

    if is_atomic; then
        # On atomic, try rpm-ostree overlay or flatpak
        if command -v rpm-ostree &>/dev/null; then
            warn "Atomic system detected. Installing distrobox via rpm-ostree overlay (requires reboot)..."
            sudo rpm-ostree install --apply-live distrobox || \
                error_exit "Failed to install distrobox via rpm-ostree. Install it manually and re-run."
        else
            error_exit "Cannot auto-install distrobox on this atomic system. Install it manually: https://distrobox.it"
        fi
    else
        # Non-atomic: try package managers
        if command -v dnf &>/dev/null; then
            sudo dnf install -y distrobox
        elif command -v apt-get &>/dev/null; then
            sudo apt-get install -y distrobox
        elif command -v pacman &>/dev/null; then
            sudo pacman -S --noconfirm distrobox
        else
            # Fallback: upstream install script
            curl -s https://raw.githubusercontent.com/89luca89/distrobox/main/install | sudo sh
        fi
    fi

    command -v distrobox &>/dev/null || error_exit "distrobox installation failed. Install it manually."
    ok "distrobox installed."
}

ensure_cli_distrobox() {
    if distrobox_exists "cli"; then
        return 0
    fi

    log "Distrobox 'cli' not found. Creating it..."
    local distro
    distro=$(get_host_distro)

    case "$distro" in
        fedora|rhel|centos)
            distrobox create --name cli --image fedora:40 --yes
            ;;
        debian|ubuntu|linuxmint)
            distrobox create --name cli --image debian:stable --yes
            ;;
        arch|manjaro|endeavouros)
            distrobox create --name cli --image archlinux:latest --yes
            ;;
        opensuse|opensuse-tumbleweed|sles)
            distrobox create --name cli --image opensuse/tumbleweed:latest --yes
            ;;
        alpine)
            distrobox create --name cli --image alpine:latest --yes
            ;;
        *)
            distrobox create --name cli --image fedora:40 --yes
            ;;
    esac

    ok "Distrobox 'cli' created."
}

ensure_distrobox_installed() {
    if command -v distrobox &>/dev/null; then
        return 0
    fi

    log "distrobox not found. Attempting to install..."

    if is_atomic; then
        if command -v rpm-ostree &>/dev/null; then
            warn "Atomic system detected. Installing distrobox via rpm-ostree overlay (requires reboot)..."
            sudo rpm-ostree install --apply-live distrobox || \
                error_exit "Failed to install distrobox via rpm-ostree. Install it manually and re-run."
        else
            error_exit "Cannot auto-install distrobox on this atomic system. Install it manually: https://distrobox.it"
        fi
    else
        if command -v dnf &>/dev/null; then
            sudo dnf install -y distrobox
        elif command -v apt-get &>/dev/null; then
            sudo apt-get install -y distrobox
        elif command -v pacman &>/dev/null; then
            sudo pacman -S --noconfirm distrobox
        else
            curl -s https://raw.githubusercontent.com/89luca89/distrobox/main/install | sudo sh
        fi
    fi

    command -v distrobox &>/dev/null || error_exit "distrobox installation failed. Install it manually."
    ok "distrobox installed."
}

ensure_cli_distrobox() {
    if distrobox_exists "cli"; then
        return 0
    fi

    log "Distrobox 'cli' not found. Creating it..."
    local distro
    distro=$(get_host_distro)

    case "$distro" in
        fedora|rhel|centos)
            distrobox create --name cli --image fedora:40 --yes
            ;;
        debian|ubuntu|linuxmint)
            distrobox create --name cli --image debian:stable --yes
            ;;
        arch|manjaro|endeavouros)
            distrobox create --name cli --image archlinux:latest --yes
            ;;
        opensuse|opensuse-tumbleweed|sles)
            distrobox create --name cli --image opensuse/tumbleweed:latest --yes
            ;;
        alpine)
            distrobox create --name cli --image alpine:latest --yes
            ;;
        *)
            distrobox create --name cli --image fedora:40 --yes
            ;;
    esac

    ok "Distrobox 'cli' created."
}

ensure_github_ssh_key() {
    if [[ -f "$GIT_KEY_PATH" ]]; then
        return 0
    fi

    warn "SSH key not found at '$GIT_KEY_PATH'."
    echo ""
    echo "Options:"
    echo "  1) Generate a new SSH key pair"
    echo "  2) Set custom key path in config"
    echo ""

    if [[ ! -t 0 ]]; then
        error_exit "Non-interactive session and SSH key is missing. Set git_key_path in $GIT_CONFIG_FILE"
    fi

    read -rp "Choose [1/2]: " choice
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"

    case "$choice" in
        1)
            read -rp "Enter your GitHub email: " gh_email
            [[ -z "$gh_email" ]] && error_exit "Email required."
            ssh-keygen -t ed25519 -C "$gh_email" -f "$GIT_KEY_PATH" -N ""
            ok "SSH key generated at $GIT_KEY_PATH"
            echo ""
            echo "Add this public key to your GitHub account:"
            echo "  https://github.com/settings/keys"
            echo ""
            cat "${GIT_KEY_PATH}.pub"
            echo ""
            read -rp "Press Enter once you've added the key to GitHub..."
            ;;
        2)
            read -rp "Enter path for SSH key: " custom_path
            [[ -z "$custom_path" ]] && error_exit "Path required."
            GIT_KEY_PATH="$custom_path"
            save_git_config
            ok "Updated git_key_path to $GIT_KEY_PATH"
            ;;
        *)
            error_exit "Invalid choice."
            ;;
    esac
}

# ─────────────────────────────────────────────
# NOTIFICATION HELPERS
# ─────────────────────────────────────────────

install_notify_pkg() {
    if is_atomic; then
        if ! command -v distrobox &>/dev/null; then
            warn "distrobox required on atomic distros. Install it first."
            return 1
        fi
        if ! distrobox_exists "cli"; then
            create_cli_distrobox
        fi
        log "Installing libnotify via distrobox..."
        distrobox enter cli -- "sudo dnf install -y libnotify" 2>/dev/null || \
        distrobox enter cli -- "sudo apt-get install -y libnotify" 2>/dev/null || \
        distrobox enter cli -- "sudo pacman -S --noconfirm libnotify" 2>/dev/null || true
    else
        if command -v apt-get &>/dev/null; then
            sudo apt-get update -qq && sudo apt-get install -y libnotify-bin
        elif command -v dnf &>/dev/null; then
            sudo dnf install -y libnotify
        elif command -v pacman &>/dev/null; then
            sudo pacman -S --noconfirm libnotify
        elif command -v zypper &>/dev/null; then
            sudo zypper install -y libnotify-tools
        elif command -v brew &>/dev/null; then
            brew install libnotify
        fi
    fi
}

notify() {
    local title="$1"
    local body="$2"

    if [[ ("$title" == *"Error"* || "$title" == *"Not Signed In"*) ]] && [[ -n "${AKTOOLS_SERVICE:-}" ]]; then
        if [[ -f "$ERROR_NOTIFY_COOLDOWN" ]]; then
            local lock_age=$(($(date +%s) - $(stat -c %Y "$ERROR_NOTIFY_COOLDOWN" 2>/dev/null || echo 0)))
            if [[ $lock_age -lt 600 ]]; then
                return 0
            fi
        fi
        touch "$ERROR_NOTIFY_COOLDOWN"
    fi

    if [[ ! -t 0 ]] || [[ -n "${AKTOOLS_SERVICE:-}" ]]; then
        command -v notify-send &>/dev/null &&             notify-send "$title" "$body" --app-name="aktools" 2>/dev/null || true
        return 0
    fi

    if command -v notify-send &>/dev/null; then
        notify-send "$title" "$body" --app-name="aktools" 2>/dev/null || true
    else
        install_notify_pkg
        command -v notify-send &>/dev/null &&             notify-send "$title" "$body" --app-name="aktools" 2>/dev/null || true
    fi
}

# ─────────────────────────────────────────────
# GIT COMMANDS
# ─────────────────────────────────────────────

git_usage() {
    cat <<EOF
Usage: aktools git <command> [options]

Commands:
  bootstrap      Check and configure all prerequisites (SSH key)
  new            Create a new git repository from an SSH remote URL
  initial        Turn an existing directory into a clean, LFS-enabled repo
  sync           Bidirectional sync with remote (commit, pull, push)
  status         Show status of all watched repositories
  watch          Manage repository watching for continuous sync
  config         Show or set configuration options

Examples:
  aktools git bootstrap
  aktools git new git@github.com:user/repo.git
  aktools git initial
  aktools git sync
  aktools git sync --local
  aktools git sync --branch develop
  aktools git status
  aktools git watch add
  aktools git watch add --local --branch develop
  aktools git watch remove
  aktools git watch list
  aktools git watch change-mode sync
  aktools git watch change-branch develop
  aktools git service install
  aktools git service remove
  aktools git service status
  aktools git config
  aktools git config --git-key-path ~/.ssh/custom_key
  aktools git config --watch-delay 10
EOF
    exit 0
}

cmd_config() {
    local show_only=true
    local new_key_path=""
    local new_watch_delay=""
    local new_error_cooldown=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --git-key-path)
                new_key_path="$2"
                show_only=false
                shift 2
                ;;
            --watch-delay)
                new_watch_delay="$2"
                show_only=false
                shift 2
                ;;
            --error-cooldown)
                new_error_cooldown="$2"
                show_only=false
                shift 2
                ;;
            -h|--help)
                cat <<'EOF'
Usage: aktools git config [options]

Options:
  --git-key-path <path>    Set path to SSH private key
  --watch-delay <seconds>  Set delay between sync cycles (default: 5)
  --error-cooldown <secs>  Set error notification cooldown (default: 600)

Examples:
  aktools git config
  aktools git config --git-key-path ~/.ssh/github
  aktools git config --watch-delay 10
EOF
                exit 0
                ;;
            *)
                shift
                ;;
        esac
    done

    if $show_only; then
        echo "Current configuration:"
        echo "  git_key_path=${GIT_KEY_PATH}"
        echo "  watch_delay=${WATCH_DELAY}"
        echo "  error_cooldown=${ERROR_COOLDOWN}"
        echo ""
        echo "Config file: $GIT_CONFIG_FILE"
        return
    fi

    [[ -n "$new_key_path" ]] && GIT_KEY_PATH="$new_key_path"
    [[ -n "$new_watch_delay" ]] && WATCH_DELAY="$new_watch_delay"
    [[ -n "$new_error_cooldown" ]] && ERROR_COOLDOWN="$new_error_cooldown"

    save_git_config
    load_git_config

    ok "Configuration updated."
    echo "  git_key_path=${GIT_KEY_PATH}"
    echo "  watch_delay=${WATCH_DELAY}"
    echo "  error_cooldown=${ERROR_COOLDOWN}"
}

cmd_new() {
    local REMOTE_URL="$1"
    [[ -z "$REMOTE_URL" ]] && { echo "Usage: aktools git new <remote-url>"; exit 1; }

    local REPO_NAME=$(basename -s .git "$REMOTE_URL")
    local CURRENT_DIR=$(basename "$PWD")

    if [[ "$CURRENT_DIR" != "$REPO_NAME" ]]; then
        log "Creating new directory '$REPO_NAME' and switching into it..."
        mkdir -p "$REPO_NAME"
        cd "$REPO_NAME"
    fi

    if [ ! -d ".git" ]; then
        log "Initializing new git repository..."
        git init
    else
        ok "Git repository already initialized."
    fi

    if git remote get-url origin >/dev/null 2>&1; then
        log "Updating existing remote origin..."
        git remote set-url origin "$REMOTE_URL"
    else
        log "Adding remote origin..."
        git remote add origin "$REMOTE_URL"
    fi

    log "Fetching remote data..."
    git fetch origin 2>/dev/null || true

    if git rev-parse --verify origin/main >/dev/null 2>&1; then
        log "Remote repo has commits. Syncing..."
        git reset --hard origin/main
    else
        ok "Remote repo is empty or no main branch found. Starting fresh."
    fi

    if ! git diff --quiet || ! git diff --cached --quiet; then
        git add .
        git commit -m "Initial commit"
    fi

    git push -u origin main --force
    ok "Sync complete!"
}

cmd_initial() {
    local BRANCH="main"
    local REMOTE="origin"
    local ORPHAN_BRANCH="clean-$BRANCH"
    local THRESHOLD_MB=50
    local DRY_RUN=false
    local KEEP_BRANCH=false

    while getopts "hdkbt:" opt; do
        case "$opt" in
            h)
                cat <<'USAGE'
Usage: aktools git initial [options]
Options:
  -d              Dry-run (no write operations)
  -k              Keep the current branch instead of deleting it
  -b              Use a backup branch instead of main
  -t <mb>         Large-file threshold in MiB (default 50)
USAGE
                exit 0
                ;;
            d) DRY_RUN=true ;;
            k) KEEP_BRANCH=true ;;
            b) BRANCH="clean-$BRANCH"; ORPHAN_BRANCH="$BRANCH" ;;
            t) THRESHOLD_MB=$OPTARG ;;
            *) exit 1 ;;
        esac
    done
    shift $((OPTIND-1))

    $DRY_RUN && log "Dry-run mode enabled"

    if ! command -v git >/dev/null 2>&1; then
        error_exit "git not found. Install it first."
    fi

    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        if [[ -t 1 ]] && read -rp "No .git found. Initialize a new repository? [y/n]: " ans; then
            case "${ans,,}" in
                y|yes)
                    git init
                    git branch -m "$BRANCH"
                    ;;
                *) exit 1 ;;
            esac
        else
            error_exit "Not a git repository. Run 'git init' first."
        fi
    fi

    if ! git remote | grep -q "^${REMOTE}$"; then
        if [[ -t 1 ]]; then
            read -rp "Enter GitHub repo URL: " REMOTE_URL
            [[ -z $REMOTE_URL ]] && exit 1
            git remote add "$REMOTE" "$REMOTE_URL"
        else
            error_exit "No remote configured. Add one with: git remote add origin <url>"
        fi
    fi

    local DEFAULT_GITIGNORE='# IntelliJ
.idea/
*.iml
.vscode/
.DS_Store
Thumbs.db
*.log
bin/
obj/
dist/
__pycache__/
*.pyc'

    if [[ -f .gitignore ]]; then
        warn ".gitignore exists, appending defaults"
        printf '\n%s\n' "$DEFAULT_GITIGNORE" >> .gitignore
    else
        printf '%s\n' "$DEFAULT_GITIGNORE" > .gitignore
    fi

    local ATTR_CONTENT='*.pdf binary
*.zip binary
*.png binary
*.jpg binary
*.jpeg binary
*.gif binary
*.pdf filter=lfs diff=lfs merge=lfs -text
*.zip filter=lfs diff=lfs merge=lfs -text'

    [[ -f .gitattributes ]] && warn ".gitattributes exists, skipping" || printf '%s\n' "$ATTR_CONTENT" > .gitattributes

    log "Scanning for files >= ${THRESHOLD_MB}MiB..."
    local LARGE_FILES=$(find . -type f -size +${THRESHOLD_MB}M -not -path './.git/*' 2>/dev/null | head -20)
    if [[ -n "$LARGE_FILES" ]]; then
        warn "Large files detected:"
        echo "$LARGE_FILES" | sed 's/^/  /'
        if command -v git-lfs >/dev/null 2>&1 && [[ -t 1 ]]; then
            read -rp "Add them to Git LFS? [y/n]: " ans
            [[ "${ans,,}" == y ]] && echo "$LARGE_FILES" | xargs -I{} git lfs track "$(basename {})" 2>/dev/null
        fi
    fi

    log "Creating clean orphan branch..."
    local tempdir=$(mktemp -d -t cleanpush-XXXXX)
    rsync -a --exclude='.git' --delete . "$tempdir/" 2>/dev/null || cp -a . "$tempdir/"
    git checkout --orphan "$ORPHAN_BRANCH"
    git rm -rf . 2>/dev/null || true
    rsync -a "$tempdir/" . 2>/dev/null || cp -a "$tempdir/"* .
    rm -rf "$tempdir"
    git add .
    git commit -m "Initial clean commit (binary-safe, LFS enabled)" 2>/dev/null || true

    log "Pushing to remote..."
    git push -u "$REMOTE" "$ORPHAN_BRANCH:$BRANCH" --force 2>/dev/null || warn "Push failed or remote branch exists"

    $KEEP_BRANCH || git branch -D "$BRANCH" 2>/dev/null || true
    git checkout "$BRANCH"
    ok "Done! Branch '$BRANCH' is ready."
}

cmd_sync() {
    setup_github_ssh_auth

    local MODE="sync"
    local FORCE=false
    local REMOTE_BRANCH="main"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --local)       MODE="local"; shift ;;
            --remote)      MODE="remote"; shift ;;
            --force)       FORCE=true; shift ;;
            --branch|-b)
                REMOTE_BRANCH="$2"
                [[ -z "$REMOTE_BRANCH" ]] && { echo "Error: --branch requires a branch name"; exit 1; }
                shift 2
                ;;
            --branch=*)    REMOTE_BRANCH="${1#*=}"; shift ;;
            --help)
                echo "Usage: git sync [--local|--remote] [--force] [--branch <name>]"
                echo "  --branch <name>  Set remote branch (default: main)"
                echo "  (no flag)        Bidirectional sync (default)"
                echo "  --local          Local is source of truth, force push to remote"
                echo "  --remote         Remote is source of truth, force pull to local"
                echo "  --force          Ignore locks and force sync"
                exit 0
                ;;
            *)             shift; break ;;
        esac
    done

    git rev-parse --is-inside-work-tree &>/dev/null || error_exit "Not inside a git repository."
    git remote get-url origin &>/dev/null || error_exit "No remote named 'origin' found."

    local REPO_LOCK_PATH="$AKTOOLS_DIR/.git-watch-$(echo "$(pwd)" | md5sum | cut -d' ' -f1).lock"
    if ! $FORCE; then
        if [[ -f "$REPO_LOCK_PATH" ]]; then
            local lock_age=$(($(date +%s) - $(stat -c %Y "$REPO_LOCK_PATH" 2>/dev/null || echo 0)))
            if [[ $lock_age -lt 60 ]]; then
                error_exit "Watcher is syncing this repo (lock: ${lock_age}s). Use --force to override."
            fi
        fi
    fi

    log "Working in: $(pwd)"
    log "Mode: $MODE  Remote branch: $REMOTE_BRANCH"

    if [[ "$MODE" == "local" ]]; then
        log "LOCAL is source of truth — pushing to origin/$REMOTE_BRANCH..."
        local has_changes=false
        git diff --quiet || has_changes=true
        git diff --cached --quiet || has_changes=true
        git ls-files --others --exclude-standard | grep -q . && has_changes=true || true
        if $has_changes; then
            git add -A
            git commit -m "Auto-commit on $(date '+%Y-%m-%d %H:%M:%S')" || true
        fi
        git push --force origin "$REMOTE_BRANCH" || error_exit "Force push failed."
        ok "Done — remote now matches local."
        return
    fi

    if [[ "$MODE" == "remote" ]]; then
        log "REMOTE is source of truth — pulling to local..."
        if ! git diff --quiet || ! git diff --cached --quiet; then
            git stash push -m "git sync --remote stash $(date)"
        fi
        git fetch origin "$REMOTE_BRANCH" || error_exit "Fetch failed."
        git reset --hard "origin/$REMOTE_BRANCH"
        ok "Done — local now matches remote."
        return
    fi

    if ! git diff --quiet || ! git diff --cached --quiet || ! git ls-files --others --exclude-standard | grep -q .; then
        git add -A
        git commit -m "Auto-commit on $(date '+%Y-%m-%d %H:%M:%S')" || true
    fi

    git fetch origin "$REMOTE_BRANCH" || error_exit "Fetch failed."

    if ! git rev-parse @{u} &>/dev/null 2>&1; then
        git branch --set-upstream-to="origin/$REMOTE_BRANCH" "$REMOTE_BRANCH" 2>/dev/null || true
    fi

    LOCAL=$(git rev-parse @)
    REMOTE=$(git rev-parse @{u})
    BASE=$(git merge-base @ @{u})

    if [[ "$LOCAL" == "$REMOTE" ]]; then
        ok "Already in sync."
    elif [[ "$LOCAL" == "$BASE" ]]; then
        log "Local is behind remote. Pulling..."
        git pull --no-rebase || warn "Merge conflict detected"
    elif [[ "$REMOTE" == "$BASE" ]]; then
        log "Local is ahead of remote. Pushing..."
        git push -u origin "$REMOTE_BRANCH"
    else
        log "Diverged. Run 'git status' to resolve manually."
    fi

    ok "Sync complete."
}

watch_ensure_service() {
    local svc="aktools-git-watch.service"
    local svc_file="$HOME/.config/systemd/user/$svc"
    local systemd_available=false

    if command -v systemctl &>/dev/null; then
        if systemctl --user list-unit-files "$svc" &>/dev/null 2>&1; then
            if systemctl --user is-active --quiet "$svc" 2>/dev/null; then
                ok "Systemd service is running."
                systemd_available=true
            else
                log "Systemd service installed but not running. Starting..."
                if systemctl --user start "$svc" 2>/dev/null; then
                    ok "Systemd service started."
                    systemd_available=true
                else
                    warn "Failed to start systemd service."
                fi
            fi
        else
            log "Systemd service not installed. Installing..."
            if mkdir -p "$HOME/.config/systemd/user" 2>/dev/null; then
                local _user_home="$HOME"
                local _script_path="$AKTOOLS_DIR/modules/git.sh"
                local _env_file="$HOME/.config/systemd/user/aktools-git-watch.env"

                cat > "$_env_file" <<EOF
HOME=${_user_home}
AKTOOLS_SERVICE=1
EOF
                cat >> "$_env_file" <<'ENVEOF'
GIT_SSH_COMMAND=ssh -i ~/.ssh/github -o IdentitiesOnly=yes
ENVEOF
                chmod 600 "$_env_file"

                cat > "$svc_file" <<EOF
[Unit]
Description=Aktools Git Watcher - keeps repositories in sync
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=${_env_file}
ExecStart=/usr/bin/env bash -c 'while true; do AKTOOLS_DIR=${_user_home}/.aktools bash ${_script_path} sync-all; sleep 5; done'
Restart=on-failure
RestartSec=5
WorkingDirectory=${_user_home}

[Install]
WantedBy=default.target
EOF
                if systemctl --user daemon-reload 2>/dev/null && systemctl --user enable --now "$svc" 2>/dev/null; then
                    ok "Systemd service installed and started."
                    systemd_available=true
                else
                    warn "Failed to install/start systemd service."
                fi
            else
                warn "Cannot create systemd user directory."
            fi
        fi
    else
        warn "systemctl not available."
    fi

    if ! $systemd_available; then
        log "Falling back to cron-based sync..."
        if command -v crontab &>/dev/null; then
            local existing_cron=$(crontab -l 2>/dev/null || true)
            if echo "$existing_cron" | grep -q "git.sh sync-all"; then
                ok "Cron job already exists."
            else
                log "Adding cron job for git sync..."
                (echo "$existing_cron"; echo "$CRON_JOB") | crontab -
                ok "Cron job added."
            fi
        else
            warn "cron not available. Repos will only sync when manually run."
        fi
    fi
}

watch_add() {
    local repo_dir="$(pwd)"
    local mode="${1:-sync}"
    local branch="${2:-main}"

    git rev-parse --is-inside-work-tree &>/dev/null || error_exit "Not inside a git repository."

    local repo_escaped
    repo_escaped=$(printf '%s' "$repo_dir" | sed 's/[[.*^$/]/\\&/g')
    if grep -q "^${repo_escaped}|" "$WATCH_REGISTRY" 2>/dev/null; then
        ok "Already watching: $repo_dir (mode: $mode, branch: $branch)"
        return
    fi

    echo "$repo_dir|$mode|$branch" >> "$WATCH_REGISTRY"
    ok "Added to watch list: $repo_dir (mode: $mode, branch: $branch)"

    watch_ensure_service
}

watch_remove() {
    local repo_dir="$(pwd)"

    if [[ ! -f "$WATCH_REGISTRY" ]]; then
        ok "Watch list is empty."
        return
    fi

    local repo_escaped
    repo_escaped=$(printf '%s' "$repo_dir" | sed 's/[[.*^$/]/\\&/g')

    local before=$(wc -l < "$WATCH_REGISTRY")
    grep -v "^${repo_escaped}|" "$WATCH_REGISTRY" > "$WATCH_REGISTRY.tmp" 2>/dev/null || true
    mv "$WATCH_REGISTRY.tmp" "$WATCH_REGISTRY"
    local after=$(wc -l < "$WATCH_REGISTRY")

    if [[ "$before" -gt "$after" ]]; then
        ok "Removed from watch list: $repo_dir"
    else
        warn "Not in watch list: $repo_dir"
    fi
}

watch_change_mode() {
    local new_mode="$1"
    local new_branch="${2:-}"
    local repo_dir="$(pwd)"

    if [[ ! "$new_mode" =~ ^(sync|local|remote)$ ]]; then
        error_exit "Mode must be: sync, local, or remote"
    fi

    if [[ ! -f "$WATCH_REGISTRY" ]]; then
        error_exit "Watch list is empty. Nothing to change."
    fi

    local repo_escaped
    repo_escaped=$(printf '%s' "$repo_dir" | sed 's/[[.*^$/]/\\&/g')

    local current_entry
    current_entry=$(grep "^${repo_escaped}|" "$WATCH_REGISTRY" 2>/dev/null | head -1)
    if [[ -z "$current_entry" ]]; then
        error_exit "Current directory is not being watched. Run 'aktools git watch add' first."
    fi

    local current_branch="main"
    if [[ "$(echo "$current_entry" | awk -F'|' '{print NF}')" -ge 3 ]]; then
        current_branch=$(echo "$current_entry" | cut -d'|' -f3)
    fi

    [[ -n "$new_branch" ]] && current_branch="$new_branch"

    grep -v "^${repo_escaped}|" "$WATCH_REGISTRY" > "$WATCH_REGISTRY.tmp" 2>/dev/null || true
    echo "$repo_dir|$new_mode|$current_branch" >> "$WATCH_REGISTRY.tmp" 2>/dev/null || true
    mv "$WATCH_REGISTRY.tmp" "$WATCH_REGISTRY"

    ok "Changed to '$new_mode' (branch: $current_branch) for: $repo_dir"
}

watch_change_branch() {
    local new_branch="$1"
    local repo_dir="$(pwd)"

    if [[ -z "$new_branch" ]]; then
        error_exit "Branch name required."
    fi

    if [[ ! -f "$WATCH_REGISTRY" ]]; then
        error_exit "Watch list is empty. Nothing to change."
    fi

    local repo_escaped
    repo_escaped=$(printf '%s' "$repo_dir" | sed 's/[[.*^$/]/\\&/g')

    local current_entry
    current_entry=$(grep "^${repo_escaped}|" "$WATCH_REGISTRY" 2>/dev/null | head -1)
    if [[ -z "$current_entry" ]]; then
        error_exit "Current directory is not being watched. Run 'aktools git watch add' first."
    fi

    local current_mode
    current_mode=$(echo "$current_entry" | cut -d'|' -f2)

    grep -v "^${repo_escaped}|" "$WATCH_REGISTRY" > "$WATCH_REGISTRY.tmp" 2>/dev/null || true
    echo "$repo_dir|$current_mode|$new_branch" >> "$WATCH_REGISTRY.tmp" 2>/dev/null || true
    mv "$WATCH_REGISTRY.tmp" "$WATCH_REGISTRY"

    ok "Changed branch to '$new_branch' for: $repo_dir"
}

watch_sync_one() {
    local repo_mode="${1:-}"
    local repo="${repo_mode%%|*}"
    local mode="${repo_mode%%|*}"
    mode="${mode##*|}"
    mode=$(echo "$repo_mode" | cut -d'|' -f2)
    local branch="main"
    [[ "$(echo "$repo_mode" | awk -F'|' '{print NF}')" -ge 3 ]] && branch=$(echo "$repo_mode" | cut -d'|' -f3)
    local log_prefix="$(date '+%Y-%m-%d %H:%M:%S') [$repo]"
    local original_dir="$(pwd)"
    local repo_lock_path=""
    local cleanup_needed=false

    if [[ -z "$repo" ]]; then
        return 1
    fi

    repo_lock_path="/tmp/git-watch-$(echo "$repo" | md5sum | cut -d' ' -f1).lock"
    local lock_age=999
    local lock_pid=""
    if [[ -f "$repo_lock_path" ]]; then
        lock_pid=$(cat "$repo_lock_path" 2>/dev/null)
        if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
            lock_age=0
        else
            lock_age=$(($(date +%s) - $(stat -c %Y "$repo_lock_path" 2>/dev/null || echo 0)))
        fi
    fi

    if [[ $lock_age -lt 60 ]]; then
        echo "$log_prefix: Repo busy (lock: ${lock_age}s by PID $lock_pid), skipping" >> "$WATCH_LOG"
        return
    fi

    echo "$$" > "$repo_lock_path"
    cleanup_needed=true

    sync_one_cleanup() {
        if [[ "$cleanup_needed" == "true" ]] && [[ -f "$repo_lock_path" ]]; then
            rm -f "$repo_lock_path"
        fi
    }

    if [[ ! -d "$repo" ]]; then
        echo "$log_prefix: Directory not found, removing from registry" >> "$WATCH_LOG"
        grep -v "^$repo|" "$WATCH_REGISTRY" > "$WATCH_REGISTRY.tmp" 2>/dev/null || true
        mv "$WATCH_REGISTRY.tmp" "$WATCH_REGISTRY"
        sync_one_cleanup
        cd "$original_dir" 2>/dev/null || true
        return
    fi

    cd "$repo" || { sync_one_cleanup; cd "$original_dir" 2>/dev/null || true; return; }

    if ! git rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
        echo "$log_prefix: Not a git repository, removing from registry" >> "$WATCH_LOG"
        grep -v "^$repo|" "$WATCH_REGISTRY" > "$WATCH_REGISTRY.tmp" 2>/dev/null || true
        mv "$WATCH_REGISTRY.tmp" "$WATCH_REGISTRY"
        sync_one_cleanup
        cd "$original_dir" 2>/dev/null || true
        return
    fi

    if ! git remote get-url origin &>/dev/null 2>&1; then
        echo "$log_prefix: No remote, skipping" >> "$WATCH_LOG"
        sync_one_cleanup
        cd "$original_dir" 2>/dev/null || true
        return
    fi

    if [[ "$mode" == "local" ]]; then
        if ! git diff --quiet || ! git diff --cached --quiet || ! git ls-files --others --exclude-standard | grep -q .; then
            echo "[local] Detected changes, committing and pushing..."
            git add -A
            if ! git commit -m "Auto-commit on $(date '+%Y-%m-%d %H:%M:%S')" 2>> "$WATCH_LOG"; then
                echo "[local] ERROR: Commit failed for $(basename "$repo")" | tee -a "$WATCH_LOG"
                notify "Git Sync Error" "Commit failed: $(basename "$repo"). Check $WATCH_LOG"
                sync_one_cleanup; cd "$original_dir" 2>/dev/null || true
                return 1
            fi
        fi
        echo "[local] Pushing to origin/$branch..."
        if ! git push --force origin "$branch" 2>> "$WATCH_LOG"; then
            echo "[local] ERROR: Push failed for $(basename "$repo")" | tee -a "$WATCH_LOG"
            notify "Git Sync Error" "Push failed: $(basename "$repo"). Check $WATCH_LOG"
            sync_one_cleanup; cd "$original_dir" 2>/dev/null || true
            return 1
        fi
        echo "$log_prefix: [local] Pushed to remote" | tee -a "$WATCH_LOG"
        notify "Git Sync" "[local] Pushed: $(basename "$repo")"
        sync_one_cleanup; cd "$original_dir" 2>/dev/null || true
        return 0
    fi

    if [[ "$mode" == "remote" ]]; then
        if ! git diff --quiet || ! git diff --cached --quiet; then
            if ! git stash push -m "git watch stash $(date)" 2>> "$WATCH_LOG"; then
                echo "[remote] WARNING: Stash failed for $(basename "$repo")" | tee -a "$WATCH_LOG"
            fi
        fi
        echo "[remote] Fetching and resetting to origin/$branch..."
        if ! git fetch origin "$branch" 2>> "$WATCH_LOG"; then
            echo "[remote] ERROR: Fetch failed for $(basename "$repo")" | tee -a "$WATCH_LOG"
            notify "Git Sync Error" "Fetch failed: $(basename "$repo"). Check $WATCH_LOG"
            sync_one_cleanup; cd "$original_dir" 2>/dev/null || true
            return 1
        fi
        if ! git reset --hard "origin/$branch" 2>> "$WATCH_LOG"; then
            echo "[remote] ERROR: Reset failed for $(basename "$repo")" | tee -a "$WATCH_LOG"
            notify "Git Sync Error" "Reset failed: $(basename "$repo"). Check $WATCH_LOG"
            sync_one_cleanup; cd "$original_dir" 2>/dev/null || true
            return 1
        fi
        echo "$log_prefix: [remote] Pulled from remote" | tee -a "$WATCH_LOG"
        notify "Git Sync" "[remote] Pulled: $(basename "$repo")"
        sync_one_cleanup; cd "$original_dir" 2>/dev/null || true
        return 0
    fi

    local has_changes=false
    if ! git diff --quiet || ! git diff --cached --quiet || ! git ls-files --others --exclude-standard | grep -q .; then
        has_changes=true
    fi

    if [[ "$has_changes" == "true" ]]; then
        echo "[sync] Detected changes, committing..."
        git add -A
        if ! git commit -m "Auto-commit on $(date '+%Y-%m-%d %H:%M:%S')" 2>> "$WATCH_LOG"; then
            echo "[sync] ERROR: Commit failed for $(basename "$repo")" | tee -a "$WATCH_LOG"
            notify "Git Sync Error" "Commit failed: $(basename "$repo") - skipping sync. Check $WATCH_LOG"
            sync_one_cleanup; cd "$original_dir" 2>/dev/null || true
            return 1
        fi
    fi

    if ! git fetch origin "$branch" 2>> "$WATCH_LOG"; then
        echo "[sync] ERROR: Fetch failed for $(basename "$repo")" | tee -a "$WATCH_LOG"
        notify "Git Sync Error" "Fetch failed: $(basename "$repo"). Check $WATCH_LOG"
        sync_one_cleanup; cd "$original_dir" 2>/dev/null || true
        return 1
    fi

    if ! git rev-parse @{u} &>/dev/null 2>&1; then
        git branch --set-upstream-to="origin/$branch" "$branch" 2>/dev/null || true
    fi

    LOCAL=$(git rev-parse @)
    REMOTE=$(git rev-parse @{u})
    BASE=$(git merge-base @ @{u})

    if [[ "$LOCAL" == "$REMOTE" ]]; then
        echo "$log_prefix: [sync] Already in sync" | tee -a "$WATCH_LOG"
    elif [[ "$LOCAL" == "$BASE" ]]; then
        echo "[sync] Local behind remote, pulling..."
        if ! git pull --no-rebase 2>> "$WATCH_LOG"; then
            echo "[sync] ERROR: Pull failed for $(basename "$repo")" | tee -a "$WATCH_LOG"
            notify "Git Sync Error" "Pull failed: $(basename "$repo"). Check $WATCH_LOG"
            sync_one_cleanup; cd "$original_dir" 2>/dev/null || true
            return 1
        fi
        echo "$log_prefix: [sync] Pulled from remote" | tee -a "$WATCH_LOG"
        notify "Git Sync" "[sync] Pulled: $(basename "$repo")"
    elif [[ "$REMOTE" == "$BASE" ]]; then
        echo "[sync] Local ahead of remote, pushing to origin/$branch..."
        if ! git push -u origin "$branch" 2>> "$WATCH_LOG"; then
            echo "[sync] ERROR: Push failed for $(basename "$repo")" | tee -a "$WATCH_LOG"
            notify "Git Sync Error" "Push failed: $(basename "$repo"). Check $WATCH_LOG"
            sync_one_cleanup; cd "$original_dir" 2>/dev/null || true
            return 1
        fi
        echo "$log_prefix: [sync] Pushed to remote" | tee -a "$WATCH_LOG"
        notify "Git Sync" "[sync] Pushed: $(basename "$repo")"
    else
        echo "$log_prefix: [sync] Diverged - requires manual resolution" | tee -a "$WATCH_LOG"
        notify "Git Sync Error" "Diverged (manual resolution needed): $(basename "$repo"). Check $WATCH_LOG"
        sync_one_cleanup; cd "$original_dir" 2>/dev/null || true
        return 1
    fi

    sync_one_cleanup
    cd "$original_dir" 2>/dev/null || true
    return 0
}

cmd_sync_all() {
    setup_github_ssh_auth

    if [[ ! -f "$WATCH_REGISTRY" ]] || [[ ! -s "$WATCH_REGISTRY" ]]; then
        ok "Watch list is empty."
        return
    fi

    local SYNC_ALL_LOCK="/tmp/git-watch-sync.lock"
    local cleanup_needed=false
    local -a failed_repos=()
    local success_count=0

    if [[ -f "$SYNC_ALL_LOCK" ]]; then
        local lock_age=$(($(date +%s) - $(stat -c %Y "$SYNC_ALL_LOCK" 2>/dev/null || echo 0)))
        if [[ $lock_age -lt 30 ]]; then
            log "Sync already in progress (lock age: ${lock_age}s). Skipping."
            return
        else
            warn "Stale lock found (${lock_age}s). Removing..."
            rm -f "$SYNC_ALL_LOCK"
        fi
    fi

    touch "$SYNC_ALL_LOCK"
    cleanup_needed=true

    sync_all_cleanup() {
        if [[ "$cleanup_needed" == "true" ]]; then
            rm -f "$SYNC_ALL_LOCK"
        fi
    }

    log "Syncing all watched repositories..."
    while IFS= read -r repo_mode; do
        [[ -z "$repo_mode" ]] && continue
        local repo="${repo_mode%%|*}"
        if watch_sync_one "$repo_mode"; then
            ((success_count++)) || true
        else
            failed_repos+=("$(basename "$repo")")
        fi
    done < "$WATCH_REGISTRY"

    sync_all_cleanup

    if [[ ${#failed_repos[@]} -gt 0 ]]; then
        local error_list=$(printf "%s, " "${failed_repos[@]}" | sed 's/, $//')
        notify "Git Sync Errors" "Failed repos: $error_list. Check $WATCH_LOG"
        warn "Sync completed with ${#failed_repos[@]} error(s)"
    fi

    ok "Sync complete. ${success_count} repos synced."
}

cmd_sync_one() {
    local repo_mode="$1"
    setup_github_ssh_auth
    watch_sync_one "$repo_mode"
}

cmd_watch() {
    local action=""
    local mode="sync"
    local branch="main"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            add)              action="add";         shift ;;
            remove)           action="remove";      shift ;;
            change-mode)      action="change-mode"; shift ;;
            change-branch)    action="change-branch"; shift ;;
            list)             action="list";        shift ;;
            logs)             action="logs";        shift ;;
            --local)          mode="local";        shift ;;
            --remote)         mode="remote";        shift ;;
            --branch|-b)      branch="$2"; shift 2 ;;
            --branch=*)       branch="${1#*=}"; shift ;;
            -h|--help)        action="help";        shift ;;
            *) break ;;
        esac
    done

    case "$action" in
        add)         watch_add "$mode" "$branch" ;;
        remove)      watch_remove ;;
        change-mode)  watch_change_mode "$1" "$2" ;;
        change-branch) watch_change_branch "$1" ;;
        list)        cmd_status ;;
        logs)        cmd_logs "$@" ;;
        help|"")
            cat <<'HELP'
Usage: aktools git watch <action> [options]

Actions:
  add             Add current repository to the watch list
  remove          Remove current repository from the watch list
  list            List all watched repositories and their modes
  logs            Show sync logs (use -f to follow, -n for lines)
  change-mode     Change the sync mode for current repository
  change-branch   Change the sync branch for current repository

Options for 'add':
  --local         Add in push-only mode (local is source of truth)
  --remote        Add in pull-only mode (remote is source of truth)
  --branch <name> Set the branch to sync (default: main)
  (default: sync mode)

Options for 'change-mode':
  sync            Bidirectional sync
  local           Push-only (local is source of truth)
  remote          Pull-only (remote is source of truth)

Options for 'change-branch':
  <branch-name>   The branch to sync with

Examples:
  aktools git watch add
  aktools git watch add --local
  aktools git watch add --branch develop
  aktools git watch remove
  aktools git watch list
  aktools git watch logs
  aktools git watch change-mode local
  aktools git watch change-branch develop
HELP
            exit 0
            ;;
        *)
            echo "Unknown action: $1"
            echo "Use: add, remove, list, logs, change-mode, or change-branch"
            exit 1
            ;;
    esac
}

cmd_logs() {
    local lines=50
    local follow=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -f|--follow) follow=true; shift ;;
            -n) lines="${2:-50}"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [[ ! -f "$WATCH_LOG" ]]; then
        ok "No logs yet."
        return
    fi

    if $follow; then
        tail -n "$lines" -f "$WATCH_LOG"
    else
        tail -n "$lines" "$WATCH_LOG"
    fi
}

cmd_status() {
    if [[ ! -f "$WATCH_REGISTRY" ]] || [[ ! -s "$WATCH_REGISTRY" ]]; then
        ok "Watch list is empty."
        return
    fi

    echo "Watched repositories:"
    echo ""
    while IFS= read -r repo_mode; do
        [[ -z "$repo_mode" ]] && continue
        local repo branch mode
        repo=$(echo "$repo_mode" | cut -d'|' -f1)
        mode=$(echo "$repo_mode" | cut -d'|' -f2)
        branch=$(echo "$repo_mode" | cut -d'|' -f3 2>/dev/null || echo "main")
        if [[ -d "$repo" ]] && git -C "$repo" rev-parse --is-inside-work-tree &>/dev/null; then
            local status=$(git -C "$repo" status --porcelain 2>/dev/null | head -1)
            if [[ -n "$status" ]]; then
                echo -e "  ${YELLOW}✘${NC} $repo [$mode] branch:$branch (uncommitted changes)"
            else
                echo -e "  ${GREEN}✔${NC} $repo [$mode] branch:$branch (clean)"
            fi
        else
            echo -e "  ${RED}✘${NC} $repo (not found or not a git repo)"
        fi
    done < "$WATCH_REGISTRY"
}

cmd_service() {
    local action="${1:-}"
    local svc="aktools-git-watch.service"
    local svc_file="$HOME/.config/systemd/user/$svc"

    case "$action" in
        install)
            mkdir -p "$HOME/.config/systemd/user"

            local user_home="$HOME"
            local script_path="$AKTOOLS_DIR/modules/git.sh"
            local env_file="$HOME/.config/systemd/user/aktools-git-watch.env"

            cat > "$env_file" <<EOF
HOME=${user_home}
AKTOOLS_SERVICE=1
EOF
            cat >> "$env_file" <<'ENVEOF'
GIT_SSH_COMMAND=ssh -i ~/.ssh/github -o IdentitiesOnly=yes
ENVEOF
            chmod 600 "$env_file"

            cat > "$svc_file" <<EOF
[Unit]
Description=Aktools Git Watcher - keeps repositories in sync
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=${env_file}
ExecStart=/usr/bin/env bash -c 'while true; do AKTOOLS_DIR=${user_home}/.aktools bash ${script_path} sync-all; sleep 5; done'
Restart=on-failure
RestartSec=5
WorkingDirectory=${user_home}

[Install]
WantedBy=default.target
EOF
            systemctl --user daemon-reload
            systemctl --user enable --now "$svc"
            ok "Service installed and started."
            ;;
        remove)
            if [[ -f "$svc_file" ]]; then
                systemctl --user stop "$svc" 2>/dev/null || true
                systemctl --user disable "$svc" 2>/dev/null || true
                rm -f "$svc_file"
                rm -f "$HOME/.config/systemd/user/aktools-git-watch.env"
                systemctl --user daemon-reload
                ok "Service removed."
            else
                warn "Service is not installed."
            fi
            ;;
        restart)
            if [[ -f "$svc_file" ]]; then
                log "Restarting $svc..."
                systemctl --user restart "$svc"
                ok "Service restarted."
            else
                warn "Service is not installed. Run: aktools git service install"
            fi
            ;;
        status)
            if systemctl --user list-unit-files "$svc" &>/dev/null; then
                echo "Service: $svc"
                echo ""
                systemctl --user status "$svc" --no-pager 2>/dev/null || echo "  Not running"
                echo ""
                echo "Recent logs:"
                journalctl --user -u "$svc" -n 10 --no-pager 2>/dev/null || echo "  No logs available"
            else
                echo "Service '$svc' is not installed."
                echo ""
                if [[ -t 1 ]]; then
                    read -rp "Would you like to install it now? [y/n]: " ans
                    case "${ans,,}" in
                        y|yes) cmd_service install ;;
                        *) echo "Installation cancelled." ;;
                    esac
                else
                    echo "To install it, run: aktools git service install"
                fi
            fi
            ;;
        "")
            cat <<'EOF'
Usage: aktools git service <action>

Actions:
  install    Install and start the git watcher service
  remove     Stop and remove the git watcher service
  restart    Restart the git watcher service
  status     Show service status and recent logs

Examples:
  aktools git service install
  aktools git service remove
  aktools git service restart
  aktools git service status
EOF
            exit 0
            ;;
        *)
            echo "Unknown action: $action"
            echo "Use: install, remove, restart, or status"
            exit 1
            ;;
    esac
}

# ─────────────────────────────────────────────
# ENTRYPOINT
# ─────────────────────────────────────────────

SUBCOMMAND="${1:-}"
case "$SUBCOMMAND" in
    bootstrap)   shift; bootstrap ;;
    new|initial|sync|status|service|config) shift; "cmd_$SUBCOMMAND" "$@" ;;
    watch)       shift; cmd_watch "$@" ;;
    sync-all)    shift; cmd_sync_all ;;
    check)
        shift
        setup_github_ssh_auth
        watch_check_changes "$1"
        exit $?
        ;;
    sync-one)
        shift
        cmd_sync_one "$1"
        ;;
    change-branch)
        shift
        watch_change_branch "$1"
        ;;
    *) git_usage ;;
esac
