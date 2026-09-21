# GraphQL: schema, resolvers, exceptions, caching, testing

*Target: Magento Open Source 2.4.4–2.4.9, PHP 8.1–8.5 (support varies by release).* Rules cited by ID are in `magekwik-magento:conventions` (A1 DI, A4 contracts, A8 dependencies, P1 no per-row loads, P3/P7 caching, S6 input validation). GraphQL is the storefront API (Hyvä checkout, PWA Studio, any headless frontend); the data it returns comes from service contracts built in `magekwik-magento:data`.

## Shape of a GraphQL module

Core keeps GraphQL in sibling modules (`Magento_Cms` → `Magento_CmsGraphQl`); do the same: `Acme_CatalogGraphQl` depends on `Acme_Catalog` for the contracts and on `Magento_GraphQl` for the schema runtime, both in `module.xml` `<sequence>` and `composer.json` (A8). Files:

| File | Purpose |
|---|---|
| `etc/schema.graphqls` | Types, `type Query { … }` / `type Mutation { … }` additions, `input` types, directives. Every module's file is stitched into one schema; a `type Query` block in yours adds fields to the shared root type. |
| `Model/Resolver/*.php` | `ResolverInterface` implementations named in `@resolver`. |
| `Model/Resolver/*/Identity.php` | `IdentityInterface` for `@cache(cacheIdentity:)`. |
| `etc/graphql/di.xml` | DI for the `graphql` area only (plugins on core resolvers, argument processors). |

The endpoint is `POST https://example.test/graphql` (and GET for cacheable queries); a store view is chosen with the `Store: <code>` header, a currency with `Content-Currency`, a customer with `Authorization: Bearer <customer token>`. There is no admin GraphQL API — admin work is REST.

## `schema.graphqls`

```graphql
type Query {
    acmeBrands(
        pageSize: Int = 20 @doc(description: "Items per page.")
        currentPage: Int = 1 @doc(description: "1-based page number.")
    ): AcmeBrands @resolver(class: "Acme\\CatalogGraphQl\\Model\\Resolver\\Brands") @doc(description: "Brands, paged.") @cache(cacheIdentity: "Acme\\CatalogGraphQl\\Model\\Resolver\\Brands\\Identity")
}

type AcmeBrands @doc(description: "A page of brands.") {
    items: [AcmeBrand] @doc(description: "The brands on this page.")
    total_count: Int @doc(description: "Brands matching, all pages.")
}

type AcmeBrand @doc(description: "A brand.") {
    entity_id: Int @doc(description: "Brand id.")
    name: String @doc(description: "Brand name.")
}

type Mutation {
    acmeCreateBrand(input: AcmeCreateBrandInput!): AcmeBrand @resolver(class: "Acme\\CatalogGraphQl\\Model\\Resolver\\CreateBrand") @doc(description: "Create a brand (customer token required).")
}

input AcmeCreateBrandInput {
    name: String! @doc(description: "Brand name.")
}
```

- Directives: `@resolver(class: "…")` (double the backslashes), `@doc(description: "…")` on every type, field and argument (the schema is the documentation GraphiQL shows), `@cache(cacheIdentity: "…")` or `@cache(cacheable: false)` on query fields, `@deprecated(reason: "…")` when removing.
- Field and argument names are snake_case in core (`total_count`, `entity_id`); GraphQL is case-sensitive and nothing converts. Types are `Int`, `Float`, `String`, `Boolean`, `ID`, lists `[T]`, non-null `T!`, and your object/input/enum/interface/union types. Prefix your types (`AcmeBrand`) — the schema is one global namespace across all modules.
- Extending a core type is declaring it again with only the extra fields, as `Magento_CatalogInventoryGraphQl` does: `interface ProductInterface { acme_brand: AcmeBrand @resolver(class: "…") }` adds `acme_brand` to every product type; `type StoreConfig { acme_brand_page_size: Int }` exposes a store config value once you register the path in `Magento\StoreGraphQl\Model\Resolver\Store\StoreConfigDataProvider` via `etc/graphql/di.xml` `extendedConfigData`.
- A field with no `@resolver` is read from the parent resolver's array by key: `AcmeBrand.name` comes from `$items[]['name']`. Add a resolver only where the value needs work; pass the model along under a private key (`'model' => $brand`) so child resolvers can use it without reloading (P1).

