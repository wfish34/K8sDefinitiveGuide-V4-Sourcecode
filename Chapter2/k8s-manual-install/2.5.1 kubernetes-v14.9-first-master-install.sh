WEB_SERVER="172.17.11.2"
IP_ADDR=$(ifconfig | grep 172.17.11. | awk '{print $2}')
HOST_NAME=$(hostname -s)
K8S_VERSION="v14u9"

yum install wget -q bash-completion net-tools bind-utils vim mtr tree wget -q bridge-utils -y -q
sed -i 's/^selinux=\.*/selinux=diabled/g' /etc/selinux/config
systemctl stop firewalld
systemctl disable firewalld

cat > /etc/hosts <<-EOF
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6
172.17.11.21 master01 master01.lab11.com
172.17.11.31 node01 node01.lab11.com
172.17.11.32 node02 node02.lab11.com
EOF


mkdir /opt/k8s/{cfg,ssl,bin} -p

cd /opt/k8s/bin/
rm -rf /opt/k8s/bin/*
wget -q http://${WEB_SERVER}/k8s/${K8S_VERSION}/kube-apiserver
wget -q http://${WEB_SERVER}/k8s/${K8S_VERSION}/kube-controller-manager
wget -q http://${WEB_SERVER}/k8s/${K8S_VERSION}/kube-scheduler
wget -q http://${WEB_SERVER}/k8s/${K8S_VERSION}/kubectl
wget -q http://${WEB_SERVER}/k8s/${K8S_VERSION}/kube-proxy
wget -q http://${WEB_SERVER}/k8s/${K8S_VERSION}/etcd
wget -q http://${WEB_SERVER}/k8s/${K8S_VERSION}/etcdctl
wget -q http://${WEB_SERVER}/k8s/${K8S_VERSION}/flanneld
wget -q http://${WEB_SERVER}/k8s/${K8S_VERSION}/mk-docker-opts.sh -O /opt/k8s/bin/mk-docker-opts.sh
chmod +x /opt/k8s/bin/*


mkdir ~/k8s/
cd ~/k8s/
wget -q http://${WEB_SERVER}/k8s/${K8S_VERSION}/cfssl_linux-amd64
wget -q http://${WEB_SERVER}/k8s/${K8S_VERSION}/cfssljson_linux-amd64
wget -q http://${WEB_SERVER}/k8s/${K8S_VERSION}/cfssl-certinfo_linux-amd64
chmod +x cfssl_linux-amd64 cfssljson_linux-amd64 cfssl-certinfo_linux-amd64
mv -f cfssl_linux-amd64 /usr/local/bin/cfssl
mv -f cfssljson_linux-amd64 /usr/local/bin/cfssljson
mv -f cfssl-certinfo_linux-amd64 /usr/bin/cfssl-certinfo

echo "PATH=/opt/k8s/bin/:\$PATH" > /etc/profile.d/k8s.sh
echo "source <(kubectl completion bash)" > /etc/profile.d/kubectl.sh
. /etc/profile.d/k8s.sh
. /etc/profile.d/kubectl.sh

cd /opt/k8s/ssl
rm -rf /opt/k8s/ssl/*
cat > etcd-ca-config.json <<-EOF
{
    "signing": {
    "default": {
        "expiry": "87600h"
    },
    "profiles": {
        "etcd": {
        "expiry": "87600h",
        "usages": [
            "signing",
            "key encipherment",
            "server auth",
            "client auth"
        ]
        }
    }
    }
}
EOF

cat > etcd-ca-csr.json <<-EOF
{
    "CN": "etcd CA",
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
            "C": "CN",
            "L": "Shanghai",
            "ST": "Shanghai"
        }
    ]
}
EOF


cat > etcd-server-csr.json <<-EOF
{
    "CN": "etcd",
    "hosts": [
    "172.17.11.21",
    "master01.lab11.com"
    ],
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
            "C": "CN",
            "L": "Shanghai",
            "ST": "Shanghai"
        }
    ]
}
EOF


cfssl gencert -initca etcd-ca-csr.json | cfssljson -bare etcd-ca

cfssl gencert -ca=etcd-ca.pem -ca-key=etcd-ca-key.pem -config=etcd-ca-config.json -profile=etcd etcd-server-csr.json | cfssljson -bare etcd-server


cd /opt/k8s/ssl
cat > /opt/k8s/ssl/k8s-ca-config.json <<-EOF
{
  "signing": {
    "default": {
      "expiry": "87600h"
    },
    "profiles": {
      "kubernetes": {
         "expiry": "87600h",
         "usages": [
            "signing",
            "key encipherment",
            "server auth",
            "client auth"
        ]
      }
    }
  }
}
EOF

cat > /opt/k8s/ssl/k8s-ca-csr.json <<-EOF
{
    "CN": "kubernetes",
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
            "C": "CN",
            "L": "Shanghai",
            "ST": "Shanghai",
            "O": "k8s",
            "OU": "System"
        }
    ]
}
EOF

cat > /opt/k8s/ssl/k8s-server-csr.json <<-EOF
{
    "CN": "kubernetes",
    "hosts": [
      "172.17.11.21",
      "172.17.11.31",
      "172.17.11.32",
      "master01.lab11.com",
      "node01.lab11.com",
      "node02.lab11.com",
      "127.0.0.1",
      "10.254.0.1",
      "kubernetes",
      "kubernetes.default",
      "kubernetes.default.svc",
      "kubernetes.default.svc.cluster",
      "kubernetes.default.svc.cluster.local"
    ],
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
            "C": "CN",
            "L": "Shanghai",
            "ST": "Shanghai",
            "O": "k8s",
            "OU": "System"
        }
    ]
}
EOF

cat > /opt/k8s/ssl/kube-proxy-csr.json <<-EOF
{
  "CN": "system:kube-proxy",
  "hosts": [],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "L": "Shanghai",
      "ST": "Shanghai",
      "O": "k8s",
      "OU": "System"
    }
  ]
}
EOF


cfssl gencert -initca k8s-ca-csr.json | cfssljson -bare k8s-ca -

cfssl gencert -ca=k8s-ca.pem -ca-key=k8s-ca-key.pem -config=k8s-ca-config.json -profile=kubernetes k8s-server-csr.json | cfssljson -bare k8s-server

cfssl gencert -ca=k8s-ca.pem -ca-key=k8s-ca-key.pem -config=k8s-ca-config.json -profile=kubernetes kube-proxy-csr.json | cfssljson -bare kube-proxy


mkdir /data/etcd -p
cat > /opt/k8s/cfg/etcd.conf <<-EOF
#[Member]
ETCD_NAME="$HOST_NAME"
ETCD_DATA_DIR="/data/etcd"
ETCD_LISTEN_PEER_URLS="https://$IP_ADDR:2380"
ETCD_LISTEN_CLIENT_URLS="https://$IP_ADDR:2379"

#[Clustering]
ETCD_INITIAL_ADVERTISE_PEER_URLS="https://$IP_ADDR:2380"
ETCD_ADVERTISE_CLIENT_URLS="https://$IP_ADDR:2379"
ETCD_INITIAL_CLUSTER="master01=https://172.17.11.21:2380"
ETCD_INITIAL_CLUSTER_TOKEN="etcd-cluster"
ETCD_INITIAL_CLUSTER_STATE="new"

#[Security]
ETCD_CERT_FILE="/opt/k8s/ssl/etcd-server.pem"
ETCD_KEY_FILE="/opt/k8s/ssl/etcd-server-key.pem"
ETCD_TRUSTED_CA_FILE="/opt/k8s/ssl/etcd-ca.pem"
ETCD_CLIENT_CERT_AUTH="true"
ETCD_PEER_CERT_FILE="/opt/k8s/ssl/etcd-server.pem"
ETCD_PEER_KEY_FILE="/opt/k8s/ssl/etcd-server-key.pem"
ETCD_PEER_TRUSTED_CA_FILE="/opt/k8s/ssl/etcd-ca.pem"
ETCD_PEER_CLIENT_CERT_AUTH="true"
EOF


cat > /usr/lib/systemd/system/etcd.service <<-EOF
[Unit]
Description=Etcd Server
After=network.target
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
WorkingDirectory=/data/etcd/
EnvironmentFile=-/opt/k8s/cfg/etcd.conf
# set GOMAXPROCS to number of processors
ExecStart=/bin/bash -c "GOMAXPROCS=\$(nproc) /opt/k8s/bin/etcd --name=\"\${ETCD_NAME}\" --data-dir=\"\${ETCD_DATA_DIR}\" --listen-client-urls=\"\${ETCD_LISTEN_CLIENT_URLS}\" --listen-peer-urls=\"\${ETCD_LISTEN_PEER_URLS}\" --advertise-client-urls=\"\${ETCD_ADVERTISE_CLIENT_URLS}\" --initial-cluster-token=\"\${ETCD_INITIAL_CLUSTER_TOKEN}\" --initial-cluster=\"\${ETCD_INITIAL_CLUSTER}\" --initial-cluster-state=\"\${ETCD_INITIAL_CLUSTER_STATE}\" --cert-file=\"\${ETCD_CERT_FILE}\" --key-file=\"\${ETCD_KEY_FILE}\" --trusted-ca-file=\"\${ETCD_TRUSTED_CA_FILE}\" --client-cert-auth=\"\${ETCD_CLIENT_CERT_AUTH}\" --peer-cert-file=\"\${ETCD_PEER_CERT_FILE}\" --peer-key-file=\"\${ETCD_PEER_KEY_FILE}\" --peer-trusted-ca-file=\"\${ETCD_PEER_TRUSTED_CA_FILE}\" --peer-client-cert-auth=\"\${ETCD_PEER_CLIENT_CERT_AUTH}\""
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF



cat > /opt/k8s/cfg/token.csv <<-EOF
f2c50331f07be89278acdaf341ff1ecc,kubelet-bootstrap,10001,"system:kubelet-bootstrap"
EOF

cat > /opt/k8s/cfg/kube-apiserver << EOF
KUBE_APISERVER_OPTS="--logtostderr=false \
--v=4 \
--etcd-servers=https://172.17.11.21:2379\
--insecure-bind-address=0.0.0.0 \
--insecure-port=8080 \
--bind-address=$IP_ADDR \
--secure-port=6443 \
--advertise-address=$IP_ADDR \
--allow-privileged=true \
--service-cluster-ip-range=10.254.0.0/16 \
--enable-admission-plugins=NamespaceLifecycle,LimitRanger,ServiceAccount,DefaultStorageClass,DefaultTolerationSeconds,MutatingAdmissionWebhook,ValidatingAdmissionWebhook,ResourceQuota \
--authorization-mode=RBAC,Node \
--enable-bootstrap-token-auth \
--token-auth-file=/opt/k8s/cfg/token.csv \
--service-node-port-range=30000-50000 \
--tls-cert-file=/opt/k8s/ssl/k8s-server.pem  \
--tls-private-key-file=/opt/k8s/ssl/k8s-server-key.pem \
--client-ca-file=/opt/k8s/ssl/k8s-ca.pem \
--service-account-key-file=/opt/k8s/ssl/k8s-ca-key.pem \
--etcd-cafile=/opt/k8s/ssl/etcd-ca.pem \
--etcd-certfile=/opt/k8s/ssl/etcd-server.pem \
--etcd-keyfile=/opt/k8s/ssl/etcd-server-key.pem \
--log-dir=/var/log/kube-apiserver"
EOF

cat > /usr/lib/systemd/system/kube-apiserver.service <<-EOF

[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/kubernetes/kubernetes

[Service]
EnvironmentFile=-/opt/k8s/cfg/kube-apiserver
ExecStart=/opt/k8s/bin/kube-apiserver \$KUBE_APISERVER_OPTS
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF




cat > /opt/k8s/cfg/kube-scheduler << EOF
KUBE_SCHEDULER_OPTS="--logtostderr=true --v=4 --master=127.0.0.1:8080 --leader-elect"
EOF

cat > /usr/lib/systemd/system/kube-scheduler.service <<-EOF

[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/kubernetes/kubernetes

[Service]
EnvironmentFile=-/opt/k8s/cfg/kube-scheduler
ExecStart=/opt/k8s/bin/kube-scheduler \$KUBE_SCHEDULER_OPTS
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF


cat > /opt/k8s/cfg/kube-controller-manager << EOF
KUBE_CONTROLLER_MANAGER_OPTS="--logtostderr=true \
--v=4 \
--master=127.0.0.1:8080 \
--leader-elect=true \
--address=127.0.0.1 \
--service-cluster-ip-range=10.254.0.0/16 \
--cluster-name=kubernetes \
--cluster-signing-cert-file=/opt/k8s/ssl/k8s-ca.pem \
--cluster-signing-key-file=/opt/k8s/ssl/k8s-ca-key.pem  \
--root-ca-file=/opt/k8s/ssl/k8s-ca.pem \
--service-account-private-key-file=/opt/k8s/ssl/k8s-ca-key.pem"
EOF


cat > /usr/lib/systemd/system/kube-controller-manager.service <<-EOF
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/kubernetes/kubernetes

[Service]
EnvironmentFile=-/opt/k8s/cfg/kube-controller-manager
ExecStart=/opt/k8s/bin/kube-controller-manager \$KUBE_CONTROLLER_MANAGER_OPTS
Restart=on-failure

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
FLANNEL_OPTIONS="--etcd-endpoints=https://172.17.11.21:2379 -etcd-cafile=/opt/k8s/ssl/etcd-ca.pem -etcd-certfile=/opt/k8s/ssl/etcd-server.pem -etcd-keyfile=/opt/k8s/ssl/etcd-server-key.pem -etcd-prefix=/opt/k8s/network"
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
systemctl enable etcd
#systemctl start etcd

systemctl daemon-reload
systemctl enable kube-apiserver
#systemctl start kube-apiserver

systemctl daemon-reload
systemctl enable kube-controller-manager
#systemctl start kube-controller-manager

systemctl daemon-reload
systemctl enable kube-scheduler
#systemctl start kube-scheduler

systemctl daemon-reload
systemctl enable kube-proxy
systemctl enable flanneld
systemctl start flanneld
systemctl start kube-proxy


ssh node01 mkdir /opt/k8s/{cfg,ssl,bin} -p
ssh node02 mkdir /opt/k8s/{cfg,ssl,bin} -p

scp /opt/k8s/ssl/* node01:/opt/k8s/ssl/
scp /opt/k8s/ssl/* node02:/opt/k8s/ssl/
