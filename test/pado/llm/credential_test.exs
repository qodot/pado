defmodule Pado.LLM.CredentialTest do
  # config 글로벌을 set하므로 async: false
  use ExUnit.Case, async: false

  alias Pado.LLM.Credential
  alias Pado.LLM.Credential.OAuth.Credentials

  setup do
    path =
      Path.join(System.tmp_dir!(), "pado_creds_dispatch_#{:rand.uniform(1_000_000_000)}.json")

    Application.put_env(:pado, :credentials, %{
      test_openai: {Pado.LLM.Credential.FileLoader, path}
    })

    on_exit(fn ->
      File.rm(path)
      Application.delete_env(:pado, :credentials)
    end)

    {:ok, path: path}
  end

  describe "save/2 + load/1" do
    test "config map의 loader로 dispatch해서 round-trip한다", %{path: path} do
      creds = Credentials.build(:openai_codex, "a", "r", 3600, %{"account_id" => "acc1"})

      assert :ok = Credential.save(:test_openai, creds)
      assert File.exists?(path)

      assert {:ok, loaded} = Credential.load(:test_openai)
      assert loaded.access == "a"
      assert loaded.refresh == "r"
      assert loaded.extra == %{"account_id" => "acc1"}
    end
  end

  describe "config에 없는 provider" do
    test "load는 {:error, {:unconfigured_provider, _}}" do
      assert {:error, {:unconfigured_provider, :unknown}} = Credential.load(:unknown)
    end

    test "save는 {:error, {:unconfigured_provider, _}}" do
      creds = Credentials.build(:openai_codex, "a", "r", 3600)
      assert {:error, {:unconfigured_provider, :unknown}} = Credential.save(:unknown, creds)
    end
  end
end
