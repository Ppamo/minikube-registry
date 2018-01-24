#!/bin/bash

RED='\e[91m'
GREEN='\e[92m'
BLUE='\e[36m'
YELLOW='\e[93m'
RESET='\e[39m'
RESOURCESPATH=./res
KUBECTL=kubectl
DMACHINE=docker-machine
MINIKUBE=${MINIKUBE:-minikube}
OBJECTS="rs.kube-registry-v0.yaml svc.kube-registry.yaml ds.kube-registry-proxy.yaml"
CLEAN=${CLEAN:-0}
MACHINE=$(uname -o)

#

is_cygwin(){
	echo "$MACHINE" | grep "Cygwin" > /dev/null
	return $?
}

is_linux(){
	echo "$MACHINE" | grep "GNU/Linux" > /dev/null
	return $?
}

is_running(){
	$MINIKUBE status | grep "Running" > /dev/null
	return $?
}

signal_handler(){
	echo "- $$:$BASHPID "
	close_docker_tunnel
}

check_context(){
	CONTEXT=$($KUBECTL config current-context)
	if [ "$CONTEXT" != "minikube" ]
	then
		printf "$RED- ERROR: $KUBECTL context is not set to minikube. $RESET\n"
		exit -1
	fi
}

get_pod(){
	POD=$($KUBECTL get pod --namespace kube-system --no-headers \
		| grep -E "kube-registry-v0.+Running" \
		| awk '{ print $1}')
}

download_images(){
	printf "$YELLOW* Downloading register images$RESET\n"
	$MINIKUBE ssh << EOF
docker pull registry:2.5.1
docker pull gcr.io/google_containers/kube-registry-proxy:0.4
exit
EOF
echo
}

clean(){
	if [ $CLEAN -eq 1 ]
	then
		printf "$YELLOW* Deleting old objects from kubernetes$RESET\n"
		for object in $OBJECTS
		do
			name=$(basename $object .yaml)
			file="$RESOURCESPATH/$object"
			printf "$RED- Deleting $name$RESET\n"
			$KUBECTL delete -f $file > /dev/null
		done
		echo
	fi
}

create(){
	printf "$YELLOW* Creating new object$RESET\n"
	for object in $OBJECTS
	do
		name=$(basename $object .yaml)
		file="$RESOURCESPATH/$object"
		if $KUBECTL get -f ./$file > /dev/null 2>&1
		then
			printf "$BLUE- The object \"$name\" already exists$RESET\n"
		else
			printf "$BLUE- Creating object \"$name\"$RESET\n"
			$KUBECTL create -f $file > /dev/null
			if [ $? -ne 0 ]
			then
				printf "$RED- ERROR creating object \"$name\"$RESET\n"
				exit -1
			fi
		fi
	done
	echo
}

wait_for_pod(){
	printf "$YELLOW* Waiting for pod to start $BLUE"
	get_pod
	while [ -z "$POD" ]
	do
		printf "."
		sleep 1
		get_pod
	done
	printf "$RESET\n"
}

create_docker_tunnel(){
	printf "$YELLOW* Creating tunnel in docker machine$RESET\n"
	DOCKERIP=$($DMACHINE ip)
	CERTPATH=$(cygpath $DOCKER_CERT_PATH/id_rsa)
	ssh -fNM -S /tmp/.mk.control.socket -o ExitOnForwardFailure=yes -T -i $CERTPATH -R 5000:localhost:5000 docker@$DOCKERIP
	if [ $? -eq 0 ]
	then
		trap signal_handler SIGINT
	fi
	sleep 2
}

close_docker_tunnel(){
	printf "\n$YELLOW* Closing tunnel in docker machine $RESET\n"
	DOCKERIP=$($DMACHINE ip)
	CERTPATH=$(cygpath $DOCKER_CERT_PATH/id_rsa)
	ssh -S /tmp/.mk.control.socket -i $CERTPATH -O exit docker@$DOCKERIP
}

forward_port(){
	printf "$YELLOW* Forwarding port 5000 in registry $RESET\n
$GREEN* To end, press ctrl-C  $RESET\n\n"
	$KUBECTL port-forward $POD --namespace kube-system 5000:5000
}

#

is_running
if [ $? -ne 0 ]
then
	printf $RED"ERROR: Minikube is not running $RESET\n"
	exit -1
fi
check_context
download_images
clean
create
wait_for_pod
is_cygwin
if [ $? -eq 0 ]
then
	create_docker_tunnel
fi
forward_port
