#!/usr/bin/env bash
# scan-secrets.sh 的斷言測試：每類 secret 都要命中、常見的安全寫法不能誤報、遮罩後重掃要乾淨、原值不能出現在任何輸出。
# 假 token 一律在執行時拼出來，repo 裡不留長得像 token 的字串（避免觸發 push protection／secret scanning）。
# 手動：bash .agents/skills/_tracker/evals/check-scan-secrets.sh
set -u
here=$(cd "$(dirname "$0")" && pwd)
scan="$here/../scan-secrets.sh"
pass=0 fail=0
rep() { printf "%${2}s" "" | tr ' ' "$1"; }   # rep <字元> <次數>
ok()  { pass=$((pass+1)); }
bad() { fail=$((fail+1)); echo "✗ $1"; }

# 應命中：<類別> <內容>
hit() {
  local kind=$1 text=$2 out err rc
  err=$(printf '%s\n' "$text" | bash "$scan" check 2>&1 >/dev/null); rc=$?
  [ "$rc" = 1 ] && printf '%s' "$err" | grep -qF "$kind" || { bad "應命中 ${kind}（rc=${rc}，stderr=${err}）"; return; }
  out=$(printf '%s\n' "$text" | bash "$scan" redact 2>/dev/null)
  printf '%s' "$out" | grep -qF "[REDACTED:${kind}]" || { bad "${kind}：redact 輸出沒有 [REDACTED:${kind}]"; return; }
  printf '%s\n' "$out" | bash "$scan" check >/dev/null 2>&1 || { bad "${kind}：遮罩後重掃仍命中"; return; }
  ok
}
# 不應命中
clean() {
  local text=$1 rc
  printf '%s\n' "$text" | bash "$scan" check >/dev/null 2>&1; rc=$?
  [ "$rc" = 0 ] && ok || bad "不應命中（rc=${rc}）：${text}"
}

A36=$(rep A 36); a20=$(rep a 20)
hit private_key       "$(printf -- '-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXktdjEAAAA\n-----END OPENSSH PRIVATE KEY-----')"
hit github_token      "push 用的 token 是 ghp_${A36}，已撤銷"
hit github_token      "github_pat_$(rep B 30)"
hit gitlab_token      "glpat-${a20}"
hit aws_access_key    "AKIA$(rep Q 16)"
hit slack_token       "xoxb-$(rep 1 12)-abc"
hit api_key           "sk-ant-${a20}x"
hit api_key           "AIza$(rep z 35)"
hit jwt               "eyJ$(rep h 10).eyJ$(rep p 10).$(rep s 12)"
hit url_credential    "DATABASE_URL=postgres://app:s3cretPassw0rd@db.internal:5432/app"
hit auth_header       "curl -H 'Authorization: Bearer ${a20}'"
hit auth_header       '"authorization": "Basic dXNlcjpwYXNz"'
hit bearer            "回應標頭帶了 bearer ${a20}xyz"
hit secret_assignment "DB_PASSWORD=hunter22"
hit secret_assignment '"api_key": "abcd1234efgh"'
hit secret_assignment "client_secret: q1w2e3r4"

clean 'curl -H "Authorization: Bearer $ACCESS_TOKEN"'
clean 'token: ${{ secrets.GITHUB_TOKEN }}'
clean 'password: <your-password>'
clean 'password: ********'
clean 'api_key: [REDACTED:api_key]'
clean 'TOKEN=${TOKEN:-}'
clean 'token 過期了，請重新登入'
clean 'password: required'
clean 'Co-Authored-By: Claude <noreply@anthropic.com>'
clean 'test_command: npm test'
clean 'https://github.com/owner/repo/pull/23'
clean 'git@github.com:owner/repo.git'
clean "commit $(rep f 40)"
clean 'pip install scikit-learn && sk-learn 不是 key'
clean '使用 `secret_assignment` 規則'

# 原值不能出現在 stderr（只報類別與筆數）
err=$(printf 'password=hunter22\n' | bash "$scan" check 2>&1 >/dev/null)
printf '%s' "$err" | grep -qF hunter22 && bad "stderr 洩漏原值" || ok
# 前綴保留、只遮罩值
out=$(printf 'Authorization: Bearer %s\n' "$a20" | bash "$scan" redact 2>/dev/null)
[ "$out" = "Authorization: Bearer [REDACTED:auth_header]" ] && ok || bad "前綴沒保留：$out"
# 多行內容其餘部分原樣保留（含中文）
out=$(printf '第一行\npassword=hunter22\n第三行\n' | bash "$scan" redact 2>/dev/null)
[ "$out" = "$(printf '第一行\npassword=[REDACTED:secret_assignment]\n第三行')" ] && ok || bad "其他行被改動：$out"
# 空輸入、錯誤用法
printf '' | bash "$scan" check >/dev/null 2>&1 && ok || bad "空輸入應為 exit 0"
bash "$scan" bogus </dev/null >/dev/null 2>&1; [ $? = 2 ] && ok || bad "錯誤用法應為 exit 2"

echo "scan-secrets：${pass} 通過，${fail} 失敗"
[ "$fail" = 0 ]
