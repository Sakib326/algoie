# Algoie

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://phoenix.hexdocs.pm/deployment.html).

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://phoenix.hexdocs.pm/overview.html
* Docs: https://phoenix.hexdocs.pm
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
# Email delivery

Development emails use Swoosh's local mailbox at `/dev/mailbox`, and tests use the test adapter.
Production email delivery is configured entirely through environment variables:

```text
EMAIL_PROVIDER=resend
RESEND_API_KEY=re_...
EMAIL_FROM_NAME=Algoie
EMAIL_FROM_ADDRESS=notifications@example.com
EMAIL_REPLY_TO=support@example.com
APP_URL=https://example.com
```

`EMAIL_PROVIDER` supports `resend` and `local`. Use `local` only for development-style
deployments where messages should remain in the Swoosh mailbox instead of being sent.
