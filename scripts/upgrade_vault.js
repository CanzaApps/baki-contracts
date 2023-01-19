const { ethers, upgrades } = require("hardhat");

// Current Address of the Vault 
const currentVaultAddress = /** Paste Vault Proxy Address */;

async function main() {
  const upgradedVault = await ethers.getContractFactory("Vault");

  const vault = await upgrades.upgradeProxy(currentVaultAddress, upgradedVault);

  console.log("Vault upgraded", vault.address);
}

main();