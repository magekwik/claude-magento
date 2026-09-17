# REST: `webapi.xml`, serialisation, searching, errors, tooling

*Target: Magento Open Source 2.4.4–2.4.9, PHP 8.1–8.5 (support varies by release).* Rules cited by ID are in `magento:conventions` (A4 contracts, A8 dependencies, S1 authorisation, S6 input validation, P1/P2 paging). The service contract itself (`Api/`, `Api/Data/`, repository, search results) is built in `magento:data`; this file publishes it.

## How a request is served

`GET https://example.test/rest/default/V1/products/24-MB01` → `pub/index.php` runs the `webapi_rest` area → `PathProcessor` strips `/rest` and, if the next segment is a store code (`default`, `all`, any store view code), sets that store and strips it too → `Router` matches `/V1/products/:sku` (exact path first, then variable routes) → `RequestValidator` checks the route's ACL resources against the token's user (`Authorization` header → `TokenUserContext`/`OauthUserContext`, else guest), `secure`, and backpressure → `InputParamsResolver` maps path/query/body onto the interface method's parameters → the object manager `get()`s the service class (your `di.xml` preference) and calls the method → `ServiceOutputProcessor` turns the return value into arrays using the `@return` type → the renderer chosen by the `Accept` header writes JSON (default, `*/*`) or XML (`application/xml`, `text/xml`).

- `/rest/V1/...` and `/rest/default/V1/...` run in the default store view; `/rest/<code>/V1/...` in that store view; `/rest/all/V1/...` in the admin scope (store id 0), which is what integrations should use for global writes.
- Request bodies need `Content-Type: application/json` (or `application/xml`); a POST/PUT that carries a body without a recognised content type is a 400 (`Content-Type header is empty.` / `is invalid.`).

## `webapi.xml` reference

`etc/webapi.xml`, root `<routes xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="urn:magento:module:Magento_Webapi:etc/webapi.xsd">`. Validated by `vendor/magento/module-webapi/etc/webapi.xsd` (which redefines `webapi_base.xsd`).

| Element / attribute | Required | Meaning |
|---|---|---|
| `<route url method>` | yes | `url` starts with the version (`/V1/...`); `method` is `GET`, `POST`, `PUT` or `DELETE` (no `PATCH` — the XSD rejects it). Path variables are `:name` segments. |
| `<route secure="true">` | no | HTTPS only; a plain-HTTP call is a 400 `Operation allowed only in HTTPS`. |
| `<route soapOperation="…">` | no | SOAP operation name when two routes map onto the same method with different resources or parameters. |
| `<service class method>` | yes | The `Api\*Interface` (A4) and the method. The class is resolved through the object manager, so the `di.xml` preference must exist. |
| `<resources><resource ref="…"/></resources>` | yes (S1) | One or more ACL ids from any `acl.xml`, or the special `self` / `anonymous`. Several `<resource>` elements are ANDed — the caller needs all of them. |
| `<data input-array-size-limit="N">` | no | Overrides the *Input List Limit* for this route's array properties. |
| `<data><parameter name="…" force="true|false">value</parameter></data>` | no | Sets a method parameter (dotted paths reach into objects: `customer.id`); `force="true"` overrides whatever the caller sent, `false` (default) fills it only when absent. The value `%customer_id%` resolves to the customer id from the token (null for admins and guests); the literal `null` is PHP `null`. |

Merging: routes are keyed by `url` + `method`, resources by `ref`, parameters by `name`. A module loaded later that declares the same `url`+`method` replaces the `<service>` and unions the resources — this is how `Magento_TwoFactorAuth` takes over `POST /V1/integration/admin/token` from `Magento_Integration` (it sequences `Magento_Integration` in `module.xml`) — so redirect a core route by declaring it again in a module that sequences the owner (A8), never by editing core (A7).

### Interface rules the framework enforces

