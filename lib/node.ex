defmodule Knode do
  import Bitwise
  import Math

  @k 20

  @type node_id :: integer
  @type udp_port :: String.t
  @type ip_address :: String.t
  @type t :: %__MODULE__{
    k_buckets: list(list({ip_address, udp_port, node_id})),
    id: node_id,
    data: Map.t
  }

  defstruct(
    k_buckets: Enum.map(0..160, fn bucket_id -> [] end),
    id: nil,
    data: %{}
  )

  @spec new_node(integer) :: __MODULE__
  def new_node(node_id) do
    %__MODULE__{
      id: node_id
    }
  end

  def send_to_front(buckets, bucket_id, node_id) do
    updated_bucket =
      Enum.at(buckets, bucket_id)
      |> Enum.slide( node_id |> Enum.find_index(Enum.at(buckets, bucket_id)), -1)

    updated_buckets = 
      buckets
      |> Enum.with_index
      |> Enum.map(fn
        {bucket, ^bucket_id} -> updated_bucket
        {bucket, _} -> bucket
      end)
  end

  @spec update_buckets(__MODULE__, node_id) :: __MODULE__
  def update_buckets(state = %{id: id, k_buckets: buckets}, sender_id) do
    distance = bxor(sender_id, id) 
    bucket_id = floor(Math.log2(distance))
    updated_buckets = if Enum.member?(Enum.at(buckets, bucket_id), sender_id) do
      updated_buckets = send_to_front(buckets, bucket_id, sender_id)
    else
      # if the bucket is full, ping the least recently seen one first. If it answers, discard the sender. 
      # Else, evict it and insert the new sender at the tail
        if Enum.count(Enum.at(buckets, bucket_id) == @k) do
          [least_recently_seen | t] = Enum.at(buckets, bucket_id)
          updated_buckets = 
            case ping(least_recently_seen) do
              :alive ->
                send_to_front(buckets, bucket_id, least_recently_seen)
              :presume_dead ->
                buckets
                |> Enum.with_index
                |> Enum.map(fn
                  {bucket, ^bucket_id} -> 
                    tmp = 
                      bucket 
                      |> Enum.reject(fn id -> id == least_recently_seen end)
                    [tmp | sender_id]
                  {bucket, _} -> bucket
                end)
            end

        # if the bucket is not full, simply add the sender_id to the bucket
        else
          updated_bucket = [Enum.at(buckets, bucket_id) | sender_id]

          updated_buckets =
          buckets
          |> Enum.with_index
          |> Enum.map(fn
            {bucket, ^bucket_id} -> updated_bucket
            {bucket, _} -> bucket
          end)
        end
    end
    

    new_state = %{id: id, k_buckets: updated_buckets}
  end

  @spec loop(__MODULE__) :: any
  def loop(state) do
    receive do
      {:request, {from, node_id}, _} -> loop(state |> update_buckets(node_id)) # TODO: implement this
      {:reply, {from, node_id}, _} -> loop(state |> update_buckets(node_id)) # TODO: implement this
    end
  end

  def ping(node) do
    pid = spawn(fn -> ping_and_wait(node, self()) end)
    receive do
      :alive -> :alive
      :preesume_dead -> :presume_dead
    end
  end

  def ping_and_wait(node, parent) do
    send(node, :ping)

    receive do
      :alive ->
        send(parent, :ok)
    after
      1_000 ->
        send(parent, :presume_dead)
    end
  end

  def store(key, value) do
    # TODO
  end

  def find_node(target_id) do
    # TODO
  end

  def find_value() do
    # TODO
  end

  def lookup(id) do
    # TODO
  end
end
