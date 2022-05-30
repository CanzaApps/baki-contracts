const router = require("express").Router();
const PriceController = require("../controller/priceController");

const priceCTL = new PriceController();

router.get("/:price_pair", (req, res) => {
  const { price_pair } = req.params;
  if (price_pair === "CELOUSD") {
    priceCTL.getCELOUSD(req, res);
  }
  if (price_pair === "NGNUSD") {
    priceCTL.getNGNUSD(req, res);
  }
  if (price_pair === "CFAUSD") {
    priceCTL.getCFAUSD(req, res);
  }
  if (price_pair === "ZARUSD") {
    priceCTL.getZARUSD(req, res);
  }
});

module.exports = router;
