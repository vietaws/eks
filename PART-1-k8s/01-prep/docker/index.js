import express from "express";
import os from "os";
import bodyParser from "body-parser";


const app = express();


app.use(bodyParser.json()); // to support JSON-encoded bodies
app.use(
  bodyParser.urlencoded({
    // to support URL-encoded bodies
    extended: true,
  })
);

// Every setting has a default, so the app starts with no environment variables at all.
// Empty values (for example `BACKGROUND_COLOR=`) also fall back to the default.
const BACKGROUND_COLOR = process.env.BACKGROUND_COLOR || "#283E5B";
const APP_PORT = Number.parseInt(process.env.PORT, 10) || 8080;
const APP_ENV = process.env.APP_ENV || "dev"; // for example: dev, prod
const APP_VERSION = process.env.APP_VERSION || "1"; // baked into the image with --build-arg
const LOG_LEVELS = ["error", "warn", "info", "debug"];
const LOG_LEVEL = LOG_LEVELS.includes((process.env.LOG_LEVEL || "").toLowerCase())
  ? process.env.LOG_LEVEL.toLowerCase()
  : "info";

// Print a message only if its level is enabled by LOG_LEVEL (error < warn < info < debug).
const log = (level, ...args) => {
  if (LOG_LEVELS.indexOf(level) <= LOG_LEVELS.indexOf(LOG_LEVEL)) {
    console[level === "debug" ? "log" : level](`[${level}]`, ...args);
  }
};

// Values come from the environment, so escape them before putting them into HTML.
const escapeHtml = (value) =>
  String(value).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));


const users = [
  { id: 1, name: "viet" },
  { id: 2, name: "aws" },
  { id: 3, name: "david" },
  { id: 4, name: "mina" },
  { id: 5, name: "jennie" },
];

const products = [
  { id: 1, name: "Keyboard", qty: 2 },
  { id: 2, name: "Monitor", qty: 3 },
  { id: 3, name: "Mouse", qty: 5 },
  { id: 4, name: "Camera", qty: 1 },
  { id: 5, name: "Microphone", qty: 2 },
];

app.get("/", async (req, res) => {
  try {

    const containerIp = req.socket.localAddress;
    const containerName = os.hostname();
    log("debug", "os hostname:", containerName);
    const ip = containerIp.split(":")[3];
    const version = escapeHtml(APP_VERSION);
    const bgColor = escapeHtml(BACKGROUND_COLOR);
    const appEnv = escapeHtml(APP_ENV);
    const html = `
    <html>
    <head>
      <title>Application Demo</title>
    </head>
    <body style='background-color: ${bgColor}; color: wheat;text-align: center;'>
      <h1 style='color: orange'>Welcome to AWS</h1>
      <h3>Container name: <span style='color: pink'>${containerName}</span></h3>
      <h3>Container's IP Address: <span style='color: pink'>${ip}</span></h3>
      <h3>Application Version: <span style='color: coral'>V${version}</span></h3>
      <h3>Environment: <span style='color: coral'>${appEnv}</span></h3>
      <h3>Log level: <span style='color: coral'>${LOG_LEVEL}</span></h3>
    <body>
    </html>
    `;
    res.send(html);
  } catch (err) {
    log("error", err);
    res.status(500).send("Internal Server Error");
  }
});


// Simple per-app pages, handy for testing path-based routing (for example an Ingress).
["app1", "app2", "orders", "payments"].forEach((name) => {
  app.get(`/${name}`, (req, res) => {
    const html = `
    <html>
    <head>
      <title>${name}</title>
    </head>
    <body style='background-color: ${escapeHtml(BACKGROUND_COLOR)}; color: wheat;text-align: center;'>
      <h1 style='color: orange'>Welcome to ${name}</h1>
      <h3>Container name: <span style='color: pink'>${escapeHtml(os.hostname())}</span></h3>
      <h3>Application Version: <span style='color: coral'>V${escapeHtml(APP_VERSION)}</span></h3>
      <h3>Environment: <span style='color: coral'>${escapeHtml(APP_ENV)}</span></h3>
    </body>
    </html>
    `;
    res.send(html);
  });
});

// Health check for Kubernetes probes
app.get("/healthz", (req, res) => {
  res.json({ status: "ok" });
});

app.get("/users", async (req, res) => {
  try {
    res.json(users);
  } catch (err) {
    log("error", err);
    res.status(500).send("Internal Server Error");
  }
});

app.get("/users/:id", async (req, res) => {
  try {
    const id = req.params.id;
    const user = users.find((user) => user.id == id);
    if (user) res.json(user);
    else res.status(404).send("Not Found");
  } catch (err) {
    log("error", err);
    res.status(500).send("Internal Server Error");
  }
});

app.get("/products", async (req, res) => {
  try {
    res.json(products);
  } catch (err) {
    log("error", err);
    res.status(500).send("Internal Server Error");
  }
});

app.get("/products/:id", async (req, res) => {
  try {
    const id = req.params.id;
    const product = products.find((product) => product.id == id);
    if (product) res.json(product);
    else res.status(404).send("Not Found");
  } catch (err) {
    log("error", err);
    res.status(500).send("Internal Server Error");
  }
});


app.listen(APP_PORT, () => {
  log("info", `Server is running at port ${APP_PORT} (env=${APP_ENV}, version=${APP_VERSION}, logLevel=${LOG_LEVEL})`);
});