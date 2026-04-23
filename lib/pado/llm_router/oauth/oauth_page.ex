defmodule Pado.LLMRouter.OAuth.OAuthPage do
  @moduledoc """
  OAuth 콜백 랜딩 페이지를 위한 최소 HTML 템플릿.

  pi-ai의 `utils/oauth/oauth-page.ts`와 대응된다. 프로바이더가
  `localhost:1455`로 리다이렉트시킨 뒤 사용자 브라우저에 표시된다.
  외부 CSS/JS 의존성이 없도록 의도적으로 자기완결 형태로 유지한다.
  """

  @doc "콜백이 정상 처리되었을 때 표시되는 성공 페이지."
  @spec success_html(String.t()) :: String.t()
  def success_html(message \\ "인증이 완료되었습니다. 이 창을 닫아도 됩니다.") do
    render(%{
      title: "인증 성공",
      heading: "인증 성공",
      message: message,
      details: nil
    })
  end

  @doc "콜백이 거절되었을 때 표시되는 오류 페이지."
  @spec error_html(String.t(), String.t() | nil) :: String.t()
  def error_html(message, details \\ nil) do
    render(%{
      title: "인증 실패",
      heading: "인증 실패",
      message: message,
      details: details
    })
  end

  # --- 내부 구현 ---

  defp render(%{title: title, heading: heading, message: message, details: details}) do
    details_block =
      case details do
        nil -> ""
        d -> ~s(<div class="details">#{escape(d)}</div>)
      end

    """
    <!doctype html>
    <html lang="ko">
    <head>
      <meta charset="utf-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1" />
      <title>#{escape(title)}</title>
      <style>
        * { box-sizing: border-box; }
        html { color-scheme: light; }
        body {
          margin: 0;
          min-height: 100vh;
          display: flex;
          align-items: center;
          justify-content: center;
          padding: 24px;
          background: #fafafa;
          color: #0f0f10;
          font-family: ui-sans-serif, system-ui, -apple-system, sans-serif;
          text-align: center;
        }
        main { max-width: 560px; }
        h1 { margin: 0 0 10px; font-size: 28px; font-weight: 650; }
        p { margin: 0; line-height: 1.7; color: #52525b; font-size: 15px; }
        .details {
          margin-top: 16px;
          font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
          font-size: 13px;
          color: #52525b;
          white-space: pre-wrap;
          word-break: break-word;
        }
      </style>
    </head>
    <body>
      <main>
        <h1>#{escape(heading)}</h1>
        <p>#{escape(message)}</p>
        #{details_block}
      </main>
    </body>
    </html>
    """
  end

  # 입력은 짧고 알려진 문자열이라고 가정하고 간단한 HTML 이스케이프만 수행한다.
  defp escape(value) when is_binary(value) do
    value
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end
end
