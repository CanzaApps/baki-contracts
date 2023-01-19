const { ethers, upgrades } = require("hardhat");

// Current Address of the Vault 
const currentVaultAddress = "0x4f419B3BCF37Ff8BAe4Db159b74fFC863e3DF2fb";

async function main() {
  const upgradedVault = await ethers.getContractFactory("Vault");

  const vault = await upgrades.upgradeProxy(currentVaultAddress, upgradedVault);

  console.log("Vault upgraded", vault.address);
}

main();