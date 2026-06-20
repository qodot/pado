defmodule PadoLocal.SessionCwdPicker do
  @prompt "Select session cwd"

  def pick do
    case System.cmd(
           "osascript",
           ["-e", "POSIX path of (choose folder with prompt \"#{@prompt}\")"],
           stderr_to_stdout: true
         ) do
      {path, 0} ->
        {:ok, String.trim(path)}

      {output, _status} ->
        if String.contains?(output, "-128") do
          :cancel
        else
          {:error, String.trim(output)}
        end
    end
  end
end
