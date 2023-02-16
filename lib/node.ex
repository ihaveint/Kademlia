defmodule Knode do
  import Bitwise
  import Math
  @type node_id :: integer
  @type udp_port :: String.t
  @type ip_address :: String.t
  @type t :: %__MODULE__{
    k_buckets: list(list({ip_address, udp_port, node_id})),
    id: node_id
  }

  defstruct(
    k_buckets: Enum.map(0..160, fn bucket_id -> [] end),
    id: nil
  )

  @spec new_node(integer) :: __MODULE__
  def new_node(node_id) do
    %__MODULE__{
      id: node_id
    }
  end

  @spec update_buckets(__MODULE__, node_id) :: __MODULE__
  def update_buckets(state = %{id: id, k_buckets: buckets}, sender_id) do
    distance = bxor(sender_id, id) 
    bucket_id = floor(Math.log2(distance))
    state = if Enum.member?(Enum.at(buckets, bucket_id), sender_id) do
      # TODO
      # move the sender to the tail of the bucket
      state
    else
      # TODO 
      # if the bucket is full, ping the least recently seen one first. If it answers, discard the sender. 
      # Else, evict it and insert the new sender at the tail
      state
    end
  end

  @spec loop(__MODULE__) :: any
  def loop(state) do
    receive do
      {:request, {from, node_id}, _} -> loop(state |> update_buckets(node_id)) # TODO: implement this
      {:reply, {from, node_id}, _} -> loop(state |> update_buckets(node_id)) # TODO: implement this
    end
  end
end
