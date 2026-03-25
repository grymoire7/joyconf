defmodule Joyconf.Talks do
  alias Joyconf.Repo
  alias Joyconf.Talks.Talk

  def list_talks, do: Repo.all(Talk)

  def get_talk!(id), do: Repo.get!(Talk, id)

  def get_talk_by_slug(slug), do: Repo.get_by(Talk, slug: slug)

  def delete_talk(%Talk{} = talk), do: Repo.delete(talk)

  def create_talk(attrs) do
    %Talk{}
    |> Talk.changeset(attrs)
    |> Repo.insert()
  end

  def generate_slug(title) do
    title
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s]/, "")
    |> String.trim()
    |> String.replace(~r/\s+/, "-")
  end
end
