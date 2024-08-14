defmodule SyncWeb.PageController do
  use SyncWeb, :controller

  def home(conn, _opts) do
    # TODO: maybe cache this in memory instead of reading the file every time
    content =
      File.read!(Application.app_dir(:sync, "priv/static/assets/index.html"))
      |> String.replace("</head>", """
        <meta name="csrf-token" content="#{get_csrf_token()}" />
      </head>
      """)

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, content)
  end
end
