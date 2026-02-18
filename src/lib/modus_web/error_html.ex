defmodule ModusWeb.ErrorHTML do
  @moduledoc "ModusWeb.ErrorHTML — auto-documented by Probatio quality pass."
  use ModusWeb, :html
  def render(template, _assigns), do: Phoenix.Controller.status_message_from_template(template)
end
