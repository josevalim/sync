import { Socket } from "phoenix";
import uuidv4 from "./uuidv4";

let storePromise = (req) => {
  return new Promise((resolve, reject) => {
    req.onsuccess = (e) => resolve(e.target.result);
    req.onerror = (e) => reject(e.target.error);
  });
}

export default class {
  constructor(vsn, tables, opts = {}) {
    this.vsn = vsn;
    this.tables = tables;
    this.csrfToken = opts.csrfToken;
    this.db = null
    this.socket = null
    this.channel = null
    this.lsn = 0
    this.snapmin = 0
  }

  // public
  async sync(callback) {
    return new Promise((resolve, reject) => {
      let req = indexedDB.open("sync_data", this.vsn);

      req.onerror = (e) => reject("IndexedDB error: " + e.target.errorCode);

      req.onsuccess = (e) => {
        this.db = e.target.result;
        this.socketConnect(() => {
          callback()
          resolve()
        }, reject);
      };

      req.onupgradeneeded = (e) => {
        this.db = e.target.result;
        this.db.createObjectStore("transactions", { keyPath: "id", autoIncrement: true });
        this.tables.forEach(table => {
          this.db.createObjectStore(table, { keyPath: "id" });
        })
      };
    });
  }

  async write(ops) {
    for (let op of ops) {
      if (op.op === "insert") { op.data.id = op.data.id || uuidv4(); }
    }
    ops = await this.insert("transactions", ops, { dispatch: true })

    let ackOps = (acked) => Promise.all(acked.map(op => this.delete("transactions", op.id)));

    return new Promise((resolve, reject) => {
      let chanOps = ops.sort((a, b) => a.id - b.id).map(({ id, op, table, data }) => [id, op, table, data])
      // TODO handle timeouts
      this.channel.push("write", { ops: chanOps })
        .receive("ok", () => {
          ackOps(ops).then(() => resolve())
        })
        .receive("error", ({ op: failedOp, errors }) => reject({ op: failedOp, errors }))
        .receive("timeout", () => reject({ reason: "timeout" }))
    });
  }

  async all(table) {
    try {
      // First transaction to get transaction data
      let trans = this.db.transaction([table, "transactions"], "readonly");
      let transStore = trans.objectStore("transactions");
      let tableStore = trans.objectStore(table);
      let transactionsData = await storePromise(transStore.getAll());
      let syncData = await storePromise(tableStore.getAll());

      let mergedData = new Map();

      syncData.forEach(data => !data._deleted_at && mergedData.set(data.id, data))

      transactionsData.forEach(({ op, table: transTable, data }) => {
        if (transTable !== table) { return }
        // TODO: client can handle the conflict resolution if needed
        if (op === "insert" || op === "update") {
          mergedData.set(data.id, data)
        } else if (op === "delete") {
          mergedData.delete(data)
        }
      });
      return Array.from(mergedData.values());
    } catch (error) {
      throw new Error(`Error fetching data: ${error}`);
    }
  }

  // private

  handleCommit({ lsn, ops }) {
    console.log("commit", lsn, ops)
    ops.forEach(({ op, data, schema, table }) => {
      if (op === "insert") {
        this.insert(table, [data], { dispatch: true })
      } else if (op === "update") {
        this.update(table, [data], { dispatch: true })
      } else if (op === "delete") {
        this.delete(table, data.id, { dispatch: true })
      }
    })
  }

  resync(resolve) {
    this.channel.push("sync", { snapmin: 0 }).receive("ok", ({ data, lsn, snapmin }) => {
      console.log("sync", { data, lsn, snapmin });
      data.forEach(([table, rows]) => this.insert(table, rows));
      this.lsn = lsn
      this.snapmin = snapmin
      this.all("transactions").then(ops => {
        if (ops.length === 0) { return resolve(); }
        this.write(ops).then(() => {
          resolve();
        }).catch(e => { console.error("Error writing transactions", e) });
      });
    })
  }
  socketConnect(resolve, reject) {
    this.socket = new Socket("/socket", { params: { _csrf_token: this.csrfToken } });
    this.socket.onMessage(({ topic, event, payload }) => {
      if (!topic.startsWith("sync:todos:")) { return }

      if (event === "commit") {
        this.handleCommit(payload)
      }
    });
    // when we get disconnected, we leave the channel to avoid pushing stale
    // transactions from the push buffer
    this.socket.onError(() => this.channel && this.channel.leave());
    this.socket.onOpen(() => {
      this.channel = this.socket.channel("sync:todos");
      this.channel
        .join()
        .receive("ok", (resp) => {
          console.log("Joined successfully", resp);
          this.resync(resolve);
        })
        .receive("error", (reason) => {
          reject(reason);
          console.error("Unable to join", reason);
        })
        .receive("timeout", () => reject("timeout"));

      this.channel.on("resync", () => this.resync(resolve))
    });
    this.socket.connect();
  }


  async insert(table, rows, opts = {}) {
    return new Promise((resolve, reject) => {
      let transaction = this.db.transaction([table], "readwrite");
      let objectStore = transaction.objectStore(table);
      if (!objectStore.autoIncrement) {
        rows.forEach(row => row.id = row.id || uuidv4());
      }
      Promise.all(rows.map(row => storePromise(objectStore.put(row)))).then(ids => {
        if (opts.dispatch) { document.dispatchEvent(new CustomEvent(`${table}:inserted`, { detail: rows })); }
        let result = rows.map((row, i) => ({ ...row, id: ids[i] }));
        resolve(result);
      }).catch(e => reject(`Error inserting into ${table}` + e.target.error));
    });
  }

  async update(table, rows, opts = {}) {
    return new Promise((resolve, reject) => {
      let transaction = this.db.transaction([table], "readwrite");
      let objectStore = transaction.objectStore(table);

      Promise.all(rows.map(row => storePromise(objectStore.put(row)))).then(result => {
        if (opts.dispatch) { document.dispatchEvent(new CustomEvent(`${table}:updated`, { detail: rows })); }
        resolve(result);
      }).catch(e => reject(`Error updating ${table}` + e.target.error));
    });
  }

  async delete(table, id, opts = {}) {
    return new Promise((resolve, reject) => {
      let transaction = this.db.transaction([table], "readwrite");
      let objectStore = transaction.objectStore(table);
      let req = objectStore.delete(id);

      req.onerror = (e) => reject(`Error deleting form ${table} ${id}`);
      req.onsuccess = (e) => {
        if (opts.dispsatch) { document.dispatchEvent(new CustomEvent(`${table}:deleted`, { detail: e.target.result })); }
        resolve(e.target.result);
      }
    });
  }
}