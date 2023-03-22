defmodule FindValueTest do
  use ExUnit.Case
  doctest Knode

  import Bitwise
  
  test "Storing a value returns :ok" do
    node1 = Knode.new_node(1)

    send(node1, {:request, {:store, self(), {1 <<< 3, 5}}})

    receive do
      :ok -> assert true
      _ -> assert false
    end
  end

  test "Finding a value after saving it on the same node" do
    node1 = Knode.new_node(1)

    send(node1, {:request, {:store, self(), {1 <<< 3, 5}}})

    receive do
      _ -> true
    end

    send(node1, {:request, {:find_value, self(), 8}})

    receive do
      5 -> assert true
      _ -> assert false
    end
  end

  #@tag mustexec: true
  test "Finding a node after connecting it to the network works" do
    node1 = Knode.new_node(1)
    node2 = Knode.new_node(2)
    
    send(node2, {:join, self(), {node1, 1}})

    receive do
      :joined -> nil
    end

    send(node1, {:find_node, self(), 2})
    k_neighbors =
    receive do
      x -> x
    end

    assert Enum.member?(k_neighbors, {node2, 2})
  end

  @tag mustexec: true
  test "Finding a node in a network of hundreds of nodes works" do
    nodes = Enum.map(1..10, fn id ->
      {Knode.new_node(id), id}
    end)

    [first_node | rest] = nodes

    Enum.reduce(
      rest,
      [first_node], fn node = {node_pid, _node_id}, network_nodes ->
        random_connection = {_random_node_pid, _random_node_id} = Enum.random(network_nodes)
        send(node_pid, {:join, self(), random_connection})
        receive do
          :joined -> 
            nil
        end
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

  test "Finding a value after saving it on another node" do
    assert true
  end
end
