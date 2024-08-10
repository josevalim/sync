export let applyDarkMode = () => {
  if (
    localStorage.theme === "dark" ||
    (!("theme" in localStorage) &&
      window.matchMedia("(prefers-color-scheme: dark)").matches)
  ) {
    document.documentElement.classList.add("dark");
    return true;
  } else {
    document.documentElement.classList.remove("dark");
    return false;
  }
}

export let enableDarkMode = (isDarkMode) => document.documentElement.classList.add("dark");
export let disableDarkMode = (isDarkMode) => document.documentElement.classList.remove("dark");