## Resolvers

`Model/Resolver/Brands.php`:

```php
<?php
declare(strict_types=1);

namespace Acme\CatalogGraphQl\Model\Resolver;

use Acme\Catalog\Api\BrandRepositoryInterface;
use Magento\Framework\Api\SearchCriteriaBuilder;
use Magento\Framework\GraphQl\Config\Element\Field;
use Magento\Framework\GraphQl\Exception\GraphQlInputException;
use Magento\Framework\GraphQl\Query\ResolverInterface;
use Magento\Framework\GraphQl\Schema\Type\ResolveInfo;

class Brands implements ResolverInterface
{
    public function __construct(
        private readonly BrandRepositoryInterface $brandRepository,
        private readonly SearchCriteriaBuilder $searchCriteriaBuilder
    ) {
    }

    /**
     * @inheritdoc
     */
    public function resolve(
        Field $field,
        $context,
        ResolveInfo $info,
        ?array $value = null,
        ?array $args = null
    ) {
        $pageSize = (int) ($args['pageSize'] ?? 20);
        $currentPage = (int) ($args['currentPage'] ?? 1);
        if ($pageSize < 1 || $currentPage < 1) {
            throw new GraphQlInputException(__('pageSize and currentPage must be greater than 0.'));
        }

        $searchCriteria = $this->searchCriteriaBuilder
            ->setPageSize($pageSize)
            ->setCurrentPage($currentPage)
            ->create();
        $results = $this->brandRepository->getList($searchCriteria);

        $items = [];
        foreach ($results->getItems() as $brand) {
            $items[] = [
                'entity_id' => $brand->getEntityId(),
                'name' => $brand->getName(),
                'model' => $brand,
            ];
        }
        return ['items' => $items, 'total_count' => $results->getTotalCount()];
    }
}
```

- Signature is fixed by `ResolverInterface`: `resolve(Field $field, $context, ResolveInfo $info, ?array $value = null, ?array $args = null)`; `$context` is untyped in the interface but is `Magento\GraphQl\Model\Query\ContextInterface`: `getUserId(): ?int`, `getUserType(): ?int` (`UserContextInterface::USER_TYPE_CUSTOMER` = 3, `USER_TYPE_GUEST` = 4), `getExtensionAttributes()->getStore()` (`StoreInterface`), `->getIsCustomer()` (bool), `->getCustomerGroupId()`. `$value` is the parent field's resolved array (null on `Query`/`Mutation`); `$args` the arguments after defaults; `$info->getFieldSelection()` tells you which sub-fields were requested.
- Resolvers are constructed once per request and shared (`objectManager->get()`), so no request state in properties (A1: constructor injection only). Return an array shaped like the field's type, a scalar for scalar fields, or a `Value` (from `Magento\Framework\GraphQl\Query\Resolver\ValueFactory::create(callable)`) whose callable runs after every sibling has been visited — the deferred pattern for collecting ids first and loading once.
- Never load per item (P1): a resolver on `ProductInterface.acme_brand` runs once per product in a `products` list. Use the deferred `Value`, or implement `BatchResolverInterface` — `resolve(ContextInterface $context, Field $field, array $requests): BatchResponse` receives every pending request for the field (`BatchRequestItemInterface::getValue()/getArgs()/getInfo()`), loads them in one query and returns a `BatchResponse` with `addResponse($request, $data)` for each. `BatchServiceContractResolverInterface` does the same through a batch-capable service contract (`getServiceContract()`, `convertToServiceArgument()`, `convertFromServiceResult()`).
- Input (S6): `$args` are typed by the schema (an `Int` argument never arrives as a string), but ranges, existence and business rules are yours — throw `GraphQlInputException`. Mutations take an `input` object; read `$args['input']`.
- Customer-only fields and mutations: `if (false === $context->getExtensionAttributes()->getIsCustomer()) { throw new GraphQlAuthorizationException(__('The current customer isn\'t authorized.')); }` — the pattern core's `customer` query uses; `$context->getUserId()` is the customer id. Cart mutations take the `cart_id` (masked id) argument instead and check it belongs to the caller.

## Exceptions and status codes

Throw only these (all take `(Phrase $phrase, ?\Exception $cause = null, $code = 0, $isSafe = true)`) — they implement `ClientAware`, so the message reaches the client:

