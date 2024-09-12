
#=
Placement Group
=#
function create_placement_group(name)
    params = Dict(
        "GroupName" => name, 
        "Strategy" => "cluster",
        "TagSpecification" => 
            Dict(
                "ResourceType" => "placement-group",
                "Tag" => [Dict("Key" => "cluster", "Value" => name),
                          Dict("Key" => "Name", "Value" => name)]
            )
        )
    Ec2.create_placement_group(params)["placementGroup"]["groupName"]
end

function delete_placement_group(name)
    params = Dict("GroupName" => name)
    Ec2.delete_placement_group(name)
end

#=
Security Group 
=#
function create_security_group(name, description)
    # Criamos o grupo
    params = Dict(
        "TagSpecification" => 
            Dict(
                "ResourceType" => "security-group",
                "Tag" => [Dict("Key" => "cluster", "Value" => name),
                          Dict("Key" => "Name", "Value" => name)]
            )
    )
    id = Ec2.create_security_group(name, description, params)["groupId"]

    # Liberamos o SSH.
    params = Dict(
        "GroupId" => id, 
        "CidrIp" => "0.0.0.0/0",
        "IpProtocol" => "tcp",
        "FromPort" => 22,
        "ToPort" => 22)
    Ec2.authorize_security_group_ingress(params)

    # Liberamos o tráfego interno do grupo.
    sg_name =  Ec2.describe_security_groups(Dict("GroupId" => id))["securityGroupInfo"]["item"]["groupName"]
    params = Dict(
        "GroupId" => id, 
        "SourceSecurityGroupName" => sg_name)
    Ec2.authorize_security_group_ingress(params)
    id
end

function delete_security_group(id)
    Ec2.delete_security_group(Dict("GroupId" => id))
end

#=
Instances 
=#
function create_instances(cluster::Cluster)
    cluster_nodes = Dict()

    # Setting up SSH connection.
    internal_key_name, user_data = set_up_ssh_connection(cluster.name)

    # Setting up NFS.
    if cluster isa ManagerWorkersWithSharedFS || cluster isa PeersWorkersWithSharedFS
        file_system_ip = cluster.environment.file_system_ip
        nfs_user_data = "apt-get -y install nfs-common
mkdir /home/ubuntu/shared/
mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2 $file_system_ip:/ /home/ubuntu/shared/
chown -R ubuntu:ubuntu /home/ubuntu/shared
"    
        user_data *= nfs_user_data
    end
    user_data_base64 = base64encode(user_data)

    # Criando as instâncias
    params = create_params(cluster, user_data_base64)
    if cluster isa ManagerWorkers
        # Criar o headnode
        instance_headnode = Ec2.run_instances(1, 1, params)
        cluster_nodes["headnode"] = instance_headnode["instancesSet"]["item"]["instanceId"]

        # Criar os worker nodes.
        params["InstanceType"] = cluster.instance_type_worker
        params["TagSpecification"]["Tag"][2]["Value"] = "worker"
        count = cluster.count
        instances_workers = Ec2.run_instances(count, count, params)
        workers = count
        for i in 1:count
            instance = ""
            if count > 1
                instance = instances_workers["instancesSet"]["item"][i]
            elseif count == 1
                instance = instances_workers["instancesSet"]["item"]
            end
            instance_id = instance["instanceId"]
            cluster_nodes["worker$i"] = instance_id
        end
    elseif cluster isa PeersWorkers
        # Criar os Peers.
        count = cluster.count
        instances_peers = Ec2.run_instances(count, count, params)
        for i in 1:count
            instance = ""
            if count > 1
                instance = instances_peers["instancesSet"]["item"][i]
            elseif count == 1
                instance = instances_peers["instancesSet"]["item"]
            end
            instance_id = instance["instanceId"]
            cluster_nodes["peer$i"] = instance_id
        end
    end   

    set_hostfile(cluster_nodes, internal_key_name)

    remove_temp_files(internal_key_name)

    cluster_nodes
end

function delete_instances(cluster_nodes)
    for id in values(cluster_nodes)
        Ec2.terminate_instances(id)
    end
end

function get_instance_status(id)
    description = Ec2.describe_instances(Dict("InstanceId" => id))
    description["reservationSet"]["item"]["instancesSet"]["item"]["instanceState"]["name"]
end

function get_instance_subnet(id)
    description = Ec2.describe_instances(Dict("InstanceId" => id))
    description["reservationSet"]["item"]["instancesSet"]["item"]["subnetId"]
end

#=
Shared File System
=#

function create_efs(subnet_id, security_group_id)
    chars = ['a':'z'; 'A':'Z'; '0':'9']
    creation_token = join(chars[Random.rand(1:length(chars), 64)])
    file_system_id = Efs.create_file_system(creation_token)["FileSystemId"]
    create_mount_point(file_system_id, subnet_id, security_group_id)
    file_system_id
end

function create_mount_point(file_system_id, subnet_id, security_group_id)
    params = Dict(
        "SecurityGroups" => [security_group_id]
    )

    status = Efs.describe_file_systems(Dict("FileSystemId" => file_system_id))["FileSystems"][1]["LifeCycleState"]
    while status != "available"
        println("Waiting for File System to be available...")
        sleep(5)
        status = Efs.describe_file_systems(Dict("FileSystemId" => file_system_id))["FileSystems"][1]["LifeCycleState"]
    end
    println("Creating Mount Target...")

    mount_target_id = Efs.create_mount_target(file_system_id, subnet_id, params)["MountTargetId"]
    status = Efs.describe_mount_targets(Dict("MountTargetId" => mount_target_id))["MountTargets"][1]["LifeCycleState"]
    while status != "available"
        println("Waiting for mount target to be available...")
        sleep(5)
        status = Efs.describe_mount_targets(Dict("MountTargetId" => mount_target_id))["MountTargets"][1]["LifeCycleState"]
    end
    mount_target_id
end

function get_mount_target_ip(file_system_id)
    mount_target_id = Efs.describe_mount_targets(Dict("FileSystemId" => file_system_id))["MountTargets"][1]["MountTargetId"]
    ip = Efs.describe_mount_targets(Dict("MountTargetId" => mount_target_id))["MountTargets"][1]["IpAddress"]
    ip
end

function delete_efs(file_system_id)
    for mount_target in Efs.describe_mount_targets(Dict("FileSystemId" => file_system_id))["MountTargets"]
        Efs.delete_mount_target(mount_target["MountTargetId"])
    end
    while length(Efs.describe_mount_targets(Dict("FileSystemId" => file_system_id))["MountTargets"]) != 0
        println("Waiting for mount targets to be deleted...")
        sleep(5)
    end
    Efs.delete_file_system(file_system_id)
end

#=
Retrieve instance IP addresses.
=#
function get_ips_instance(instance_id::String)
    public_ip = Ec2.describe_instances(Dict("InstanceId" => instance_id))["reservationSet"]["item"]["instancesSet"]["item"]["ipAddress"]
    private_ip = Ec2.describe_instances(Dict("InstanceId" => instance_id))["reservationSet"]["item"]["instancesSet"]["item"]["privateIpAddress"]
    Dict("public_ip" => public_ip, "private_ip" => private_ip)
end