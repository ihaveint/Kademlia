defmodule Kademlia.API do
  def new_node(node_id) do
    Knode.new_node(node_id)
  end
  def join(node_pid, contact_node) do
    send(node_pid, {:join, self(), contact_node})
    receive do
      :joined -> :joined
    end
  end

  def store(node_pid, key_value) do
    send(node_pid, {:request, {:store, self(), key_value}})

    receive do
      response -> response
    end
  end

  def find_node(node_pid, key) do
    send(node_pid, {:find_node, self(), key})

    receive do
      response -> response
    end
  end

  def find_value(node_pid, key) do
    send(node_pid, {:find_value, self(), key})

    receive do
      response -> response
    end
  end
end
