defmodule Pado.LLMRouter.Credential.FileLoaderTest do
  use ExUnit.Case, async: true

  alias Pado.LLMRouter.Credential.FileLoader
  alias Pado.LLMRouter.Credential.OAuth.Credentials

  setup do
    path = Path.join(System.tmp_dir!(), "pado_creds_test_#{:rand.uniform(1_000_000_000)}.json")
    on_exit(fn -> File.rm(path) end)
    {:ok, path: path}
  end

  describe "save/2" do
    test "credentials를 JSON으로 저장한다", %{path: path} do
      creds = Credentials.build(:openai_codex, "a", "r", 3600, %{"account_id" => "acc1"})
      assert :ok = FileLoader.save(creds, path)
      assert File.exists?(path)
    end

    test "디렉토리가 없으면 만들어준다" do
      tmp_dir = Path.join(System.tmp_dir!(), "pado_test_#{:rand.uniform(1_000_000_000)}")
      nested_path = Path.join([tmp_dir, "subdir", "creds.json"])
      on_exit(fn -> File.rm_rf(tmp_dir) end)

      creds = Credentials.build(:openai_codex, "a", "r", 3600)
      assert :ok = FileLoader.save(creds, nested_path)
      assert File.exists?(nested_path)
    end
  end

  describe "fetch/1" do
    test "저장된 credentials를 읽어 반환한다", %{path: path} do
      creds =
        Credentials.build(:openai_codex, "access", "refresh", 3600, %{"account_id" => "acc1"})

      :ok = FileLoader.save(creds, path)

      assert {:ok, loaded} = FileLoader.fetch(path)
      assert loaded.access == creds.access
      assert loaded.refresh == creds.refresh
      assert loaded.provider == creds.provider
      assert loaded.extra == creds.extra
    end

    test "파일이 없으면 {:error, :enoent}", %{path: path} do
      assert {:error, :enoent} = FileLoader.fetch(path)
    end

    test "JSON이 깨졌으면 {:error, _}", %{path: path} do
      File.write!(path, "not a json")
      assert {:error, _} = FileLoader.fetch(path)
    end

    test "지원되지 않는 provider면 refresh 시 {:error, {:unsupported_provider, _}}", %{path: path} do
      # expires_at을 과거로 두어 stale 트리거
      stale_creds = %Credentials{
        provider: :unknown_provider,
        access: "a",
        refresh: "r",
        expires_at: DateTime.add(DateTime.utc_now(), -100, :second),
        extra: %{}
      }

      :ok = FileLoader.save(stale_creds, path)

      assert {:error, {:unsupported_provider, :unknown_provider}} = FileLoader.fetch(path)
    end
  end
end
