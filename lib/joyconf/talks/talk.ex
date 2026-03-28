defmodule Joyconf.Talks.Talk do
  use Ecto.Schema
  import Ecto.Changeset

  schema "talks" do
    field :title, :string
    field :slug, :string

    has_many :talk_sessions, Joyconf.Talks.TalkSession

    timestamps(type: :utc_datetime)
  end

  def changeset(talk, attrs) do
    talk
    |> cast(attrs, [:title, :slug])
    |> validate_required([:title, :slug])
    |> validate_format(:slug, ~r/^[a-z0-9][a-z0-9-]*$/,
      message: "only lowercase letters, numbers, and hyphens"
    )
    |> validate_length(:slug, max: 100)
    |> unique_constraint(:slug)
  end
end
