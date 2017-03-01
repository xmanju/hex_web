defmodule HexWeb.API.PackageController do
  use HexWeb.Web, :controller

  @sort_params ~w(name downloads inserted_at updated_at)

  def index(conn, params) do
    page     = HexWeb.Utils.safe_int(params["page"])
    search   = HexWeb.Utils.parse_search(params["search"])
    sort     = HexWeb.Utils.safe_to_atom(params["sort"] || "name", @sort_params)
    packages = Packages.search(page, 100, search, sort)

    when_stale(conn, packages, [modified: false], fn conn ->
      conn
      |> api_cache(:public)
      |> render(:index, packages: packages)
    end)
  end

  def show(conn, %{"name" => name}) do
    package = Packages.get(name)

    if package do
      when_stale(conn, package, fn conn ->
        package = Packages.preload(package)
        package = %{package | owners: Owners.all(package, :emails)}

        conn
        |> api_cache(:public)
        |> render(:show, package: package)
      end)
    else
      not_found(conn)
    end
  end
end
