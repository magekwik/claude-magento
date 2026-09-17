# ACL, authentication and CSRF

*Target: Magento Open Source 2.4.4–2.4.9, PHP 8.1–8.5 (support varies by release).* Rules cited by ID are in `magento:conventions` (S1 authorisation, S2 CSRF and HTTP verbs, S4 secrets, S6 input). Admin controllers, menus and the module scaffold are in `magento:module`; this file covers the permission model they share with the web API, how callers authenticate, and what protects a browser-facing controller.

## `acl.xml`

`etc/acl.xml`, validated by `vendor/magento/framework/Acl/etc/acl.xsd` (URN `urn:magento:framework:Acl/etc/acl.xsd`):

```xml
<?xml version="1.0"?>
<config xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="urn:magento:framework:Acl/etc/acl.xsd">
    <acl>
        <resources>
            <resource id="Magento_Backend::admin">
                <resource id="Magento_Catalog::catalog">
                    <resource id="Acme_Catalog::brands" title="Brands" translate="title" sortOrder="200">
                        <resource id="Acme_Catalog::brands_view" title="View" translate="title" sortOrder="10"/>
                        <resource id="Acme_Catalog::brands_manage" title="Manage" translate="title" sortOrder="20"/>
                    </resource>
                </resource>
            </resource>
        </resources>
    </acl>
</config>
```

- `id` must match `Vendor_Module::name` (`([A-Z]+[a-zA-Z0-9]+)_[A-Z]+[A-Za-z0-9]+::[A-Za-z_0-9]+`) and be unique across every module's `acl.xml`; `title` is 3–50 characters and is what the role editor shows; `sortOrder` orders siblings; `disabled="true"` hides a resource. Nest under the core resource whose branch you want in the role tree — `Magento_Backend::admin` for a top-level entry, `Magento_Catalog::catalog` to sit under *Catalog* (then `Magento_Catalog` belongs in `module.xml` `<sequence>`, A8). Files merge across modules, so re-declaring a core id with children attaches yours beneath it.
- One resource per distinct permission: reading and writing are different rights (`brands_view` / `brands_manage`), a parent resource is the "everything under it" right. The same ids serve every consumer:

| Consumer | Where the id goes |
|---|---|
| Admin controller | `public const ADMIN_RESOURCE = 'Acme_Catalog::brands_manage';` on a `Magento\Backend\App\Action` subclass — `_isAllowed()` checks it before `execute()`; failure renders *Access Denied* (`magento:module`) |
| Admin menu | `etc/adminhtml/menu.xml` `<add … resource="Acme_Catalog::brands"/>` — hides the entry from roles without it |
| Config section | `etc/adminhtml/system.xml` `<section><resource>Acme_Catalog::config</resource>` (Q6) |
| REST/SOAP route | `etc/webapi.xml` `<resources><resource ref="Acme_Catalog::brands_view"/></resources>` |
| Extension attribute | `etc/extension_attributes.xml` `<attribute><resources><resource ref="…"/></resources>` — the attribute is omitted from API output for callers without it |
| Layout block | `<block … aclResource="Acme_Catalog::brands"/>` in admin layout |

`acl.xml` is read into the `config` cache: `bin/magento cache:clean config` before a new resource appears in the role editor.

### How roles resolve a resource

- A role is either *All* (one `allow` row for `Magento_Backend::all`) or *Custom*: on save, `Rules::saveRel()` writes one `authorization_rule` row per resource in the whole tree — `allow` for every ticked id **plus `Magento_Backend::admin`**, `deny` for the rest. That appended row is why `Magento_Backend::admin` is held by every role that has anything at all and is useless as a guard (S1).
- A resource that has no row for a role (added after the role was saved) is denied to that role until the role is re-saved with it ticked; *All* roles are allowed everything, new ids included. When you ship a new resource, tell the merchant which roles need re-saving.
- In the role tree, ticking a parent ticks every descendant, but a child can be ticked on its own and rules are stored per id — a route guarded by `Acme_Catalog::brands` is satisfied only by roles holding that exact id (or *All*), not by roles holding only `brands_view`. Guard routes with the leaf you mean.
- Integrations (System → Extensions → Integrations → API tab) are roles too: *Resource Access: All* or a *Custom* tree from the same `acl.xml`, saved through the same code. Their user type is `integration`, admin users are `admin`; both are authorised by their role's rows.

