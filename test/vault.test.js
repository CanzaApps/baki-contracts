const Vault = artifacts.require("Vault");

contract("Vault", accounts => {
  it("should deposit cUSD", async () => {
    const vault = await Vault.deployed();
    await vault.deposit(web3.utils.toWei("1", "ether"), { from: accounts[0] });
    const getVault = await vault.getVault(accounts[0]);
    assert.equal(getVault.collateralAmount, web3.utils.toWei("1", "ether"));
  });
});
