import { Socket } from "phoenix";


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

  handleCommit({ lsn, ops }) {
    console.log("commit", lsn, ops)
    ops.forEach(({ op, data, schema, table }) => {
      if (op === "insert") {
        this.insert(table, data)
      } else if (op === "update") {
        this.update(table, data)
      } else if (op === "delete") {
        this.delete(table, data.id)
      }
    })
  }

  socketConnect(resolve, reject) {
    this.socket = new Socket("/socket", { params: { _csrf_token: this.csrfToken } });
    this.channel = this.socket.channel("sync:todos");
    this.socket.onMessage(({ topic, event, payload }) => {
      if (!topic.startsWith("sync:todos:")) { return }

      if (event === "commit") {
        this.handleCommit(payload)
      }
    });
    this.channel
      .join()
      .receive("ok", (resp) => {
        this.channel.push("sync", { snapmin: 0 }).receive("ok", ({ data, lsn, snapmin }) => {
          console.log("sync", { data, lsn, snapmin });
          data.forEach(([table, rows]) => {
            rows.forEach(row => this.insert(table, row));
          });
          this.lsn = lsn
          this.snapmin = snapmin
          resolve();
        })
        console.log("Joined successfully", resp);
      })
      .receive("error", (reason) => {
        reject(reason);
        console.error("Unable to join", reason);
      })
      .receive("timeout", () => reject("timeout"));

    this.socket.connect();
  }

  async sync() {
    return new Promise((resolve, reject) => {
      let request = indexedDB.open("sync_data", this.vsn);

      request.onerror = (e) => reject("IndexedDB error: " + e.target.errorCode);

      request.onsuccess = (e) => {
        this.db = e.target.result;
        this.socketConnect(resolve, reject);
      };

      request.onupgradeneeded = (e) => {
        this.db = e.target.result;
        this.tables.forEach(table => {
          this.db.createObjectStore(table, { keyPath: "id" });
        })
      };
    });
  }

  async all(table) {
    return new Promise((resolve, reject) => {
      let transaction = this.db.transaction([table], "readonly");
      let objectStore = transaction.objectStore(table);
      let request = objectStore.getAll();

      request.onerror = (e) => reject(`Error fetching ${table}`);
      request.onsuccess = (e) => resolve(e.target.result);
    });
  }

  async insert(table, record) {
    return new Promise((resolve, reject) => {
      let transaction = this.db.transaction([table], "readwrite");
      let objectStore = transaction.objectStore(table);
      let request = objectStore.put(record);

      request.onerror = (e) => reject(`Error inserting into ${table}` + e.target.error);
      request.onsuccess = (e) => {
        document.dispatchEvent(new CustomEvent(`${table}:inserted`, { detail: record }));
        resolve(e.target.result);
      }
    });
  }

  async update(table, record) {
    return new Promise((resolve, reject) => {
      let transaction = this.db.transaction([table], "readwrite");
      let objectStore = transaction.objectStore(table);
      let request = objectStore.put(record);

      request.onerror = (e) => reject(`Error updating ${table}`);
      request.onsuccess = (e) => {
        document.dispatchEvent(new CustomEvent(`${table}:updated`, { detail: record }));
        resolve(e.target.result);
      }
    });
  }

  async delete(table, id) {
    return new Promise((resolve, reject) => {
      let transaction = this.db.transaction([table], "readwrite");
      let objectStore = transaction.objectStore(table);
      let request = objectStore.delete(id);

      request.onerror = (e) => reject(`Error deleting form ${table} ${id}`);
      request.onsuccess = (e) => {
        document.dispatchEvent(new CustomEvent(`${table}:deleted`, { detail: e.target.result }));
        resolve(e.target.result);
      }
    });
  }
}