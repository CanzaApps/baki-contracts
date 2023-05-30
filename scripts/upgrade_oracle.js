const { ethers, upgrades } = require("hardhat");

// Current Address of the Baki Oracle
const currentOracleAddress = "0x3ab5E7a3466d0e5B556e0005D705cbC3ADc34767";

async function main() {
  const upgradedOracle = await ethers.getContractFactory("BakiOracle");

  const oracle = await upgrades.upgradeProxy(
    currentOracleAddress,
    upgradedOracle
  );

  console.log("Oracle upgraded", oracle.address);
}

main();
