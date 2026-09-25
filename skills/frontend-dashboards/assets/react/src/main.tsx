import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { Provider } from "react-redux";
import { makeStore, syncFiltersWithUrl } from "./store";
import { App } from "./App";
import "./styles/tokens.css";
import "./styles/components.css";

const store = makeStore();
syncFiltersWithUrl(store);

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <Provider store={store}>
      <App />
    </Provider>
  </StrictMode>,
);
