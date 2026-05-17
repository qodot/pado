defmodule Pado.Agent.Session.CompactionSummary do
  @type t :: %__MODULE__{
          summary: String.t(),
          first_kept_seq: non_neg_integer(),
          tokens_before: non_neg_integer() | nil
        }

  @enforce_keys [:summary, :first_kept_seq]
  defstruct [:summary, :first_kept_seq, tokens_before: nil]
end
