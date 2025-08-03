# Kademlia DHT

A peer-to-peer distributed hash table implementation in Elixir, based on the [Kademlia protocol](https://pdos.csail.mit.edu/~petar/papers/maymounkov-kademlia-lncs.pdf).

## Overview

Kademlia is a distributed hash table that provides efficient storage and retrieval of key-value pairs across a decentralized network of nodes. This implementation follows the original Kademlia paper and provides a robust, fault-tolerant P2P storage system.

### Key Features

- **Distributed Storage**: Store and retrieve key-value pairs across multiple nodes
- **Efficient Routing**: O(log N) lookup complexity using XOR distance metric
- **Self-Organizing**: Nodes automatically discover and maintain routing tables
- **Fault Tolerant**: Built-in redundancy and failure detection
- **Scalable**: Supports networks with millions of nodes

### Technical Specifications

- **Replication Factor (k)**: 20 nodes per k-bucket
- **Concurrency Factor (α)**: 10 parallel lookups
- **Address Space**: 160-bit node IDs (2^160 possible nodes)
- **Timeout**: 100ms for network operations
- **Architecture**: Actor-based using Elixir processes

## Installation

### Prerequisites
- Elixir 1.14 or higher
- Erlang/OTP 24 or higher

### Setup
```bash
git clone <repository-url>
cd kademlia
mix deps.get
```

## Usage

### Basic Operations

#### Creating a Node
```elixir
# Create a new node with ID 1
node_pid = Kademlia.API.new_node(1)
```

#### Joining a Network
```elixir
# Create two nodes
node1 = Kademlia.API.new_node(1)
node2 = Kademlia.API.new_node(2)

# Node2 joins the network through node1
Kademlia.API.join(node2, {node1, 1})
```

#### Storing Data
```elixir
# Store a key-value pair
Kademlia.API.store(node_pid, {key, value})

# Example: Store the value 42 with key 100
Kademlia.API.store(node1, {100, 42})
```

#### Retrieving Data
```elixir
# Find a value by key
value = Kademlia.API.find_value(node_pid, key)

# Example: Retrieve the value for key 100
result = Kademlia.API.find_value(node2, 100)
# Returns: 42
```

#### Finding Nodes
```elixir
# Find k closest nodes to a target ID
closest_nodes = Kademlia.API.find_node(node_pid, target_id)
```

### Advanced Example: Building a Network

```elixir
# Create a network of 20 nodes
nodes = Enum.map(1..20, fn id ->
  {Kademlia.API.new_node(id), id}
end)

# Connect nodes to form a network
[first_node | rest] = nodes

Enum.reduce(rest, [first_node], fn {node_pid, _id}, network ->
  # Each new node joins through a random existing node
  {random_node_pid, random_node_id} = Enum.random(network)
  Kademlia.API.join(node_pid, {random_node_pid, random_node_id})
  [{node_pid, _id} | network]
end)

# Store data from any node
{random_node, _} = Enum.random(nodes)
Kademlia.API.store(random_node, {"my_key", "my_value"})

# Retrieve from any other node
{another_node, _} = Enum.random(nodes)
value = Kademlia.API.find_value(another_node, "my_key")
# Returns: "my_value"
```

## Architecture

### Node Structure
Each node maintains:
- **Node ID**: 160-bit identifier
- **K-buckets**: Routing table with 160 buckets
- **Data Store**: Local key-value storage
- **Process**: Independent Elixir actor

### Message Types
- `join`: Connect to the network
- `store`: Store key-value pairs
- `find_node`: Locate closest nodes
- `find_value`: Retrieve stored values
- `ping`: Check node liveness

### Routing Algorithm
1. Calculate XOR distance between node IDs
2. Route to nodes in appropriate k-bucket
3. Perform recursive lookup with α parallelism
4. Return k closest nodes or stored value

## Testing

Run the test suite:
```bash
mix test
```

### Test Coverage
- Basic storage and retrieval
- Network joining and discovery
- Large network simulation (20+ nodes)
- Fault tolerance scenarios
- Concurrent operations

**Note**: Some tests use randomized networks and may occasionally fail due to network timing. This is expected behavior in distributed systems testing.

## API Reference

### `Kademlia.API`

- `new_node(node_id)` - Create a new node with the given ID
- `join(node_pid, {contact_node_pid, contact_node_id})` - Join an existing network
- `store(node_pid, {key, value})` - Store a key-value pair
- `find_value(node_pid, key)` - Find and return a stored value
- `find_node(node_pid, target_id)` - Find k closest nodes to target ID

## Implementation Details

This implementation closely follows the original Kademlia paper with these characteristics:

- **XOR Metric**: Uses bitwise XOR for distance calculations
- **Binary Tree**: Implicitly partitions nodes into a binary tree
- **Iterative Lookups**: Implements iterative rather than recursive lookups
- **Bucket Refresh**: Automatic k-bucket maintenance and refresh
- **Redundant Storage**: Stores values on k closest nodes

## Contributing

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

## References

- [Kademlia: A Peer-to-peer Information System Based on the XOR Metric](https://pdos.csail.mit.edu/~petar/papers/maymounkov-kademlia-lncs.pdf) - Original paper by Petar Maymounkov and David Mazières

## License

[Add your license information here]
