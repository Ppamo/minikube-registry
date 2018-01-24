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
DEFAULT_NS="componentes comun geolocalizacion fundacional"
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
	minikube status | grep "Running" > /dev/null
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
		printf "$RED- ERROR: $KUBECTL no esta usando el contexto minikube. $RESET\n"
		exit -1
	fi
}

get_pod(){
	POD=$($KUBECTL get pod --namespace kube-system --no-headers \
		| grep -E "kube-registry-v0.+Running" \
		| awk '{ print $1}')
}

download_images(){
	printf "$YELLOW* Descargando imagenes requeridas por el registro$RESET\n"
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
		printf "$YELLOW* Eliminando objectos antiguos en kubernetes$RESET\n"
		for object in $OBJECTS
		do
			name=$(basename $object .yaml)
			file="$RESOURCESPATH/$object"
			printf "$RED- Eliminando objeto $name$RESET\n"
			$KUBECTL delete -f $file > /dev/null
		done
		echo
	fi
}

create(){
	printf "$YELLOW* Creando nuevos objetos$RESET\n"
	for ns in $DEFAULT_NS
	do
		if $KUBECTL get namespace $ns > /dev/null 2>&1
		then
			printf "$BLUE- El namespace \"$ns\" ya existe$RESET\n"
		else
			printf "$BLUE- Creando namespace \"$ns\"$RESET\n"
			$KUBECTL create namespace $ns > /dev/null
		fi
	done
	for object in $OBJECTS
	do
		name=$(basename $object .yaml)
		file="$RESOURCESPATH/$object"
		if $KUBECTL get -f ./$file > /dev/null 2>&1
		then
			printf "$BLUE- El objeto \"$name\" ya existe$RESET\n"
		else
			printf "$BLUE- Creando objecto \"$name\"$RESET\n"
			$KUBECTL create -f $file > /dev/null
			if [ $? -ne 0 ]
			then
				printf "$RED- ERROR creando objeto \"$name\"$RESET\n"
				exit -1
			fi
		fi
	done
	echo
}

wait_for_pod(){
	printf "$YELLOW* Esperando que el pod se inicie $BLUE"
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
	printf "$YELLOW* Creando tunel en el docker-nachine$RESET\n"
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
	printf "\n$YELLOW* Cerrando tunel ssh a maquina docker$RESET\n"
	DOCKERIP=$($DMACHINE ip)
	CERTPATH=$(cygpath $DOCKER_CERT_PATH/id_rsa)
	ssh -S /tmp/.mk.control.socket -i $CERTPATH -O exit docker@$DOCKERIP
}

forward_port(){
	printf "$YELLOW* Forwardeando puerto 5000 del registro $RESET\n
$GREEN* Para terminar presione control-C$RESET\n\n"
	$KUBECTL port-forward $POD --namespace kube-system 5000:5000
}

#

is_running
if [ $? -ne 0 ]
then
	printf $RED"ERROR: Minikube no esta corriendo $RESET\n"
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
