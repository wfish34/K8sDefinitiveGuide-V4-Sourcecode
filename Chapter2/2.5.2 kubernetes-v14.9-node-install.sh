yum install wget -q bash-completion net-tools bind-utils vim mtr tree wget -q bridge-utils -y -q
sed -i 's/^selinux=\.*/selinux=diabled/g' /etc/selinux/config
systemctl stop firewalld
systemctl disable firewalld

cat > /etc/hosts <<-EOF
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6
172.16.31.21 master01 master01.lab31.com
172.16.31.22 master02 master02.lab31.com
172.16.31.23 master03 master03.lab31.com
172.16.31.31 node01 node01.lab31.com
172.16.31.32 node02 node02.lab31.com
172.16.31.33 node03 node03.lab31.com
EOF


rm -rf /etc/yum.repos.d/docker-ce.repo
wget -q -O /etc/yum.repos.d/docker-ce.repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
rm -rf rpm-package-key.gpg
wget -q https://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg
rpm --import rpm-package-key.gpg


swapoff -a
sed -ie '/\<swap\>/d' /etc/fstab

yum install docker-ce -y -q

cat > /etc/docker/daemon.json <<-EOF
{
 "registry-mirrors": ["https://hsfthhg1.mirror.aliyuncs.com"]
}
EOF


systemctl daemon-reload
systemctl enable docker
systemctl restart docker

cat > /etc/sysctl.d/k8s.conf << EOF
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF

sysctl -p /etc/sysctl.d/k8s.conf


mkdir /opt/k8s/{cfg,ssl,bin} -p
#rm -rf /opt/k8s/ssl/*
cd /opt/k8s/bin/
rm -rf /opt/k8s/bin/*
wget -q http://172.16.21.10/k8s/v14u9/kubectl
wget -q http://172.16.21.10/k8s/v14u9/kube-proxy
wget -q http://172.16.21.10/k8s/v14u9/kubelet

wget -q http://172.16.21.10/k8s/v14u9/flanneld
wget -q http://172.16.21.10/k8s/v14u9/mk-docker-opts.sh -O /opt/k8s/bin/mk-docker-opts.sh

chmod +x /opt/k8s/bin/*

echo "PATH=/opt/k8s/bin/:\$PATH" > /etc/profile.d/k8s.sh
. /etc/profile.d/k8s.sh


cat > /opt/k8s/cfg/environment.sh <<-EOF
#!/bin/bash
#创建kubelet bootstrapping kubeconfig
BOOTSTRAP_TOKEN=f2c50331f07be89278acdaf341ff1ecc
KUBE_APISERVER="https://172.16.31.21:6443"

#设置集群参数
/opt/k8s/bin/kubectl config set-cluster kubernetes \
  --certificate-authority=/opt/k8s/ssl/k8s-ca.pem \
  --embed-certs=true \
  --server=\${KUBE_APISERVER} \
  --kubeconfig=bootstrap.kubeconfig

#设置客户端认证参数
/opt/k8s/bin/kubectl config set-credentials kubelet-bootstrap \
  --token=\${BOOTSTRAP_TOKEN} \
  --kubeconfig=bootstrap.kubeconfig

# 设置上下文参数
/opt/k8s/bin/kubectl config set-context default \
  --cluster=kubernetes \
  --user=kubelet-bootstrap \
  --kubeconfig=bootstrap.kubeconfig

# 设置默认上下文
/opt/k8s/bin/kubectl config use-context default --kubeconfig=bootstrap.kubeconfig

#----------------------
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

cd ~

IP_ADDR=$(ifconfig | grep 172.16.31 | awk '{print $2}')
HOST_NAME=$(hostname -s)

cat > /opt/k8s/cfg/kubelet.config <<-EOF
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
address: ${IP_ADDR}
port: 10250
readOnlyPort: 10255
cgroupDriver: cgroupfs
clusterDNS: ["10.254.0.10"]
clusterDomain: cluster.local.
failSwapOn: false
authentication:
  anonymous:
    enabled: true
EOF

cat > /opt/k8s/cfg/kubelet <<-EOF
KUBELET_OPTS="--logtostderr=true \
--v=4 \
--hostname-override=${HOST_NAME} \
--kubeconfig=/opt/k8s/cfg/kubelet.kubeconfig \
--bootstrap-kubeconfig=/opt/k8s/cfg/bootstrap.kubeconfig \
--config=/opt/k8s/cfg/kubelet.config \
--cert-dir=/opt/k8s/ssl"
EOF

cat > /usr/lib/systemd/system/kubelet.service <<-EOF
[Unit]
Description=Kubernetes Kubelet
After=docker.service
Requires=docker.service

[Service]
EnvironmentFile=/opt/k8s/cfg/kubelet
ExecStart=/opt/k8s/bin/kubelet \$KUBELET_OPTS
Restart=on-failure
KillMode=process

[Install]
WantedBy=multi-user.target
EOF

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

cat > /usr/lib/systemd/system/docker.service <<-EOF
[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com
After=network-online.target firewalld.service
Wants=network-online.target

[Service]
Type=notify
EnvironmentFile=/run/flannel/subnet.env
ExecStart=/usr/bin/dockerd \$DOCKER_NETWORK_OPTIONS
ExecReload=/bin/kill -s HUP \$MAINPID
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
TimeoutStartSec=0
Delegate=yes
KillMode=process
Restart=on-failure
StartLimitBurst=3
StartLimitInterval=60s

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl stop docker
systemctl enable kubelet
systemctl enable kube-proxy
systemctl enable flanneld
systemctl start flanneld
systemctl start docker
systemctl start kube-proxy
systemctl start kubelet

