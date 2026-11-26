# GitOps 实验平台（2026-11-01）

业务持续交付链路已完成，当前架构、发布门禁、回滚验证与面试讲述见 [DELIVERY.md](DELIVERY.md)。下文保留基础组件部署时的安装记录；其中“待完成的业务流水线”是当时的历史状态。

## 组件与入口

- GitLab：tool 主机 `https://192.168.119.166/`
- Harbor：tool 主机 `https://192.168.119.166:8443/`
- NGINX Ingress Controller：`ingress-nginx` 命名空间，工作节点 NodePort `30080`（HTTP）、`30443`（HTTPS）
- Argo CD：`argocd` 命名空间，登录请用 `https://192.168.119.65:30443/`；也支持 `https://argocd.lab:30443/`（需解析域名）。HTTP 30080 只用于入口连通性检查，Argo CD 的 Secure 会话 Cookie 无法在 HTTP 下维持登录。
- Jenkins：`jenkins` 命名空间，`http://jenkins.lab:30080/`，数据 PVC `jenkins`，`local-path` 8 GiB
- Metrics Server：`kube-system`，用于 `kubectl top` 和后续 HPA

2026-11-01 验证结果：4 个节点 Ready；Ingress 与 Argo CD Pod 正常；Jenkins `2/2 Running`；两个入口均返回 HTTP 200；`kubectl top nodes` 可用。`agent-smoke` 构建结果 `SUCCESS`，动态 Agent Pod 调度到 `k8s-node-04`，运行后已自动回收。

浏览器所在机器的 hosts 文件需配置：

```text
192.168.119.65 argocd.lab jenkins.lab
```

目前 HTTP 入口仅用于隔离实验网；正式接入凭据前应配置 TLS 和域名。

## 部署与检查命令

```bash
export NO_PROXY=192.168.119.61,127.0.0.1,localhost
export no_proxy="$NO_PROXY"
kubectl apply -f metrics-server.yaml
kubectl apply -f ingress-nginx.yaml
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply --server-side --force-conflicts -n argocd -f argocd-install.yaml
kubectl apply -f argocd-ingress.yaml
helm repo add jenkins https://charts.jenkins.io
helm repo update jenkins
helm upgrade --install jenkins jenkins/jenkins --version 5.10.9 --namespace jenkins --create-namespace -f jenkins-values.yaml
kubectl get pods -n ingress-nginx
kubectl get pods -n argocd
kubectl get pods,pvc,ingress -n jenkins
kubectl top nodes
curl --noproxy '*' --cacert /root/codex/project-study/harbor-lab-ca.crt -I https://192.168.119.65:30443/
curl --noproxy '*' -I -H 'Host: jenkins.lab' http://192.168.119.65:30080/login
./run-agent-smoke.sh
```

三个工作节点的 containerd systemd drop-in `/etc/systemd/system/containerd.service.d/proxy.conf` 使用现有代理拉镜像；CA `/usr/local/share/ca-certificates/harbor-lab-ca.crt` 用于信任 Harbor HTTPS。镜像预拉示例：

```bash
HTTPS_PROXY=http://192.168.1.5:10808 HTTP_PROXY=http://192.168.1.5:10808 ctr -n k8s.io images pull registry.k8s.io/metrics-server/metrics-server:v0.8.0
```

Ingress Controller 使用 `--default-ssl-certificate=ingress-nginx/gitops-lab-ingress-tls`。证书由实验 CA 签发，包含 `argocd.lab`、`jenkins.lab`、`demo.lab` 及各节点 IP。公网/生产环境应使用受客户端信任的证书。

Jenkins 的 Java 插件管理器需要 `JAVA_TOOL_OPTIONS` 中的 JVM 代理参数；仅设置 `HTTP_PROXY` 时部分镜像站连接会停滞。Metrics Server 因本实验集群 kubelet 证书缺少 IP SAN，使用了 `--kubelet-insecure-tls`。

## 凭据读取（不要复制到公开日志）

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
kubectl -n jenkins get secret jenkins -o jsonpath='{.data.jenkins-admin-password}' | base64 -d
```

两个账号初始用户名均为 `admin`。首次登录后更换密码。Jenkins Chart 的 Kubernetes 插件配置动态 Agent，Agent 使用 WebSocket 连接控制器。

## 待完成的业务流水线

将示例项目导入 GitLab 后，再创建 Jenkins Pipeline、Webhook、Harbor 镜像仓库及 GitOps 配置仓库，随后在 Argo CD 创建 Application，验证构建、扫描、推送、发布审批和回滚。当前基础组件部署不等于这些业务链路已验证。
