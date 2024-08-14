import { writable, get } from 'svelte/store';

function createTodosStore() {
  // TODO handle proper decoding of types on sync
  // we receive Ecto decoded types on sync, but uncasted values on replicate
  let decodeTypes = (todo) => {
    ["inserted_at", "updated_at", "_deleted_at"].forEach(field => {
      let dateStr = todo[field];
      if (dateStr && !dateStr.endsWith("Z")) { dateStr = dateStr + "Z"; }
    })
    todo.done = todo.done === "t" || todo.done === "f" ? todo.done === "t" : todo.done;
    return todo
  }

  let todos = {
    items: [],
    add(todo) {
      this.items = [...this.items, decodeTypes(todo)];
    },
    update(id, callback) {
      let foundTodo;
      this.items = this.items.map(todo => {
        if (todo.id === id) {
          foundTodo = decodeTypes(callback(todo));
          return foundTodo;
        } else {
          return todo;
        }
      });
      return foundTodo;
    },
    delete(id) {
      this.items = this.items.filter(item => item.id !== id);
    }
  };

  const { subscribe, set, update } = writable(todos);

  return {
    subscribe,
    add: (todo) => update(store => {
      store.add(todo);
      return store;
    }),
    update: (id, callback) => {
      let updatedTodo;
      update(store => {
        updatedTodo = store.update(id, callback);
        return store;
      });
      return updatedTodo;
    },
    delete: (id) => update(store => {
      store.delete(id);
      return store;
    }),
    reset: () => set(todos)
  };
}

export const todos = createTodosStore();