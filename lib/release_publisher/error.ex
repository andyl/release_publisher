defmodule ReleasePublisher.Error do
  @moduledoc """
  Structured error returned by publishers and the runner.

  Every user-correctable failure in `release_publisher` is expressed as
  one of these, not a raw string. The Mix task runs `format/1` on the
  error to produce the three-line output the user sees:

      <publisher>: <step> failed
        <message>
        fix: <fix>

  `:publisher` is a short identity string (e.g. `"github"` or
  `"file[/mnt/releases/myapp]"`) produced by
  `ReleasePublisher.Publisher.identity/1`.
  """

  @type t :: %__MODULE__{
          publisher: String.t(),
          step: String.t(),
          message: String.t(),
          fix: String.t() | nil
        }

  defstruct [:publisher, :step, :message, :fix]

  @doc """
  Build a new error struct. All fields optional except `:step` and
  `:message`, which are required for a useful error.
  """
  @spec new(keyword()) :: t()
  def new(fields), do: struct!(__MODULE__, fields)

  @doc """
  Format the error into the three-line user-facing message.
  """
  @spec format(t()) :: String.t()
  def format(%__MODULE__{} = err) do
    publisher = err.publisher || "release_publisher"
    step = err.step || "error"
    message = err.message || ""

    lines = [
      "#{publisher}: #{step} failed",
      "  #{message}"
    ]

    lines =
      case err.fix do
        nil -> lines
        "" -> lines
        fix -> lines ++ ["  fix: #{fix}"]
      end

    Enum.join(lines, "\n")
  end
end
