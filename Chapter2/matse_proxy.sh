cat > /opt/k8s/cfg/environment.sh <<-EOF
#!/bin/bash
#创建kubelet bootstrapping kubeconfig
BOOTSTRAP_TOKEN=f2c50331f07be89278acdaf341ff1ecc
KUBE_APISERVER="https://172.16.31.21:6443"


# 创建kube-proxy kubeconfig文件
/opt/k8s/bin/kubectl config set-cluster kubernetes \
  --certificate-authority=/opt/k8s/ssl/k8s-ca.pem \
  --embed-certs=true \
  --server=\${KUBE_APISERVER} \
  --kubeconfig=kube-proxy.kubeconfig

/opt/k8s/bin/kubectl config set-credentials kube-proxy \
  --client-certificate=/opt/k8s/ssl/kube-proxy.pem \
  --client-key=/opt/k8s/ssl/kube-proxy-key.pem \
  --embed-certs=true \
  --kubeconfig=kube-proxy.kubeconfig

/opt/k8s/bin/kubectl config set-context default \
  --cluster=kubernetes \
  --user=kube-proxy \
  --kubeconfig=kube-proxy.kubeconfig

# 设置当前使用的上下文
/opt/k8s/bin/kubectl config use-context default --kubeconfig=kube-proxy.kubeconfig
EOF

cd /opt/k8s/cfg/
. /opt/k8s/cfg/environment.sh

IP_ADDR=$(ifconfig | grep 172.16.31 | awk '{print $2}')
HOST_NAME=$(hostname -s)
cat > /opt/k8s/cfg/kube-proxy <<-EOF
KUBE_PROXY_OPTS="--logtostderr=true \
--v=4 \
--hostname-override=${HOST_NAME} \
--cluster-cidr=10.254.0.0/16 \
--kubeconfig=/opt/k8s/cfg/kube-proxy.kubeconfig"
EOF


cat > /usr/lib/systemd/system/kube-proxy.service <<-EOF
[Unit]
Description=Kubernetes Proxy
After=network.target

[Service]
EnvironmentFile=-/opt/k8s/cfg/kube-proxy
ExecStart=/opt/k8s/bin/kube-proxy \$KUBE_PROXY_OPTS
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

cat > /opt/k8s/cfg/flanneld << EOF
FLANNEL_OPTIONS="--etcd-endpoints=https://172.16.31.21:2379,https://172.16.31.22:2379,https://172.16.31.23:2379 -etcd-cafile=/opt/k8s/ssl/etcd-ca.pem -etcd-certfile=/opt/k8s/ssl/etcd-server.pem -etcd-keyfile=/opt/k8s/ssl/etcd-server-key.pem -etcd-prefix=/opt/k8s/network"
EOF

cat > /usr/lib/systemd/system/flanneld.service <<-EOF
[Unit]
Description=Flanneld overlay address etcd agent
After=network-online.target network.target
Before=docker.service

[Service]
Type=notify
EnvironmentFile=/opt/k8s/cfg/flanneld
ExecStart=/opt/k8s/bin/flanneld --ip-masq \$FLANNEL_OPTIONS
ExecStartPost=/opt/k8s/bin/mk-docker-opts.sh -k DOCKER_NETWORK_OPTIONS -d /run/flannel/subnet.env
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF


systemctl daemon-reload
systemctl enable kube-proxy
systemctl enable flanneld
systemctl start flanneld
systemctl start kube-proxy
