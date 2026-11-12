// Oficina Digital · © 2026 Izan Trompeta (HubIzan) · Licencia MIT · https://github.com/HubIzan/oficina-digital
import "../recargar.js";
import { createRoot } from "react-dom/client";
import Isla from "./Isla.jsx";
import { enCarcasa } from "./carcasa.js";
import "./isla.css";

document.documentElement.classList.toggle("en-carcasa", enCarcasa);
createRoot(document.getElementById("raiz")).render(<Isla />);
