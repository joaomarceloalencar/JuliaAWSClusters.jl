
# A Julia Package for Creating AWS Clusters

## Requisites

* Julia.
* The AWS CLI.
* An instance type that supports placement groups (e.g, c6i.large).

## Create clusters using the REPL

There are four types of clusters for defining the cluster settings.

### Defining the cluster settings.

A cluster with a headnode, four workers, and shared filesystem:
```julia
cluster = ManagerWorkersWithoutSharedFS("my_cluster", "c6i.large", "c6i.large", 4, "my_key", "ami-04b70fa74e45c3917", nothing, nothing)
```

A cluster with no headnode, four peers, and a shared filesystem:
```julia
cluster = PeersWorkersWithoutSharedFS("my_cluster", "c6i.large", 4, "my_key", "ami-04b70fa74e45c3917", nothing, nothing)
```

A cluster with a headnode, four workers, and no shared filesystem:
```julia
cluster = ManagerWorkersWithSharedFS("my_cluster", "c6i.large", "c6i.large", 4, "my_key", "ami-04b70fa74e45c3917", nothing, nothing)
```

A cluster with no headnode, four peers, and no shared filesystem:
```julia
cluster = PeersWorkersWithSharedFS("my_cluster", "c6i.large", 4, "my_key", "ami-04b70fa74e45c3917", nothing, nothing)
```

### Creating the cluster.

```
cluster_handle = create_cluster(cluster)
get_ips_instance(cluster_handle.cluster_nodes["peer1"])    # for Peers
get_ips_instance(cluster_handle.cluster_nodes["headnode"]) # for ManagerWorkers
```

### Cleaning the resources.

```julia
delete_cluster(cluster_handle)
```