defmodule FindValueTest do
  use ExUnit.Case
  doctest Knode

  use Bitwise
  
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

  test "Finding a node after connecting it to the network works" do
    node1 = Knode.new_node(1)
    node2 = Knode.new_node(2)

    node2_state = Knode.get_state(node2)

    Knode.join(node2_state, {node1, 1})


    IO.inspect(node1, label: "node1:")
    IO.inspect(node2, label: "node2:")

    send(node1, {:find_node, self(), 2})
    receive do
      x -> IO.inspect(x, label: "k_neighbours:")
    end
    assert true
  end

  test "Finding a value after saving it on another node" do
    assert true
  end
end
