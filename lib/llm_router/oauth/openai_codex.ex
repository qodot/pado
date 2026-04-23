defmodule LLMRouter.OAuth.OpenAICodex do
  @moduledoc """
  OpenAI Codex("simplified") 플로우로 로그인한다. ChatGPT Plus/Pro
  구독 자격으로 인증해 `https://chatgpt.com/backend-api/codex/responses`
  엔드포인트에 쓸 토큰을 발급받는 경로다.

  `LLMRouter.OAuth.Provider`를 구현한다. 구조는 pi-ai의
  `utils/oauth/openai-codex.ts`를 거의 그대로 옮긴 것이다.

  ## 공용 public 클라이언트

  `client_id`와 등록된 `redirect_uri`(`localhost:1455`)는 Codex CLI
  OAuth 앱의 공개된 값이며 pi-ai, 이 라이브러리, 다른 커뮤니티 도구가
  함께 쓴다. 현재로서는 이 플로우용으로 독립 `client_id`를 등록할 공식
  경로가 없다.

  redirect URI가 서버에 등록되어 있어 클라이언트 측에서 바꿀 수 없다.
  즉 **`login/2`를 시작하는 머신에서 브라우저를 열어야 한다.** 콜백을
  원격 서버로 우회시킬 수 없다. 서버 사이드 OAuth가 필요하다면 사전에
  얻어둔 크레덴셜로 `refresh/1`만 호출하는 방식으로 운영한다
  (README 참고).

  ## Originator

  authorize URL의 `originator` 파라미터는 서버가 로그로 남기거나
  클라이언트 구분에 쓸 수 있는 짧은 식별자다. Pi는 `"pi"`를 쓴다.
  이 모듈도 기본값을 `"pi"`로 둔다. 업스트림 서버가 실제로 허용하는
  값 중 확인된 것이 `"pi"`뿐이기 때문이다(보수적 기본값). 다른 값으로
  실험하려면 `login/2`에 `originator: "llm-router"` 같은 옵션을
  넘긴다.
  """

  @behaviour LLMRouter.OAuth.Provider

  alias LLMRouter.OAuth.{CallbackServer, Credentials, PKCE}

  require Logger

  # --- OAuth 상수(등록된 클라이언트와 일치해야 한다) ---

  @client_id "app_EMoamEEZ73f0CkXaXp7hrann"
  @authorize_url "https://auth.openai.com/oauth/authorize"
  @token_url "https://auth.openai.com/oauth/token"
  @redirect_uri "http://localhost:1455/auth/callback"
  @scope "openid profile email offline_access"
  @jwt_claim_path "https://api.openai.com/auth"
  @default_originator "pi"
  @default_timeout 300_000

  # --- Provider 콜백 구현 ---

  @impl true
  def id, do: :openai_codex

  @impl true
  def name, do: "ChatGPT Plus/Pro (Codex Subscription)"

  @impl true
  def uses_callback_server?, do: true

  @impl true
  def login(callbacks, opts \\ []) when is_map(callbacks) and is_list(opts) do
    originator = Keyword.get(opts, :originator, @default_originator)
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    pkce = PKCE.generate()
    state = PKCE.state()
    url = build_authorize_url(pkce.challenge, state, originator)

    with {:ok, code} <- collect_code(url, state, callbacks, timeout, opts),
         {:ok, token} <- exchange_code(code, pkce.verifier),
         {:ok, account_id} <- parse_account_id(token.access) do
      {:ok,
       Credentials.build(:openai_codex, token.access, token.refresh, token.expires_in, %{
         "account_id" => account_id,
         "originator" => originator
       })}
    end
  end

  @impl true
  def refresh(%Credentials{provider: :openai_codex, refresh: refresh_token, extra: extra}) do
    with {:ok, token} <- refresh_token_request(refresh_token),
         {:ok, account_id} <- parse_account_id(token.access) do
      originator = Map.get(extra, "originator", @default_originator)

      {:ok,
       Credentials.build(:openai_codex, token.access, token.refresh, token.expires_in, %{
         "account_id" => account_id,
         "originator" => originator
       })}
    end
  end

  def refresh(%Credentials{provider: other}),
    do: {:error, {:wrong_provider, other}}

  @impl true
  def api_key(%Credentials{access: access}), do: access

  # --- 공개 헬퍼(테스트와 다른 프로바이더 구현에서도 사용) ---

  @doc "Codex access 토큰(JWT)에서 `chatgpt_account_id`를 추출한다."
  @spec parse_account_id(String.t()) :: {:ok, String.t()} | {:error, term}
  def parse_account_id(access_token) when is_binary(access_token) do
    with [_h, payload_b64, _s] <- String.split(access_token, "."),
         {:ok, payload_json} <- Base.url_decode64(pad_base64(payload_b64), padding: true),
         {:ok, payload} <- Jason.decode(payload_json),
         %{} = auth <- Map.get(payload, @jwt_claim_path),
         account_id when is_binary(account_id) and account_id != "" <-
           Map.get(auth, "chatgpt_account_id") do
      {:ok, account_id}
    else
      _ -> {:error, :missing_account_id}
    end
  end

  @doc """
  사용자가 수동으로 입력한 값을 파싱해 `%{code: code, state: state}`를
  돌려준다. 인가 코드만 붙여넣는 경우, `code=…&state=…` 형태의
  쿼리스트링, 리다이렉트 URL 전체 모두를 받아들인다.

  pi-ai의 `parseAuthorizationInput`과 대응된다.
  """
  @spec parse_authorization_input(String.t()) ::
          %{optional(:code) => String.t(), optional(:state) => String.t()}
  def parse_authorization_input(input) when is_binary(input) do
    value = String.trim(input)

    cond do
      value == "" ->
        %{}

      String.starts_with?(value, "http://") or String.starts_with?(value, "https://") ->
        parse_full_url(value)

      String.contains?(value, "#") ->
        [code, state] = String.split(value, "#", parts: 2)
        %{code: code, state: state}

      String.contains?(value, "code=") ->
        parse_querystring(value)

      true ->
        %{code: value}
    end
  end

  # --- 내부 구현: 플로우 조합 ---

  defp collect_code(url, state, callbacks, timeout, opts) do
    case start_callback_server(state, opts) do
      {:ok, server} ->
        try do
          notify_on_auth(callbacks, url, "브라우저 창이 열립니다. 로그인을 완료해주세요.")

          case CallbackServer.await_code(server, timeout: timeout) do
            {:ok, _code} = ok ->
              ok

            {:error, reason} = err ->
              Logger.debug("[openai-codex] 콜백 오류: #{inspect(reason)}, 프롬프트 폴백 시도")
              prompt_fallback(callbacks, state) || err
          end
        after
          CallbackServer.stop(server)
        end

      {:error, reason} ->
        Logger.warning("[openai-codex] 콜백 서버 바인딩 실패(#{inspect(reason)}). 수동 붙여넣기 모드로 전환합니다.")

        notify_on_auth(
          callbacks,
          url,
          "브라우저에서 로그인을 완료한 뒤 리다이렉트된 URL을 붙여 넣어주세요."
        )

        case prompt_fallback(callbacks, state) do
          {:ok, _} = ok -> ok
          nil -> {:error, {:no_callback_server, reason}}
          err -> err
        end
    end
  end

  defp start_callback_server(state, opts) do
    # 테스트에서는 :port/:host를 덮어쓸 수 있게 한다. 운영에서는 프로토콜이
    # 요구하는 기본값을 그대로 둬야 한다.
    server_opts =
      opts
      |> Keyword.take([:port, :host])

    try do
      CallbackServer.start(state, server_opts)
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  defp notify_on_auth(%{on_auth: on_auth}, url, instructions) when is_function(on_auth, 1) do
    on_auth.(%{url: url, instructions: instructions})
    :ok
  end

  defp notify_on_auth(_callbacks, _url, _instructions), do: :ok

  defp prompt_fallback(%{on_prompt: on_prompt} = _callbacks, expected_state)
       when is_function(on_prompt, 1) do
    case on_prompt.(%{
           message: "인가 코드(또는 리다이렉트된 URL 전체)를 붙여넣어 주세요:",
           allow_empty: false
         }) do
      {:ok, raw} ->
        parsed = parse_authorization_input(raw)

        cond do
          is_nil(Map.get(parsed, :code)) ->
            {:error, :missing_code}

          is_binary(Map.get(parsed, :state)) and Map.get(parsed, :state) != expected_state ->
            {:error, :state_mismatch}

          true ->
            {:ok, Map.fetch!(parsed, :code)}
        end

      {:error, _} = err ->
        err
    end
  end

  defp prompt_fallback(_callbacks, _state), do: nil

  # --- 내부 구현: HTTP ---

  defp build_authorize_url(challenge, state, originator) do
    query =
      URI.encode_query(%{
        "response_type" => "code",
        "client_id" => @client_id,
        "redirect_uri" => @redirect_uri,
        "scope" => @scope,
        "code_challenge" => challenge,
        "code_challenge_method" => "S256",
        "state" => state,
        "id_token_add_organizations" => "true",
        "codex_cli_simplified_flow" => "true",
        "originator" => originator
      })

    @authorize_url <> "?" <> query
  end

  defp exchange_code(code, verifier) do
    token_request(%{
      "grant_type" => "authorization_code",
      "client_id" => @client_id,
      "code" => code,
      "code_verifier" => verifier,
      "redirect_uri" => @redirect_uri
    })
  end

  defp refresh_token_request(refresh_token) do
    token_request(%{
      "grant_type" => "refresh_token",
      "refresh_token" => refresh_token,
      "client_id" => @client_id
    })
  end

  defp token_request(form) do
    case Req.post(@token_url,
           form: Enum.to_list(form),
           headers: [{"content-type", "application/x-www-form-urlencoded"}],
           decode_body: :json
         ) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        validate_token_response(body)

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:token_request_failed, status, body}}

      {:error, exception} ->
        {:error, {:transport, exception}}
    end
  end

  defp validate_token_response(%{
         "access_token" => access,
         "refresh_token" => refresh,
         "expires_in" => expires_in
       })
       when is_binary(access) and is_binary(refresh) and is_integer(expires_in) do
    {:ok, %{access: access, refresh: refresh, expires_in: expires_in}}
  end

  defp validate_token_response(body),
    do: {:error, {:invalid_token_response, body}}

  # --- 내부 구현: 입력 파싱 헬퍼 ---

  defp parse_full_url(value) do
    case URI.new(value) do
      {:ok, %URI{query: nil}} ->
        %{}

      {:ok, %URI{query: q}} ->
        params = URI.decode_query(q)
        take_code_state(params)

      _ ->
        %{}
    end
  end

  defp parse_querystring(value) do
    value
    |> URI.decode_query()
    |> take_code_state()
  end

  defp take_code_state(params) do
    %{}
    |> maybe_put(:code, Map.get(params, "code"))
    |> maybe_put(:state, Map.get(params, "state"))
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  # base64url 입력은 패딩이 없이 올 수 있다. Base.url_decode64 호출 전에
  # 길이를 4의 배수로 맞춰준다.
  defp pad_base64(s) do
    case rem(byte_size(s), 4) do
      0 -> s
      n -> s <> String.duplicate("=", 4 - n)
    end
  end
end
