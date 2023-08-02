const { ethers, upgrades } = require("hardhat");

// Current Address of the Vault 
const currentVaultAddress = "0x158855D3CA96D7a51601B2167FA1D322F8cC7c0e";

async function main() {
  const upgradedVault = await ethers.getContractFactory("Vault");

  const vault = await upgrades.upgradeProxy(currentVaultAddress, upgradedVault);

  console.log("Vault upgraded", vault.address);
}

main();