- The service name derives from the class: `Acme\Catalog\Api\BrandRepositoryInterface` at `/V1/...` becomes `acmeCatalogBrandRepositoryV1` — used by `?services=`, Swagger and SOAP. Anything outside `Vendor\Module\Api\` throws `The service interface name "…" is invalid.` when the schema or WSDL is generated.
- Every method has a docblock with `@return`; the return annotation is authoritative — `TypeProcessor` throws `Each method must have a doc block.` for a bare method and `Method's return type must be specified using @return annotation` for a docblock without one, even with a native `: array` or `: BrandInterface`. Supported types: `string`, `int`, `float`, `bool` (also `boolean`, `integer`, `double`), `mixed` (`anyType`), an `Api/Data` interface, and `[]` arrays of any of those. `Type|null` marks the return nullable.
- Parameters take their type from the native declaration (`int $id`, `BrandInterface $brand`); an untyped or `array` parameter needs a `@param Type[] $name` tag in position. Optional parameters need PHP defaults (`?int $storeId = null`) — a caller omitting a parameter without a default gets `"storeId" is required. Enter and try again.` (400).
- Data objects are `Api/Data` interfaces. Incoming JSON is hydrated through the implementation's constructor (only simple types and `*\Api\Data\*` types are accepted there) and then `set*` methods; unknown keys are a 400 `"foo" is not supported. Correct the field name and try again.` Outgoing objects are read through the declared interface's `get*`/`is*`/`has*` methods with no parameters — `getEntityId()` → `entity_id`, `isActive()` → `active`, `hasOptions()` → `options`. `getExtensionAttributes()` → `extension_attributes`, `getCustomAttributes()` → `custom_attributes` (EAV, `magento:data`).
- Key names convert camelCase↔snake_case both ways; avoid digits next to underscores in field names (`default_shipping1`, not `default_shipping_1`).
- A method returning `void`/`null` produces `[]`; returning `true` produces `true` (the usual `delete()` shape). An associative array declared `string[]` is re-indexed to a JSON list — return an `Api/Data` object when keys matter.

### Parameters by HTTP method

| Method | Reads | Notes |
|---|---|---|
| GET, DELETE | path variables + query string | `?a[b][c]=1` becomes the nested array/object `a.b.c`; no body is parsed. |
| POST | JSON body merged with path variables and query | Path and query win over body keys. |
| PUT | as POST, plus the last path variable is copied onto the matching body property | `PUT /V1/brands/:entityId` with body `{"brand": {...}}` sets `brand.entity_id` from the URL, so the id cannot be spoofed in the body. |

Path variable names must equal the method parameter names (`/V1/brands/:entityId` ↔ `getById(int $entityId)`); the framework accepts `entity_id` from callers too. Values are URL-decoded; a route needs the same number of segments as the request.

### Example: a repository published as CRUD routes

For the `BrandRepositoryInterface` from `magento:data` (`save`, `getById`, `getList`, `deleteById`):

```xml
<?xml version="1.0"?>
<routes xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="urn:magento:module:Magento_Webapi:etc/webapi.xsd">
    <route url="/V1/acme/brands" method="GET">
        <service class="Acme\Catalog\Api\BrandRepositoryInterface" method="getList"/>
        <resources><resource ref="Acme_Catalog::brands"/></resources>
    </route>
    <route url="/V1/acme/brands/:entityId" method="GET">
        <service class="Acme\Catalog\Api\BrandRepositoryInterface" method="getById"/>
        <resources><resource ref="Acme_Catalog::brands"/></resources>
    </route>
    <route url="/V1/acme/brands" method="POST">
        <service class="Acme\Catalog\Api\BrandRepositoryInterface" method="save"/>
        <resources><resource ref="Acme_Catalog::brands_manage"/></resources>
    </route>
    <route url="/V1/acme/brands/:entityId" method="PUT">
        <service class="Acme\Catalog\Api\BrandRepositoryInterface" method="save"/>
        <resources><resource ref="Acme_Catalog::brands_manage"/></resources>
    </route>
    <route url="/V1/acme/brands/:entityId" method="DELETE">
        <service class="Acme\Catalog\Api\BrandRepositoryInterface" method="deleteById"/>
        <resources><resource ref="Acme_Catalog::brands_manage"/></resources>
    </route>
</routes>
```

