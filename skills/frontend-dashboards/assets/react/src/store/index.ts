import { configureStore } from "@reduxjs/toolkit";
import dataReducer from "./dataSlice";
import filtersReducer, { filtersFromHash, hashFromFilters, hydrated } from "./filtersSlice";

export function makeStore(hash = typeof location === "undefined" ? "" : location.hash) {
  return configureStore({
    reducer: { data: dataReducer, filters: filtersReducer },
    preloadedState: { filters: filtersFromHash(hash) },
    middleware: (getDefault) =>
      getDefault({
        // Dev-only checks walk the whole state on every action; skip the big immutable dataset.
        immutableCheck: { ignoredPaths: ["data.dataset"] },
        serializableCheck: { ignoredPaths: ["data.dataset"] },
      }),
  });
}

export type AppStore = ReturnType<typeof makeStore>;
export type RootState = ReturnType<AppStore["getState"]>;
export type AppDispatch = AppStore["dispatch"];

/** Keep the URL hash in sync with filters, and filters in sync with back/forward navigation. */
export function syncFiltersWithUrl(store: AppStore): () => void {
  let last = store.getState().filters;
  const unsubscribe = store.subscribe(() => {
    const f = store.getState().filters;
    if (f === last) return;
    last = f;
    const hash = hashFromFilters(f);
    if (hash !== location.hash) history.replaceState(null, "", hash || location.pathname + location.search);
  });
  const onHash = () => store.dispatch(hydrated(filtersFromHash(location.hash)));
  window.addEventListener("hashchange", onHash);
  return () => {
    unsubscribe();
    window.removeEventListener("hashchange", onHash);
  };
}
