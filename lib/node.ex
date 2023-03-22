defmodule Knode do
  import Bitwise

  @k 20
  @a 10
  @timeout 100

  @type node_id :: integer
  @type node_pid :: Node.t
  @type t :: %__MODULE__{
    k_buckets: list(list({node_pid, node_id})),
    id: node_id,
    data: Map.t
  }

  defstruct(
    k_buckets: Enum.map(0..160, fn _bucket_id -> [] end),
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
      |> Enum.slide(Enum.find_index(Enum.at(buckets, bucket_id), fn x -> x == node_id end), -1)

    _updated_buckets = 
      buckets
      |> Enum.with_index
      |> Enum.map(fn
        {_bucket, ^bucket_id} -> updated_bucket
        {bucket, _} -> bucket
      end)
  end

  @spec update_buckets(__MODULE__, node_id) :: __MODULE__
  def update_buckets(state = %{id: id, k_buckets: buckets}, sender = {_sender_pid, sender_id}) do
    distance = bxor(sender_id, id) 
    bucket_id = floor(Math.log2(distance))
    updated_buckets = if Enum.member?(Enum.at(buckets, bucket_id), sender) do
      _updated_buckets = send_to_front(buckets, bucket_id, sender)
    else
      # if the bucket is full, ping the least recently seen one first. If it answers, discard the sender. 
      # Else, evict it and insert the new sender at the tail
        if Enum.count(Enum.at(buckets, bucket_id)) == @k do
          [least_recently_seen | _t] = Enum.at(buckets, bucket_id)
          _updated_buckets = 
            #case ping(least_recently_seen, id) do
            case :alive do
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

          _updated_buckets =
          buckets
          |> Enum.with_index
          |> Enum.map(fn
            {_bucket, ^bucket_id} -> updated_bucket
            {bucket, _} -> bucket
          end)
        end
    end

    %{state | k_buckets: updated_buckets}
  end

  @spec loop(__MODULE__) :: any
  def loop(state = %{id: id, k_buckets: buckets}) do
    receive do
      {:debug, :k_buckets, from} ->
        send(from, buckets)
        loop(state)
      {:join, from, _contact_node = {contact_node_pid, contact_node_id}} ->
        new_state = update_buckets(state, {contact_node_pid, contact_node_id})
        lookup(self(), new_state, id)
        send(from, :joined)
        loop(new_state)
      {:request, {:store, from, {key, value}}} ->
        k_closests = lookup(self(), state, key)
        Enum.map(k_closests, fn {node_pid, _node_id} ->
          send(node_pid, {:request, {:rpc_store, {self(), id}, key, value}})
        end)

        send(from, :ok)
        
        loop(state)
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
      {:request, {:rpc_find_node, from, initiator = {_initiator_pid, initiator_id}, target_id}} ->
        spawn(fn ->
          k_closests = 
            Enum.map(buckets, fn bucket ->
              bucket |> Enum.map(fn node = {_node_pid, node_id} ->
                {bxor(node_id, target_id), node}
              end)
            end)
            |> List.flatten
            |> Enum.sort()
            |> Enum.uniq
            |> Enum.take(@k)
            |> Enum.map(fn {_distance, node} -> node end)


          send(from, k_closests)
        end)

        if initiator_id != id do
          loop(state |> update_buckets(initiator))
        else
          loop(state)
        end
      {:lookup_node, from, target_id}  ->
        send(from, lookup_node(self(), state, target_id))
        loop(state)
      {:find_node, from, target_id} ->
        spawn(fn ->
          k_closests = 
            Enum.map(buckets, fn bucket ->
              bucket |> Enum.map(fn node = {_node_pid, node_id} ->
                {bxor(node_id, target_id), node}
              end)
            end)
            |> List.flatten
            |> Enum.sort()
            |> Enum.uniq
            |> Enum.take(@k)
            |> Enum.map(fn {_distance, node} -> node end)


          send(from, k_closests)
        end)
        loop(state)
      {:find_value, from, target_id} ->
        pid = self()
        spawn(fn ->
          value = find_value(pid, target_id, state)
          send(from, value)
        end)
        loop(state)
      {:request, {:rpc_find_value, from, initiator = {_initiator_pid, _initiator_id}, ^id}} ->
        data = Map.get(state, :data)
        value = Map.get(data, id)
        send(from, value)
        loop(state |> update_buckets(initiator))
      {:request, {:rpc_find_value, from, initiator = {_initiator_pid, _initiator_id}, key}} ->
        pid = self()
        spawn(fn ->
          value = find_value(pid, key, state)
          send(from, value)
        end)
        loop(state |> update_buckets(initiator))
      {:request, {:find_value, from, key}} ->
        pid = self()
        spawn(fn ->
          value = find_value(pid, key, state)
          send(from, value)
        end)
        loop(state)
      {:reply, {from, node_id}, _} -> loop(state |> update_buckets({from, node_id})) 
    end
  end

  def ping(node, id) do
    _pid = spawn(fn -> ping_and_wait(node, {self(), id}) end)
    receive do
      :alive -> :alive
      :preesume_dead -> :presume_dead
    end
  end

  def ping_and_wait(node, parent) do
    send(node, {:request, {:rpc_ping, parent}})

    receive do
      :alive ->
        send(parent, :ok)
    after
      @timeout ->
        send(parent, :presume_dead)
    end
  end

  def store(state = %{data: data}, key, value) do
    %{state | data: Map.put(data, key, value)}
  end

  def lookup_node(initiator_pid, state, node_id) do
    lookup(initiator_pid, state, node_id, :rpc_find_node)
  end

  def find_value(pid, key, state) do
    lookup(pid, state, key, :rpc_find_value)
  end

  defp recursive_lookup(initiator_pid, learned_nodes, target_id, queried, initiator_state = %{id: initiator_id}, rpc_type) do
    new_learned_nodes =
    learned_nodes
    |> Task.async_stream(fn node = {node_pid, _node_id} ->
      send(node_pid, {:request, {rpc_type, self(), {initiator_pid, initiator_id}, target_id}})
      receive do
         response when is_list(response) ->
           send(initiator_pid, {:reply, node, response})
          response |> Enum.map(fn {node_pid, node_id} -> {bxor(node_id, target_id), {node_pid, node_id}} end)
         value ->
           send(initiator_pid, {:reply, node, value})
           [{:terminate, value}]
      after
        @timeout ->
          :remove
      end
    end)
    |> Enum.map(fn {:ok, value} -> value end)
    |> Enum.reject(fn x -> x == :remove end)
    |> List.flatten()
    |> Enum.reject(fn {_node_pid, node_id} -> Enum.member?(learned_nodes, node_id) end)
    
    value? = Enum.find(new_learned_nodes, fn x ->
      case x do
        {:terminate, _value} -> true
        _ -> false
      end
    end)

    if value? do
      {:terminate, value} = value?
      value
    else

      new_learned_nodes =
        new_learned_nodes
        |> Enum.map(fn {_distance, node} -> node end)

      k_closests = 
        new_learned_nodes
        |> Enum.sort()
        |> Enum.uniq
        |> Enum.take(@k)


      a_closests = k_closests
      |> Enum.reject(fn {_node_pid, node_id} -> MapSet.member?(queried, node_id) end)
      |> Enum.uniq
      |> Enum.take(@a)

      if length(a_closests) == 0 or bxor(hd(a_closests) |> elem(1), target_id) >= bxor(hd(learned_nodes) |> elem(1), target_id) do
        xx = 
        k_closests
        |> Task.async_stream(fn node = {node_pid, _node_id} ->
          send(node_pid, {:request, {rpc_type, self(), {initiator_pid, initiator_id}, target_id}})
          receive do
            response when is_list(response) -> 
              send(initiator_pid, {:reply, node, response})
              response |> Enum.map(fn {node_pid, node_id} -> {bxor(node_id, target_id), {node_pid, node_id}} end)
            value ->
              send(initiator_pid, {:reply, node, value})
              {:terminate, value}
          after
            @timeout ->
              :remove
          end
        end)
        |> Enum.map(fn {:ok, value} -> value end)
        |> Enum.reject(fn x -> x == :remove end)
        |> List.flatten()
          
        
          value? = Enum.find(xx, fn x ->
            case x do
            {:terminate, _value} -> true
            _ -> false
            end
          end)

          if value? do
            {:terminate, value} = value?
            value
          else
            xx
            ++ Enum.map(learned_nodes, fn {node_pid, node_id} ->
              {bxor(node_id, target_id), {node_pid, node_id}}
            end)
            |> Enum.sort(&(&1 |> elem(1) <= &2 |> elem(1)))
            |> Stream.map(fn {_distance, node} -> node end)
            |> Enum.uniq
            |> Enum.take(@k)
          end
      else
        recursive_lookup(initiator_pid, a_closests, target_id, Enum.reduce(a_closests, queried, fn x, acc ->
          MapSet.put(acc, x)
        end), initiator_state, rpc_type)
      end
    end
  end

  def lookup(initiator_pid, initiator_state = %{k_buckets: buckets, id: id, data: data}, target_id, rpc_type \\ :rpc_find_node) do
    alpha_closests = buckets
    |> List.flatten
    |> Stream.map(fn {node_pid, node_id} -> {bxor(node_id, target_id), {node_pid, node_id}} end )
    |> Enum.sort()
    |> Enum.uniq
    |> Enum.take(@a)
    |> Enum.map(fn {_dist, node} -> node end)


    learned_nodes =
    alpha_closests
    |> Task.async_stream(fn node = {node_pid, _node_id} ->
      send(node_pid, {:request, {rpc_type, self(), {initiator_pid, id}, target_id}})
       receive do
         response when is_list(response) ->
           send(initiator_pid, {:reply, node, response})
           response |> Enum.map(fn node = {_node_pid, node_id} -> {bxor(node_id, target_id), node} end)
         value ->
           send(initiator_pid, {:reply, node, value})
           [{:terminate, value}]
       after
         @timeout ->
           :remove
       end
    end)
    |> Enum.map(fn {:ok, value} -> value end)
    |> Enum.reject(fn x -> x == :remove end)
    |> List.flatten()

    value? = Enum.find(learned_nodes, fn x ->
      case x do
        {:terminate, _value} -> true
        _ -> false
      end
    end)

    if value? do
      {:terminate, value} = value?
      value
    else
      learned_nodes =
        learned_nodes
        |> Enum.map(fn {_distance, node} -> node end)

      if length(learned_nodes) > 0 do
        recursive_lookup(initiator_pid, learned_nodes, target_id, MapSet.new([id | alpha_closests]), initiator_state, rpc_type)
      else
        case rpc_type do
          :rpc_find_node -> 
            [{initiator_pid, id}] # NOTE: should I do this?
          :rpc_find_value -> Map.get(data, target_id)
        end
      end
    end

  end

  def refresh(state, _bucket_id) do
    nil # TODO
    state
  end

  def get_state(node_pid) do
    send(node_pid, {:request, {:current_state, self()}})
    receive do
      state -> state
    end
  end
end
