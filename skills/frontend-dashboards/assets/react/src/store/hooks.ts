// Typed hooks (react-redux 9 `.withTypes`). Components import these, never plain useSelector/useDispatch.
import { useDispatch, useSelector } from "react-redux";
import type { AppDispatch, RootState } from "./index";

export const useAppDispatch = useDispatch.withTypes<AppDispatch>();
export const useAppSelector = useSelector.withTypes<RootState>();
