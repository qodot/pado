defmodule Pado.LLMRouter.OAuth.Credentials do
  @moduledoc """
  OAuth 크레덴셜 값 객체.

  이 모듈은 의도적으로 순수한 데이터와 작은 헬퍼만 담는다. 라이브러리
  자체는 어떤 저장소도 소유하지 않는다. 호출자가 원하는 곳(파일, Vault,
  시크릿 매니저, DB 등)에 저장한다. 편의를 위해 `to_map/1`과 `from_map/1`
  을 통한 JSON 직렬화를 제공한다.

  구조체는 pi-ai의 `OAuthCredentials`와 같은 역할이지만 Elixir 관습을 따른다.

    * `:expires_at`은 `DateTime`이다(Pi는 epoch 밀리초).
    * 프로바이더별 부가 필드(예: OpenAI의 `account_id`)는 `:extra`에 둔다.
      이렇게 하면 프로바이더가 늘어나도 핵심 구조체는 안정적이다.
  """

  @type t :: %__MODULE__{
          provider: atom,
          access: String.t(),
          refresh: String.t(),
          expires_at: DateTime.t(),
          extra: map
        }

  @derive {Jason.Encoder, only: [:provider, :access, :refresh, :expires_at, :extra]}
  @enforce_keys [:provider, :access, :refresh, :expires_at]
  defstruct [:provider, :access, :refresh, :expires_at, extra: %{}]

  @doc """
  access 토큰이 만료 시각에 도달했거나 지났는지 확인한다.

  실제 만료 직전에 선제적으로 갱신하고 싶다면 `stale?/2`를 쓴다.
  """
  @spec expired?(t) :: boolean
  def expired?(%__MODULE__{expires_at: at}) do
    DateTime.compare(DateTime.utc_now(), at) != :lt
  end

  @doc """
  `skew_seconds` 안에 만료될 예정이면 `true`를 반환한다.

  선제적 갱신에 쓰인다(권장 범위: 60~300초).
  """
  @spec stale?(t, non_neg_integer) :: boolean
  def stale?(%__MODULE__{expires_at: at}, skew_seconds) when skew_seconds >= 0 do
    threshold = DateTime.add(DateTime.utc_now(), skew_seconds, :second)
    DateTime.compare(threshold, at) != :lt
  end

  @doc """
  토큰 엔드포인트가 반환하는 `expires_in`(지금부터의 초)을 기준으로
  크레덴셜을 조립한다.
  """
  @spec build(atom, String.t(), String.t(), non_neg_integer, map) :: t
  def build(provider, access, refresh, expires_in_seconds, extra \\ %{})
      when is_atom(provider) and is_binary(access) and is_binary(refresh) and
             is_integer(expires_in_seconds) and is_map(extra) do
    %__MODULE__{
      provider: provider,
      access: access,
      refresh: refresh,
      expires_at: DateTime.add(DateTime.utc_now(), expires_in_seconds, :second),
      extra: extra
    }
  end

  @doc """
  JSON 호환 맵으로 직렬화한다. `:expires_at`은 ISO8601 문자열,
  `:provider`는 문자열로 변환해 다른 언어와의 호환을 보장한다.
  """
  @spec to_map(t) :: map
  def to_map(%__MODULE__{} = c) do
    %{
      "provider" => Atom.to_string(c.provider),
      "access" => c.access,
      "refresh" => c.refresh,
      "expires_at" => DateTime.to_iso8601(c.expires_at),
      "extra" => c.extra
    }
  end

  @doc """
  맵(보통 `Jason.decode!/1`의 결과)을 `t/0`로 파싱한다.

  키는 문자열과 아톰 모두 허용하고, `expires_at`은 ISO8601 문자열과
  epoch 밀리초 정수를 모두 받는다. 밀리초 형식은 Pi의 디스크 포맷과
  동일해 마이그레이션에 유리하다.
  """
  @spec from_map(map) :: {:ok, t} | {:error, term}
  def from_map(map) when is_map(map) do
    with {:ok, provider} <- fetch(map, :provider),
         {:ok, access} <- fetch(map, :access),
         {:ok, refresh} <- fetch(map, :refresh),
         {:ok, expires_raw} <- fetch(map, :expires_at),
         {:ok, expires_at} <- parse_expires(expires_raw) do
      extra =
        case fetch(map, :extra) do
          {:ok, m} when is_map(m) -> m
          _ -> %{}
        end

      {:ok,
       %__MODULE__{
         provider: to_atom(provider),
         access: access,
         refresh: refresh,
         expires_at: expires_at,
         extra: extra
       }}
    end
  end

  def from_map(_), do: {:error, :invalid_map}

  defp fetch(map, key) do
    case map do
      %{^key => v} when not is_nil(v) ->
        {:ok, v}

      _ ->
        sk = if is_atom(key), do: Atom.to_string(key), else: key

        case map do
          %{^sk => v} when not is_nil(v) -> {:ok, v}
          _ -> {:error, {:missing, key}}
        end
    end
  end

  defp parse_expires(%DateTime{} = dt), do: {:ok, dt}

  defp parse_expires(ms) when is_integer(ms) do
    DateTime.from_unix(ms, :millisecond)
  end

  defp parse_expires(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> {:ok, dt}
      {:error, reason} -> {:error, {:invalid_expires_at, reason}}
    end
  end

  defp parse_expires(other), do: {:error, {:invalid_expires_at, other}}

  defp to_atom(a) when is_atom(a), do: a
  defp to_atom(s) when is_binary(s), do: String.to_atom(s)
end
