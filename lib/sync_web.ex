defmodule SyncWeb do
  @moduledoc """
  The entrypoint for defining your web interface, such
  as controllers, components, channels, and so on.

  This can be used in your application as:

      use SyncWeb, :controller
      use SyncWeb, :html

  The definitions below will be executed for every controller,
  component, etc, so keep them short and clean, focused
  on imports, uses and aliases.

  Do NOT define functions inside the quoted expressions
  below. Instead, define additional modules and import
  those modules here.
  """

  def static_paths, do: ~w(assets fonts images favicon.ico robots.txt)

  # TODO vite suffixes the bundles for cache busting, so we need to
  # read the manifest and cache the lookup. A proper approach would
  # be to cache this into an ETS lookup in the same way the phoenix
  # manifest is cached.
  #
  # We need to run the build to ensure it exists before we read it
  System.cmd("npm", ["run", "build"], cd: "assets")
  @manifest_path "priv/static/assets/manifest.json"
  @external_resource @manifest_path
  @manifest Jason.decode!(File.read!(@manifest_path))
  @index_js_paths @manifest
                  |> Map.fetch!("index.html")
                  |> Map.fetch!("file")
                  |> List.wrap()
                  |> Enum.map(&"/assets/#{&1}")

  @index_css_paths @manifest
                   |> Map.fetch!("index.html")
                   |> Map.fetch!("css")
                   |> List.wrap()
                   |> Enum.map(&"/assets/#{&1}")

  def index_js_paths do
    @index_js_paths
  end

  def index_css_paths do
    @index_css_paths
  end

  def router do
    quote do
      use Phoenix.Router, helpers: false

      # Import common connection and controller functions to use in pipelines
      import Plug.Conn
      import Phoenix.Controller
      import Phoenix.LiveView.Router
    end
  end

  def channel do
    quote do
      use Phoenix.Channel
    end
  end

  def controller do
    quote do
      use Phoenix.Controller,
        formats: [:html, :json],
        layouts: [html: SyncWeb.Layouts]

      import Plug.Conn
      import SyncWeb.Gettext

      unquote(verified_routes())
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView,
        layout: {SyncWeb.Layouts, :app}

      unquote(html_helpers())
    end
  end

  def live_component do
    quote do
      use Phoenix.LiveComponent

      unquote(html_helpers())
    end
  end

  def html do
    quote do
      use Phoenix.Component

      # Import convenience functions from controllers
      import Phoenix.Controller,
        only: [get_csrf_token: 0, view_module: 1, view_template: 1]

      # Include general helpers for rendering HTML
      unquote(html_helpers())
    end
  end

  defp html_helpers do
    quote do
      # HTML escaping functionality
      import Phoenix.HTML
      # Core UI components and translation
      import SyncWeb.CoreComponents
      import SyncWeb.Gettext

      # Shortcut for generating JS commands
      alias Phoenix.LiveView.JS

      # Routes generation with the ~p sigil
      unquote(verified_routes())
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: SyncWeb.Endpoint,
        router: SyncWeb.Router,
        statics: SyncWeb.static_paths()
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/live_view/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
