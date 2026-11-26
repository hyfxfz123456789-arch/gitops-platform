#!/usr/bin/env bash
set -euo pipefail
export NO_PROXY=192.168.119.61,127.0.0.1,localhost
export no_proxy="$NO_PROXY"
jenkins_url='http://192.168.119.65:30080'
cookie_jar="$(mktemp)"
trap 'rm -f "$cookie_jar"' EXIT
password="$(kubectl -n jenkins get secret jenkins -o jsonpath='{.data.jenkins-admin-password}' | base64 -d)"
crumb_json="$(curl --noproxy '*' -fsS -c "$cookie_jar" -b "$cookie_jar" -u "admin:${password}" -H 'Host: jenkins.lab' "${jenkins_url}/crumbIssuer/api/json")"
crumb="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["crumb"])' <<<"${crumb_json}")"
status="$(curl --noproxy '*' -sS -o /dev/null -w '%{http_code}' -b "$cookie_jar" -u "admin:${password}" -H 'Host: jenkins.lab' -H "Jenkins-Crumb: ${crumb}" -H 'Content-Type: application/xml' --data-binary @/root/codex/project-study/gitops-platform/agent-smoke.xml "${jenkins_url}/createItem?name=agent-smoke")"
if [[ "$status" != 200 && "$status" != 201 && "$status" != 400 ]]; then echo "create job HTTP ${status}"; exit 1; fi
status="$(curl --noproxy '*' -sS -o /dev/null -w '%{http_code}' -b "$cookie_jar" -u "admin:${password}" -H 'Host: jenkins.lab' -H "Jenkins-Crumb: ${crumb}" -X POST "${jenkins_url}/job/agent-smoke/build")"
echo "trigger build HTTP ${status}"
if [[ "$status" != 201 && "$status" != 302 ]]; then exit 1; fi
for attempt in $(seq 1 60); do
  build_json="$(curl --noproxy '*' -fsS -u "admin:${password}" -H 'Host: jenkins.lab' "${jenkins_url}/job/agent-smoke/lastBuild/api/json" 2>/dev/null || true)"
  if [[ -n "$build_json" ]]; then
    result="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("result") or "RUNNING")' <<<"${build_json}")"
    if [[ "$result" != RUNNING ]]; then
      echo "build result: ${result}"
      curl --noproxy '*' -fsS -u "admin:${password}" -H 'Host: jenkins.lab' "${jenkins_url}/job/agent-smoke/lastBuild/consoleText" | tail -25
      [[ "$result" == SUCCESS ]]
      exit $?
    fi
  fi
  sleep 5
done
echo 'build timed out after 5 minutes'
exit 1