`POST /V1/acme/brands` takes `{"brand": {"name": "Acme"}}` — the body key is the parameter name (`save(BrandInterface $brand)`), the nested keys are the data interface's fields. `getById` and `deleteById` throw `NoSuchEntityException` → 404; `save` throws `CouldNotSaveException` → 400. Split read and write resources (`brands` / `brands_manage`) so an integration can be read-only.

A customer-scoped route uses `self` and the overrider:

```xml
<route url="/V1/acme/wishlists/mine" method="GET">
    <service class="Acme\Catalog\Api\WishlistManagementInterface" method="getForCustomer"/>
    <resources><resource ref="self"/></resources>
    <data><parameter name="customerId" force="true">%customer_id%</parameter></data>
</route>
```

`self` admits any valid customer token; `force="true"` guarantees `$customerId` is the token's customer whatever the request contained. Without the parameter, `self` alone is only "some customer is logged in".

## Searching: `SearchCriteria` over the query string

A `getList(SearchCriteriaInterface $searchCriteria)` method is driven entirely from the query string (the parameter name becomes the top-level key):

```
GET /rest/V1/acme/brands
  ?searchCriteria[filter_groups][0][filters][0][field]=name
  &searchCriteria[filter_groups][0][filters][0][value]=Ac%25
  &searchCriteria[filter_groups][0][filters][0][condition_type]=like
  &searchCriteria[filter_groups][1][filters][0][field]=entity_id
  &searchCriteria[filter_groups][1][filters][0][value]=1,2,3
  &searchCriteria[filter_groups][1][filters][0][condition_type]=in
  &searchCriteria[sortOrders][0][field]=name
  &searchCriteria[sortOrders][0][direction]=ASC
  &searchCriteria[pageSize]=20
  &searchCriteria[currentPage]=1
```

- Filters inside one `filter_groups[n]` are ORed; separate groups are ANDed; there is no OR across groups. `condition_type` defaults to `eq`; documented values: `eq`, `finset`, `from`, `gt`, `gteq`, `in`, `like`, `lt`, `lteq`, `moreq`, `neq`, `nfinset`, `nin`, `nlike`, `notnull`, `null`, `to` (`in`/`nin` take a comma-separated list; `like` needs the `%` you want, URL-encoded as `%25`).
- `searchCriteria=` alone (no filters) is allowed for "everything" — always send `pageSize` (P2); with *Enable Input Limits* on, a missing `pageSize` gets the *Default Page Size* and a larger-than-*Maximum Page Size* request is a 400 `Maximum SearchCriteria pageSize is 300`.
- The response is the search results interface: `{"items": [...], "search_criteria": {...}, "total_count": N}`. `total_count` is the unpaged count.
- `?fields=` trims the response: `?fields=items[name,entity_id],total_count`; nested `extension_attributes[stock_item[qty]]`; no brackets after an object name returns the whole object. Combine with `searchCriteria` using `&`.

## Errors

Body shape (JSON): `{"message": "…", "parameters": {…} | [...], "errors": [{"message": "…", "parameters": {…}}], "code": N, "trace": "…"}` — `errors` only for aggregate exceptions (`InputException` with several `addError()` calls, validator exceptions), `code` only when non-zero, `trace` only in developer mode. `message` keeps `%placeholders` with the values in `parameters`.

| Thrown by the service | HTTP | Client sees |
|---|---|---|
| `Magento\Framework\Webapi\Exception` | its `$httpCode` (400 default; constants 400/401/403/404/405/406/429/500) | message |
| `NoSuchEntityException` | 404 | message |
| `AuthorizationException`, `AuthenticationException` | 401 | message |
| any other `LocalizedException` (`InputException`, `CouldNotSaveException`, `CouldNotDeleteException`, `StateException`, `ValidatorException`) | 400 | message |
| `\InvalidArgumentException`, `\UnexpectedValueException`, `\BadMethodCallException`, `\PDOException`, `Zend_Db_*` | 400 | masked: `Internal Error. Details are available in Magento log file. Report ID: webapi-…` (real message only in developer mode) |
| anything else (`\RuntimeException`, `\TypeError`, …) | 500 | masked as above; logged to `var/log/exception.log` |

