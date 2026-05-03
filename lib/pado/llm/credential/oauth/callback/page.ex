defmodule Pado.LLM.Credential.OAuth.Callback.Page do
  def success_html(message \\ "인증이 완료되었습니다. 이 창을 닫아도 됩니다.") do
    render(%{
      title: "인증 성공",
      heading: "인증 성공",
      message: message,
      details: nil
    })
  end

  def error_html(message, details \\ nil) do
    render(%{
      title: "인증 실패",
      heading: "인증 실패",
      message: message,
      details: details
    })
  end

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

  defp escape(value) when is_binary(value) do
    value
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end
end
