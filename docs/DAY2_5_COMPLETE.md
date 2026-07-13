# Day 2.5 Complete — Auth UI, Session Handling, Dashboard Shell

## What was added

### 1. Registration Flow
- **`/register`** — Custom LiveView (`AlgoieWeb.RegistrationLive`) that creates a new Tenant + Store + Owner User + StoreStaff membership in a single atomic operation via `Algoie.Tenants.Provisioner.create_tenant_with_setup/1`
- Form fields: Business Name, Store Name, Store URL (slug with live availability check), Email, Password, Password Confirmation
- Slug availability is checked in real-time via debounced LiveView events against the `StoreRegistry` table
- All validation (required fields, password match, password length ≥8, slug uniqueness) runs client-side before submission
- On success, shows a confirmation page with a link to sign in
- Uses `Layouts.app` public layout (no auth required)

### 2. Login Flow
- Uses `ash_authentication_phoenix`'s built-in sign-in components via `sign_in_route` macro with DaisyUI overrides
- **`AlgoieWeb.AuthController.success/4`** handles post-login: resolves the user's store context, stores tenant/store_id/store_name/user_stores in the Phoenix session, then redirects to `/dashboard`
- Failed login shows generic "Invalid email or password" message (no account enumeration)
- **`AlgoieWeb.AuthController.sign_out/2`** clears the session and redirects to home

### 3. Session & Tenant Context Wiring
- **`AlgoieWeb.Plugs.LoadTenantFromSession`** — reads `store_tenant` from session and sets Ash tenant context on every request
- **`AlgoieWeb.Live.OnDashboardMount`** — OnMount hook for all dashboard routes that:
  - Redirects to `/sign-in` if no `current_user` in socket assigns
  - Loads tenant, store_id, store_name, user_stores from session
  - Falls back to loading from user's StoreStaff memberships if session data is missing
  - Sets `current_scope` for Ash authorization
- **`Algoie.Accounts.UserContext`** — Enhanced with `load_all_user_stores/1` and `get_user_tenants/1` helpers for multi-store support

### 4. Store-Switcher
- **`/store-select`** — LiveView that lists all stores the authenticated user has access to
- Clicking a store redirects to **`/switch-store/:store_id`** (controller action) which updates the session's tenant/store_id/store_name and redirects to dashboard
- Dashboard sidebar shows the current store name; if the user has multiple stores, a "Switch store" link appears in the sidebar

### 5. Dashboard Shell (Layout)
- **`Layouts.dashboard`** now accepts: `tenant`, `store_id`, `store_name`, `user_stores` attributes
- Sidebar navigation includes:
  - Dashboard (home)
  - Products
  - Categories
  - Brands
  - Orders
  - **Conversations** (placeholder — Day 3–4)
  - **Ad Campaigns** (placeholder — Day 5)
- User section at bottom shows avatar (first letter of email), user name, and logout button
- All dashboard templates updated to pass the new layout attributes

### 6. Route Protection
- All dashboard routes use `ash_authentication_live_session :dashboard` which requires a valid auth token in the session
- `OnDashboardMount` hook ensures user, tenant, and store context are resolved before any dashboard page renders
- Unauthenticated access to any `/dashboard/*` route redirects to `/sign-in`

## Verification

### Test results
```
5 tests, 0 failures
```

### Manual verification
1. **Register page loads** → `GET /register` → HTTP 200, form with all fields renders
2. **Sign-in page loads** → `GET /sign-in` → HTTP 200, ash_authentication_phoenix form renders
3. **Dashboard redirects when unauthenticated** → `GET /dashboard` → HTTP 302 → `/sign-in`
4. **Home page loads** → `GET /` → HTTP 200

### Full registration flow (manual)
1. Navigate to `/register`
2. Fill in: Business Name, Store Name, Store URL, Email, Password, Password Confirmation
3. Store URL availability shows in real-time ("my-store.localhost:4000 is available")
4. Submit → success page shown ("Store Created!")
5. Navigate to `/sign-in` → log in with the credentials
6. Redirected to `/dashboard` with correct store context

### Login flow (manual)
1. Navigate to `/sign-in`
2. Enter credentials → on success, redirected to `/dashboard`
3. Dashboard shows correct store name in sidebar
4. Wrong password → generic "Invalid email or password" flash message

### Store switching (manual)
1. Log in as a user with multiple store memberships
2. Sidebar shows "Switch store" link
3. Click → `/store-select` shows list of accessible stores
4. Click a store → redirected to dashboard with new store context
5. Sidebar now shows the newly selected store name

### Route protection (manual)
1. Try to access `/dashboard` while logged out → redirected to `/sign-in`
2. Try to access `/dashboard/products` while logged out → redirected to `/sign-in`

## Files changed/created

### New files
- `lib/algoie_web/live/registration_live.ex` — Registration LiveView
- `lib/algoie_web/live/registration_live.html.heex` — Registration template
- `lib/algoie_web/live/store_selector_live.ex` — Store selector LiveView
- `lib/algoie_web/live/store_selector_live.html.heex` — Store selector template
- `lib/algoie_web/live/conversation_live/index.ex` — Placeholder LiveView
- `lib/algoie_web/live/conversation_live/index.html.heex` — Placeholder template
- `lib/algoie_web/live/campaign_live/index.ex` — Placeholder LiveView
- `lib/algoie_web/live/campaign_live/index.html.heex` — Placeholder template
- `lib/algoie_web/controllers/store_switch_controller.ex` — Store switching controller

### Modified files
- `lib/algoie_web/router.ex` — Added registration, store-select, switch-store routes; moved store-select into dashboard live_session
- `lib/algoie_web/controllers/auth_controller.ex` — Enhanced to resolve and store full store context in session
- `lib/algoie_web/live/on_dashboard_mount.ex` — Added multi-store context loading with session fallback
- `lib/algoie/accounts/user_context.ex` — Added `load_all_user_stores/1` and `get_user_tenants/1`
- `lib/algoie_web/components/layouts.ex` — Added store-switcher, Conversations/Ad Campaigns nav items, new layout attrs
- `lib/algoie_web/live/dashboard_live.ex` — No changes needed (OnDashboardMount handles assigns)
- `lib/algoie_web/live/dashboard_live.html.heex` — Updated to pass new layout attributes
- `lib/algoie_web/live/product_live/index.html.heex` — Updated layout call
- `lib/algoie_web/live/category_live/index.html.heex` — Updated layout call
- `lib/algoie_web/live/brand_live/index.html.heex` — Updated layout call
- `lib/algoie_web/live/order_live/index.html.heex` — Updated layout call
- `lib/algoie_web/live/order_live/show.html.heex` — Updated layout call

## Known limitations & deferred items

- **Password reset/forgot-password flow** — Not implemented. The `reset_route` is configured in the router but no custom UI exists. This is a critical production feature but not blocking for Day 3–4.
- **Email verification on signup** — Not implemented. Users can register with any email address.
- **Social/OAuth login** — Not implemented. Only password-based authentication is available.
- **Dynamic roles** — Only `owner` and `staff` roles exist. No custom role definitions.
- **2FA/MFA** — Not implemented.
- **Session expiry** — Sessions persist until explicit sign-out. No automatic timeout.
- **CSRF on store-switch** — The `/switch-store/:store_id` route uses GET, which is acceptable for session switching but should use POST for production security.

## Future improvements
- Add password reset flow with email sending
- Add email verification on registration
- Implement OAuth/social login providers
- Add session timeout and refresh tokens
- Add audit logging for store switches
- Make Conversations and Ad Campaigns functional (Day 3–5)
- Add role-based access control UI (invite staff, manage roles)
