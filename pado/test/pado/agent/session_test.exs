defmodule Pado.Agent.SessionTest do
  use ExUnit.Case, async: true

  alias Pado.Agent.Session
  alias Pado.Agent.Session.Entry
  alias Pado.LLM.Message.User

  @now ~U[2026-05-17 12:00:00Z]

  describe "to_map/1과 from_map/1" do
    test "세션 구조체를 저장 가능한 맵으로 왕복한다" do
      session = %Session{
        id: "session-1",
        version: 1,
        created_at: @now,
        updated_at: @now,
        entries: [
          %Entry{
            id: "entry-1",
            seq: 0,
            kind: :user,
            payload: %User{content: "hello", timestamp: @now},
            timestamp: @now
          }
        ]
      }

      assert {:ok, ^session} = session |> Session.to_map() |> Session.from_map()
    end

    test "type이 session이 아니면 에러를 반환한다" do
      assert {:error, {:invalid_session_map, %{"type" => "entry"}}} =
               Session.from_map(%{"type" => "entry"})
    end
  end
end
