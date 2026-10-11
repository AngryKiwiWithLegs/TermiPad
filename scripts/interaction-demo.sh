#!/usr/bin/env bash
# M4-3 interaction point demo script (docs/m4-interactive-session-design.md):
# print a few lines → ask (stdout matches the INTERACT_CONTINUE? pattern of the task definition) →
# read stdin and wait for the phone's choice → finish along a different branch depending on the choice.
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
