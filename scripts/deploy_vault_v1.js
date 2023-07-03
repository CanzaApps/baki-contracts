const { ethers, upgrades } = require("hardhat");

let tokens = {
  zUSD: null,
  zNGN: null,
  zZAR: null,
  zZAF: null,
};

async function deployToken(_name, _symbol) {
  const ZToken = await ethers.getContractFactory("ZToken");
  console.log(`deploying ${_name}`);

  const ztoken = await ZToken.deploy(_name, _symbol);

  await ztoken.deployed();
  tokens[_name] = ztoken.address;
  console.log(`${_name} token is deployed at ${ztoken.address}`);
  return ztoken.address;
}

async function deployOracle() {
  const Oracle = await ethers.getContractFactory("BakiOracle");
  console.log("deploying oracle");

  const oracle = await Oracle.deploy();

  await oracle.deployed();

  console.log(`oracle is deployed is ${oracle.address}`);
  return oracle.address;
}

async function deployCollateral() {
  const Cusd = await ethers.getContractFactory("USDC");
  console.log(`deploying USDC`);

  const usdc = await Cusd.deploy();

  await usdc.deployed();

  console.log(`USDC collateral is deployed at ${usdc.address}`);
  return usdc.address;
}

async function setVaultAddress(_name, _vaultAddress) {
  const zToken = await hre.ethers.getContractAt("ZToken", tokens[_name]);

  const txn = await zToken.addVaultAddress(_vaultAddress);

  console.log(`Set Vault address on ${_name}:`, txn.hash);
}

async function deployCollateral() {
  const Cusd = await ethers.getContractFactory("USDC");
  console.log(`deploying USDC`);

  const usdc = await Cusd.deploy();

  await usdc.deployed();

  console.log(`USDC collateral is deployed at ${usdc.address}`);
  return usdc.address;
}

async function main() {
  const Vault = await ethers.getContractFactory("Vault");

  // deploy ztokens and oracle contracts
  const zUSD = await deployToken("zUSD", "zUSD");
  const zNGN = await deployToken("zNGN", "zNGN");
  const zZAR = await deployToken("zZAR", "zZAR");
  const zXAF = await deployToken("zXAF", "zXAF");

  const collateral = await deployCollateral();

  const Oracle = await deployOracle();

  const vault = await upgrades.deployProxy(
    Vault,
    [Oracle, collateral],
    {
      initializer: "vault_init",
    }
  );

  await vault.deployed();
  console.log("Vault deployed to:", vault.address);

  await 

  await setVaultAddress("zUSD", vault.address);
  await setVaultAddress("zNGN", vault.address);
  await setVaultAddress("zZAR", vault.address);
  await setVaultAddress("zXAF", vault.address);
}

main();
