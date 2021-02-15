#!/bin/sh
PROGNAME=$0

namespace="kuma-system"

usage() {
  cat << EOF >&2

USAGE: 
  $PROGNAME 
   [-1 "name of first cluster, default is remote1"] 
   [-2 "name of second cluster, default is remote2"]

Example: $PROGNAME -1 gcp-us-east-1 -2 eks-europe-central-1

EOF
  exit 1
}

while getopts n:1:2: parameter; do
  case $parameter in
    1) first=${OPTARG};;
    2) second=${OPTARG};;
    *) usage;;
  esac
done

shift "$((OPTIND - 1))"

if [ -z "$first" ]; then
  first=remote1
fi
if [ -z "$second" ]; then
  second=remote2
fi
echo "Zone 1: $first"
echo "Zone 2: $second"

echo "Starting global cluster"
k3d cluster create KongMeshGlobal --k3s-server-arg '--no-deploy=traefik' -p '5681:31681@agent[0]' -p '5685:31685@agent[0]' --agents 1
kumactl install control-plane --mode=global | kubectl apply -f -
kubectl apply -f global-control-plane-nodeport-services.yaml -n $namespace

echo "Starting first remote cluster"
k3d cluster create KongMeshRemote1 --k3s-server-arg '--no-deploy=traefik' -p '7681:31681@agent[0]' --agents 1
kumactl install control-plane \
  --mode=remote \
  --zone=$first \
  --ingress-enabled \
  --kds-global-address grpcs://host.k3d.internal:5685 | kubectl apply -f -
kumactl install dns | kubectl apply -f -

echo "Starting second remote cluster"
k3d cluster create KongMeshRemote2 --k3s-server-arg '--no-deploy=traefik' -p '8681:31681@agent[0]' --agents 1
kumactl install control-plane \
  --mode=remote \
  --zone=$second \
  --ingress-enabled \
  --kds-global-address grpcs://host.k3d.internal:5685 | kubectl apply -f -
kumactl install dns | kubectl apply -f -

kumactl config control-planes add --name k3d-zones --address http://localhost:5681 --overwrite
kubectl config use-context k3d-KongMeshRemote1

echo ""
echo "*********************************************"
echo "Kuma settings"
echo ""
echo "kumactl has been configured with a new zone called k3d-zones and has been switched to use it"
echo "Kuma API is available at http://localhost:5681"
echo "Kuma GUI is available at http://localhost:5681/gui"
echo ""
echo "*********************************************"
echo "Kubernetes / kubectl"
echo "Switch to global control plane: kubectl config use-context k3d-KongMeshGlobal"
echo "Switch to $first control plane: kubectl config use-context k3d-KongMeshRemote1 (default)"
echo "Switch to $second control plane: kubectl config use-context k3d-KongMeshRemote2"
echo
echo ""
