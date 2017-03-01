defmodule HexWeb.Requirement do
  use HexWeb.Web, :model
  require Logger

  schema "requirements" do
    field :app, :string
    field :requirement, :string
    field :optional, :boolean

    # The name of the dependency used to find the package
    field :name, :string, virtual: true

    belongs_to :release, Release
    belongs_to :dependency, Package
  end

  def changeset(requirement, params, dependencies) do
    cast(requirement, params, ~w(name app requirement optional))
    |> put_assoc(:dependency, dependencies[params["name"]])
    |> validate_required(~w(name app requirement optional)a)
    |> validate_required(:dependency, message: "package does not exist")
    |> validate_requirement(:requirement)
  end

  # TODO: Raise validation error if field is not set
  def build_all(release_changeset) do
    dependencies = preload_dependencies(release_changeset.params["requirements"])

    release_changeset =
      release_changeset
      |> cast_assoc(:requirements, with: &changeset(&1, &2, dependencies))

    if release_changeset.valid? do
      requirements =
        get_change(release_changeset, :requirements, [])
        |> Enum.map(&Ecto.Changeset.apply_changes/1)

      build_tools = get_field(release_changeset, :meta).build_tools

      {time, result} = :timer.tc(fn ->
        case Resolver.run(requirements, build_tools) do
          :ok ->
            release_changeset
          {:error, reason} ->
            release_changeset = update_in(release_changeset.changes.requirements, fn req_changesets ->
              Enum.map(req_changesets, fn req_changeset ->
                add_error(req_changeset, :requirement, reason)
              end)
            end)
            %{release_changeset | valid?: false}
        end
      end)

      Logger.warn "DEPENDENCY_RESOLUTION_COMPLETED (#{div time, 1000}ms)"
      result
    else
      release_changeset
    end

    # TODO: Remap requirements errors to hex http spec
  end

  defp preload_dependencies(requirements)  do
    names = requirement_names(requirements)
    from(p in Package, where: p.name in ^names, select: {p.name, p})
    |> HexWeb.Repo.all
    |> Enum.into(%{})
  end

  defp requirement_names(requirements) when is_list(requirements) do
    Enum.flat_map(requirements, fn
      req when is_map(req) -> [req["name"]]
      _ -> []
    end)
    |> Enum.filter(&is_binary/1)
  end
  defp requirement_names(_requirements), do: []
end
