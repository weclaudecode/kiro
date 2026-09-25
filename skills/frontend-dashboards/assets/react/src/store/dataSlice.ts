// Load-once dataset + request status. Loading/empty/error are first-class states, not afterthoughts.
import { createAsyncThunk, createSlice } from "@reduxjs/toolkit";
import { DataError, fetchCostDoc, prepare } from "../lib/data";
import type { Dataset } from "../lib/types";

export interface DataState {
  status: "idle" | "loading" | "succeeded" | "failed";
  error: string | null;
  dataset: Dataset | null;
}

const initialState: DataState = { status: "idle", error: null, dataset: null };

export const loadCostData = createAsyncThunk<Dataset, string, { rejectValue: string }>(
  "data/load",
  async (url, { rejectWithValue }) => {
    try {
      return prepare(await fetchCostDoc(url));
    } catch (err) {
      return rejectWithValue(err instanceof DataError ? err.message : "Unexpected error - see the browser console.");
    }
  },
  // Don't refetch if a load is already in flight or done (StrictMode double-invokes effects in dev).
  { condition: (_url, { getState }) => (getState() as { data: DataState }).data.status === "idle" },
);

const dataSlice = createSlice({
  name: "data",
  initialState,
  reducers: {},
  extraReducers: (builder) => {
    builder
      .addCase(loadCostData.pending, (state) => {
        state.status = "loading";
        state.error = null;
      })
      .addCase(loadCostData.fulfilled, (state, action) => {
        state.status = "succeeded";
        // The dataset is immutable after load. Freezing/draft-proxying 10k+ rows buys nothing,
        // so the store ignores this path in the dev immutability/serializability checks (store/index.ts).
        state.dataset = action.payload;
      })
      .addCase(loadCostData.rejected, (state, action) => {
        state.status = "failed";
        state.error = action.payload ?? action.error.message ?? "Failed to load data";
      });
  },
});

export default dataSlice.reducer;
