# Kademlia

Kademlia is a peer-to-peer distributed hash table. You can see the original paper [here](https://pdos.csail.mit.edu/~petar/papers/maymounkov-kademlia-lncs.pdf). The goal of this project is to have a working version of kademlia that is mainly based on the descriptions in the paper.

## Installation

You can clone this project, and given that you already have Elixir installed, you can simply run ```mix deps.get``` to get the dependencies.


## Running tests
You can run the tests by the ```mix test``` command. Currently, some tests are generating random networks, and although I have tried running them multiple times, it might be the case that they don't work as expected on your machine; I will do my best to fix them in the future.

## How to use the API
There are some functions provided as an API to make it easier for a client (you in this case) to use the protocol:
- You can create a new node by calling ```Kademlia.API.new_node(node_id)```, where node_id is the id you want your node to have.
- A node can join an already existing network of nodes (given that it knows of a contact node and its id that is already in the network), by calling ```Kademlia.API.join(new_node_pid, {contact_node_pid, contact_node_id}```
- A key-value can be stored on a node with by ```Kademlia.API.store(node_pid, {key, value})``` where node_pid is pid of the node.
- ```Kademlia.API.find_value(node_pid, key)``` can be called to initiate a search starting from node_pid to find the value stored for the given key.
