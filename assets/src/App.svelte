<script>
  import { onMount } from "svelte";
  import SyncDB from "./lib/sync_db";
  import { todos } from "./lib/todos_store";
  import { applyDarkMode, enableDarkMode, disableDarkMode } from "./lib/utils";

  $: sortedTodos = [...$todos.items].sort((a, b) => {
    let diff = new Date(a.inserted_at).getTime() - new Date(b.inserted_at).getTime();
    return diff;
  });

  let newTodo = "";
  let isDarkMode = applyDarkMode();
  let csrfToken = document
    .querySelector("meta[name='csrf-token']")
    .getAttribute("content");

  let db = new SyncDB(1, ["items"], { csrfToken });

  document.addEventListener("items:inserted", ({ detail: items }) => {
    items.forEach((item) => todos.add(item));
  });
  document.addEventListener("items:updated", ({ detail: items }) => {
    items.forEach((item) => {
      if (item._deleted_at) {
        todos.delete(item.id);
      } else {
        todos.update(item.id, () => item);
      }
    });
  });
  document.addEventListener("items:deleted", ({ detail }) => {
    todos.delete(detail);
  });

  onMount(async () => {
    await db.sync();
    let items = await db.all("items");
    items.forEach((item) => todos.add(item));
  });

  let addTodo = async () => {
    if (newTodo.trim() !== "") {
      let now = new Date();
      let todo = {
        name: newTodo,
        done: false,
        inserted_at: now.toISOString(),
        updated_at: now.toISOString(),
      };
      todos.add(todo);
      newTodo = "";
      db.write([{ op: "insert", table: "items", data: todo }]);
    }
  };

  let handleSubmit = (e) => {
    e.preventDefault();
    addTodo();
  };

  let toggleTodoCompletion = async (id) => {
    let updatedTodo = todos.update(id, (todo) => {
      return { ...todo, done: !todo.done };
    });
    await db.write([{ op: "update", table: "items", data: updatedTodo }]);
  };

  let deleteTodo = async (id) => {
    todos.delete(id);
    await db.write([{ op: "delete", table: "items", data: id }]);
  };

  let toggleDarkMode = () => {
    isDarkMode = !isDarkMode;
    isDarkMode ? enableDarkMode() : disableDarkMode();
  };
</script>

<div
  class={`min-h-screen flex items-center justify-center p-5 ${isDarkMode ? "bg-gray-900" : "bg-gray-100"}`}
>
  <div
    class={`p-6 rounded-lg shadow-md w-full max-w-md ${isDarkMode ? "bg-gray-800 text-white" : "bg-white text-black"}`}
  >
    <h1 class="text-2xl font-bold mb-4 text-center">Svelte ToDo App</h1>

    <div class="absolute top-1 right-1 z-10">
      <div class="flex items-center dark:border-slate-800">
        <button on:click={toggleDarkMode}>
          <span class={isDarkMode && "hidden"}>
            <svg
              viewBox="0 0 24 24"
              fill="none"
              stroke-width="2"
              stroke-linecap="round"
              stroke-linejoin="round"
              class="w-6 h-6"
            >
              <path
                d="M15 12a3 3 0 1 1-6 0 3 3 0 0 1 6 0Z"
                class="stroke-slate-400 dark:stroke-slate-500"
              />
              <path
                d="M12 4v1M17.66 6.344l-.828.828M20.005 12.004h-1M17.66 17.664l-.828-.828M12 20.01V19M6.34 17.664l.835-.836M3.995 12.004h1.01M6 6l.835.836"
                class="stroke-slate-400 dark:stroke-slate-500"
              />
            </svg>
          </span>
          <span class={!isDarkMode && "hidden"}>
            <svg viewBox="0 0 24 24" fill="none" class="w-6 h-6">
              <path
                fill-rule="evenodd"
                clip-rule="evenodd"
                d="M17.715 15.15A6.5 6.5 0 0 1 9 6.035C6.106 6.922 4 9.645 4 12.867c0 3.94 3.153 7.136 7.042 7.136 3.101 0 5.734-2.032 6.673-4.853Z"
                class="fill-transparent"
              />
              <path
                d="m17.715 15.15.95.316a1 1 0 0 0-1.445-1.185l.495.869ZM9 6.035l.846.534a1 1 0 0 0-1.14-1.49L9 6.035Zm8.221 8.246a5.47 5.47 0 0 1-2.72.718v2a7.47 7.47 0 0 0 3.71-.98l-.99-1.738Zm-2.72.718A5.5 5.5 0 0 1 9 9.5H7a7.5 7.5 0 0 0 7.5 7.5v-2ZM9 9.5c0-1.079.31-2.082.845-2.93L8.153 5.5A7.47 7.47 0 0 0 7 9.5h2Zm-4 3.368C5 10.089 6.815 7.75 9.292 6.99L8.706 5.08C5.397 6.094 3 9.201 3 12.867h2Zm6.042 6.136C7.718 19.003 5 16.268 5 12.867H3c0 4.48 3.588 8.136 8.042 8.136v-2Zm5.725-4.17c-.81 2.433-3.074 4.17-5.725 4.17v2c3.552 0 6.553-2.327 7.622-5.537l-1.897-.632Z"
                class="fill-slate-400 dark:fill-slate-500"
              />
              <path
                fill-rule="evenodd"
                clip-rule="evenodd"
                d="M17 3a1 1 0 0 1 1 1 2 2 0 0 0 2 2 1 1 0 1 1 0 2 2 2 0 0 0-2 2 1 1 0 1 1-2 0 2 2 0 0 0-2-2 1 1 0 1 1 0-2 2 2 0 0 0 2-2 1 1 0 0 1 1-1Z"
                class="fill-slate-400 dark:fill-slate-500"
              />
            </svg>
          </span>
        </button>
      </div>
    </div>
    <form on:submit={handleSubmit} class="mb-4">
      <input
        type="text"
        bind:value={newTodo}
        placeholder="Enter a new task"
        class={`w-full p-2 border rounded-md ${isDarkMode ? "bg-gray-700 border-gray-600 text-white" : "bg-white border-gray-300 text-black"}`}
      />
      <button
        type="submit"
        class="mt-2 w-full bg-blue-500 text-white py-2 rounded-md hover:bg-blue-600 transition duration-200"
      >
        Add Task
      </button>
    </form>

    <ul>
      {#each sortedTodos as todo (todo.id)}
        <li
          class={`flex items-center justify-between p-2 rounded-md mb-2 ${isDarkMode ? "bg-gray-700 text-white" : "bg-gray-100 text-zinc-900"}`}
        >
          <span class={todo.done ? "line-through opacity-50" : ""}>
            {todo.name}
          </span>
          <div class="flex space-x-2">
            <button
              on:click={() => toggleTodoCompletion(todo.id)}
              class={todo.done
                ? `text-green-500 hover:text-green-400`
                : `text-gray-500 hover:text-gray-400`}
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
                stroke-width="1.5"
                stroke="currentColor"
                class="size-6"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  d="M9 12.75 11.25 15 15 9.75M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z"
                />
              </svg>
            </button>
            <button
              on:click={() => deleteTodo(todo.id)}
              class="text-red-500 hover:text-red-400"
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
                stroke-width="1.5"
                stroke="currentColor"
                class="size-6"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  d="m9.75 9.75 4.5 4.5m0-4.5-4.5 4.5M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z"
                />
              </svg>
            </button>
          </div>
        </li>
      {/each}
    </ul>
  </div>
</div>
