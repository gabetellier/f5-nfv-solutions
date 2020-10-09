#!/bin/bash
echo '******Starting Additional Network Configuration******' >> /var/log/cloud/f5-vnf/cloud_config.log

echo 'Setting up DHCP to not accept foreign hostname'
tmsh modify  sys management-dhcp sys-mgmt-dhcp-config request-options delete { hostname }
vlan_params=""
selfip_params=""
vlan_name=""

logFile="/var/log/cloud/f5-vnf/cloud_config.log"
gateway_opt=""
msg=""
stat="FAILURE"

mgmt_mtu=" "${1}" "

#vlan vars
vlan_creates=" "${2}" "
vlan_names=" "${3}" "
vlan_tags=" "${4}" "
vlan_mtus=" "${5}" "
port_macs=" "${6}" "
vlan_nics=""
vlan_nic_count=" "${7}" "

self_port_lockdowns=" "${8}" "
self_ips=" "${9}" "
self_ip_names=''
self_ip_cidrs=" "${10}" "

#default gateway for vnf only:
#change arg number from 10 to 9
default_gateway=""${11}""

#cmp vlans
cmp_src_vlans=""${12}""
cmp_dst_vlans=""${13}""

tier=""${14}""

user=""${15}""
pwd=""${16}""

bgp_pgw_peer_ip=""${17}""
bgp_pgw_peer_as=""${18}""
bgp_egw_peer_ip=""${19}""
bgp_egw_peer_as=""${20}""

function set_vlan_params() {
    local vlan_opt=""
    local vlan=""

    if [[ "$vlan_nic" == "" && "$port_mac" == "None" ]]; then
        vlan_nic_ctr=$(( vlan_nic_index + 1 ))
        vlan_nic="1.${vlan_nic_ctr}"
    else
        vlan_nic=$(tmsh show sys mac-address | grep $port_mac |  awk -F' ' '{print $4}' |  sed -r 's/\s+//g')
    fi

    if [[ "$vlan_name" == "None" || "$vlan_name" == "" ]]; then
        vlan_name="${vlan_nic}_vlan"
    fi

    if [[ "$vlan_create" == "True" ]]; then
        if [ "$vlan_mtu" == "0" ]; then
            vlan_mtu=""
        elif [ "$vlan_mtu" == "None" ]; then
            vlan_mtu=",mtu:1500"
        else
            vlan_mtu=",mtu:$vlan_mtu"
        fi

        if [ "$vlan_tag" == "None" ]; then
            vlan_tag=""
        else
            vlan_tag=",tag:${vlan_tag}"
        fi
        vlan="name:${vlan_name},nic:${vlan_nic}${vlan_mtu}${vlan_tag}"
        vlan_opt="--vlan"
        vlan_params="${vlan_params} ${vlan_opt} ${vlan}"
    else
        vlan=""
        vlan_opt=""
        vlan_params="${vlan_params}"
    fi

}

function set_selfip_params() {
    case "$self_port_lockdown" in
        " " | "" | "None" | "allow-default" )
            self_port_lockdown=",allow:default"
            ;;
        "allow-all" )
            self_port_lockdown=",allow:all"
            ;;
        "allow-none" )
            self_port_lockdown=",allow:none"
            ;;
        * )
            self_port_lockdown=",allow:${self_port_lockdown//;/ }"
            ;;
    esac

    self_port_lockdown="${self_port_lockdown//allow-default/default}"
    self_port_lockdown="${self_port_lockdown//allow-all/all}"
    self_port_lockdown="${self_port_lockdown//allow-none/none}"

    if [[ "$self_ip_name" == "None" || "$self_ip_name" == "" ]]; then
        self_ip_name="${vlan_name}_self"
    fi

    selfip_params="${selfip_params} --self-ip name:${self_ip_name},address:${self_ip}/${self_ip_prefix},vlan:${vlan_name}""'""${self_port_lockdown}""'"
}

