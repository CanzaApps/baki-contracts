const { ethers, upgrades } = require("hardhat");

const datafeed = process.env.MAINNET_DATAFEED;
const Controller = process.env.MAINNET_CONTROLLER;

let tokens = {
  zUSD: null,
  zNGN: null,
  zZAR: null,
  zZAF: null,
};

let Oracle;

let collateral = "0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E";

async function deployToken(_name, _symbol) {
  const ZToken = await ethers.getContractFactory("ZToken");
  console.log(`deploying ${_name}`);

  const ztoken = await ZToken.deploy(_name, _symbol);

  await ztoken.deployed();
  tokens[_name] = ztoken.address;
  console.log(`${_name} token is deployed at ${ztoken.address}`);

  return ztoken.address;
}

async function deployOracle(_datafeed, _zusd, _zngn, _zzar ,_zxaf) {
  const Oracle = await ethers.getContractFactory("BakiOracle");
  console.log("deploying oracle");

  const oracle = await Oracle.deploy(_datafeed, _zusd, _zngn, _zzar ,_zxaf);

  await oracle.deployed();

  console.log(`oracle is deployed is ${oracle.address}`);
  return oracle.address;
}

async function setVaultAddress(_name, _vaultAddress) {
  const zToken = await hre.ethers.getContractAt("ZToken", tokens[_name]);

  const txn = await zToken.addVaultAddress(_vaultAddress);

  console.log(`Set Vault address on ${_name}:`, txn.hash);
}

async function main() {

  console.log("deploying mainnet");

  const Vault = await ethers.getContractFactory("Vault");

  // deploy ztokens contracts
  const zUSD = await deployToken("zUSD", "zUSD");
  const zNGN = await deployToken("zNGN", "zNGN");
  const zZAR = await deployToken("zZAR", "zZAR");
  const zXAF = await deployToken("zXAF", "zXAF");

  Oracle = await deployOracle(datafeed, zUSD, zNGN, zZAR, zXAF);

  console.log(Oracle);

  const vault = await upgrades.deployProxy(
    Vault,
    [Controller, Oracle, collateral, zUSD],
    {
      initializer: "vault_init",
    }
  );

  await vault.deployed();
  console.log("Vault deployed to:", vault.address);

  await setVaultAddress("zUSD", vault.address);
  await setVaultAddress("zNGN", vault.address);
  await setVaultAddress("zZAR", vault.address);
  await setVaultAddress("zXAF", vault.address);
}

main();
