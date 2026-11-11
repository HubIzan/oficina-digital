import "../recargar.js";
import { createRoot } from "react-dom/client";
import Isla from "./Isla.jsx";
import { enCarcasa } from "./carcasa.js";
import "./isla.css";

document.documentElement.classList.toggle("en-carcasa", enCarcasa);
createRoot(document.getElementById("raiz")).render(<Isla />);
