defmodule FindValueTest do
  use ExUnit.Case
  doctest Knode

  import Bitwise
  
  test "Storing a value returns :ok" do
    node1 = Kademlia.API.new_node(1)

    case Kademlia.API.store(node1, {1 <<< 3, 5}) do
      :ok -> assert true
      _ -> assert false
    end
  end

  test "Finding a value after saving it on the same node" do
    node1 = Kademlia.API.new_node(1)

    Kademlia.API.store(node1, {1 <<< 3, 5})

    case Kademlia.API.find_value(node1, 8) do
      5 -> assert true
      _ -> assert false
    end
  end

  #@tag mustexec: true
  test "Finding a node after connecting it to the network works" do
    node1 = Kademlia.API.new_node(1)
    node2 = Kademlia.API.new_node(2)

    Kademlia.API.join(node2, {node1, 1})

    k_neighbors = Kademlia.API.find_node(node1, 2)

    assert Enum.member?(k_neighbors, {node2, 2})
  end

  # @tag mustexec: true
  test "Finding a node in a network of hundreds of nodes works" do
    nodes = Enum.map(1..20, fn id ->
      {Kademlia.API.new_node(id), id}
    end)

    [first_node | rest] = nodes

    Enum.reduce(
      rest,
      [first_node], fn node = {node_pid, _node_id}, network_nodes ->
        random_connection = {_random_node_pid, _random_node_id} = Enum.random(network_nodes)
        Kademlia.API.join(node_pid, random_connection)
        [node | network_nodes]
      end)

    discovery_enum =
      Enum.map(1..100, fn _ ->
      {random_node_pid, _random_node_id} = Enum.random(nodes)
      {random_node2_pid, random_node2_id} = Enum.random(nodes)


      if random_node_pid == random_node2_pid do
        true
      else
        send(random_node_pid, {:lookup_node, self(), random_node2_id})
        k_neighbors =
          receive do
            x -> x
          end
        Enum.member?(k_neighbors, {random_node2_pid, random_node2_id})
      end

    end)

    assert Enum.member?(discovery_enum, false) == false
  end

  @tag mustexec: true
  test "Finding a value after saving it on another node" do
    node1 = Kademlia.API.new_node(1)
    node2 = Kademlia.API.new_node(2)

    Kademlia.API.join(node2, {node1, 1})

    Kademlia.API.store(node1, {1 <<< 3, 5})

    case Kademlia.API.find_value(node2, 8) do
      5 -> assert true
      sth_else ->
        IO.inspect(sth_else, label: "oops, got")
        assert false
    end
  end

  test "Finding a value in a random generated network works" do
    nodes = Enum.map(1..20, fn id ->
      {Kademlia.API.new_node(id), id}
    end)

    [first_node | rest] = nodes

    Enum.reduce(
      rest,
      [first_node], fn node = {node_pid, _node_id}, network_nodes ->
      random_connection = {_random_node_pid, _random_node_id} = Enum.random(network_nodes)
      Kademlia.API.join(node_pid, random_connection)
      [node | network_nodes]
    end)

    {first_node_pid, _first_node_id} = first_node
    Kademlia.API.store(first_node_pid, {8, 5})

    discovery_enum =
      Enum.map(1..10, fn _ ->
          {random_node_pid, _random_node_id} = Enum.random(nodes)

          case Kademlia.API.find_value(random_node_pid, 8) do
            nil -> false
            _ -> true
          end
      end)

    assert Enum.member?(discovery_enum, false) == false
  end
end