Framework-generated: no route → 404 `Request does not match any route.`; ACL failure → 401 `The consumer isn't authorized to access %resources.`; missing parameter, unknown field, wrong scalar type → 400; `secure` violated → 400; backpressure → 429 `Too Many Requests`. Throw `LocalizedException` subclasses with `__()` phrases (Q5) — a bare `\Exception` becomes an opaque 500.

## Authentication in one screen

`Authorization: Bearer <token>` on every call. Tokens: `POST /V1/integration/customer/token` `{"username": "<email>", "password": "…"}` (returns a JSON string, 1 h); `POST /V1/integration/admin/token` `{"username", "password"}` (4 h) — on a 2.4 install with `Magento_TwoFactorAuth` enabled this route validates the credentials and returns a 400 `Please use the 2fa provider-specific endpoints to obtain a token.`; use `POST /V1/tfa/provider/google/authenticate` `{"username", "password", "otp"}` (or the `authy/authenticate`, `duo_security/authenticate`, `u2fkey/verify` provider routes). Integration access tokens (System → Extensions → Integrations → Activate) are Bearer-usable only when `oauth/consumer/enable_integration_as_bearer` is `1`; otherwise sign with OAuth 1.0a. Roles, resources and lifetimes: `acl-and-auth.md`.

## Limits, rate limiting, reCAPTCHA

- *Stores → Configuration → Services → Magento Web API → Web Api Input Limits* (`webapi/validation/*`): when *Enable Input Limits* is Yes, *Input List Limit* caps array properties per entity (documented default 20; per-route override `input-array-size-limit`), *Maximum Page Size* (300) rejects larger `pageSize`, *Default Page Size* (20) fills a missing one. Exceeding the list limit is a 400 `Maximum items of type "…" is N`.
- Rate limiting (`sales/backpressure/*`, *Stores → Configuration → Sales → Sales → Rate Limiting*, off by default, needs Redis) throttles order placement — REST answers 429, GraphQL answers 200 with an error entry. It covers the checkout/order services, not your routes; to limit your own, register a `Magento\Framework\Webapi\Backpressure\BackpressureRequestTypeExtractorInterface` in `CompositeRequestTypeExtractor` and a `Magento\Framework\App\Backpressure\SlidingWindow\LimitConfigManagerInterface` in `CompositeLimitConfigManager`, as `Magento_Quote`'s `etc/di.xml` does.
- `Magento_ReCaptchaWebapiRest` gates the customer-facing endpoints reCAPTCHA is enabled for in *Stores → Configuration → Security → Google reCAPTCHA Storefront* (customer token, account creation, password reset, contact, …): the client sends `X-ReCaptcha: <token>`; a bad or missing token is a 400 `ReCaptcha validation failed, please try again`. The check is per endpoint, not per caller — with *Customer Create* reCAPTCHA on, an integration's `POST /V1/customers` needs the header too. Gate your own endpoint by providing a `WebapiValidationConfigProviderInterface`.
- *Allow Anonymous Guest Access* (`webapi/webapisecurity/allow_insecure`, default No) is what turns `Magento_Catalog::products`-guarded catalogue/CMS/store *reads* anonymous. Leave it off and give integrations a token.

## Swagger, schema, SOAP, async

