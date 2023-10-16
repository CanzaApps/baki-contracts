const { ethers, upgrades } = require("hardhat");

// Current Address of the Faucet 
const currentFaucetAddress = "0x16A4C191DB629ABC4c2c416b09eB4675A639D3C3";

async function main() {
  const upgradedFaucet = await ethers.getContractFactory("Faucet");

  const faucet = await upgrades.upgradeProxy(currentFaucetAddress, upgradedFaucet);

  console.log("Faucet upgraded", faucet.address);
}

main();