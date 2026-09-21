---
name: api
description: Magento 2 web APIs — webapi.xml REST routes, GraphQL schema and resolvers, ACL resources, token/OAuth authentication and CSRF for controllers. Use when exposing or consuming REST or GraphQL in Magento Open Source 2.4.
---

# Magento 2 web APIs

*Target: Magento Open Source 2.4.4–2.4.9, PHP 8.1–8.5 (support varies by release).*

Rules: see `magekwik-magento:conventions` A4, S1, S2, S6. This skill cites them by ID and does not restate them.

## When to use

- Exposing a service contract over REST (`etc/webapi.xml`) or GraphQL (`etc/schema.graphqls` + resolvers).
- Deciding which ACL resource a route needs and how callers authenticate (admin, customer, integration, guest).
- Calling the Magento REST or GraphQL API from a script, integration or headless storefront.
- A frontend or admin controller that must accept POSTs safely (form key, `HttpPostActionInterface`, `CsrfAwareActionInterface`).

## When not to

- The repository, data interfaces, search results or extension attributes the API will expose → `magekwik-magento:data` (build the service contract there first; this skill only publishes it).
- Admin UI (controllers, menus, grids), plugins, observers, `di.xml` wiring → `magekwik-magento:module`.
- Rendering anything in a theme → `magekwik-magento:frontend-luma` or `magekwik-magento:frontend-hyva`.

## Decision guide

| Need | Use | Reference |
|---|---|---|
| System-to-system or admin-tool integration (ERP, PIM, scripts) | REST route in `webapi.xml` | `rest.md` |
| Storefront data for Hyvä, PWA Studio or any headless frontend | GraphQL query/mutation + resolver | `graphql.md` |
| Both | One `Api/*Interface` service contract; REST maps it directly, the GraphQL resolver calls it | `rest.md`, `graphql.md`, `magekwik-magento:data` |
| Caller is a store admin or an integration | Admin token, or an integration's OAuth credentials; route guarded by your own `acl.xml` resource | `acl-and-auth.md` |
| Caller is a logged-in customer acting on own data | Customer token; `<resource ref="self"/>` + `%customer_id%` parameter | `acl-and-auth.md` |
| Genuinely public catalogue read | `<resource ref="anonymous"/>` (S1: nothing else) | `acl-and-auth.md` |
| A browser form or AJAX call on the storefront, not an API | Frontend controller implementing `HttpPostActionInterface` (S2) | `acl-and-auth.md` |

Token endpoints: `POST /V1/integration/customer/token` (customers, 1 h); `POST /V1/integration/admin/token` (admins, 4 h) — which, with `Magento_TwoFactorAuth` enabled (the 2.4 default), only validates credentials and tells you to use the provider endpoint `POST /V1/tfa/provider/google/authenticate` with `{"username","password","otp"}`. Integrations (System → Extensions → Integrations) sign requests with OAuth 1.0a HMAC-SHA256, or use their access token as a Bearer token once `oauth/consumer/enable_integration_as_bearer` is `1`.

## Rules that bite

