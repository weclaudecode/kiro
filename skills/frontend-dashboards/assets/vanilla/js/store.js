// One store, one reducer, derived data via selectors. Same mental model as the React/Redux track,
// so a dashboard can graduate from vanilla to Redux Toolkit without redesigning its state.
//
// Rule: the store holds only what the user chose (filters, grouping). Everything visible -
// totals, series, table rows - is derived from (data, state) by selectors. Never store derived data.

export const DIMENSIONS = ["accounts", "environments", "services", "regions"];
export const RANGE_PRESETS = ["7d", "30d", "90d", "mtd", "prev-month", "all"];
export const GROUP_BYS = ["service", "accountName", "environment", "region"];

export const initialState = Object.freeze({
  range: "30d",
  accounts: [], // empty = all
  environments: [],
  services: [],
  regions: [],
  groupBy: "service",
});

export function reducer(state, action) {
  switch (action.type) {
    case "range/set":
      return RANGE_PRESETS.includes(action.value) ? { ...state, range: action.value } : state;
    case "dimension/set":
      return DIMENSIONS.includes(action.dimension) ? { ...state, [action.dimension]: [...action.values] } : state;
    case "dimension/toggle": {
      const current = state[action.dimension];
      const next = current.includes(action.value) ? current.filter((v) => v !== action.value) : [...current, action.value];
      return { ...state, [action.dimension]: next };
    }
    case "groupBy/set":
      return GROUP_BYS.includes(action.value) ? { ...state, groupBy: action.value } : state;
    case "filters/reset":
      return { ...initialState, groupBy: state.groupBy };
    case "state/hydrate":
      return { ...state, ...action.state };
    default:
      return state;
  }
}

export function createStore(reduce, preloaded) {
  let state = preloaded;
  const listeners = new Set();
  return {
    getState: () => state,
    dispatch(action) {
      const next = reduce(state, action);
      if (next === state) return;
      const prev = state;
      state = next;
      listeners.forEach((fn) => fn(state, prev));
    },
    subscribe(fn) {
      listeners.add(fn);
      return () => listeners.delete(fn);
    },
  };
}

// ---- URL hash sync: filters are shareable and survive reload ----

export function stateFromHash(hash = location.hash) {
  const params = new URLSearchParams(hash.replace(/^#/, ""));
  const out = {};
  if (RANGE_PRESETS.includes(params.get("range"))) out.range = params.get("range");
  if (GROUP_BYS.includes(params.get("groupBy"))) out.groupBy = params.get("groupBy");
  for (const dim of DIMENSIONS) {
    const raw = params.get(dim);
    if (raw) out[dim] = raw.split(",").filter(Boolean);
  }
  return out;
}

export function hashFromState(state) {
  const params = new URLSearchParams();
  if (state.range !== initialState.range) params.set("range", state.range);
  if (state.groupBy !== initialState.groupBy) params.set("groupBy", state.groupBy);
  for (const dim of DIMENSIONS) if (state[dim].length) params.set(dim, state[dim].join(","));
  const s = params.toString();
  return s ? `#${s}` : "";
}

export function syncToUrl(store) {
  store.subscribe((state) => {
    const hash = hashFromState(state);
    if (hash !== location.hash) history.replaceState(null, "", hash || location.pathname + location.search);
  });
  window.addEventListener("hashchange", () => store.dispatch({ type: "state/hydrate", state: { ...initialState, ...stateFromHash() } }));
}
