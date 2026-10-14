#!/usr/bin/env bash
# 列出本機的全域開發快取大小，以及各工具官方的清理指令。不刪任何東西；清理一律交給官方指令（它們知道哪些還在用）。
#
# 用法：scan-caches.sh
# 輸出：TSV（tool size_kb path clean_command note），依大小排序；沒裝的工具不列。
set -u
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"
# 在家目錄執行：在 Yarn Berry 等專案目錄內，cache 指令指的是專案自己的 .yarn/cache（zero-install 時是 commit 進去的）
cd "$HOME" || exit 1
# corepack 管理的 yarn／pnpm 第一次執行可能跳下載確認；stdin 關掉、prompt 關掉，避免卡住
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0

have() { command -v "$1" >/dev/null 2>&1; }
q() { "$@" </dev/null 2>/dev/null; }
row() { # tool path clean note
  [ -n "$2" ] && [ -d "$2" ] || return 0
  printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$(size_kb "$2")" "$2" "$3" "$4"
}
lib="$HOME/Library"; cache="${XDG_CACHE_HOME:-$HOME/.cache}"
gradle_home="${GRADLE_USER_HOME:-$HOME/.gradle}"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

{
  have npm   && row npm   "$(q npm config get cache)" "npm cache clean --force" "下次 install 重新下載"
  have pnpm  && row pnpm  "$(q pnpm store path)" "pnpm store prune" "只刪沒有專案引用的套件"
  have yarn  && row yarn  "$(q yarn cache dir)" "cd ~ && yarn cache clean" "Yarn 1 的全域 cache；Yarn Berry 沒有全域 cache 指令，不會列出"
  have bun   && row bun   "$HOME/.bun/install/cache" "bun pm cache rm" ""
  have pip3  && row pip   "$(q pip3 cache dir)" "pip3 cache purge" ""
  have uv    && row uv    "$(q uv cache dir)" "uv cache prune" "只刪沒在用的；uv cache clean 為全清"
  have poetry && row poetry "$(q poetry config cache-dir)" "poetry cache clear --all PyPI" ""
  have go    && row go    "$(q go env GOMODCACHE)" "go clean -modcache" "下次 build 重新下載 module"
  have go    && row go-build "$(q go env GOCACHE)" "go clean -cache" ""
  have cargo && row cargo "$HOME/.cargo/registry" "cargo cache --autoclean（需 cargo-cache）或手動刪 registry/cache" "各專案 target/ 屬於「可重建產物」範圍"
  row gradle "$gradle_home/caches" "gradle --stop && rm -rf \"$gradle_home/caches\"" "下次 build 重新下載"
  row maven "$HOME/.m2/repository" "rm -rf ~/.m2/repository" "連本機 mvn install 的 SNAPSHOT／內部 artifact 一起刪，那些要從原始碼重建；只清單一專案依賴可用 mvn dependency:purge-local-repository"
  have brew  && row homebrew "$(q brew --cache)" "brew cleanup -s --prune=all（先跑 brew cleanup -n 預覽）" "大小只含下載 cache；另會移除舊版本 keg（pin 住的除外），實際釋放可能更多"
  row xcode-deriveddata "$lib/Developer/Xcode/DerivedData" "rm -rf ~/Library/Developer/Xcode/DerivedData/*" "先關 Xcode"
  row xcode-archives "$lib/Developer/Xcode/Archives" "（逐個確認，含發版用的 dSYM）" "不建議整批刪"
  row ios-device-support "$lib/Developer/Xcode/iOS DeviceSupport" "刪掉舊 iOS 版本的子目錄" ""
  have xcrun  && row simulators "$lib/Developer/CoreSimulator/Devices" "xcrun simctl delete unavailable" "只刪已不支援的模擬器"
  row playwright "$lib/Caches/ms-playwright" "npx playwright uninstall --all" ""
  row playwright "$cache/ms-playwright" "npx playwright uninstall --all" ""
  row huggingface "$cache/huggingface" "huggingface-cli delete-cache" "互動式挑選要刪的模型"
} 2>/dev/null | sort -t$'\t' -k2,2nr > "$tmp/rows"

printf 'tool\tsize_kb\tpath\tclean_command\tnote\n'
cat "$tmp/rows"

# Docker 的空間在 VM 磁碟映像裡，du 看不準，改看 docker system df
if have docker && q docker info >/dev/null; then
  echo "# docker system df（清理：docker system prune；加 -a 連未使用的 image、加 --volumes 連 volume，volume 可能有資料）："
  q docker system df | sed 's/^/#   /'
elif have docker; then
  echo "# docker：daemon 沒在跑，略過（Docker Desktop 的磁碟映像本身也可能很大）"
fi