1. **S1** — Every `<route>` has `<resources>`. `Magento_Backend::admin` is granted to every admin role and integration that has *any* permission (`Rules::saveRel()` appends it), so a route guarded by it is open to all admins: declare your own resource in `etc/acl.xml` and reference it. `anonymous` is for public reads only.
2. **S1** — A resource that a role's rules do not mention is denied: roles saved with *Resource Access: Custom* before your `acl.xml` existed stay locked out until the role is re-saved with the new resource ticked; roles with *All* get it immediately.
3. **A4** — `<service class>` is an `Api\*Interface`, instantiated through its `di.xml` `preference`. The name must match `Vendor\Module\Api\...`: a `Model\` class there makes `ServiceMetadata::getServiceName()` throw and breaks `/rest/all/schema` (Swagger) and SOAP for every service.
4. **A4** — Every service method on the `Api` interface needs a docblock with `@return` — `TypeProcessor` reads the annotation, not the native return type, and throws without it. Arrays are `string[]` or `\Acme\Catalog\Api\Data\BrandInterface[]`; a native `array` parameter needs `@param Type[] $name`; nullable is `Type|null`. The response walks the declared type's `get*`/`is*`/`has*` getters into snake_case keys; methods not on the interface are dropped, `null` serialises as `[]`, and an associative array declared `string[]` is re-indexed to a list.
5. **S6** — Input names match camelCase or snake_case; a missing required parameter is a 400 `"name" is required. Enter and try again.`; scalars are type-checked and coerced; an unknown key on an object parameter is a 400 `"x" is not supported`. That is all the framework validates — ranges, existence and business rules are yours (`InputException`, `NoSuchEntityException`).
6. GET and DELETE read path variables (`:sku`) plus the query string (`a[b][c]=` builds nested objects, which is how `searchCriteria` works); POST and PUT read the JSON body merged with path/query (path wins). Path variable names must equal the method's parameter names. `<data><parameter name="customerId" force="true">%customer_id%</parameter></data>` binds the token's customer id and is what makes `self` safe.
7. Exceptions → status: `NoSuchEntityException` 404; `AuthorizationException`/`AuthenticationException` 401 (a missing ACL resource is 401, not 403); any other `LocalizedException` (`InputException`, `CouldNotSaveException`, `StateException`) 400 with its message; `Magento\Framework\Webapi\Exception` its own code (backpressure 429). Any other `\Exception` is masked to `Internal Error. Details are available in Magento log file. Report ID: …` — 500, except `\InvalidArgumentException`, `\UnexpectedValueException`, `\BadMethodCallException` and DB exceptions, which are 400 but masked too; a `\TypeError` inside the service call is 400 with the raw PHP message in every mode (it can name a file path), and any other `\Error` escapes the JSON layer as a `text/plain` 500. Developer mode adds `trace`.
8. **A2** — `webapi_rest`, `webapi_soap` and `graphql` are DI areas (`etc/webapi_rest/di.xml`, `etc/graphql/di.xml`); a plugin on the service interface in global `di.xml` fires for REST, GraphQL and PHP callers alike because they all call the same object.
9. **A1/P1** — GraphQL: the schema is `etc/schema.graphqls`; resolvers implement `ResolverInterface` and are shared singletons — constructor-injected services only, no per-request state in properties; never query per row — batch (`BatchResolverInterface`, DataProviders) or defer with `Value`; throw only `GraphQl*Exception` classes — anything else is masked as "Internal server error" outside developer mode.
10. **P3** — GraphQL and FPC: only GET requests are cached, and only when at least one resolver contributed tags via `@cache(cacheIdentity: "…")` and none declared `@cache(cacheable: false)`. A field with no `@cache` neither adds tags nor blocks caching, so its output is cached whenever it is queried next to `products` or `cmsPage` — mark every per-customer field `cacheable: false`. Mutations must be POST (GET → 405).
11. Caches: `webapi.xml` is in `config_webservice` ("Web Services Configuration"), not `config`; interface docblock changes are in `reflection`; `acl.xml`, `di.xml` and `schema.graphqls` are in `config` (plugin lists from `di.xml` in `compiled_config`). After touching any of them: `bin/magento cache:clean config compiled_config config_webservice reflection` (production also needs `setup:di:compile` for `di.xml`).
12. **S2** — Tokens travel as `Authorization: Bearer <token>`; sessions and form keys belong to controllers, not APIs. A storefront controller that mutates state implements `HttpPostActionInterface` (any other verb → 404); the form key is validated on every POST unless the request is XHR; admin POSTs are form-key checked with no XHR exemption, and admin GETs need the secret `key` URL parameter while *Add Secret Key to URLs* is on (the default).

## Minimal correct example

`GET /V1/acme/brands` returning brand names, callable by store managers (any admin role or integration granted the resource) and by nobody else. Files, in the order the request meets them.

`app/code/Acme/Catalog/etc/webapi.xml`:

```xml
<?xml version="1.0"?>
<routes xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="urn:magekwik-magento:module:Magento_Webapi:etc/webapi.xsd">
    <route url="/V1/acme/brands" method="GET">
        <service class="Acme\Catalog\Api\BrandListInterface" method="getNames"/>
        <resources>
            <resource ref="Acme_Catalog::brands"/>
        </resources>
    </route>