- Swagger UI: `https://example.test/swagger` — developer mode only (since 2.4.4), unless `Magento\Swagger\Model\Config` is given `enabledInProduction` = `true` in `di.xml`. Paste a token into `api_key` (top right) to try authenticated routes.
- JSON schema behind it: `/rest/all/schema?services=all`, or `?services=acmeCatalogBrandRepositoryV1,catalogProductRepositoryV1`; per store view: `/rest/<code>/schema?services=…`. The schema is filtered by the caller: without a token only `anonymous` routes appear, so send `Authorization: Bearer` to see yours.
- SOAP: `/soap/default?wsdl&services=acmeCatalogBrandRepositoryV1`; every REST route is also a SOAP operation named `<service><Method>` (`acmeCatalogBrandRepositoryV1GetById`).
- Asynchronous and bulk: every non-GET route is also served under `/async/V1/...` with the same HTTP method (the request is queued and a `bulk_uuid` returned) and under `/async/bulk/V1/...` with an array of payloads; status via `GET /V1/bulk/:bulkUuid/status`. Needs `bin/magento queue:consumers:start async.operations.all` running.

## Caches and workflow

- `webapi.xml` (routes, ACL refs, parameters) → `config_webservice` cache type ("Web Services Configuration"). Interface reflection (types, `@return`, parameter lists) → `reflection`. `acl.xml`, `di.xml` → `config`.
- After any change: `bin/magento cache:clean config config_webservice reflection`; production mode additionally `bin/magento setup:di:compile` for `di.xml`. New module: `bin/magento module:enable Acme_Catalog && bin/magento setup:upgrade`.
- Smoke test order: an unauthenticated call (expect 401 `The consumer isn't authorized…`; a 404 `Request does not match any route.` means the route is not loaded — `cache:clean config_webservice`, module enabled?), then `GET /rest/all/schema?services=acmeCatalogBrandRepositoryV1` with the token (route and types as expected?), then the real call.
- Integration tests: `Magento\TestFramework\TestCase\WebapiAbstract` with `_webApiCall()` drives the real REST and SOAP stacks (Q3); unit-test the service class like any other class.

## Sources

- https://developer.adobe.com/commerce/webapi/get-started/ — Getting Started with Adobe Commerce Web APIs (REST/SOAP/GraphQL, authentication types, resources assigned to accounts and integrations)
- https://developer.adobe.com/commerce/php/development/components/web-api/services — Configure services as web APIs (`webapi.xml` elements `route`/`service`/`resources`/`data`/`parameter`, `force`, `%customer_id%`, `:id` template parameters, `@param`/`@return` PHPDoc requirement, constructor-hydration restriction to simple types and `Api\Data` interfaces)
- https://developer.adobe.com/commerce/webapi/rest/use-rest/performing-searches/ — Search using REST endpoints (`searchCriteria[filter_groups][…][filters][…][field|value|condition_type]`, `sortOrders`, `pageSize`, `currentPage`, condition types, OR within a group / AND across groups)
- https://developer.adobe.com/commerce/webapi/rest/use-rest/retrieve-filtered-responses/ — Retrieve filtered responses for REST endpoints (`?fields=` syntax, nested selection, no brackets for whole objects)
- https://developer.adobe.com/commerce/webapi/get-started/authentication/gs-authentication-token — Token-based authentication (token endpoints, 2FA provider endpoints, `Authorization: Bearer`, 4 h / 1 h lifetimes, integration tokens no longer Bearer by default)
- https://developer.adobe.com/commerce/webapi/rest/quick-reference/generate-local — Generate a local REST reference (`/swagger` developer-mode only since 2.4.4, `/rest/<store>/schema?services=…`, `api_key` box, service naming `catalogProductRepositoryV1`)
- https://developer.adobe.com/commerce/webapi/get-started/api-security — Input limiting (Enable Input Limits, Input List Limit 20, Maximum Page Size 300, Default Page Size 20)
- https://developer.adobe.com/commerce/webapi/get-started/rate-limiting — Rate limiting (`sales/backpressure/*`, REST 429 vs GraphQL 200, Redis requirement)
- https://developer.adobe.com/commerce/webapi/rest/use-rest/anonymous-api-security — Restricting access to anonymous web APIs (*Allow Anonymous Guest Access*, affected catalogue/CMS/store endpoints)
