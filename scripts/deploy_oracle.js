const { ethers, upgrades } = require("hardhat");

async function main() {
  const Oracle = await ethers.getContractFactory("BakiOracle");

  const oracle = await upgrades.deployProxy(Oracle, [], {
    initializer: "oracle_init",
  });

  await oracle.deployed();
  console.log("Oracle deployed to:", oracle.address);
}

main();
