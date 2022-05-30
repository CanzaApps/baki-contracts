const express = require("express");
const cors = require("cors");

const server = express();

// middlewares
server.use(express.urlencoded({ extended: true }));
server.use(express.json());
server.use(cors());

// API routes
server.use("/api/v1/", require("./apis/apis"));

// setting port number
const port = process.env.PORT || 3000;

server.listen(port, () => {
  console.log(`Oracle server is running on port ${port}`);
});
