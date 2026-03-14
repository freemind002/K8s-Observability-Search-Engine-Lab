#!/bin/bash

# ============================================================
# Kibana 自動化部署腳本 (K8s 學習環境專用版)
# ============================================================

# --- 設定參數 ---
KIBANA_IP="192.168.150.141"  # 換成你的 Node IP
KIBANA_PORT="30601"
KIBANA_SYSTEM_PW="kibanapassword"
RELEASE_NAME="kibana"

echo ">>> [Step 1/5] 清理環境：移除舊有的 Release 與殘留 Secret..."
helm uninstall $RELEASE_NAME --no-hooks 2>/dev/null
kubectl delete jobs -l release=$RELEASE_NAME --ignore-not-found
kubectl delete secret kibana-kibana-es-token kibana-server-tls --ignore-not-found

echo ">>> [Step 2/5] 建立安全防線：生成自簽 SSL 憑證 (HTTPS)..."
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout tls.key -out tls.crt \
  -subj "/CN=$KIBANA_IP"
kubectl create secret tls kibana-server-tls --cert=tls.crt --key=tls.key

echo ">>> [Step 3/5] 通訊授權：同步 Elasticsearch 後端密碼..."
ELASTIC_PW=$(kubectl get secrets elasticsearch-master-credentials -ojsonpath='{.data.password}' | base64 -d)
kubectl exec elasticsearch-master-0 -- curl -k -u "elastic:$ELASTIC_PW" \
  -X POST "https://localhost:9200/_security/user/kibana_system/_password" \
  -H "Content-Type: application/json" \
  -d "{\"password\":\"$KIBANA_SYSTEM_PW\"}"

echo ">>> [Step 4/5] 設定生成：建立輕量化 values-kibana-auto.yaml..."
cat <<EOF > values-kibana-auto.yaml
elasticsearchHosts: "https://elasticsearch-master:9200"
protocol: https

# 資源限制：避免佔用過多 Node 資源導致 Pending
resources:
  requests:
    cpu: "100m"
    memory: "512Mi"
  limits:
    cpu: "500m"
    memory: "1Gi"

extraEnvs:
  - name: "ELASTICSEARCH_SERVICEACCOUNTTOKEN"
    value: ""

kibanaConfig:
  kibana.yml: |
    server.ssl.enabled: true
    server.ssl.certificate: /usr/share/kibana/config/custom-certs/tls.crt
    server.ssl.key: /usr/share/kibana/config/custom-certs/tls.key
    elasticsearch.username: "kibana_system"
    elasticsearch.password: "$KIBANA_SYSTEM_PW"
    elasticsearch.ssl.verificationMode: none

secretMounts:
  - name: kibana-certs
    secretName: kibana-server-tls
    path: /usr/share/kibana/config/custom-certs

service:
  type: NodePort
  nodePort: $KIBANA_PORT
EOF

# 修補 Helm Chart 缺失的 Token Secret 佔位符
kubectl create secret generic kibana-kibana-es-token --from-literal=token=dummy --dry-run=client -o yaml | kubectl apply -f -

echo ">>> [Step 5/5] 執行部署：啟動 Helm Install..."
helm install $RELEASE_NAME elastic/kibana -f values-kibana-auto.yaml --no-hooks

echo ""
echo "============================================================"
echo " ✅ Kibana 部署指令發送成功！"
echo "============================================================"
echo " 1. 監控啟動進度:  kubectl get pods -w"
echo " 2. 查看連線日誌:  kubectl logs -f -l app=kibana"
echo " 3. 登入資訊如下:"
echo "    - 網址: https://$KIBANA_IP:$KIBANA_PORT"
echo "    - 帳號: elastic"
echo "    - 密碼: $ELASTIC_PW"
echo "============================================================"
echo "提示: 第一次啟動約需 2-3 分鐘，請耐心等候 Ready 1/1。"