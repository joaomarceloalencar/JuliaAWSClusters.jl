# Auxiliary Functions.
function set_up_ssh_connection(cluster_name)
   # Criar chave interna pública e privada do SSH.
   chars = ['a':'z'; 'A':'Z'; '0':'9']
   random_suffix = join(chars[Random.rand(1:length(chars), 5)])
   internal_key_name = cluster_name * random_suffix
   run(`ssh-keygen -f /tmp/$internal_key_name -N ""`)
   private_key = base64encode(read("/tmp/$internal_key_name", String))
   public_key = base64encode(read("/tmp/$internal_key_name.pub", String))
  
   # Define o script que irá instalar a chave pública e privada no headnode e workers.
   user_data = "#!/bin/bash
echo $private_key | base64 -d > /home/ubuntu/.ssh/$cluster_name
echo $public_key | base64 -d > /home/ubuntu/.ssh/$cluster_name.pub
echo 'Host *
   IdentityFile /home/ubuntu/.ssh/$cluster_name
   StrictHostKeyChecking no' > /home/ubuntu/.ssh/config
cat /home/ubuntu/.ssh/$cluster_name.pub >> /home/ubuntu/.ssh/authorized_keys
chown -R ubuntu.ubuntu /home/ubuntu/.ssh
chmod 600 /home/ubuntu/.ssh/*
"
   [internal_key_name, user_data]
end

function create_params(cluster::Cluster, user_data_base64)
    instance_type = ""
    node_name = ""
    if cluster isa ManagerWorkers
        instance_type = cluster.instance_type_headnode
        node_name = "headnode"
    elseif cluster isa PeersWorkers
        instance_type = cluster.instance_type_peer
        node_name = "peer"
    end
    params = Dict(
        "InstanceType" => instance_type,
        "ImageId" => cluster.image_id,
        "KeyName" => cluster.key_name,
        "Placement" => Dict("GroupName" => cluster.environment.placement_group),
        "SecurityGroupId" => [cluster.environment.security_group_id],
        "SubnetId" => cluster.environment.subnet_id,    
        "TagSpecification" => 
            Dict(
                "ResourceType" => "instance",
                "Tag" => [Dict("Key" => "cluster", "Value" => cluster.name),
                          Dict("Key" => "Name", "Value" => node_name) ]
            ),
        "UserData" => user_data_base64,
    )
    params
end
 
function remove_temp_files(internal_key_name)
    run(`rm /tmp/$internal_key_name`)
    run(`rm /tmp/$internal_key_name.pub`)
end
 
function set_hostfile(cluster_nodes, internal_key_name)
    # Testando se a conexão SSH está ativa.
    for instance in keys(cluster_nodes)
        public_ip = Ec2.describe_instances(Dict("InstanceId" => cluster_nodes[instance]))["reservationSet"]["item"]["instancesSet"]["item"]["ipAddress"]
        connection_ok = false
        while !connection_ok
            try
                connect(public_ip, 22)
                connection_ok = true
            catch e
                println("Waiting for $instance to be acessible...")
                sleep(5)
            end
        end
    end

    # Criando o arquivo hostfile.
    hostfile_content = ""
    for instance in keys(cluster_nodes)
        private_ip = Ec2.describe_instances(Dict("InstanceId" => cluster_nodes[instance]))["reservationSet"]["item"]["instancesSet"]["item"]["privateIpAddress"]
        hostfile_content *= "$instance $private_ip\n"
    end

    # Atualiza o hostname e o hostfile.
    for instance in keys(cluster_nodes)
        public_ip = Ec2.describe_instances(Dict("InstanceId" => cluster_nodes[instance]))["reservationSet"]["item"]["instancesSet"]["item"]["ipAddress"]
        private_ip = Ec2.describe_instances(Dict("InstanceId" => cluster_nodes[instance]))["reservationSet"]["item"]["instancesSet"]["item"]["privateIpAddress"]
        run(`ssh -i /tmp/$internal_key_name -o StrictHostKeyChecking=no ubuntu@$public_ip "sudo hostnamectl set-hostname $instance"`)
        run(`ssh -i /tmp/$internal_key_name -o StrictHostKeyChecking=no ubuntu@$public_ip "echo '$hostfile_content' > /home/ubuntu/hostfile"`)
        run(`ssh -i /tmp/$internal_key_name -o StrictHostKeyChecking=no ubuntu@$public_ip "awk '{ print \$2 \" \" \$1 }' hostfile >> hosts.tmp"`)
        run(`ssh -i /tmp/$internal_key_name -o StrictHostKeyChecking=no ubuntu@$public_ip "sudo chown ubuntu:ubuntu /etc/hosts"`)
        run(`ssh -i /tmp/$internal_key_name -o StrictHostKeyChecking=no ubuntu@$public_ip "cat hosts.tmp >> /etc/hosts"`)
        run(`ssh -i /tmp/$internal_key_name -o StrictHostKeyChecking=no ubuntu@$public_ip "sudo chown root:root /etc/hosts"`)
        run(`ssh -i /tmp/$internal_key_name -o StrictHostKeyChecking=no ubuntu@$public_ip "rm hosts.tmp"`)
    end
end



