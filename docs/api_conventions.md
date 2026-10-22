# API layer conventions

Every backend call lives in `lib/app/api/<feature>/` and is consumed through fquery (TanStack Query for Flutter). Screens never call Dio or `ApiClient` themselves.

Reference implementation: `lib/app/api/splashscreen/` and `lib/app/api/component/`. Copy their shape.

## Files per feature folder

| File | Contents |
| --- | --- |
| `<feature>_api.dart` | `abstract final class XxxApi` with static `Future<T>` methods: one per endpoint, plus the normalization the RN service did. No caching, no state. |
| `<feature>_keys.dart` | `abstract final class XxxKeys`: every query key of the feature. |
| `<feature>_queries.dart` | Hooks: `useXxx(BuildContext context, …)` for reads, `useXxxMutation(…)` for writes, plus `ensureXxx()` wrappers around `queryCache.fetchQuery` for non-widget callers. |
| `<feature>_models.dart` | Small typed models (optional). Keep the full JSON in a `raw` field and expose getters for what the app reads, like `AppConfig`. |

A large feature may split `_api.dart` by domain (for example `wallet_api.dart` and `razorpay_api.dart`). The rule is that each file has one job.

## Rules

1. **HTTP only through `ApiClient`** (`get/post/put/patch/delete/upload`). It:
   - prefixes `/api`, so write paths exactly as RN did (`'/me/interests'`);
   - adds the user token, or the app token before login;
   - refreshes on 401;
   - retries transient GET failures (2 retries with backoff, never on 4xx);
   - returns the decoded body and throws only `ApiException`.
2. **Errors.** Never catch an error just to return `null` or `[]`; let `ApiException` propagate, and the UI decides (`QueryView`, `CAlert.error`, `CToast.error`).
   - **Exception:** where the RN service deliberately degraded (for example "fall back to defaults when this optional call fails"), keep that, and comment why.
   - **Your own failures:** throw `ApiException(ApiErrorType.rejected | parse, messageKey: '<ns>:errors.<key>')` and add the key to your i18n namespace.
3. **Queries.**
   - Use `useApiQuery` and `useApiMutation` from `core/query/query_hooks.dart`; never raw `useQuery`.
   - The error type is always `ApiException`.
   - **Keys** are lists of JSON-encodable values: `['client', 'blocked-users', userId]`.
   - **Types:** one key always holds one data type, because fquery casts the cache by type.
   - **Parameters:** put every parameter that changes the result into the key.
4. **Mutations** pass `invalidates:` with every key whose data they change. Use `queryCache.setQueryData` only for optimistic updates, and comment it.
5. **Stale time:** choose from `StaleTime.none/short/medium/long/static`.
   - Reference data (countries, languages, categories, report categories): `static` or `long`.
   - Feeds and lists: `short`.
   - Wallet balance and call status: `none`.
6. **Persisted queries.** These were cached on disk in RN (`app-cache.store.js`) and should render instantly on launch: my profile (user and expert), wallet (balance and recent transactions), call history page 1, app-config, menu pages, and host stats.
   - Use `usePersistedQuery` with `toJson` and `fromJson`.
   - Persisted data must be JSON (maps, lists, primitives) or a model with `toJson`/`fromJson`.
7. **No hidden state.** RN services kept module-level caches, in-flight dedupe and AsyncStorage copies. Drop them: fquery dedupes and caches. Keep the business rules (fallback fields, Strapi v4/v5 shape tolerance, filters, sort order).
8. **Strapi helpers** (`core/network/strapi.dart`):
   - `Strapi.node/map/list/body/pagination`: RN `xnode`/`xlist`.
   - `Strapi.mediaUrl/mediaFromAsset/mediaThumbFromAsset`: RN `media*`.
   - `J.str/integer/number/boolean/date`: lenient readers.
   - **Query strings:** pass Strapi filters as `query:` maps with flat bracket keys, `{'filters[user][documentId][\$eq]': id}`. Inlining them in the path like RN also works.
9. **IDs come in as parameters.** API functions take `userDocumentId`, `expertId` and so on as parameters and never read `SessionStore`. Hooks may default them from `SessionStore.instance.value`.
10. **i18n.**
    - No user-facing English in the API layer.
    - Messages are keys in your namespace file, `assets/i18n/{en,hi}/<namespace>.json`.
    - Both languages are required, with the same keys.
11. **Style.**
    - Match the reference files.
    - Write doc comments only where the RN code had a non-obvious reason (keep that reason in one or two lines).
    - Use no `print`.
    - Run `dart format` and get a clean `dart analyze`.
