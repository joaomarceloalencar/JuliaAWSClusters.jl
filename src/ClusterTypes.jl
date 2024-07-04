abstract type Environment end
mutable struct EnvironmentWithSharedFS <: Environment
    subnet_id::String
    placement_group::String
    security_group_id::String
    file_system_id::String  
    file_system_ip::String
end

mutable struct EnvironmentWithoutSharedFS <: Environment
    subnet_id::String
    placement_group::String
    security_group_id::String
end

abstract type Cluster end
abstract type PeersWorkers <: Cluster end
abstract type ManagerWorkers <: Cluster end

mutable struct ManagerWorkersWithSharedFS <: ManagerWorkers
    name::String
    instance_type_headnode::String
    instance_type_worker::String
    count::Int
    key_name::String
    image_id::String
    environment::Union{EnvironmentWithSharedFS, Nothing}
    cluster_nodes::Union{Dict{String, String}, Nothing}
end

mutable struct ManagerWorkersWithoutSharedFS <: ManagerWorkers
    name::String
    instance_type_headnode::String
    instance_type_worker::String
    count::Int
    key_name::String
    image_id::String
    environment::Union{EnvironmentWithoutSharedFS, Nothing}
    cluster_nodes::Union{Dict{String, String}, Nothing}
end

mutable struct PeersWorkersWithSharedFS <: PeersWorkers
    name::String
    instance_type_peer::String
    count::Int
    key_name::String
    image_id::String
    environment::Union{EnvironmentWithSharedFS, Nothing}
    cluster_nodes::Union{Dict{String, String}, Nothing}
end

mutable struct PeersWorkersWithoutSharedFS <: PeersWorkers
    name::String
    instance_type_peer::String
    count::Int
    key_name::String
    image_id::String
    environment::Union{EnvironmentWithoutSharedFS, Nothing}
    cluster_nodes::Union{Dict{String, String}, Nothing}
end

