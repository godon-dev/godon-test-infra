<!--
Copyright (c) 2019 Matthias Tafelmeier.

This file is part of godon

godon is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as
published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version.

godon is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this godon. If not, see <http://www.gnu.org/licenses/>.
-->
# Godon Test Session Coordinator

## config

> config generation auxiliary logic

### config generate

#### config generate observability

> generate helm value overrides for godon-observability chart with dynamic test VM scrape targets

~~~bash
set -eEux

__kcli_cmd="mask --maskfile ${MASKFILE_DIR}/maskfile.md util kcli run"

__target_ip_addresses_array=($(${__kcli_cmd} "list vm" | grep 'micro_stack' | awk -F\| '{ print $4 }' | xargs))

if [ ${#__target_ip_addresses_array[@]} -lt 2 ]; then
    echo "error: expected at least 2 VMs, found ${#__target_ip_addresses_array[@]}" >&2
    exit 1
fi

cat << EOF > "${MASKFILE_DIR}/observability-override.yaml"
prometheus:
  enabled: true
  server:
    hostNetwork: true
  extraScrapeConfigs: |
    - job_name: 'socket_statistics'
      scrape_interval: 500ms
      scrape_timeout: 400ms
      static_configs:
        - targets:
          - '${__target_ip_addresses_array[0]}:8090'
          - '${__target_ip_addresses_array[1]}:8090'
          labels:
            vm_role: 'source'
    - job_name: 'godon-metrics-exporter'
      scrape_interval: 5s
      static_configs:
        - targets:
          - 'godon-metrics-exporter.godon.svc.cluster.local:9099'
EOF

echo "generated ${MASKFILE_DIR}/observability-override.yaml"

~~~

#### config generate breeder (output_file)

> config generator for breeder test run

~~~bash
set -eEux

__template_file="${MASKFILE_DIR}/../examples/network.yml"
__kcli_cmd="mask --maskfile ${MASKFILE_DIR}/maskfile.md util kcli run"

 ## generate breeder test run config from running instances
__target_ip_addresses_array=($(${__kcli_cmd} "list vm" | grep 'micro_stack' | awk -F\| '{ print $4 }' | xargs))


  ## empty existing targets
cat "${__template_file}" | yq '.breeder.effectuation.targets |= []' - > ${output_file}

for __target_ip_address in ${__target_ip_addresses_array[@]}
do
  export target_object="{ "user": "godon_robot", "key_file": "/opt/airflow/credentials/id_rsa", "address": "${__target_ip_address}" }"
  yq -i '.breeder.effectuation.targets += env(target_object)' "${output_file}"
done

~~~



## observability

> observability stack deployment via godon-observability helm chart

### observability deploy

> deploy or upgrade godon-observability helm release with test VM scrape targets

~~~bash
set -eEux

__release_name="godon-observability"
__namespace="godon-observability"
__chart="godon-observability"
__override_file="${MASKFILE_DIR}/observability-override.yaml"

if [ ! -f "${__override_file}" ]; then
    echo "error: ${__override_file} not found - run 'config generate observability' first" >&2
    exit 1
fi

helm upgrade --install "${__release_name}" "${__chart}" \
    --namespace "${__namespace}" \
    --create-namespace \
    -f "${__override_file}"

~~~

### observability cleanup

> remove godon-observability helm release

~~~bash
set -eEux

__release_name="godon-observability"
__namespace="godon-observability"

helm uninstall "${__release_name}" --namespace "${__namespace}" || true

~~~



## infra

> micro infrastructure stack related logic

### infra create

#### infra create machines

> Instanciate Micro Test Infra Stack machines based on kcli/libvirt

~~~bash
set -eEux

__plan_name=micro_stack
__kcli_cmd="mask --maskfile ${MASKFILE_DIR}/maskfile.md util kcli run"

echo "instanciating machines"
${__kcli_cmd} "create plan -f ./infra/machines/plan.yml ${__plan_name}"

sleep 10

${__kcli_cmd} "list plan"
${__kcli_cmd} "list vm"

~~~

#### infra create network

> Errect micro test network

~~~bash
set -eEux

 # improvised since of mininet disarray and kcli work ongoing
 # create link between switches

link_instance_to_switch() {

    __instance="${1}"
    __switch="${2}"
    __port_name="${3}"

     # render libvirt to ovs link config
    __link_template="${MASKFILE_DIR}/infra/libvirt/network/ovs_link_template.xml"
    __link_definition="${MASKFILE_DIR}/infra/libvirt/network/ovs_link.xml"
    export __switch
    export __port_name
    envsubst < "${__link_template}" > "${__link_definition}"


    virsh attach-device --domain "${__instance}" \
                        --file "${__link_definition}" \
                        --persistent
}

ip link add veth_port_0 type veth peer name veth_port_1

for switch_number in $(seq 0 1)
do
    switch_name="switch_${switch_number}"

    # connect 
    ovs-vsctl add-br "${switch_name}"
    ovs-vsctl add-port "${switch_name}" "veth_port_${switch_number}"

    # activate
    ip link set "${switch_name}" up
    ip link set "veth_port_${switch_number}" up
done

tc qdisc add dev veth_port_0 root netem rate 10mbit delay 4ms

link_instance_to_switch "source_vm" "switch_0" "source_vm_port"
link_instance_to_switch "sink_vm" "switch_1" "sink_vm_port"

~~~

### infra cleanup

#### infra cleanup machines

> Cleanup libvirt based test instances

~~~bash
set -eEux

__kcli_cmd="mask --maskfile ${MASKFILE_DIR}/maskfile.md util kcli run"

${__kcli_cmd} "delete plan -y micro_stack"
~~~

#### infra cleanup network

> Cleanup micro test network

~~~bash
set -eEux


for switch_number in $(seq 0 1)
do
    switch_name="switch_${switch_number}"
    ovs-vsctl del-br "${switch_name}" || exit 0
done

ip link del veth_port_0 || exit 0

~~~

### infra provision

#### infra provision machines

> Provision Test Infra Machine Instances

~~~bash
set -eEux

__plan_name=micro_stack
__kcli_cmd="mask --maskfile ${MASKFILE_DIR}/maskfile.md util kcli run"

echo "provisioning infra instances"

~~~

## testing

### testing perform

> Orchestrate and Perform Session of Test Run

~~~bash
set -eEux

echo "performing tests"
__kcli_cmd="mask --maskfile ${MASKFILE_DIR}/maskfile.md util kcli run"
__ssh_cmd="ssh -o UserKnownHostsFile=/dev/null -o GlobalKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -i ${MASKFILE_DIR}/infra/credentials/ssh/id_rsa_robot"

__source_vm_ip_address=($(${__kcli_cmd} "list vm" | grep 'micro_stack' | grep 'source' | awk -F\| '{ print $4 }' | xargs))
__sink_vm_ip_address=($(${__kcli_cmd} "list vm" | grep 'micro_stack' | grep 'sink' | awk -F\| '{ print $4 }' | xargs))

__sink_vm_test_iface_ip_address=($(${__ssh_cmd} "godon_robot@${__sink_vm_ip_address}" "ip --json a show dev ens8  | jq '.[0].addr_info[0].local'"))

${__ssh_cmd} "godon_robot@${__sink_vm_ip_address}" "sudo systemctl stop test-server; sudo systemctl start test-server"

${__ssh_cmd} "godon_robot@${__source_vm_ip_address}" "echo "SINK_IP=${__sink_vm_test_iface_ip_address}" > /home/test/sink_ip"
${__ssh_cmd} "godon_robot@${__source_vm_ip_address}" "sudo systemctl stop test-client; sudo systemctl start test-client"


~~~

## util

> Test flow utilities 

### util kcli 

> kcli specific wrappers

#### util kcli run (cmd)

> kcli invocation wrapper 

~~~bash
set -eEux

container_name="quay.io/karmab/kcli:22.07"
pool_dir="/github-runner/artifacts/"

docker run --net host --rm \
           -t -a stdout -a stderr \
           -v ${pool_dir}:${pool_dir} \
           -v /var/run/libvirt:/var/run/libvirt \
           -v  ${MASKFILE_DIR}:/workdir \
           ${container_name} ${cmd}

~~~
