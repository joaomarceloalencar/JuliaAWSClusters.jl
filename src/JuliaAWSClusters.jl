module JuliaAWSClusters

# Fixing AWS.jl parameter names
using AWS
using FilePathsBase
aws_package_dir = ENV["HOME"] * "/.julia/packages/AWS"
all_entries = readdir(aws_package_dir)
subdirs = filter(entry -> isdir(joinpath(aws_package_dir, entry)), all_entries)

for subdir in subdirs
    ec2_file = joinpath(aws_package_dir, subdir, "src", "services", "ec2.jl")
    chmod(ec2_file, 0o644)
    content = read(ec2_file, String)
    new_content = replace(content, "Dict{String,Any}(\"groupName\" => groupName);" => "Dict{String,Any}(\"GroupName\" => groupName);")
    new_content = replace(new_content, "\"MaxCount\" => MaxCount, \"MinCount\" => MinCount, \"clientToken\" => string(uuid4())" => 
                                       "\"MaxCount\" => MaxCount, \"MinCount\" => MinCount, \"ClientToken\" => string(uuid4())")
    new_content = replace(new_content, "\"clientToken\" => string(uuid4())" =>  "\"ClientToken\" => string(uuid4())")
    open(ec2_file, "w") do io
        write(io, new_content)
    end
end

using Random
using AWS: @service
using Serialization
using Base64
using Sockets
@service Ec2 
@service Efs

# Including Cluster Types
include("ClusterTypes.jl")

# Including Auxiliary Functions for Instance Configuration
include("InstanceSetup.jl")

# Including AWS Operations
include("AWSOperations.jl")

export ManagerWorkersWithoutSharedFS, ManagerWorkersWithSharedFS, PeersWorkersWithoutSharedFS, PeersWorkersWithSharedFS
export create_cluster, delete_cluster
export get_ips, get_instance_status, get_instance_check

function create_environment(cluster_name::String, shared_fs::Bool)
    # Using the first available subnet.
    subnet_id = Ec2.describe_subnets()["subnetSet"]["item"][1]["subnetId"]
    println("Subnet ID: $subnet_id")
    placement_group = create_placement_group(cluster_name)
        
    println("Placement Group: $placement_group")
    security_group_id = create_security_group(cluster_name, "$cluster_name")
    println("Security Group ID: $security_group_id")

    if (shared_fs)
        file_system_id = create_efs(subnet_id, security_group_id)
        println("File System ID: $file_system_id")
        file_system_ip = get_mount_target_ip(file_system_id)
        println("File System IP: $file_system_ip")
        env = EnvironmentWithSharedFS(subnet_id, placement_group, security_group_id, file_system_id, file_system_ip)
        return env
    else
        env = EnvironmentWithoutSharedFS(subnet_id, placement_group, security_group_id)
        return env
    end
end

# The user must invoke this function with the desired Cluster Type.
function create_cluster(cluster::Cluster)
    shared_fs = false
    if cluster isa ManagerWorkersWithSharedFS || cluster isa PeersWorkersWithSharedFS
        shared_fs = true
    end

    cluster.environment = create_environment(cluster.name, shared_fs)
    cluster.cluster_nodes = create_instances(cluster)
    cluster
end

function delete_cluster(cluster_handle::Cluster)
    delete_instances(cluster_handle.cluster_nodes)
    for instance in cluster_handle.cluster_nodes
        status = get_instance_status(instance[2])
        while status != "terminated"
            println("Waiting for instances to terminate...")
            sleep(5)
            status = get_instance_status(instance[2])
        end
    end
    if cluster_handle isa ManagerWorkersWithSharedFS || cluster_handle isa PeersWorkersWithSharedFS
        delete_efs(cluster_handle.environment.file_system_id)
    end
    delete_security_group(cluster_handle.environment.security_group_id)
    delete_placement_group(cluster_handle.environment.placement_group)
end

# Get the IPs for the
function get_ips(cluster_handle::Cluster)
    ips = Dict()
    for (node, id) in cluster_handle.cluster_nodes
        ips[node] = get_ips_instance(id)
    end
    ips
end

end # module JuliaAWSCluster
