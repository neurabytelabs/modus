defmodule Modus.World.AgentChatViewer do
  @moduledoc """
  AgentChatViewer — Track and stream agent-to-agent conversations in real-time.

  Stores all agent conversations in an ETS ring buffer (last 100).
  Streams new conversations via PubSub to WorldChannel subscribers.
  Supports filtering by agent_id or topic.

  ETS for fast reads, GenServer for writes.
  """
  use GenServer
  require Logger

  @pubsub Modus.PubSub
  @chat_topic "agent_chats"
  @ets_table :modus_agent_chats
  @max_chats 100

  @type chat_entry :: %{
          id: integer(),
          agent_a: String.t(),
          agent_b: String.t(),
          agent_a_name: String.t(),
          agent_b_name: String.t(),
          messages: String.t(),
          topic: atom(),
          timestamp: integer(),
          tick: non_neg_integer(),
          affect_states: %{agent_a: atom(), agent_b: atom()}
        }

  # ── Public API ──────────────────────────────────────────

  @doc "Start the AgentChatViewer GenServer."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "Record a new agent-to-agent conversation. Returns the chat entry."
  @spec record_chat(map()) :: chat_entry()
  def record_chat(params) do
    GenServer.call(__MODULE__, {:record_chat, params})
  end

  @doc "List recent chats from ETS. Options: limit, agent_id, topic."
  @spec list_chats(keyword()) :: [chat_entry()]
  def list_chats(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    agent_id = Keyword.get(opts, :agent_id)
    topic = Keyword.get(opts, :topic)

    chats =
      try do
        :ets.tab2list(@ets_table)
        |> Enum.map(fn {_id, chat} -> chat end)
      catch
        :error, :badarg -> []
      end

    chats
    |> maybe_filter_agent(agent_id)
    |> maybe_filter_topic(topic)
    |> Enum.sort_by(& &1.id, :desc)
    |> Enum.take(limit)
  end

  @doc "Get a single chat by id."
  @spec get_chat(integer()) :: chat_entry() | nil
  def get_chat(chat_id) do
    case :ets.lookup(@ets_table, chat_id) do
      [{^chat_id, chat}] -> chat
      [] -> nil
    end
  rescue
    ArgumentError -> nil
  end

  @doc "Get the count of stored chats."
  @spec count() :: non_neg_integer()
  def count do
    try do
      :ets.info(@ets_table, :size)
    catch
      :error, :badarg -> 0
    end
  end

  # ── GenServer Callbacks ─────────────────────────────────

  @impl true
  def init(_opts) do
    if :ets.whereis(@ets_table) != :undefined do
      :ets.delete(@ets_table)
    end

    :ets.new(@ets_table, [:set, :public, :named_table, read_concurrency: true])
    {:ok, %{next_id: 1, oldest_id: 1}}
  end

  @impl true
  def handle_call({:record_chat, params}, _from, state) do
    chat = %{
      id: state.next_id,
      agent_a: params.agent_a_id,
      agent_b: params.agent_b_id,
      agent_a_name: params[:agent_a_name] || "Unknown",
      agent_b_name: params[:agent_b_name] || "Unknown",
      messages: params[:messages] || "",
      topic: params[:topic] || :general,
      timestamp: System.system_time(:millisecond),
      tick: params[:tick] || 0,
      affect_states: %{
        agent_a: params[:affect_a] || :neutral,
        agent_b: params[:affect_b] || :neutral
      }
    }

    :ets.insert(@ets_table, {chat.id, chat})

    # Ring buffer: evict oldest if over limit
    new_state =
      if state.next_id - state.oldest_id >= @max_chats do
        :ets.delete(@ets_table, state.oldest_id)
        %{state | next_id: state.next_id + 1, oldest_id: state.oldest_id + 1}
      else
        %{state | next_id: state.next_id + 1}
      end

    # Broadcast via PubSub
    Phoenix.PubSub.broadcast(@pubsub, @chat_topic, {:new_agent_chat, serialize_chat(chat)})

    {:reply, chat, new_state}
  end

  # ── Private Helpers ─────────────────────────────────────

  defp maybe_filter_agent(chats, nil), do: chats

  defp maybe_filter_agent(chats, agent_id) do
    Enum.filter(chats, fn c -> c.agent_a == agent_id or c.agent_b == agent_id end)
  end

  defp maybe_filter_topic(chats, nil), do: chats

  defp maybe_filter_topic(chats, topic) when is_binary(topic) do
    topic_atom = String.to_existing_atom(topic)
    Enum.filter(chats, fn c -> c.topic == topic_atom end)
  rescue
    ArgumentError -> chats
  end

  defp maybe_filter_topic(chats, topic) when is_atom(topic) do
    Enum.filter(chats, fn c -> c.topic == topic end)
  end

  @doc false
  def serialize_chat(chat) do
    %{
      id: chat.id,
      agent_a: chat.agent_a,
      agent_b: chat.agent_b,
      agent_a_name: chat.agent_a_name,
      agent_b_name: chat.agent_b_name,
      messages: chat.messages,
      topic: to_string(chat.topic),
      timestamp: chat.timestamp,
      tick: chat.tick,
      affect_states: %{
        agent_a: to_string(chat.affect_states.agent_a),
        agent_b: to_string(chat.affect_states.agent_b)
      }
    }
  end
end
