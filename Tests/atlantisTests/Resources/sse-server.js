const http = require("http");

function sendSSE(res, chunks) {
  res.writeHead(200, {
    "Content-Type": "text/event-stream; charset=utf-8",
    "Cache-Control": "no-cache, no-transform",
    "Connection": "keep-alive",
    "X-Accel-Buffering": "no"
  });
  res.flushHeaders();

  const timers = chunks.map(([delay, body]) => {
    return setTimeout(() => {
      if (!res.destroyed) {
        res.write(body);
      }
    }, delay);
  });

  res.on("close", () => {
    timers.forEach(clearTimeout);
  });
}

const server = http.createServer((req, res) => {
  switch (req.url) {
    case "/basic":
      sendSSE(res, [
        [0, "event: greeting\nid: basic-1\ndata: hello-atlantis\n\n"],
        [50, "event: greeting\nid: basic-2\ndata: goodbye-atlantis\n\n"]
      ]);
      break;
    case "/multiline":
      sendSSE(res, [
        [0, "event: note\nid: multiline-1\ndata: first line\ndata: second line\n\n"]
      ]);
      break;
    case "/comment-retry":
      sendSSE(res, [
        [0, ": keep-alive\nretry: 1500\n\n"],
        [50, "event: update\nid: comment-1\ndata: after-comment\n\n"]
      ]);
      break;
    case "/split-event":
      sendSSE(res, [
        [0, "event: split\nid: split-1\ndata: first"],
        [50, " line\ndata: second line\n\n"]
      ]);
      break;
    default:
      res.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" });
      res.end("Not Found");
  }
});

server.listen(0, "127.0.0.1", () => {
  const address = server.address();
  process.stdout.write(`PORT ${address.port}\n`);
});

function shutdown() {
  server.close(() => {
    process.exit(0);
  });
  setTimeout(() => {
    process.exit(0);
  }, 100).unref();
}

process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
