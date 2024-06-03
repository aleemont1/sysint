#!/bin/bash
echo "Creating base Debian image with network utilities"

# Check if the container exists before attempting to kill and remove it
if [ "$(docker ps -q -f name=debian_base_networking)" ]; then
    docker kill debian_base_networking
fi

docker build -t $USER/debian_with_network_utilities .

for container in Ca Cb; do
	if [ "$(docker ps -q -f name=$container)" ]; then
		echo "Killing running docker container ${container}"
    	read -p "Are you sure? (Y/n): " confirm
    	confirm=${confirm:-Y}
        if [[ $confirm =~ ^[Yy]$ ]]; then
            docker kill $container
        fi
    fi
    if [ "$(docker ps -aq -f name=$container)" ]; then
		echo "Removing existing docker container ${container}"
		read -p "Are you sure? (Y/n): " confirm
		confirm=${confirm:-Y}
		if [[ $confirm =~ ^[Yy]$ ]]; then
			docker rm $container
		fi
  	fi
done



for network in N100 N200; do
	if [ "$(docker network ls -q -f name=${network})" ]; then
		echo "Removing existing docker network ${network}"
		read -p "Are you sure? (Y/n): " confirm
		confirm=${confirm:-Y}
		if [[ $confirm =~ ^[Yy]$ ]]; then
			docker network rm $network
		fi
	fi
done

echo "Creating Docker networks"
docker network create -d bridge -o "com.docker.network.bridge.name=br100" -o "com.docker.network.bridge.enable_ip_masquerade=true" --subnet 10.0.100.0/24 --ip-range=10.0.100.0/24  --gateway 10.0.100.1  N100
docker network create -d bridge -o "com.docker.network.bridge.name=br200" --subnet 10.0.200.0/24 --ip-range 10.0.200.0/24 --gateway 10.0.200.1 N200
ifconfig
echo "Creating Docker containers"

docker run -itd --network N100 --ip 10.0.100.10 --name Ca --cap-add NET_ADMIN $USER/debian_with_network_utilities
docker run -itd --network N200 --ip 10.0.200.20 --name Cb --cap-add NET_ADMIN $USER/debian_with_network_utilities
docker ps
echo "Connecting Ca to network N200"
docker network connect --ip 10.0.200.21 N200 Ca
docker exec Ca ip route
docker exec Cb ip route
echo "Deleting default route from Cb"
docker exec Cb ip route del default
echo "Adding new route for Cb via Ca"
docker exec Cb ip route add default dev eth0 via 10.0.200.21
echo "Current routes for Ca and Cb"
docker exec Ca ip route
docker exec Cb ip route
echo "Creating new netfilter rule to enable packet masquerading in Ca"
docker exec Ca iptables -t nat -L
docker exec Ca iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
echo "Testing functionality"
docker exec Cb ping -c 5 130.136.1.110
