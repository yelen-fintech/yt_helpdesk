# lib/imap_api_client/mailer.ex
defmodule ImapApiClient.Mailer do
  @moduledoc """
  Swoosh mailer configuration module.
  """
  use Swoosh.Mailer, otp_app: :imap_api_client
end