| Exception | `extensions.category` | HTTP status (2.4.9) |
|---|---|---|
| `GraphQlInputException` | `graphql-input` | 200 |
| `GraphQlNoSuchEntityException` | `graphql-no-such-entity` | 200 |
| `GraphQlAlreadyExistsException` | `graphql-already-exists` | 200 |
| `GraphQlAuthorizationException` | `graphql-authorization` | 403 |
| `GraphQlAuthenticationException` | `graphql-authentication` | 401 |

Errors land in `{"errors": [{"message": "…", "extensions": {"category": "…"}, "locations": [...], "path": [...]}], "data": {...}}` next to whatever else resolved; clients must read `errors[].extensions.category`, not the status. Any other throwable (`NoSuchEntityException` from a repository, `\RuntimeException`, `\TypeError`) is masked as `Internal server error` with a `Report ID: graph-ql-…` line in `var/log/exception.log`, and the real message and trace appear only in developer mode — wrap repository calls: `catch (NoSuchEntityException $e) { throw new GraphQlNoSuchEntityException(__($e->getMessage()), $e); }`. Syntax errors are 400; a mutation sent by GET is 405; a request without `Content-Type: application/json` on POST is rejected by `ContentTypeValidator`. `GraphQlInputException::addError()` aggregates several messages into one error.

## Full-page cache and identities

`Magento_GraphQlCache` puts GraphQL GET responses into the same full-page cache as pages (built-in or Varnish; P3, P7):

- Only GET is cached; POST responses and anything containing `mutation` get no-cache headers. `X-Magento-Cache-Id` (SHA-256 of store, currency, logged-in flag, customer group, tax rate, salt) is returned so a client can vary its own cache per customer context; send it back on GET requests when logged in.
- A response is cacheable when `CacheableQuery` is still valid after every resolver ran and at least one resolver added tags. `@cache(cacheIdentity: "…")` on a query field adds the tags its identity class returns for the resolved data; `@cache(cacheable: false)` marks the whole response uncacheable. A field with no `@cache` does neither — so an un-annotated field that returns per-customer data is cached whenever it is queried together with `products`; annotate it `cacheable: false`. The identity class:

```php
<?php
declare(strict_types=1);

namespace Acme\CatalogGraphQl\Model\Resolver\Brands;

use Magento\Framework\GraphQl\Query\Resolver\IdentityInterface;

class Identity implements IdentityInterface
{
    private const CACHE_TAG = 'acme_brand';

    /**
     * @inheritdoc
     */
    public function getIdentities(array $resolvedData): array
    {
        $ids = [];
        foreach ($resolvedData['items'] ?? [] as $item) {
            if (!empty($item['entity_id'])) {
                $ids[] = sprintf('%s_%s', self::CACHE_TAG, $item['entity_id']);
            }
        }
        if ($ids !== []) {
            array_unshift($ids, self::CACHE_TAG);
        }
        return $ids;
    }
}
```

The tags become `X-Magento-Tags` on the response (`acme_brand,acme_brand_1,acme_brand_2`) and are what invalidates the entry. Invalidation is the model's job: `Acme\Catalog\Model\Brand` implements `Magento\Framework\DataObject\IdentityInterface` with `getIdentities(): array { return ['acme_brand', 'acme_brand_' . $this->getEntityId()]; }` — the base tag so that a *new* brand flushes every cached list, the id tag for entries built around one brand — and every save or delete through the resource model dispatches `clean_cache_by_tags`, which `Magento_PageCache` turns into a tag flush. Without that, cached brand lists live until the TTL or a manual flush.

- Core cacheable queries: `products`, `categories`, `categoryList`, `cmsPage`, `cmsBlocks`, `storeConfig`, `route`, `urlResolver`, `currency`, `countries`, `customAttributeMetadata`, … Customer-specific ones (`customer`, `cart`, `customerCart`, `wishlist`) are `cacheable: false`.
- Schema (`schema.graphqls`) is cached in the `config` cache type: `bin/magento cache:clean config` after editing it. A field that "does not exist" after you added it is this cache.

## Request limits