function set_vars() {

    # sanitize artifact [ ]  generated by heat for the list
    vlan_creates="${vlan_creates:1:${#vlan_creates}-2}"
    vlan_names=${vlan_names:1:${#vlan_names}-2}
    vlan_tags=${vlan_tags:1:${#vlan_tags}-2}
    vlan_mtus=${vlan_mtus:1:${#vlan_mtus}-2}
    vlan_nics=${vlan_nics:1:${#vlan_nics}-2}
    port_macs=${port_macs:1:${#port_macs}-2}

    # sanitize artifact [ ]  generated by heat for the list
    self_port_lockdowns=${self_port_lockdowns:1:${#self_port_lockdowns}-2}
    self_ips=${self_ips:1:${#self_ips}-2}
    self_ip_names=${self_ip_names:1:${#self_ip_names}-2}
    self_ip_cidrs=${self_ip_cidrs:1:${#self_ip_cidrs}-2}

    OIFS="$IFS"
    IFS=', '
    # sanitize artifact " generated by heat and read value into array var
    read -r -a creates <<< "${vlan_creates//\"}"
    read -r -a vlans <<< "${vlan_names//\"}"
    read -r -a tags <<< "${vlan_tags//\"}"
    read -r -a mtus <<< "${vlan_mtus//\"}"
    read -r -a nics <<< "${vlan_nics//\"}"
    read -r -a macs <<< "${port_macs//\"}"
    read -r -a portLockdowns <<< "${self_port_lockdowns//\"}"
    read -r -a ips <<< "${self_ips//\"}"
    read -r -a ipNames <<< "${self_ip_names//\"}"
    read -r -a cidrs <<< "${self_ip_cidrs//\"}"
    IFS="$OIFS"

    local counter=0
    while [[ $counter -lt $vlan_nic_count ]]; do
        vlan_create=${creates[$counter]}
        vlan_name=${vlans[$counter]}
        vlan_tag=${tags[$counter]}
        vlan_mtu=${mtus[$counter]}
        vlan_nic=${nics[$counter]}
        vlan_nic_index=$counter
        self_port_lockdown=${portLockdowns[$counter]}
        self_ip=${ips[$counter]}
        self_ip_name=${ipNames[$counter]}
        self_ip_cidr=${cidrs[$counter]}
        self_ip_prefix=${self_ip_cidr#*/}
        port_mac=${macs[$counter]}

        set_vlan_params
        set_selfip_params

        let counter+=1;
    done

    if [[ "$default_gateway" != "None" && "$default_gateway" != "" ]]; then
        default_gateway="${default_gateway}"
        gateway_opt="--default-gw"
    else
        default_gateway=""
        gateway_opt=""
    fi

    echo "onboard-network-nic: Vlan params: $vlan_params" >> /var/log/cloud/f5-vnf/cloud_config.log
    echo "onboard-network-nic: SelfIp params: $selfip_params" >> /var/log/cloud/f5-vnf/cloud_config.log
}

function onboard_network_run() {
    echo 'onboard-network-nic: Starting network.js call' >> /var/log/cloud/f5-vnf/cloud_config.log
    cmd="f5-rest-node /config/cloud/f5-vnf/node_modules/@f5devcentral/f5-cloud-libs/scripts/network.js "
    cmd+="-o ${logFile} "
    cmd+="--log-level debug "
    cmd+="--host localhost "
    cmd+="--user admin "
    cmd+="--password-url file:///config/cloud/f5-vnf/.adminPwd "
    cmd+="--password-encrypted "
    cmd+="${vlan_params} "
    cmd+="${selfip_params} "
    cmd+="${gateway_opt} ${default_gateway} "
    eval "$cmd"
}

function set_vlan_cmp() {
    IFS=','
    for vlan in ${cmp_src_vlans}; do
        echo "onboard-network-nic: Setting src cmp-hash on ${vlan} VLAN" >> /var/log/cloud/f5-vnf/cloud_config.log
        if tmsh modify net vlan ${vlan} cmp-hash src-ip; then
            echo "onboard-network-nic: Successfully updated src cmp-hash on ${vlan} VLAN" >> /var/log/cloud/f5-vnf/cloud_config.log
        else
            echo "onboard-network-nic: Could not update src cmp-hash on ${vlan} VLAN" >> /var/log/cloud/f5-vnf/cloud_config.log
        fi
    done

    for vlan in ${cmp_dst_vlans}; do
        echo "onboard-network-nic: Setting dst cmp-hash on ${vlan} VLAN" >> /var/log/cloud/f5-vnf/cloud_config.log
        if tmsh modify net vlan ${vlan} cmp-hash dst-ip; then
            echo "onboard-network-nic: Successfully updated dst cmp-hash on ${vlan} VLAN" >> /var/log/cloud/f5-vnf/cloud_config.log
        else
            echo "onboard-network-nic: Could not update dst cmp-hash on ${vlan} VLAN" >> /var/log/cloud/f5-vnf/cloud_config.log
        fi
    done
}

function enable_bgp() {
    if [[ "$bgp_pgw_peer_as" == "" ]]; then
        echo "onboard-network-nic: Not enabling BGP. Inputs not provided." >> /var/log/cloud/f5-vnf/cloud_config.log
        return 1
    elif [[ "$bgp_pgw_peer_ip" == "" ]]; then
        echo "onboard-network-nic: Not enabling BGP. Inputs not provided." >> /var/log/cloud/f5-vnf/cloud_config.log
        return 1
    elif [[ "$bgp_egw_peer_ip" == "" ]]; then
        echo "onboard-network-nic: Not enabling BGP. Inputs not provided." >> /var/log/cloud/f5-vnf/cloud_config.log
        return 1
    elif [[ "$bgp_egw_peer_as" == "" ]]; then
        echo "onboard-network-nic: Not enabling BGP. Inputs not provided." >> /var/log/cloud/f5-vnf/cloud_config.log
        return 1
    fi
    echo "onboard-network-nic: Enabling BGP on route domain 0" >> /var/log/cloud/f5-vnf/cloud_config.log

    if tmsh modify sys db tmrouted.tmos.routing value enable; then
         echo "onboard-network-nic: Enabled BGP on route domain 0" >> /var/log/cloud/f5-vnf/cloud_config.log
         sleep 5
    else
         echo "onboard-network-nic: Did not enable BGP on route domain 0" >> /var/log/cloud/f5-vnf/cloud_config.log
    fi

    echo "onboard-network-nic: Creating BGP object" >> /var/log/cloud/f5-vnf/cloud_config.log
    if [[ "$tier" == "dag" || "$tier" == "cgnat_offering" ]]; then
        # we are DAG, peer with PGW and EGW
        response=$(curl -skvvu $user:$(pwd) -w "%{http_code}" https://localhost/mgmt/tm/net/routing/bgp -H "Content-Type: application/json" -X POST -d '{"name": "f5Bgp", "localAs": "'"$bgp_pgw_peer_as"'", "addressFamily": [ {"name": "ipv4", "redistribute": [{"name": "kernel"}, {"name": "static"}]}, {"name": "ipv6", "redistribute": [{"name": "kernel"}]}]}'  -o /dev/null)

        if [[ "$response" == "200" ]]; then
             echo "onboard-network-nic: Created DAG BGP router" >> /var/log/cloud/f5-vnf/cloud_config.log
             sleep 5

             echo "onboard-network-nic: Setting up DAG PGW BGP peering" >> /var/log/cloud/f5-vnf/cloud_config.log
             response=$(curl -skvvu $user:$(pwd) -w "%{http_code}" https://localhost/mgmt/tm/net/routing/bgp/f5Bgp/neighbor -H "Content-Type: application/json" -X POST -d '{"name":"'"$bgp_pgw_peer_ip"'", "remoteAs" : "'"$bgp_pgw_peer_as"'"}'  -o /dev/null)

             if [[ "$response" == "200" ]]; then
                  echo "onboard-network-nic: Set up DAG PGW BGP peering" >> /var/log/cloud/f5-vnf/cloud_config.log
                  sleep 5
             else
                  echo "onboard-network-nic: Did not set up PGW DAG BGP peering: $response" >> /var/log/cloud/f5-vnf/cloud_config.log
             fi

             echo "onboard-network-nic: Setting up DAG EGW BGP peering" >> /var/log/cloud/f5-vnf/cloud_config.log
             response=$(curl -skvvu $user:$(pwd) -w "%{http_code}" https://localhost/mgmt/tm/net/routing/bgp/f5Bgp/neighbor -H "Content-Type: application/json" -X POST -d '{"name":"'"$bgp_egw_peer_ip"'", "remoteAs" : "'"$bgp_egw_peer_as"'"}'  -o /dev/null)

             if [[ "$response" == "200" ]]; then
                  echo "onboard-network-nic: Set up DAG EGW BGP peering" >> /var/log/cloud/f5-vnf/cloud_config.log
                  sleep 5
             else
                  echo "onboard-network-nic: Did not set up EGW DAG BGP peering: $response" >> /var/log/cloud/f5-vnf/cloud_config.log
             fi
        else
             echo "onboard-network-nic: Did not create DAG BGP router: $response" >> /var/log/cloud/f5-vnf/cloud_config.log
        fi
    else
        # we are VNF, only peer with PGW
        response=$(curl -skvvu $user:$(pwd) -w "%{http_code}" https://localhost/mgmt/tm/net/routing/bgp -H "Content-Type: application/json" -X POST -d '{"name": "f5Bgp","localAs": "'"$bgp_pgw_peer_as"'"}'  -o /dev/null)

        if [[ "$response" == "200" ]]; then
             echo "onboard-network-nic: Created VNF BGP router" >> /var/log/cloud/f5-vnf/cloud_config.log
             sleep 5

             echo "onboard-network-nic: Setting up VNF BGP peering" >> /var/log/cloud/f5-vnf/cloud_config.log
             response=$(curl -skvvu $user:$(pwd) -w "%{http_code}" https://localhost/mgmt/tm/net/routing/bgp/f5Bgp/neighbor -H "Content-Type: application/json" -X POST -d '{"name":"'"$bgp_pgw_peer_ip"'", "remoteAs" : "'"$bgp_pgw_peer_as"'"}'  -o /dev/null)

             if [[ "$response" == "200" ]]; then
                  echo "onboard-network-nic: Set up VNF PGW BGP peering" >> /var/log/cloud/f5-vnf/cloud_config.log
                  sleep 5
             else
                  echo "onboard-network-nic: Did not set up VNF PGW BGP peering: $response" >> /var/log/cloud/f5-vnf/cloud_config.log
             fi
        else
             echo "onboard-network-nic: Did not create VNF BGP router: $response" >> /var/log/cloud/f5-vnf/cloud_config.log
        fi
    fi
}

function modify_mtu {
    # CloudLibs does not support mtu parm for mgmt interface.
    [[ "$mgmt_mtu" =~ "None" ]] && mgmt_mtu="1500" || mgmt_mtu=$(echo -e "${mgmt_mtu}" | grep -o -E "[0-9]+")

    echo "onboard-network-nic: Changing MTU to default for management-route ($mgmt_mtu)" >> /var/log/cloud/f5-vnf/cloud_config.log
    ifconfig mgmt mtu $mgmt_mtu up
    tmsh modify sys management-route default mtu $mgmt_mtu
    sleep 4
}

function print_msg() {
    onboardNetworkErrorCount=$(tail "$logFile" | grep "Network setup error" -i -c)

    if [ "$onboardNetworkErrorCount" -gt 0 ]; then
        msg="Onboard-network command exited with error. See $logFile for details."
    else
        onboardNetworkFailureCount=$(tail "$logFile" | grep "network setup failed" -i -c)
        if [ "$onboardNetworkFailureCount" -gt 0 ]; then
            msg="Onboard-network command exited with failure. See $logFile for details."
        else
            msg="Onboard-network command exited without error."
        fi
    fi

    echo -e "$msg" >> /var/log/cloud/f5-vnf/cloud_config.log
}

function main() {
    set_vars
    onboard_network_run
    set_vlan_cmp
    enable_bgp
    modify_mtu
    print_msg
    echo '******Finished Additional Network Configuration******' >> /var/log/cloud/f5-vnf/cloud_config.log
}

main