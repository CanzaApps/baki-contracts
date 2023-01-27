const { ethers, upgrades } = require("hardhat");

// Current Address of the Vault 
const currentVaultAddress = "0xB5df3C05f46c0D15849B9129121063A47591a88C";

async function main() {
  const upgradedVault = await ethers.getContractFactory("Vault");

  const vault = await upgrades.upgradeProxy(currentVaultAddress, upgradedVault);

  console.log("Vault upgraded", vault.address);
}

main();