Outside developer mode `QueryComplexityLimiter` enforces query complexity 1000 and depth 20 (`Magento\Framework\GraphQl\Query\QueryComplexityLimiter` arguments in `di.xml`), the alias limit (`graphql/validation/maximum_alias_allowed`, 10), the query length limit (`graphql/validation/query_length_limit_allowed`, 1 048 576 characters) and `graphql/disable_introspection`. *Stores → Configuration → Services → GraphQl Input Limits* also caps `pageSize` (`graphql/validation/maximum_page_size`, 300 when enabled). A query that works in developer mode can therefore fail in production — test with production mode on staging. Order placement is rate-limited by `sales/backpressure/*` (see `rest.md`; GraphQL answers 200 with an error entry). reCAPTCHA-protected mutations (`generateCustomerToken`, `createCustomer`, password changes) need the `X-ReCaptcha` header when the storefront form is protected.

## Testing

```bash
# query (POST)
curl -s https://example.test/graphql -H 'Content-Type: application/json' \
  -H 'Store: default' \
  -d '{"query":"{ acmeBrands(pageSize: 2) { total_count items { entity_id name } } }"}'

# same query cacheable (GET, URL-encoded); look for X-Magento-Tags in the response headers
curl -si 'https://example.test/graphql?query=%7B%20acmeBrands%20%7B%20items%20%7B%20name%20%7D%20%7D%20%7D'

# mutation with a customer token
TOKEN=$(curl -s https://example.test/graphql -H 'Content-Type: application/json' \
  -d '{"query":"mutation { generateCustomerToken(email: \"jane@example.com\", password: \"secret\") { token } }"}' \
  | php -r 'echo json_decode(stream_get_contents(STDIN))->data->generateCustomerToken->token;')
curl -s https://example.test/graphql -H 'Content-Type: application/json' -H "Authorization: Bearer $TOKEN" \
  -d '{"query":"mutation($name: String!) { acmeCreateBrand(input: {name: $name}) { entity_id name } }","variables":{"name":"Initech"}}'
```

Interactive: GraphiQL or Altair (browser extensions or desktop) pointed at `/graphql` — schema introspection gives autocomplete and your `@doc` strings; add the `Authorization` and `Store` headers in the tool. Automated: `Magento\TestFramework\TestCase\GraphQlAbstract` (`dev/tests/api-functional`) with `graphQlQuery()`/`graphQlMutation()` against the real schema (Q3); resolvers are also plain classes for unit tests.

## Sources

- https://developer.adobe.com/commerce/webapi/graphql/ — GraphQL overview (endpoint `/graphql`, GraphiQL, Altair, Apollo Studio)
- https://developer.adobe.com/commerce/webapi/graphql/develop/ — Define the GraphQL schema for a module (`etc/schema.graphqls`, `@resolver`, `@doc`, `@cache(cacheIdentity:)` and `@cache(cacheable: false)`)
- https://developer.adobe.com/commerce/webapi/graphql/develop/resolvers — GraphQL resolvers (`resolve(Field, $context, ResolveInfo, ?array $value, ?array $args)`, `ContextInterface`, `Value` deferred callable, `BatchResolverInterface`, `BatchServiceContractResolverInterface`)
- https://developer.adobe.com/commerce/webapi/graphql/develop/exceptions — Exception handling (the five `GraphQl*Exception` classes and categories; non-`ClientAware` exceptions masked as internal server error and logged)
- https://developer.adobe.com/commerce/webapi/graphql/develop/identity-class — Identity class (`getIdentities(array $resolvedData): array`, tag prefix + id pattern)
- https://developer.adobe.com/commerce/webapi/graphql/usage/caching — GraphQL caching (GET only, POST never cached, `X-Magento-Cache-Id` factors, cacheable core queries, no cache id on mutations)
- https://developer.adobe.com/commerce/webapi/graphql/usage/authorization-tokens — GraphQL authorization (`generateCustomerToken`, `Authorization: Bearer`, no admin token mutation, 1 h / 4 h lifetimes, `graphql/session/disable`)
- https://developer.adobe.com/commerce/webapi/graphql/usage/headers — GraphQL headers (`Authorization`, `Content-Currency`, `Store`, `X-Captcha`, `X-Magento-Cache-Id`, `X-ReCaptcha`, `Preview-Version`)
- https://developer.adobe.com/commerce/webapi/graphql/usage/ — Run GraphQL queries and mutations (query/mutation structure, variables, input objects)
