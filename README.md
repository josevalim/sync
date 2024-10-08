# Sync

A proof of concept of an Elixir/Phoenix node that runs PostgreSQL Replication to automatically synchronize data to clients, showcased at my ElixirConf US 2024 keynote.

**Beware: messy code ahead!** You will find plenty of TODOs, missing abstractions, and non-optimal decisions. Our goal is only to show how to use channels, transaction snapshots, and PostgreSQL replication to synchronize data with the front-end in a way that preserves transactional consistency. See `priv/repo/migrations` for the required SQL instructions and `lib/sync/replication.ex` for the replication logic.

See the [Design.md](DESIGN.md) document for an extensive discussion on the design, possible optimizations, and trade-offs one might consider when implementing this. [The slides are also available](Slides.pdf).

## Setup

This project builds on top of PostgreSQL replication and it requires PostgreSQL 14+. You must also enable replication in your PostgreSQL instance:

```sql
ALTER SYSTEM SET wal_level='logical';
ALTER SYSTEM SET max_wal_senders='64';
ALTER SYSTEM SET max_replication_slots='64';
```

Then **you must restart your database**.

You can also set those values when starting "postgres". This is useful, for example, when running it from Docker:

```yaml
services:
  postgres:
    image: postgres:14
    env:
      ...
    command: ["postgres", "-c", "wal_level=logical"]
```

For CI, GitHub Actions do not support setting command, so you can update and restart Postgres instead in a step:

```yaml
- name: "Set PG settings"
  run: |
    docker exec ${{ job.services.postgres.id }} sh -c 'echo "wal_level=logical" >> /var/lib/postgresql/data/postgresql.conf'
    docker restart ${{ job.services.pg.id }}
```

In production, `max_wal_senders` and `max_replication_slots` must be set roughly to twice the number of machines you are using in production (to encompass blue-green/canary deployments). 64 is a reasonable number for the huge majority of applications out there.

## Running the app

To start your Phoenix server:

  * Run `mix setup` to install and setup dependencies
  * Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## Acknowledgements

[Anthony Accomazzo](https://github.com/acco) for insights, review of design documents, and code reviews. [Chris McCord](https://github.com/chrismccord) for feedback, code reviews, and writing all of my JavaScript. [Steffen Deusch](https://github.com/SteffenDE) for feedback and code reviews.

## License

Copyright 2024 Dashbit

```
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```
