#!/usr/bin/env bash
# M4-3 交互点演示脚本（docs/m4-interactive-session-design.md）：
# 输出几行 → 提问（stdout 匹配任务定义的 INTERACT_CONTINUE? 模式）→
# 读 stdin 等手机选择 → 按选择走不同分支收尾。
echo "interaction demo started"
sleep 2
echo "INTERACT_CONTINUE?"
read -r answer
if [ "$answer" = "yes" ]; then
  echo "user chose yes - finishing successfully"
  exit 0
else
  echo "user chose no - exiting with failure code"
  exit 3
fi
