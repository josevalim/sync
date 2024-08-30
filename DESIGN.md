# Design

> Disclaimer: I am not a Postgres specialist and the document below may have inaccuracies or wrong assumptions.

This document outlines an implementation of implementing live queries and synchronization on top of Phoenix Channels and PostgreSQL.

The idea behind implementing "live queries" is that a client can request "select * from tasks where org_id = 42" and they will receive both the current tasks but subscribe to any future insert, update, or deletion of these tasks.

One way to implement such tasks is via direct table polling. However, if we have several queries and several users, polling can quickly become expensive. Furthermore, [PostgreSQL does not guarantee rows become available in the same order as primary keys/sequences](https://event-driven.io/en/ordering_in_postgres_outbox/), which is a big challenge that we reference to throughout this document.

Another approach is to set Postgres Replication and then duplicate all of Postgres data elsewhere. If you want to catch-up on past events, then you go through the replicated data, and unpack it. Copying the data elsewhere requires additional services, for both compute and storage, which I would like to avoid.

Instead, we want to use Postgres Replication alongside Elixir. The idea is that each Elixir node will establish a replication connection with Postgres and receive all events as they happen. Those events can then be filtered and sent to the appropriate clients via Phoenix Channels. This requires at least two Postgres connections: one for replication and another for queries. Both can come from replicas, as long as they are from the same replica.

## Live queries

To implement live queries, we first perform a **catch-up query** and then you wait for further changes from the replication. In order to discuss the possible problems that may happen, consider we want to query a table and two transactions are changing it at the same time:

```sql
UPDATE tasks WHERE id=13 SET title="A" -- xacc1
UPDATE tasks WHERE id=13 SET title="B" -- xacc2
```

Since we want to receive live updates, the first step is to subscribe to the PostgreSQL replication service before we query the data. Then, as we receive updates from replication, we broadcast them to the interested parties via Phoenix Channels. This makes sure no updates are losts. Otherwise the following may happen:

1. `UPDATE tasks WHERE id=13 SET title="A"`
2. We perform the catch-up query and see `title="A"`
3. `UPDATE tasks WHERE id=13 SET title="B"`
4. We start the subscription

Because we started the subscription _after_  SET title="B", we have never received this event. Instead, we want this to happen:

1. We start the subscription
2. `UPDATE tasks WHERE id=13 SET title="A"`
3. We perform the catch-up query and see `title="A"`
4. `UPDATE tasks WHERE id=13 SET title="B"`

Of course this means we will receive the information title="A" twice, but we can largely assume that receiving duplicate data is not a problem. On the other hand, this solution may also mean we go back in time or stutter. Take the following order of events:

1. We start the subscription
2. `UPDATE tasks WHERE id=13 SET title="A"`
3. `UPDATE tasks WHERE id=13 SET title="B"`
4. We perform the catch-up query and see title="B"

The catch-up query sees title="B". However, when receiving the events, we will first receive title="A" and then receive title="B". If for some reason there is a huge gap in the replication log between title="A" and title="B", it may mean the UI can stutter between B -> A -> B or show inconsistent data.

Therefore, we need a way to merge the data from the catch-up query and the replication log. We can solve this problem by Postgres' log sequence numbers (LSN), which are monotonically increasing: after the catch-up query, we will fetch `pg_current_wal_lsn()`, let's call it the _query-LSN_. Each update we receive from the replication subscription will also have a LSN, let's call it _sync-LSN_. Now we must buffer all replication events until the sync-LSN matches the query-LSN, only then we can show the catch-up query results and the queued updates to the user. For this "overtaking" to happen, the catch-up queries and the subscription server must use the same replica, otherwise we may have gaps in the data. From this moment on, the client continues to track the _sync-LSN_.

The _sync-LSN_ is important to avoid transactional inconsistency on live queries. For example, imagine you have a "projects" table with a foreign key to "managers". If you query managers first, and then projects, the projects may point to a manager that has not yet been sent by the replication. Using the sync-LSN addresses that. The downside is that, if the replication layer is slow, it will delay when data can be shown to the client. We will explore solutions to address this particular problem after we introduce synchronization.

## Synchronization

So far we have discussed live queries but there is another feature we could build on top of this system, which is synchronization. Because our live query implementation broadcasts PostgreSQL replication event as they happen, without storing past data, if the user closes the application and joins after 1 hour or a day or a week, we cannot catch them up.

The good news is that the latest version of the data can be found directly in the tables we want to synchronize. To do so, we can issue another live query, but it would be a waste to download all data again. Unfortunately, we cannot simply use the ID or a database sequence to solve this problem because they are not monotonically increasing: a transaction that started earlier and inserted an entry ID=11 may be committed after a transaction that started later with ID=13. Here is [an excellent article](https://blog.sequinstream.com/postgres-sequences-can-commit-out-of-order/) that discusses this problem and possible solutions.

We can adapt one of the solutions in the article by introducing a `snapmin` column to every table we want to live/sync. The `snapmin` column tells us the minimum transaction version that may have been committed after us. It can be computed by using triggers on INSERT and UPDATE to set the `snapmin` column to the following

```sql
pg_snapshot_xmin(pg_current_snapshot())
```

We will also augment the catch-up query to return the value of  `pg_snapshot_xmin(pg_current_snapshot())` at the beginning of the transaction. This will be our pointer, subsequent catch-up queries should only return records where their `snapmin` column is later or equal to our pointer. Furthermore, as we receive updates from subscription, we will update our pointer with the latest `snapmin` from the replicated rows (per table). This overall enables us to catch-up data in any table with subsequent queries.

Unfortunately, this solution may introduce two pitfalls in practice.

The first one can be caused by slow replication. If replication is slow, we delay when to show data in the client, because the query-LSN and the sync-LSN must match. Luckily, now that we introduce `snapmin`, we can use it to compute data that is safe to show. The cient can show any data, without waiting, as long as the resource `snapmin` retrieved from a catch-up query is less than the latest `snapmin` seen by the replication.

The second issue is caused by long running transactions. Because our synchronization point is `pg_snapshot_xmin(pg_current_snapshot())`, any long transaction will cause several resources to be introduced with the same `snapmin`, forcing them to be replayed in future catch-up queries. A simple solution to the problem would be for the catch-up query to not show data where `snapmin < pg_snapshot_xmin(pg_current_snapshot())`, but that comes with the downside of potentially delaying when data is seen until the long running transaction either commits or rolls back. Instead, we can reduce the impact long running transactions have on the system by using shared locks and topics.

Most applications namespace their data by a key, such as the `organization_id`, `company_id` or `team_id`. Of all transactions happening on a database, only some of them affect a given organization, and only some of them affect sync tables. Therefore, we could use a shared advisory lock: the `classid` will partition the namespace (such as organization id) and the `objid` will store the lower 32 bits of `pg_current_xact_id`. Now, instead of storing `pg_snapshot_xmin(pg_current_snapshot())` in the `snapmin` column or reading it at the beginning of catch-up queries, we will query the shared lock and filter the snapshot to only hold the transaction IDs with matching lower 32 bits. This means that regular long running transactions will not affect our system (because they won't be using the advisory locks) and, if a transaction in a sync table needs to run for long, it will only affect a subset of the organizations (split over a 32 bits namespace). Once you have enough over 2 billion organizations, you may have overlap between organization IDs, but those are safe to overlap, as this is purely an optimization.

A potential downside of this approach is that we can only allow changes to sync tables if they are wrapped in these "sync transactions", although you may bypass this limitation by introducing functions that use either `pg_snapshot_xmin(pg_current_snapshot())` or the shared advisory lock, depending on local transactional variables.

## Offline-first

Now that we have live queries and synchronization in place, the next challenge is to make our application offline-first.

The idea is that writes on the client will first go to a transaction store, that stores events. Entries in the transaction store are sent to the server as soon as possible but it may also work while offline, [similar to Linear's](https://linear.app/blog/scaling-the-linear-sync-engine). The server will eventually accept or refute these transactions and their changes to the underlying tables eventually make their way back to the client via replication. There are many trade-offs and design decisions that could be made in regards to how and when transactions are submitted, accepted, or refuted.

It is also important to keep the transaction store is kept separate from the synchronized data. What the user sees on the screen is the result of the transaction store events applies to the synchronized data.

I'd also recommend to allow developers to store events of different types inside the transaction store, not only synchronization ones. For each event type stored, the client needs to know how to apply that event to its in-memory data, and the server needs to know how to process it.

## To be explored

There are several topics not explored here:

* Since we are doing synchronization, we need to store how schemas evolve over time, so changes to the schema on the server are automatically mirrored on the client. Not all schema changes can be automatically mirrored to the client.

* We have not discussed the object model for JavaScript, this is important for both reads and writes. For example, if we have to load all data for a given company on page load, that won't be a good user experience. We probably want to control which collections are synchronized and which ones are live. Figma's [LiveGraph](https://www.figma.com/blog/livegraph-real-time-data-fetching-at-figma/) may be a source of inspiration.

* One important topic to discuss is authentication and authorization, which must still live on the server. My early thoughts on this is that, at least part of authorization layer, must be based on "topics": as the user signs in, or uses the application, the client will request the server for authorization to listen to topics, such as "organization:ID", "project:ID", etc. Our live query system will broadcast data to clients based on the topics they have been subscribed to. Furthermore, I'd suggest for most tables in your database to have at least a `organization_id` (or `company_id`, `subdomain_id`, etc) column, which will behave as the "root key" of all operations. This will be important to guarantee event ordering and enable several optimizations (for tables that are publically available, having no key whatsoever is fine). Other keys within the organization, such as `post_id`, `project_id`, may also be kept as additional columns (and additional authorization topics).

* Other authorization rules may be written either in regular Elixir code, an embedded Elixir DSL (such as one inspired by [Ecto Query](https://hexdocs.pm/ecto/Ecto.Query.html)), or using an external language, such as [Google CEL](https://cel.dev/). When a channel subscribes to a replication event, it can do so via ETS tables. These authorization rules can be stored in the ETS table and be applied on-the-fly as the replication events arrive.

* What is the programming model for Phoenix? Phoenix LiveView removed the serialization layer (REST, GraphQL, etc) and squeezed the controllers/views into a single entity, simplifying the amount of concepts we have to juggle at once. The approach here similarly allows us to squeeze some layers (albeit different ones?) by keeping the focus on the data schema (and its evolution) and on how mutations (from the transaction DB) are handled.

## Requirements and benefits

Each table you wnat to synchronize, aka "sync table", needs to adhere to the following rules:

* All tables must have `snapmin` columns.

* We strongly recommend (as per the previous section) for all sync tables to have a "root key" column, such as `organization_id`, with all information necessary to broadcast its update. Tables may have additional keys, if necessary.

* Information about deleted row must be preserved somewhere. You could use [a "soft" `deleted_at` column](https://dashbit.co/blog/soft-deletes-with-ecto), which is the approach implemented in this proof of concept, but I believe for this problem, [an additional "deletions" table per "sync table"](https://brandur.org/fragments/deleted-record-insert) would be easier to operate and scale.

This approach is elegant for a few reasons:

* Database tables semantics and features are preserved as is (it does not enforce a new programming model)

* The table has the latest version of the data, for efficient catch-ups, and the replication gives deltas

* We can scale by moving all live queries and synchronization to the read replicas

* Several live queries can happen in parallel, as long as we track the snapmin/snapcur per query/table

* Soft deletes are a requirement, but also a free feature

* Phoenix and stock PostgreSQL only: no PostgreSQL extensions required, no addition services, no copies of the data to third party services, no need for higher database isolation levels
