# Arrow Pipeline Example

Demonstrates building a multi-step API pipeline using Arrow composition with `Service`.

## What it shows

`Service` is a `Category`, `Arrow`, and `ArrowChoice`. This means you can compose services
using the same combinators Haskell provides for pure functions, with automatic error
short-circuiting at every step.

| Combinator | What it does |
|---|---|
| `>>>` | Chain services sequentially (output of one feeds into the next) |
| `arr` | Lift a pure function into a `Service` |
| `second` | Run a service on the second element of a tuple, carrying the first through |
| `\|\|\|` | Route `Left` values to one service and `Right` values to another |
| `(&)` | Apply middleware (retry, timeout, circuit breaker) to a service |

## The pipeline

Fetches a post from JSONPlaceholder, then fetches the post's author, and combines both
into a summary. If any step fails, the pipeline stops and returns the error.

**Pipeline 1 -- sequential composition:**

```
Int --(fetchPost)--> Post --(arr)--> (title, userId) --(second fetchUser)--> (title, User) --(arr)--> PostWithAuthor
```

`second fetchUser` is the key Arrow combinator here: it runs `fetchUser` on the userId
while carrying the post title alongside untouched.

**Pipeline 2 -- ArrowChoice routing:**

```
Int --(fetchPost)--> Post --(arr classify)--> Either (title, userId) title
                                                |                      |
                                          fetch author            skip fetch
                                                |                      |
                                                +-------> PostWithAuthor
```

Routes based on userId: `<=5` fetches the full author profile, `>5` uses a placeholder.
The effectful branch (with its retry/timeout/circuit-breaker stack) only runs when needed.

## Why Arrow instead of do-notation

- **Error handling disappears from the call site.** Every `>>>` is an implicit
  `case result of Left err -> stop; Right ok -> continue`.
- **Data flow is explicit.** `second` and `arr` make it visible where data goes,
  instead of relying on variable scoping in a do-block.
- **Middleware composes orthogonally.** The `http` service carries retry, timeout,
  and circuit breaker. Every pipeline using `http` gets that resilience automatically.
  Arrow composition handles *what* to do; middleware handles *how reliably* to do it.

## Running

```bash
stack run example-arrow-pipeline
```