</routes>
```

`app/code/Acme/Catalog/etc/acl.xml`:

```xml
<?xml version="1.0"?>
<config xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="urn:magento:framework:Acl/etc/acl.xsd">
    <acl>
        <resources>
            <resource id="Magento_Backend::admin">
                <resource id="Acme_Catalog::brands" title="Brands API" translate="title" sortOrder="200"/>
            </resource>
        </resources>
    </acl>
</config>
```

`app/code/Acme/Catalog/Api/BrandListInterface.php`:

```php
<?php
declare(strict_types=1);

namespace Acme\Catalog\Api;

/**
 * @api
 */
interface BrandListInterface
{
    /**
     * Return the brand names known to the catalogue.
     *
     * @return string[]
     */
    public function getNames(): array;
}
```

`app/code/Acme/Catalog/Model/BrandList.php`:

```php
<?php
declare(strict_types=1);

namespace Acme\Catalog\Model;

use Acme\Catalog\Api\BrandListInterface;

class BrandList implements BrandListInterface
{
    /**
     * @inheritdoc
     */
    public function getNames(): array
    {
        return ['Acme', 'Globex', 'Initech'];
    }
}
```

`app/code/Acme/Catalog/etc/di.xml`:

```xml
<?xml version="1.0"?>
<config xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="urn:magento:framework:ObjectManager/etc/config.xsd">
    <preference for="Acme\Catalog\Api\BrandListInterface" type="Acme\Catalog\Model\BrandList"/>
</config>
```

Calling it with an admin token (2FA enabled, Google Authenticator; `TOKEN` is the JSON string the token endpoint returns):

```bash
TOKEN=$(curl -s -X POST https://example.test/rest/V1/tfa/provider/google/authenticate \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"secret","otp":"123456"}' | tr -d '"')
curl -s https://example.test/rest/V1/acme/brands -H "Authorization: Bearer $TOKEN"
# ["Acme","Globex","Initech"]
```

Without a token the same call returns 401 `{"message":"The consumer isn't authorized to access %resources.","parameters":{"resources":"Acme_Catalog::brands"}}`. On a development install with `Magento_TwoFactorAuth` disabled, `POST /rest/V1/integration/admin/token` with `{"username","password"}` returns the token directly.

Why this shape: the route maps straight onto a service contract (A4) — the same `getNames()` is callable from PHP, from a GraphQL resolver and from SOAP (every `webapi.xml` route is also a SOAP operation, here `acmeCatalogBrandListV1GetNames`), and the `@return string[]` docblock is what the web API serialises (rule 4; `getNames(): array` alone is rejected). `Acme_Catalog::brands` is a real resource: it appears under *Magento Admin* in System → Permissions → User Roles and in an integration's *API* tab, so a merchant grants it deliberately; nothing anonymous, nothing `self`. The framework reflects the interface named in `webapi.xml`, never the model, so the model's `@inheritdoc` is for readers and PHPCS (Q1), not for the API. Enable and flush: `bin/magento setup:upgrade && bin/magento cache:clean config config_webservice reflection` — then `GET /rest/all/schema?services=acmeCatalogBrandListV1` with the same Bearer token shows the route in the Swagger schema (the schema lists only what the caller may use).

## Routing table

| For | Read |
|---|---|
| `webapi.xml` element reference, path variables, `secure`, `<data>`/`force`, request/response serialisation rules, `searchCriteria` and `fields` query syntax, store codes in URLs, token endpoints, error format, input limits and rate limiting, Swagger and the schema endpoint, `/async` and `/async/bulk` | `references/rest.md` |
| `etc/schema.graphqls` types, queries, mutations, inputs, `@resolver`/`@doc`/`@cache`/`@deprecated`, resolver signature and `$context`, batch resolvers and `Value`, `GraphQl*Exception` classes and HTTP status, identity classes and FPC, request headers, testing with curl and GraphiQL | `references/graphql.md` |
| `acl.xml` structure and role semantics, `ADMIN_RESOURCE`, `<resource ref>` mapping, `self` and `anonymous`, admin/customer/integration tokens and lifetimes, OAuth 1.0a, 2FA token endpoints, form key, `CsrfAwareActionInterface`, `Http*ActionInterface`, GraphQL customer authorisation | `references/acl-and-auth.md` |
