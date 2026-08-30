#!/bin/zsh
set -euo pipefail

ACCOUNT_HOME=${HOME:?HOME is required}
INSTALLED_APP="$ACCOUNT_HOME/Applications/ChatGPT 额度.app"
LAUNCH_AGENT="$ACCOUNT_HOME/Library/LaunchAgents/com.frankzhang.chatgpt-quota-bar.plist"
USER_ID=$(id -u)

launchctl bootout "gui/$USER_ID" "$LAUNCH_AGENT" 2>/dev/null || true
rm -f "$LAUNCH_AGENT"
rm -rf "$INSTALLED_APP"

echo "已卸载 ChatGPT 额度菜单栏。"
read -r "?按回车关闭窗口。"
