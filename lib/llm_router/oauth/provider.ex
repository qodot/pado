defmodule LLMRouter.OAuth.Provider do
  @moduledoc """
  OAuth 기반 LLM 프로바이더의 behaviour.

  pi-ai의 `OAuthProviderInterface`를 Elixir 관용구로 옮긴 것이다.
  구현체는 상태 없는 모듈로서 다음을 수행한다.

    * authorize URL을 만들고 인가 코드를 받아들인다.
    * 코드를 크레덴셜로 교환한다.
    * 만료된 크레덴셜을 갱신한다.
    * HTTP `Authorization` 헤더에 쓸 API 키(토큰) 문자열을 도출한다.

  크레덴셜 저장, 갱신 스케줄링, 사용자 상호작용(브라우저·터미널·웹 UI 등)
  은 전부 호출자 책임이다. 사용자 상호작용은 `c:login/2`의 `callbacks`
  맵으로 주입한다.

  ## 설계 메모

  * 이 behaviour는 크레덴셜이 어디에 저장되는지를 규정하지 않는다.
    `c:login/2`는 `LLMRouter.OAuth.Credentials.t/0`만 돌려준다.
  * `localhost` redirect URI를 쓰는 프로바이더
    (`uses_callback_server?/0 == true`)는 내부에서 단명 HTTP 리스너를
    띄우도록 기대된다. `LLMRouter.OAuth.CallbackServer`를 쓰는 것이
    표준 경로다. 이는 정책 선택이 아니라 OAuth 프로토콜 자체의 제약이다.
  """

  alias LLMRouter.OAuth.Credentials

  @typedoc """
  로그인 플로우 시작 시점에 사용자에게 전달되는 정보.

    * `:url` — 브라우저로 열어야 하는 authorize URL.
    * `:instructions` — 선택. 사람이 읽는 안내 문구(예: "브라우저 창이 열린다").
  """
  @type auth_info :: %{
          required(:url) => String.t(),
          optional(:instructions) => String.t()
        }

  @typedoc "수동 입력 폴백용 구조화된 프롬프트."
  @type prompt :: %{
          required(:message) => String.t(),
          optional(:placeholder) => String.t(),
          optional(:allow_empty) => boolean()
        }

  @typedoc """
  프로바이더가 `c:login/2` 도중 호출하는 상호작용 콜백들.

  `:on_auth`만 필수이며, 프로바이더는 authorize URL을 확보한 시점에
  정확히 한 번 호출한다.

    * `:on_auth` — 필수. URL/안내문을 받아 호출자 쪽에서 브라우저를 열거나
      UI를 렌더링한다.
    * `:on_prompt` — 자유 형식 입력(예: 붙여 넣은 리다이렉트 URL)을
      요청한다. `{:error, reason}`을 돌려주면 로그인이 중단된다.
    * `:on_progress` — 선택. 진행 상황 메시지.
    * `:on_manual_code_input` — 선택. 지정하면 프로바이더가 콜백 서버와
      이 함수의 완료를 경쟁시켜 먼저 끝나는 쪽을 채택한다. 콜백 서버가
      포트를 바인딩하지 못할 때(이미 사용 중, 방화벽 등) 사용자가
      수동으로 붙여 넣는 경로가 필요한 경우를 위한 것이다.
  """
  @type callbacks :: %{
          required(:on_auth) => (auth_info -> any),
          optional(:on_prompt) => (prompt -> {:ok, String.t()} | {:error, term}),
          optional(:on_progress) => (String.t() -> any),
          optional(:on_manual_code_input) => (-> {:ok, String.t()} | {:error, term})
        }

  @typedoc "CLI와 저장소 키에 쓰이는 안정된 식별자."
  @type id :: atom

  @doc "안정된 식별자(예: `:openai_codex`)."
  @callback id() :: id

  @doc "사람이 읽는 이름."
  @callback name() :: String.t()

  @doc """
  고정된 `localhost` 리다이렉트 URI에 로컬 콜백 서버가 필요한지 여부.
  """
  @callback uses_callback_server?() :: boolean

  @doc """
  OAuth 로그인 플로우를 실행하고 새로 발급받은 크레덴셜을 반환한다.

  `opts`는 프로바이더마다 다르지만 보통 다음을 포함한다.

    * `:originator` — OAuth `originator` 파라미터(클라이언트 식별자).
    * `:timeout` — 인가 코드 대기 시간(밀리초).
    * `:port`, `:host` — 콜백 서버 바인딩(테스트용).
  """
  @callback login(callbacks, keyword) :: {:ok, Credentials.t()} | {:error, term}

  @doc """
  크레덴셜을 갱신한다.

  구현체는 refresh 토큰이 로테이션되더라도 **항상 전체가 채워진 새
  크레덴셜**을 반환해야 한다. 반환된 값을 저장하는 것은 호출자의 책임이다.
  """
  @callback refresh(Credentials.t()) :: {:ok, Credentials.t()} | {:error, term}

  @doc """
  크레덴셜로부터 bearer 토큰(또는 동등물)을 도출한다.

  대부분 `credentials.access`를 그대로 반환하지만, 변환이 필요한
  프로바이더(접두사 붙이기, 디코드 등)도 있다.
  """
  @callback api_key(Credentials.t()) :: String.t()

  @optional_callbacks [uses_callback_server?: 0]
end