## `<resource ref>` in `webapi.xml`

`RequestValidator` runs `Magento\Framework\Webapi\Authorization::isAllowed()` over the route's refs; every ref must pass (AND), otherwise 401 `The consumer isn't authorized to access %resources.` with the refs in `parameters.resources`. Three kinds of ref:

| Ref | Who passes | Mechanism |
|---|---|---|
| `Acme_Catalog::brands_view` (any `acl.xml` id) | admin users and integrations whose role allows it | `AclRetriever` → role rules |
| `self` | any request carrying a valid **customer** token (or customer session over XHR) for a customer of this website | `Magento_Customer`'s `CustomerAuthorization` plugin answers "allowed" when the user type is customer *and* the current store is among the customer's shared store ids (`Customer\Model\Customer\Authorization::isAllowed()`); admins and integrations do **not** pass `self` |
| `anonymous` | everyone, token or not | `GuestAuthorization` plugin short-circuits `isAllowed()` |

- `self` says "some customer is logged in", nothing about *which* record the call touches. Pair it with `<data><parameter name="customerId" force="true">%customer_id%</parameter></data>` (or `cartId` → `%cart_id%` in checkout modules) so the service works on the token's customer, and write the service to take that id — never one from the body.
- `anonymous` is the whole of the route's protection: use it for public reads only (S1) and validate input harder (S6). Core catalogue/CMS/store reads are guarded by real resources (`Magento_Catalog::products`, `Magento_Cms::page`, …) and become anonymous only when *Stores → Configuration → Services → Magento Web API → Web API Security → Allow Anonymous Guest Access* is Yes (`webapi/webapisecurity/allow_insecure`, default No).
- A guest (no token, no session) has exactly the `anonymous` permission; a customer has `self` (+ `anonymous`); admins and integrations have their role. There is no way to grant a customer an `acl.xml` resource — customer-facing functionality is `self` + parameter override, or GraphQL.

## Authentication

Every API request is resolved to a user context by `CompositeUserContext` in `webapi_rest` `di.xml` sort order: `Authorization: Bearer <token>` (`TokenUserContext`, 10 — admin, customer or integration token), customer session (`CustomerSessionUserContext`, 20), admin session (`AdminSessionUserContext`, 30), OAuth 1.0a signature (`OauthUserContext`, 40 — integration), else guest (100).

### Admin and customer tokens

| | Endpoint | Body | Lifetime (`oauth/access_token_lifetime/*`, hours; empty = never expires) |
|---|---|---|---|
| Customer | `POST /V1/integration/customer/token` | `{"username": "<email>", "password": "…"}` | `customer` = 1 |
| Admin, 2FA disabled | `POST /V1/integration/admin/token` | `{"username", "password"}` | `admin` = 4 |
| Admin, 2FA enabled (default) | `POST /V1/tfa/provider/google/authenticate` (other providers: `authy/authenticate`, `duo_security/authenticate`, `u2fkey/verify`) | `{"username", "password", "otp"}` | `admin` = 4 |

- The response is a bare JSON string; send it back as `Authorization: Bearer <token>` with `Content-Type: application/json`. Config lives at *Stores → Configuration → Services → OAuth → Access Token Expiration*; an expired token is treated as no token (guest), not as an error, so a sudden 401 on a previously working call usually means expiry.
- With `Magento_TwoFactorAuth` enabled, `POST /V1/integration/admin/token` checks the credentials and then throws (400) `Please use the 2fa provider-specific endpoints to obtain a token.` (or, for a user who has not configured 2FA yet, sends the configuration email and reports that). Scripts therefore either use an Integration, or the provider endpoint with a TOTP. `bin/magento module:disable Magento_TwoFactorAuth` is for local development only.
- Six failed token requests lock the account for 30 minutes (`oauth/authentication_lock/max_failures_count` = 6, `timeout` = 1800 s). Customers with unconfirmed accounts get `EmailNotConfirmedException`.
- Revocation: `POST /V1/integration/customer/revoke-customer-token` (`self`) or the `revokeCustomerToken` mutation; tokens are revoked automatically when the account is deactivated or deleted and when a customer's email changes; expired rows are purged hourly by the `expired_tokens_cleanup` cron job. Never log or store tokens in plain text (S4).

### Integrations (OAuth 1.0a)

System → Extensions → Integrations → *Add New Integration*: name, the admin's password, *API* tab → resource tree; save, then *Activate* (for a callback-URL integration the store posts the consumer credentials to the app and completes the two-legged handshake `POST /oauth/token/request` → `POST /oauth/token/access`; for a manual one the dialog shows the four keys). The four credentials: **Consumer Key**, **Consumer Secret**, **Access Token**, **Access Token Secret**.

Two ways to call:

1. **OAuth 1.0a signed requests** (always available): `Authorization: OAuth oauth_consumer_key="…", oauth_nonce="…", oauth_signature_method="HMAC-SHA256", oauth_signature="…", oauth_timestamp="…", oauth_token="…", oauth_version="1.0"` — `HMAC-SHA256` is the only accepted method in 2.4.9 (`HMAC-SHA1` is deprecated and rejected). Any OAuth 1.0a client library does the signing.
2. **Access token as Bearer** (`Authorization: Bearer <access token>`): off since 2.4.4; enable with `bin/magento config:set oauth/consumer/enable_integration_as_bearer 1` (*Stores → Configuration → Services → OAuth → Consumer Settings → Allow OAuth Access Tokens to be used as standalone Bearer tokens*). While it is off, a Bearer call with an integration token is a guest request and fails with 401 on any non-anonymous route.

Integration tokens do not expire; rotate by re-activating the integration. Integrations pass `acl.xml` resources, never `self`.

### Session-based

A customer logged into the storefront can call REST from the browser with the session cookie, but only over XHR: `Magento\Webapi\Model\Plugin\Authorization\CustomerSessionUserContext` returns the session's customer id only when `X-Requested-With: XMLHttpRequest` is present (Luma's `mage/storage` sends it; this is the CSRF guard, since a cross-origin XHR with that header needs CORS approval). This is how Luma checkout calls `/rest/default/V1/carts/mine/…`. API requests carry no form key.

### GraphQL

- Customers: `mutation { generateCustomerToken(email: "…", password: "…") { token } }`, then `Authorization: Bearer <token>`; same 1 h lifetime and lockout as REST customer tokens; `mutation { revokeCustomerToken { result } }` to log out. There is no admin token mutation and admin tokens are not meant for GraphQL — use REST for admin work.
- Anything that reads or writes a specific customer's data needs the token: `customer` (and its `orders`), `customerCart`, `wishlist`, `updateCustomer`, `createCustomerAddress`, `setShippingAddressesOnCart` on a customer cart, `placeOrder` on a customer cart. Guest carts work without a token through the masked `cart_id` (`createGuestCart` since 2.4.7; `createEmptyCart` on 2.4.4–2.4.6, still present but deprecated in 2.4.9 in favour of `createGuestCart` / `customerCart`); a guest cart used *with* a customer token is refused (`The current user cannot perform operations on cart "…"`, `graphql-authorization`) — merge it with `mergeCarts` after login instead. Public catalogue queries (`products`, `categories`, `cmsPage`, `storeConfig`) take no token.
- In a resolver, `$context->getExtensionAttributes()->getIsCustomer()` / `$context->getUserId()` identify the caller; throw `GraphQlAuthorizationException(__('The current customer isn\'t authorized.'))` when a guest hits a customer-only field (403; `graphql.md`).
- GraphQL also honours the storefront session cookie; `bin/magento config:set graphql/session/disable 1` turns that off so headless clients rely on tokens only (recommended by Adobe; avoids session locks).

## CSRF protection for controllers

APIs are protected by tokens; browser-facing controllers (`frontend` and `adminhtml` areas) are protected by the form key and the HTTP-verb interfaces. `FrontController` runs a `RequestValidator` chain before every action: `CsrfValidator` (form key), `HttpMethodValidator` (verb interfaces), backpressure.

### Verb interfaces (S2)

Implement one of the ten `Magento\Framework\App\Action\Http*ActionInterface`s — `HttpGetActionInterface`, `HttpPostActionInterface`, `HttpPutActionInterface`, `HttpDeleteActionInterface`, `HttpPatchActionInterface`, `HttpHeadActionInterface`, `HttpOptionsActionInterface`, `HttpConnectActionInterface`, `HttpTraceActionInterface`, `HttpPropfindActionInterface` (the first two are what you will use) — or several, instead of the bare `ActionInterface`. `HttpMethodValidator` then rejects any other verb with a 404 *Page not found* (logged at debug level as `URI '…' cannot be accessed with GET method`). A mutating action is `HttpPostActionInterface` only — that is what makes the form-key check reachable, because the check runs on POST alone.

### Form key

`CsrfValidator` (frontend area) accepts a request when it is not POST, **or** it is XHR (`X-Requested-With: XMLHttpRequest`), **or** `form_key` in the request equals the session's key (`Magento\Framework\Data\Form\FormKey\Validator`, constant-time compare). Otherwise it throws `InvalidRequestException` → redirect to the referer (or base URL) with the message `Invalid Form Key. Please refresh the page.`

- Templates: `<?= $block->getBlockHtml('formkey') ?>` renders `<input name="form_key" type="hidden" value="…"/>`. On the storefront the key is delivered FPC-safely by `Magento_PageCache`'s `form-key-provider.js`, which keeps it in the `form_key` cookie and fills every `input[name="form_key"]`; `lib/web/mage/common.js` then copies that value into a non-GET form on submit when the form lacks its own and its action is on the site's base URL — a form with an empty page (no `form_key` input anywhere) or an external action gets nothing. The global `FORM_KEY` JS variable exists only in the admin (`Magento_Backend`'s `require_js.phtml`); storefront scripts read the cookie or the hidden input. PHP: `Magento\Framework\Data\Form\FormKey::getFormKey()`. Hyvä has its own helper — see `magento:frontend-hyva`.
- The form key is per session and rotates on login; a cached page that embeds it is the classic *Invalid Form Key* bug — the key must come from private content (customer-data sections / Hyvä private content), never from FPC-cached markup (P3).
- Admin area: `Magento\Backend\App\Request\BackendValidator` (via `AbstractAction::_processUrlKeys()`) requires `form_key` on every POST with no XHR exemption, and the secret `key` URL parameter on every other request while *Stores → Configuration → Advanced → Admin → Security → Add Secret Key to URLs* is on (the default); admin links must therefore come from `$block->getUrl()` / `UrlInterface`. Failure redirects to the dashboard (or returns `{"error": true, "message": …}` when `isAjax=1`).

### `CsrfAwareActionInterface`

Implement it only when the default check is wrong for one action — an endpoint that receives a signed webhook, a form posted from another domain, or an action that must answer JSON instead of redirecting. Exact signatures (`Magento\Framework\App\CsrfAwareActionInterface extends ActionInterface`):

```php
public function createCsrfValidationException(RequestInterface $request): ?InvalidRequestException;
public function validateForCsrf(RequestInterface $request): ?bool;
```

`validateForCsrf()` returns `true` (accept), `false` (reject) or `null` (run the default form-key check); `createCsrfValidationException()` returns the exception whose `$replaceResult` (a `ResultInterface`/`ResponseInterface`) is sent instead, or `null` for the default redirect. A webhook receiver that verifies an HMAC header:

```php
<?php
declare(strict_types=1);

namespace Acme\Catalog\Controller\Webhook;

use Magento\Framework\App\Action\HttpPostActionInterface;
use Magento\Framework\App\CsrfAwareActionInterface;
use Magento\Framework\App\Request\Http as HttpRequest;
use Magento\Framework\App\Request\InvalidRequestException;
use Magento\Framework\App\RequestInterface;
use Magento\Framework\Controller\Result\JsonFactory;
use Magento\Framework\Controller\ResultInterface;
use Magento\Framework\Encryption\EncryptorInterface;

class Receive implements HttpPostActionInterface, CsrfAwareActionInterface
{
    private const SIGNATURE_HEADER = 'X-Acme-Signature';

    public function __construct(
        private readonly RequestInterface $request,
        private readonly JsonFactory $jsonFactory,
        private readonly EncryptorInterface $encryptor,
        private readonly string $sharedSecret = ''
    ) {
    }

    public function execute(): ResultInterface
    {
        // handle the verified payload
        return $this->jsonFactory->create()->setData(['received' => true]);
    }

    public function validateForCsrf(RequestInterface $request): ?bool
    {
        if (!$request instanceof HttpRequest) {
            return false;
        }
        $expected = hash_hmac('sha256', (string) $request->getContent(), $this->encryptor->decrypt($this->sharedSecret));
        return hash_equals($expected, (string) $request->getHeader(self::SIGNATURE_HEADER));
    }

    public function createCsrfValidationException(RequestInterface $request): ?InvalidRequestException
    {
        $result = $this->jsonFactory->create()->setHttpResponseCode(403)->setData(['error' => 'invalid signature']);
        return new InvalidRequestException($result, [__('Invalid signature.')]);
    }
}
```

`$sharedSecret` is an encrypted value injected through `di.xml` (S4); `HttpPostActionInterface` still restricts the verb. Returning `true` unconditionally from `validateForCsrf()` disables CSRF protection for that action — core does it only where another mechanism authenticates the request (the OAuth token-exchange endpoints `Magento\Integration\Controller\Token\Request`/`Access`, payment-provider callbacks); `LoginPost`, `CreatePost` and `EditPost` return `null` and only customise the exception. Treat an unconditional `true` as a review finding (S2).

## Sources

- https://developer.adobe.com/commerce/webapi/get-started/authentication/ — Authentication (administrators/integrations, customers with `anonymous`/`self`, guests with `anonymous`; `anonymous` needs no `acl.xml` entry; `self` = resources the authenticated user owns)
- https://developer.adobe.com/commerce/webapi/get-started/authentication/gs-authentication-token — Token-based authentication (customer and admin token endpoints, 2FA provider endpoints, Bearer header, 4 h / 1 h defaults, *Access Token Expiration* config, hourly cleanup cron, integration tokens no longer Bearer by default)
- https://developer.adobe.com/commerce/webapi/get-started/authentication/gs-authentication-oauth — OAuth-based authentication (System → Extensions → Integrations, the four credentials, `oauth_*` header parameters with `HMAC-SHA256`, `/oauth/token/request` → `/oauth/token/access` handshake)
- https://developer.adobe.com/commerce/webapi/graphql/usage/authorization-tokens — GraphQL authorization (`generateCustomerToken`, no admin mutation, lifetimes, `graphql/session/disable`)
- https://developer.adobe.com/commerce/php/tutorials/backend/create-access-control-list-rule — Create Access Control List rules (`acl.xml` tree under `Magento_Backend::admin`, `Vendor_ModuleName::resourceName`, `ADMIN_RESOURCE`, `menu.xml` `resource`, `webapi.xml` `<resource ref>`, `aclResource` on blocks, System → Permissions → User Roles → Resource Access: Custom)
- https://developer.adobe.com/commerce/php/development/security/cross-site-request-forgery — Cross-Site Request Forgery (form keys added by `lib/web/mage/common.js`, `FORM_KEY` global, `Magento\Framework\Data\Form\FormKey`, `Http<Method>ActionInterface` opt-in, `CsrfAwareActionInterface` to customise validation)
- https://developer.adobe.com/commerce/webapi/rest/use-rest/anonymous-api-security — Restricting access to anonymous web APIs (*Allow Anonymous Guest Access*, affected catalogue/CMS/store read endpoints)
- https://experienceleague.adobe.com/en/docs/commerce-operations/release/notes/magento-open-source/2-4-7 — Magento Open Source 2.4.7 release notes (`createGuestCart` added, `createEmptyCart` deprecated)
