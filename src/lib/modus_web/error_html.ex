defmodule ModusWeb.ErrorHTML do
  use ModusWeb, :html
  def render(template, _assigns), do: Phoenix.Controller.status_message_from_template(template)
end
