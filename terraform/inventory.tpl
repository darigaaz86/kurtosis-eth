[chain_node]
${chain_ip} ansible_user=${user} ansible_ssh_private_key_file=${key_file} ansible_python_interpreter=/usr/bin/python3

[tps_node]
${tps_ip} ansible_user=${user} ansible_ssh_private_key_file=${key_file} ansible_python_interpreter=/usr/bin/python3 chain_ip=${chain_ip}

[ethereum_testnet:children]
chain_node
tps_node
