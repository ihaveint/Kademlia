defmodule Knode do
  import Bitwise
  import Math

  @k 20
  @a 10

  @type node_id :: integer
  @type node_pid :: Node.t
  @type t :: %__MODULE__{
    k_buckets: list(list({node_pid, node_id})),
    id: node_id,
    data: Map.t
  }

  defstruct(
    k_buckets: Enum.map(0..160, fn bucket_id -> [] end),
    id: nil,
    data: %{}
  )

  @spec new_node(integer) :: node_pid
  def new_node(node_id) do
    state = %__MODULE__{
      id: node_id,
    }

    pid = spawn(fn -> 
      loop(state)
    end)

    pid
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
  def update_buckets(state = %{id: id, k_buckets: buckets}, sender = {sender_pid, sender_id}) do
    distance = bxor(sender_id, id) 
    bucket_id = floor(Math.log2(distance))
    updated_buckets = if Enum.member?(Enum.at(buckets, bucket_id), sender) do
      updated_buckets = send_to_front(buckets, bucket_id, sender)
    else
      # if the bucket is full, ping the least recently seen one first. If it answers, discard the sender. 
      # Else, evict it and insert the new sender at the tail
        if Enum.count(Enum.at(buckets, bucket_id)) == @k do
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
                    tmp ++ [sender]
                  {bucket, _} -> bucket
                end)
            end

        # if the bucket is not full, simply add the sender_id to the bucket
        else
          updated_bucket = Enum.at(buckets, bucket_id) ++ [sender]

          updated_buckets =
          buckets
          |> Enum.with_index
          |> Enum.map(fn
            {bucket, ^bucket_id} -> updated_bucket
            {bucket, _} -> bucket
          end)
        end
    end

    #IO.inspect("updated buckets for ", label: id)
    #IO.inspect(updated_buckets)
    
    %{state | k_buckets: updated_buckets}
  end

  @spec loop(__MODULE__) :: any
  def loop(state = %{id: id}) do
    receive do
      {:request, {:store, from, {key, value}}} ->
        {k_closests, new_state} = lookup(state, key)
        Enum.map(k_closests, fn {node_pid, node_id} ->
          send(node_pid, {:request, {:rpc_store, {self(), id}, key, value}})
        end)

        send(from, :ok)
        
        loop(new_state)
      {:request, {:rpc_store, {from, node_id}, key, value}} -> 
        if node_id != id do
          loop(state |> store(key, value) |> update_buckets({from, node_id}))
        else
          loop(state |> store(key, value))
        end
      {:request, {:current_state, from}} ->
        send(from, state)
        loop(state)
      {:request, {:rpc_ping, {from, node_id}}} -> 
        send(from, :alive)
        loop(state |> update_buckets({from, node_id}))
      {:request, {:rpc_find_node, {from, node_id}, target_id}} ->
        {k_closests, new_state} = lookup(state, target_id)
        send(from, k_closests)
        loop(new_state |> update_buckets({from, node_id}))
      {:find_node, from, target_id} ->
        {k_closests, new_state} = lookup(state, target_id)
        send(from, k_closests)
        loop(state)
      {:request, {:rpc_find_value, {from, node_id}, key}} ->
        {value, new_state} = find_value(key, state)
        send(from, value)
        loop(new_state |> update_buckets({from, node_id}))
      {:request, {:find_value, from, key}} ->
        {value, new_state} = find_value(key, state)
        send(from, value)
        loop(state)
      {:reply, {from, node_id}, _} -> loop(state |> update_buckets({from, node_id})) 
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

  def store(state = %{data: data}, key, value) do
    %{state | data: Map.put(data, key, value)}
  end

  def find_node(state, node_id) do
    lookup(state, node_id, :rpc_find_value)
  end

  def find_value(key, state) do
    lookup(state, key, :rpc_find_value)
  end

  defp recursive_lookup(learned_nodes, target_id, queried \\ MapSet.new(), initiator_state = %{id: initiator_id}, rpc_type) do
    new_learned_nodes =
    learned_nodes
    |> Task.async_stream(fn {node_pid, node_id} ->
      send(node_pid, {rpc_type, {self(), initiator_id}, target_id})
      receive do
         response when is_list(response) ->
          response |> Enum.map(fn {node_pid, node_id} -> {bxor(node_id, target_id), {node_pid, node_id}} end)
         value ->
           [{:terminate, value}]
      after
        500 ->
          :remove
      end
    end)
    |> Enum.map(fn {:ok, value} -> value end)
    |> Enum.reject(fn x -> x == :remove end)
    |> List.flatten()
    |> Enum.reject(fn {node_pid, node_id} -> Enum.member?(learned_nodes, node_id) end)
    
    value? = Enum.find(new_learned_nodes, fn x ->
      case x do
        {:terminate, value} -> true
        _ -> false
      end
    end)

    if value? do
      {:terminate, value} = value?
      value
    else
      k_closests = new_learned_nodes
      |> Enum.take(2 * @k)
      |> Enum.sort(&(&1 |> elem(1) <= &2 |> elem(1)))
      |> Stream.map(fn {distance, node} -> node end)
      |> Enum.take(@k)


      a_closests = k_closests
      |> Enum.reject(fn {_node_pid, node_id} -> MapSet.member?(queried, node_id) end)
      |> Enum.take(@a)


      if length(a_closests) == 0 or bxor(hd(a_closests) |> elem(1), target_id) >= bxor(hd(learned_nodes) |> elem(1), target_id) do
        xx = 
        new_learned_nodes ++ learned_nodes
        |> Enum.reject(fn {_node_pid, node_id} -> MapSet.member?(queried, node_id) end)
        |> Enum.map(fn {node_pid, node_id} -> {bxor(node_id, target_id), {node_pid, node_id}} end)
        |> Enum.sort(&(&1 |> elem(1) <= &2 |> elem(1)))
        |> Enum.take(@k)
        |> Task.async_stream(fn {_distance, {node_pid, node_id}} ->
          send(node_pid, {rpc_type, {self(), initiator_id}, target_id})
          receive do
            response when is_list(response) -> 
              response |> Enum.map(fn {node_pid, node_id} -> {bxor(node_id, target_id), {node_pid, node_id}} end)
            value ->
              {:terminate, value}
          after
            500 ->
              :remove
          end
        end)
        |> Enum.map(fn {:ok, value} -> value end)
        |> Enum.reject(fn x -> x == :remove end)
        |> List.flatten()
          
        
          value? = Enum.find(xx, fn x ->
            case x do
            {:terminate, value} -> true
            _ -> false
            end
          end)

          if value? do
            {:terminate, value} = value?
            value
          else
            xx
            |> Enum.sort(&(&1 |> elem(1) <= &2 |> elem(1)))
            |> Stream.map(fn {distance, node} -> node end)
            |> Enum.take(@k)
          end
      else
        recursive_lookup(new_learned_nodes ++ learned_nodes, target_id, Enum.reduce(learned_nodes, queried, fn x, acc ->
          MapSet.put(acc, x)
        end), initiator_id, rpc_type)
      end
    end
  end

  def lookup(initiator_state = %{k_buckets: buckets, id: id, data: data}, target_id, rpc_type \\ :rpc_find_node) do
    alpha_closests = buckets
    |> List.flatten
    |> Stream.map(fn {node_pid, node_id} -> {bxor(node_id, target_id), {node_pid, node_id}} end )
    |> Enum.take(2 * @a)
    |> Enum.sort()
    |> Enum.take(@a)
    |> Enum.map(fn {_dist, node} -> node end)

    learned_nodes =
    alpha_closests
    |> Task.async_stream(fn {node_pid, _node_id} ->
        send(node_pid, {rpc_type, {self(), id}, target_id})
       receive do
         response when is_list(response) ->
           response |> Enum.map(fn {node_pid, node_id} -> {bxor(node_id, target_id), {node_pid, node_id}} end)
         value ->
           [{:terminate, value}]
       after
         500 ->
           :remove
       end
    end)
    |> Enum.map(fn {:ok, value} -> value end)
    |> Enum.reject(fn x -> x == :remove end)
    |> List.flatten()

    value? = Enum.find(alpha_closests, fn x ->
      case x do
        {:terminate, value} -> true
        _ -> false
      end
    end)

    if value? do
      {:terminate, value} = value?
      {value, initiator_state}
    else
      if length(learned_nodes) > 0 do
        recursive_lookup(learned_nodes, target_id, MapSet.new([id | alpha_closests]), initiator_state, rpc_type)
      else
        case rpc_type do
          :rpc_find_node -> {[{self(), id}], initiator_state} # NOTE: should I do this?
          :rpc_find_value -> {Map.get(data, target_id), initiator_state}
        end
      end
    end

  end

  def refresh(state, bucket_id) do
    nil # TODO
    state
  end

  def get_state(node_pid) do
    send(node_pid, {:request, {:current_state, self()}})
    receive do
      state -> state
    end
  end

  def join(state = %{id: id}, {contact_node_pid, contact_node_id}) do
    new_state = update_buckets(state, {contact_node_pid, contact_node_id})
    {_, new_state} = lookup(new_state, id)
    # TODO: refresh all k-buckets further away than its closest neighbor
    new_state # TODO: return the final state
  end
end
