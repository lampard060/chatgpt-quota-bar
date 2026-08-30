#!/bin/zsh
set -euo pipefail

PACKAGE_DIR=${0:A:h}
SOURCE_APP="$PACKAGE_DIR/ChatGPT 额度.app"
ACCOUNT_HOME=${HOME:?HOME is required}
INSTALL_DIR="$ACCOUNT_HOME/Applications"
INSTALLED_APP="$INSTALL_DIR/ChatGPT 额度.app"
LAUNCH_AGENTS_DIR="$ACCOUNT_HOME/Library/LaunchAgents"
LAUNCH_AGENT="$LAUNCH_AGENTS_DIR/com.frankzhang.chatgpt-quota-bar.plist"
USER_ID=$(id -u)

if [[ ! -d "$SOURCE_APP" ]]; then
  echo "未找到：$SOURCE_APP"
  read -r "?按回车退出。"
  exit 1
fi

mkdir -p "$INSTALL_DIR" "$LAUNCH_AGENTS_DIR"
rm -rf "$INSTALLED_APP"
ditto "$SOURCE_APP" "$INSTALLED_APP"

rm -f "$LAUNCH_AGENT"
plutil -create xml1 "$LAUNCH_AGENT"
plutil -insert Label -string "com.frankzhang.chatgpt-quota-bar" "$LAUNCH_AGENT"
plutil -insert ProgramArguments -array "$LAUNCH_AGENT"
plutil -insert ProgramArguments.0 -string "$INSTALLED_APP/Contents/MacOS/ChatGPTQuotaBar" "$LAUNCH_AGENT"
plutil -insert RunAtLoad -bool true "$LAUNCH_AGENT"
plutil -insert KeepAlive -dictionary "$LAUNCH_AGENT"
plutil -insert KeepAlive.SuccessfulExit -bool false "$LAUNCH_AGENT"
plutil -insert ProcessType -string "Interactive" "$LAUNCH_AGENT"
plutil -insert StandardOutPath -string "/tmp/com.frankzhang.chatgpt-quota-bar.log" "$LAUNCH_AGENT"
plutil -insert StandardErrorPath -string "/tmp/com.frankzhang.chatgpt-quota-bar.error.log" "$LAUNCH_AGENT"

launchctl bootout "gui/$USER_ID" "$LAUNCH_AGENT" 2>/dev/null || true
launchctl bootstrap "gui/$USER_ID" "$LAUNCH_AGENT"

echo "安装完成：$INSTALLED_APP"
echo "菜单栏将在几秒内显示额度。"
read -r "?按回车关闭窗口。"
