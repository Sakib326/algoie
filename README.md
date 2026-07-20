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

## Platform and tenant administration

`APP_URL` is the single canonical public origin, including its scheme and any non-default port.
For example, `APP_URL=http://localhost:4100` produces
`http://localhost:4100/tenant/<workspace>/dashboard` and
`http://<store-slug>.localhost:4100/dashboard`. `APP_DOMAIN` is only an optional
host-routing override for backwards compatibility.

Tenant owners and staff use `<store-slug>.<APP_URL host>/dashboard`. The apex
`/dashboard` and `/admin` routes are reserved for SaaS owners whose account email is listed in:

```text
PLATFORM_ADMIN_EMAILS=founder@example.com,ops@example.com
SESSION_COOKIE_DOMAIN=.example.com
```

This list is authorization configuration, not an account creator; each listed email must belong
to an existing platform user. `SESSION_COOKIE_DOMAIN` must cover the apex and store subdomains so
an authenticated session can safely follow store-switch and post-login redirects.
