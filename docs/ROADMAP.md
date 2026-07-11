# Roadmap

Project milestones and future work.

---

## Completed

### Day 1 — Foundation ✓

**Goals:** Establish multi-tenant architecture, store hierarchy, authentication, authorization, provisioning, and routing.

**Deliverables:**
- Ash domains and resources (6 resources, 2 domains)
- Policy-based authorization (4 policy checks)
- Password authentication strategy
- Tenant provisioning pipeline
- Subdomain routing via StoreRegistry
- Verification script (14/14 passing)

**Status:** Complete. See [DAY1_FOUNDATION.md](DAY1_FOUNDATION.md).

---

## Current

### Day 2 — Products & Storefront (Planned)

**Goals:** Build the product catalog and basic public storefront.

**Deliverables:**
- Product, Category, Variant, and Image resources
- Inventory management with stock tracking
- Public product browsing per store
- Product image upload and storage
- Basic storefront rendering

**Dependencies:** Day 1 foundation (complete)

**Success criteria:**
- A merchant can create products with categories and images
- A customer can browse products on a store's subdomain
- Stock levels track correctly

---

## Planned

### Day 3 — Orders & Checkout

**Goals:** Enable customers to place orders.

**Deliverables:**
- Order, OrderItem, and Cart resources
- Checkout flow
- Payment integration (Stripe or similar)
- Order status tracking
- Email notifications for order events

**Dependencies:** Product catalog (Day 2)

### Day 4 — Staff Management & JWT

**Goals:** Enable proper staff management and JWT authentication.

**Deliverables:**
- Staff invitation and management APIs
- Role-based access control (owner, manager, staff)
- JWT token configuration with proper secret management
- Session handling with tokens
- Password reset flow

**Dependencies:** Day 1 foundation (complete)

### Day 5 — Admin Dashboard

**Goals:** Build the merchant-facing admin interface.

**Deliverables:**
- Dashboard with key metrics
- Store settings management
- Staff management UI
- Product management UI
- Order management UI

**Dependencies:** Days 1-4

---

## Future

### Phase 2 — Advanced Features

- Custom domain support with SSL/TLS
- Multi-currency and tax configuration
- Shipping integration
- Discount and coupon system
- Customer accounts and order history

### Phase 3 — Intelligence

- AI-assisted product descriptions
- Sales analytics and reporting
- Inventory forecasting
- Customer segmentation
- Automated marketing emails

### Phase 4 — Multi-Channel

- POS integration
- Messaging channel (WhatsApp, SMS)
- Marketplace integrations
- API for third-party apps
