# K8s-Observability-Search-Engine-Lab
利用 Kubespray 建立 Elasticsearch 與 Kibana 服務，並練習透過 Prometheus 與 Grafana 觀察系統狀態（包含 VM、ES 叢集及容器資源），紀錄過程中的學習與心得。

🏗️ 實驗環境架構
| Column 1    | Column 2                                       |
| ----------- | ---------------------------------------------- |
| OS          | Ubuntu (via VM)                                |
| Cluster     | 3-Node Kubernetes (node1, node2, node3)        |
| Provisioner | Kubespray                                      |
| Stack       | Search: Elasticsearch, Kibana                  |
|             | Monitoring: Prometheus, Grafana, Node Exporter |
|             | Exporter: Elasticsearch Exporter               |

🛠️ 安裝與設定流程

第一階段：Kubespray 叢集建立

建議使用 Python 虛擬環境（virtualenv）以維持系統環境整潔。
```
# 1. 取得與初始化 Kubespray
git clone https://github.com/kubernetes-sigs/kubespray.git
cd kubespray
workon kubespray
pip install -r requirements.txt

# 2. 設定叢集資訊與 Addons
cp -rfp inventory/sample inventory/my-elk-cluster
# 修改 inventory/my-elk-cluster/hosts.yaml 以符合 Node IP
# 修改 inventory/my-elk-cluster/group_vars/k8s_cluster/addons.yml (啟用 helm 與 dashboard)

# 3. 部署 K8s 叢集
ansible-playbook -i inventory/my-elk-cluster/hosts.yaml --become --become-user=root cluster.yml -K
```

第二階段：環境基礎建設

在管理機 (VM 0) 設定 kubectl 與 helm：
```
# 取得 config 並修正權限
scp toor@<node1_ip>:/etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# 在各節點建立資料夾並賦權 (用於 Local PV)
for ip in 192.168.150.141 192.168.150.142 192.168.150.143; do 
  ssh -t toor@$ip "sudo mkdir -p /mnt/elastic-data && sudo chmod 777 /mnt/elastic-data"
done

# 安裝 Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

第三階段：部署 ELK Stack (Search Engine)

1.建立 PV: kubectl apply -f pv-elk.yaml
2.安裝 Elasticsearch:
```
helm repo add elastic https://helm.elastic.co
helm install elasticsearch elastic/elasticsearch -f values-es.yaml
```
3.安裝 Kibana:
```
. deploy-kibana.sh
```

第四階段：部署 Prometheus + Grafana (Monitoring)

除了基礎 K8s 監控，額外安裝 elasticsearch-exporter 以抓取 ES 效能指標。

```
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
kubectl create namespace monitoring

# 1. 安裝 Prometheus Stack
helm install prometheus prometheus-community/kube-prometheus-stack -n monitoring

# 2. 安裝 Elasticsearch Exporter (注意需配置帳密與 SSL 跳過驗證)
helm install elasticsearch-exporter prometheus-community/prometheus-elasticsearch-exporter \
  -n monitoring \
  --set es.uri=https://elastic:<password>@elasticsearch-master.default.svc.cluster.local:9200 \
  --set es.sslSkipVerify=true
```